#!/usr/bin/env python3
"""Build user-selected thunder music from verified local originals. No network/export."""
import json
from pathlib import Path
import numpy as np
from build_licensed_wind_audio import decode,sha,loudness,encode,SR
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]
SRC=HERE/'thunder_selected_sources'
OUT=ROOT/'assets/audio/content_v290'
def main():
 from restore_thunder_sources import restore
 restore(SRC)
 results=[]
 for source in json.loads((SRC/'sources.json').read_text()):
  t=dict(source);assert sha(SRC/t['source'])==t['expected_source_sha256']
  x=decode(SRC/t['source']);frames=len(x)
  # Preserve authored full loops and musical timing. Remove only sample-edge residuals.
  n=round(.005*SR);x[:n]*=np.sin(np.linspace(0,np.pi/2,n))[:,None]**2;x[-n:]*=np.cos(np.linspace(0,np.pi/2,n))[:,None]**2
  m=loudness(x);gain=min(-22-m['input_i'],-2.1-m['input_tp']);x*=10**(gain/20)
  dest=OUT/(t['id']+'.ogg');encode(x,dest,t);y=decode(dest);final=loudness(y)
  correction=min(-22-final['input_i'],-2.1-final['input_tp'])
  if abs(correction)>.1:
   x*=10**(correction/20);gain+=correction;encode(x,dest,t);y=decode(dest);final=loudness(y)
  jump=float(np.max(np.abs(y[0]-y[-1])));p999=float(np.percentile(np.abs(np.diff(y,axis=0)),99.9))
  rec={k:v for k,v in t.items() if k not in ['files','sample_file','sample_sha256','sample_duration_seconds','sample_changes','audition_source','proposed_context','selection_reason_inferred','status']}
  rec.update(path='res://assets/audio/content_v290/'+dest.name,source_sha256=sha(SRC/t['source']),sha256=sha(dest),bytes=dest.stat().st_size,frames=len(y),duration_seconds=len(y)/SR,sample_rate=SR,channels=2,gain_db=gain,measured_lufs=final['input_i'],measured_true_peak_db=final['input_tp'],loop_boundary_jump=jump,within_track_step_p999=p999,seam_jump_below_p999=jump<=p999,mode='full_authored_loop',subjective_listening_verified=False,user_selection_confirmed=True,changes=['Retained complete selected authored loop and original tempo/instrumentation.','Applied 5 ms cosine/sine fades only at file edges to suppress sample discontinuities.',f'Applied constant gain {gain:.6f} dB targeting -22 LUFS and -2.1 dBTP ceiling; no dynamic compression.','Encoded stereo 44100 Hz Ogg Vorbis quality 6.'])
  assert len(y)==frames
  assert final['input_tp']<=-2
  assert abs(final['input_i']+22)<.25
  assert jump<=p999
  results.append(rec);print(json.dumps({k:rec[k] for k in ['id','duration_seconds','measured_lufs','measured_true_peak_db','seam_jump_below_p999']}),flush=True)
 (OUT/'manifest.json').write_text(json.dumps(results,ensure_ascii=False,indent=2)+'\n')
 credits=['Thunder music: selected by user','CC BY tracks require artist/title/license/source and modification credit when distributed.','CC0 attribution is retained voluntarily.','']
 for t in results:
  credits += [t['id']+'.ogg',t['title']+' — '+t['creator'],t['license'],t['license_url'],t['page'],t['attribution'],'Original download: '+t['download'],'Source SHA-256: '+t['source_sha256'],'Changes: '+' '.join(t['changes']),'']
 (OUT/'LICENSES.txt').write_text('\n'.join(credits)+'\n')
 (SRC/'verification.json').write_text(json.dumps({'scope':'Source checksums, decode, frame count, loudness, true peak, seam. User selection confirmed; no claim of assistant subjective audition. No packaging/publication.','tracks':results},ensure_ascii=False,indent=2)+'\n')
if __name__=='__main__':main()
