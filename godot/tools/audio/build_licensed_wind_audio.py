#!/usr/bin/env python3
"""Build approved CC music from retained original sources; no network, game or repo writes.
Requires Python 3 + numpy and ffmpeg/ffprobe. Run with --root DIR (required explicit local source directory).
Only scalar gain, extraction of authored loop, and <=20 ms boundary repair are applied.
No pitch shifting, stretching, re-composition, compression or added instruments.
"""
import argparse, hashlib, json, math, subprocess
from pathlib import Path
import numpy as np
SR=44100
TARGET_I=-22.0
MAX_TP=-2.0
TRACKS=[
 dict(id="tiya_reveal", title="Bright Wish", creator="Kevin MacLeod (incompetech.com)", source="bright_wish.mp3", license="CC BY 4.0", license_url="https://creativecommons.org/licenses/by/4.0/", page="https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1100377", loop_offset_seconds=0.0, mode="full_cadence", expected_sha256="1b0fa563ffad8f1d83bc4b308fe118096a4e25a5c818f67a167e933005216dd3"),
 dict(id="lumi_reveal", title="Happy moments 1.4", creator="Centurion_of_war", source="happy_moments_1_4.ogg", license="CC0 1.0", license_url="https://creativecommons.org/publicdomain/zero/1.0/", page="https://opengameart.org/content/happy-moments", loop_offset_seconds=25.6, mode="intro_then_main", expected_sha256="c8a94e9bc928e6701784c6533a467392f7fee7490c53c65766401a71e5d5b496"),
 dict(id="windpass_road", title="Happy Flutes", creator="Tomasz Kucza / magory.games", source="happy_flutes_oga.mp3", license="CC BY 3.0", license_url="https://creativecommons.org/licenses/by/3.0/", page="https://opengameart.org/content/happy-flutes-for-fantasy-setting", loop_offset_seconds=0.0, mode="full_cadence", expected_sha256="40cb712d9b0c1b6ba8c02338f845790252ea19214c3d0777e221a0024b116b7d"),
 dict(id="windpass_gallery", title="The World At Your Door", creator="Jonathan Shaw (www.jshaw.co.uk)", source="world-original/The World At Your Door MP3.mp3", license="CC BY 3.0", license_url="https://creativecommons.org/licenses/by/3.0/", page="https://opengameart.org/content/the-world-at-your-door-rpg-orchestral-essentials-overworld-music", loop_offset_seconds=0.0, mode="authored_cycle", authored_cycle_samples=3293392, expected_sha256="e9de1adfaf385d003ae3e281bd1d7158e0d8c127964177daf8eea75a072eaa64")
]
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def run(a,**kw):return subprocess.run(a,check=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE,**kw)
def decode(p):return np.frombuffer(run(['ffmpeg','-v','error','-i',str(p),'-vn','-ar',str(SR),'-ac','2','-f','f32le','pipe:1']).stdout,dtype='<f4').reshape(-1,2).copy()
def raw_args():return ['-f','f32le','-ar',str(SR),'-ac','2','-i','pipe:0']
def loudness(x):
 r=run(['ffmpeg','-hide_banner',*raw_args(),'-af','loudnorm=I=-22:TP=-2:LRA=11:print_format=json','-f','null','-'],input=x.astype('<f4').tobytes())
 s=r.stderr.decode();d=json.loads(s[s.rfind('{'):s.rfind('}')+1]);return {k:float(v) if v.replace('.','',1).replace('-','',1).isdigit() else v for k,v in d.items()}
def boundary_repair(x, prior, seconds=.020):
 # Last samples approach the actual source preceding loop start, not a silence fade.
 n=round(seconds*SR);w=np.sin(np.linspace(0,math.pi/2,n))**2
 x[-n:]=x[-n:]*(1-w[:,None])+prior[-n:]*w[:,None]
 return x

def encode(x,path,t,codec='libvorbis'):
 cmd=['ffmpeg','-hide_banner','-loglevel','error','-y',*raw_args(),'-map_metadata','-1','-fflags','+bitexact','-flags:a','+bitexact','-c:a',codec]
 cmd+=['-q:a','6'] if codec=='libvorbis' else ['-b:a','192k']
 cmd+=['-metadata','title='+t['title'],'-metadata','artist='+t['creator'],'-metadata','copyright='+t['license']+'; '+t['license_url'],'-metadata','comment=Game edit: scalar loudness alignment and documented loop preparation; source '+t['page'],str(path)]
 run(cmd,input=x.astype('<f4').tobytes())

