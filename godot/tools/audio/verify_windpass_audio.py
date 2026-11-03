#!/usr/bin/env python3
"""Audio-only validation. Decode, measure mix/seams and write review previews.
Does not launch the game, alter saves, run a gameplay suite or mark listening done.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import numpy as np
from scipy.io.wavfile import read,write

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'assets/audio/content_v280'

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--preview-dir',type=Path,default=Path('/tmp/windpass-v280-listening'));args=parser.parse_args()
    args.preview_dir.mkdir(parents=True,exist_ok=True)
    report=[];previews=[];sfx_previews=[]
    old_hashes={hashlib.sha256(p.read_bytes()).hexdigest() for p in (ROOT/'assets/audio').rglob('*') if p.is_file() and p.suffix in ('.ogg','.mp3') and OUT not in p.parents}
    manifest=json.loads((OUT/'manifest.json').read_text())
    for item in manifest:
        path=OUT/(item['id']+'.ogg')
        digest=hashlib.sha256(path.read_bytes()).hexdigest()
        assert digest==item['sha256'] and digest not in old_hashes
        with tempfile.TemporaryDirectory() as tmp:
            wav=Path(tmp)/'decoded.wav'
            subprocess.run(['ffmpeg','-v','error','-y','-i',str(path),'-c:a','pcm_f32le',str(wav)],check=True)
            sr,x=read(wav); x=x.astype(np.float64)
        assert sr==44100 and x.ndim==2 and x.shape[1]==2
        assert np.isfinite(x).all()
        peak=float(20*np.log10(np.max(np.abs(x))))
        assert peak < -6 if item['loop'] else peak < -3
        entry={'id':item['id'],'sha256':digest,'new_audio_bytes':True,'sample_rate':sr,'channels':2,'decoded_duration_seconds':len(x)/sr,'peak_dbfs':peak,'rms_dbfs':float(20*np.log10(np.sqrt(np.mean(x*x)))),'finite':True,'clipped':False}
        if item['loop']:
            duration=len(x)/sr;assert 60<=duration<=90
            seam=float(np.max(np.abs(x[0]-x[-1])))
            typical=float(np.percentile(np.abs(np.diff(x,axis=0)),99.9))
            seam_rms=float(np.sqrt(np.mean(np.concatenate([x[-4410:],x[:4410]])**2)))
            assert seam<typical,(item['id'],seam,typical)
            p=subprocess.run(['ffmpeg','-hide_banner','-i',str(path),'-af','loudnorm=print_format=json','-f','null','-'],capture_output=True,text=True,check=True)
            loud=json.loads(p.stderr[p.stderr.rfind('{'):p.stderr.rfind('}')+1])
            lufs=float(loud['input_i']);truepeak=float(loud['input_tp'])
            assert -23.5<=lufs<=-20.5,(item['id'],lufs)
            assert truepeak<-6,(item['id'],truepeak)
            correlation=float(np.corrcoef(x.T)[0,1])
            mono=np.mean(x,axis=1); mono_rms=float(np.sqrt(np.mean(mono*mono)))
            stereo_rms=float(np.sqrt(np.mean(x*x)))
            mono_loss=float(20*np.log10(mono_rms/stereo_rms));assert mono_loss>-3
            entry.update(loop_boundary_jump=seam,within_track_99_9_percentile_step=typical,seam_pass=True,seam_rms=seam_rms,integrated_lufs=lufs,true_peak_dbtp=truepeak,mono_loss_db=mono_loss,channel_correlation=correlation)
            # A 12-second established section and an explicit repeated seam.
            snippet=x[sr*15:sr*27].copy(); fade=np.linspace(0,1,round(sr*.08))
            snippet[:len(fade)]*=fade[:,None];snippet[-len(fade):]*=fade[::-1,None]
            previews.append(snippet);previews.append(np.zeros((round(sr*.5),2)))
            write(str(args.preview_dir/(item['id']+'-seam.wav')),sr,(np.concatenate([x[-3*sr:],x[:3*sr]])*32767).astype(np.int16))
            write(str(args.preview_dir/(item['id']+'-excerpt.wav')),sr,(snippet*32767).astype(np.int16))
        else:
            assert .15<=len(x)/sr<=1.5
            # Edge protection is tested after Vorbis decode, not before encoding.
            assert np.max(np.abs(x[[0,-1]]))<.02
            sfx_previews.extend([x,np.zeros((round(sr*.35),2))])
        report.append(entry)
    write(str(args.preview_dir/'five-track-review.wav'),44100,(np.concatenate(previews)*32767).astype(np.int16))
    write(str(args.preview_dir/'effects-review.wav'),44100,(np.concatenate(sfx_previews)*32767).astype(np.int16))
    result={'subjective_listening_verified':False,'subjective_listening_status':'pending actual playback review; signal checks alone do not establish musical quality','checks':report,'preview_directory':str(args.preview_dir)}
    (OUT/'verification.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(result,ensure_ascii=False,indent=2))
if __name__=='__main__':main()
