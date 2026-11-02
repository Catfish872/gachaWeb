#!/usr/bin/env python3
"""Bounded asset checks, not a game suite. Writes measurements and a 24s preview."""
import json,subprocess,tempfile
from pathlib import Path
import numpy as np
from scipy.io.wavfile import read,write
OUT=Path(__file__).resolve().parents[2]/'assets/audio/content_v270'
report=[]; previews=[]
for a in json.loads((OUT/'manifest.json').read_text()):
 with tempfile.TemporaryDirectory() as td:
  wav=Path(td)/'a.wav'
  subprocess.run(['ffmpeg','-v','error','-y','-i',str(OUT/(a['id']+'.ogg')),str(wav)],check=True)
  sr,x=read(wav); x=x.astype(float)/32768
  assert np.isfinite(x).all() and np.max(np.abs(x))<1
  r={'id':a['id'],'duration_seconds':len(x)/sr,'peak_dbfs':float(20*np.log10(np.max(np.abs(x)))),'rms_dbfs':float(20*np.log10(np.sqrt(np.mean(x*x)))),'finite':True,'clipped':False}
  if a['loop']:
   assert 60<=len(x)/sr<=90
   seam=float(np.max(np.abs(x[0]-x[-1]))); typical=float(np.percentile(np.abs(np.diff(x,axis=0)),99.9))
   assert seam<typical, (a['id'],seam,typical)
   r.update(loop_boundary_jump=seam,within_track_99_9_percentile_step=typical,seam_pass=seam<typical)
   proc=subprocess.run(['ffmpeg','-hide_banner','-i',str(OUT/(a['id']+'.ogg')),'-af','loudnorm=print_format=json','-f','null','-'],capture_output=True,text=True,check=True)
   data=json.loads(proc.stderr[proc.stderr.rfind('{'):proc.stderr.rfind('}')+1]); r['integrated_lufs']=float(data['input_i']); r['true_peak_dbtp']=float(data['input_tp'])
   snippet=x[sr*12:sr*20].copy(); fade=np.linspace(0,1,int(sr*.08)); snippet[:len(fade)]*=fade[:,None]; snippet[-len(fade):]*=fade[::-1,None]; previews.append(snippet)
  report.append(r)
(OUT/'verification.json').write_text(json.dumps({'subjective_listening_verified':False,'checks':report},indent=2)+'\n')
write('/tmp/lantern-v270-preview.wav',44100,(np.concatenate(previews)*32767).astype(np.int16))
print(json.dumps(report,indent=2))