def main():
 a=argparse.ArgumentParser();a.add_argument('--root',type=Path,required=True,help='Local preparation directory containing sources/');args=a.parse_args();root=args.root
 out=root/'delivery/godot/assets/audio/licensed_wind_v281';out.mkdir(parents=True,exist_ok=True)
 previews=root/'loop_previews';previews.mkdir(exist_ok=True)
 results=[]
 for t0 in TRACKS:
  t=dict(t0);src=root/'sources'/t['source'];source_sha=sha(src)
  if t.get('expected_sha256'): assert source_sha==t['expected_sha256'],t['id']+' source hash mismatch'
  x=decode(src);source_peak=float(np.max(np.abs(x)));source_frames=len(x);offset=round(t['loop_offset_seconds']*SR)
  changes=['Decoded original source to float32 stereo 44100 Hz; no integer clipping before attenuation.']
  if t['mode']=='authored_cycle':
   lag=t['authored_cycle_samples'];x=boundary_repair(x[lag:2*lag].copy(),x[lag-882:lag]);changes.append(f'Extracted second existing authored cycle, source samples {lag}..{2*lag-1}; final 20 ms blended to original pre-loop audio.')
  elif t['mode']=='intro_then_main':
   x=boundary_repair(x,x[offset-882:offset].copy());changes.append('Preserved 76.8 s composition and introduction; playback wraps from 76.8 s to 25.6 s. Final 20 ms blended to original audio immediately preceding 25.6 s.')
  else:
   # Both recordings end in a quiet cadence, not a score-proven continuous bar loop.
   # Preserve all notes, original timing and natural silence; smooth only terminal 5ms.
   n=round(.005*SR);x[-n:]*=np.cos(np.linspace(0,math.pi/2,n))[:,None]**2
   changes.append('Preserved entire composition, cadence, timing and natural tail/pause; final 5 ms fade to zero for whole-piece restart. No claim of musically seamless bar loop.')
  measured=loudness(x);gain=min(TARGET_I-measured['input_i'],MAX_TP-measured['input_tp']);x*=10**(gain/20)
  path=out/(t['id']+'.ogg');encode(x,path,t)
  y=decode(path);final=loudness(y)
  # One small global correction if the lossy encoder creates a significant overshoot.
  correction=min(TARGET_I-final['input_i'],MAX_TP-final['input_tp'])
  if abs(correction)>.15:
   x*=10**(correction/20);gain+=correction;encode(x,path,t);y=decode(path);final=loudness(y)
  assert len(y)==len(x),(t['id'],len(y),len(x))
  jump=float(np.max(np.abs(y[offset]-y[-1])));steps=np.abs(np.diff(y,axis=0));p999=float(np.percentile(steps,99.9))
  boundary=np.concatenate([y[-6*SR:],y[offset:offset+6*SR]])
  # Preview only: outer-edge fades do not modify delivered loop assets.
  n=round(.010*SR);boundary[:n]*=np.linspace(0,1,n)[:,None];boundary[-n:]*=np.linspace(1,0,n)[:,None]
  preview=previews/(t['id']+'_loop_join_12s.mp3');encode(boundary,preview,t,codec='libmp3lame')
  changes.extend([f'Applied constant gain {gain:.6f} dB, target {TARGET_I} LUFS, true-peak ceiling {MAX_TP} dBTP; no dynamic compressor/limiter.', 'Encoded Ogg Vorbis quality 6 stereo 44100 Hz; original MP3 sources remain MP3-limited.'])
  rec={**t,'source_sha256':source_sha,'source_duration_seconds':source_frames/SR,'source_decoded_sample_peak':source_peak,'duration_seconds':len(y)/SR,'frames':len(y),'sample_rate':SR,'channels':2,'path':'res://assets/audio/licensed_wind_v281/'+path.name,'sha256':sha(path),'bytes':path.stat().st_size,'gain_db':gain,'measured_lufs':final['input_i'],'measured_true_peak_db':final['input_tp'],'loudness_range_lu':final['input_lra'],'decoded_max_sample':float(np.max(np.abs(y))),'loop_boundary_jump':jump,'within_track_step_p999':p999,'seam_jump_below_p999':jump<=p999,'changes':changes,'subjective_listening_verified':False,'loop_preview':str(preview.relative_to(root))}
  assert final['input_tp']<=-1.8,t['id']+' true peak'
  assert abs(final['input_i']-TARGET_I)<.25,t['id']+' loudness'
  assert jump<=p999,t['id']+' boundary discontinuity larger than ordinary track sample steps'
  results.append(rec);print(json.dumps({k:rec[k] for k in ['id','duration_seconds','measured_lufs','measured_true_peak_db','loop_boundary_jump','seam_jump_below_p999']},ensure_ascii=False),flush=True)
 (out/'manifest.json').write_text(json.dumps(results,ensure_ascii=False,indent=2)+'\n')
 (root/'TECHNICAL_VERIFICATION.json').write_text(json.dumps({'ffmpeg':run(['ffmpeg','-version']).stdout.decode().splitlines()[0],'checks':'File decoding, frame count, loudness, true peak and boundary jump only. No game execution; no subjective audition.','tracks':results},ensure_ascii=False,indent=2)+'\n')
if __name__=='__main__': main()
