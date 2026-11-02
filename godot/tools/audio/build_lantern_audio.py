#!/usr/bin/env python3
"""Original score + deterministic instrument synthesis. Python/numpy/scipy + ffmpeg.
No sampled recordings or external melodies. Run from any cwd; writes only v270 audio.
"""
import json, math, subprocess, tempfile
from pathlib import Path
import numpy as np
from scipy.signal import butter, sosfilt
from scipy.io.wavfile import write, read
SR=32000
OUT=Path(__file__).resolve().parents[2]/'assets/audio/content_v270'
RNG=np.random.default_rng(270)
def hz(m): return 440*2**((m-69)/12)
def envelope(t,d,a=.015,r=.2): return np.minimum(t/a,1)*np.minimum((d-t)/r,1).clip(0,1)
def tone(m,d,kind):
 t=np.arange(int(SR*d))/SR; f=hz(m)
 if kind=='pluck':
  y=sum(np.sin(2*np.pi*f*k*t+.1*k)*np.exp(-t*(1.8+k*.65))/(k**1.6) for k in range(1,9)); e=envelope(t,d,.004,.14)
 elif kind=='bell':
  y=sum(np.sin(2*np.pi*f*k*t)*np.exp(-t*(1.1+i*.6))*a for i,(k,a) in enumerate([(1,1),(2.006,.27),(3.98,.09),(5.02,.03)])); e=envelope(t,d,.008,.2)
 elif kind=='string':
  y=sum((np.sin(2*np.pi*f*k*t+.012*k*np.sin(t*31))+ .45*np.sin(2*np.pi*f*k*1.0017*t))/(k**2) for k in range(1,7)); e=envelope(t,d,.45,.6)
 else:
  y=np.sin(2*np.pi*f*t)+.12*np.sin(2*np.pi*f*2*t); e=envelope(t,d,.03,.3)
 return y*e*.5

def add(buf,x,at,gain=1,pan=0):
 start=int(at*SR); ids=(np.arange(len(x))+start)%len(buf)
 np.add.at(buf[:,0],ids,x*gain*np.sqrt((1-pan)/2)); np.add.at(buf[:,1],ids,x*gain*np.sqrt((1+pan)/2))

def drum(d=.35,high=False):
 t=np.arange(int(d*SR))/SR
 if high: return sosfilt(butter(2,2500,fs=SR,btype='highpass',output='sos'),RNG.normal(0,1,len(t)))*np.exp(-t*45)*.12
 return np.sin(2*np.pi*(49*t+15*(1-np.exp(-t*25))/25))*np.exp(-t*13)*envelope(t,d,.003,.08)

# D minor with modal sixth: an eight-bar arc, not random note selection.
CHORDS=[(50,57,62,65),(46,53,58,62),(48,55,60,64),(45,52,57,61),
        (50,57,62,65),(53,60,65,69),(55,62,67,70),(45,52,57,61)]
MELODY=[[(0,74,1),(1.5,77,.5),(2,76,1),(3,69,.75)],[(.5,74,1),(2,70,1.5)],
        [(0,72,1.5),(2,76,.75),(3,79,.75)],[(0,73,1),(1.5,76,.5),(2.5,69,1)],
        [(0,77,1),(1.5,81,.5),(2,79,1),(3,77,.75)],[(.5,76,.75),(1.5,72,.75),(3,69,.75)],
        [(0,74,.75),(1,77,.75),(2,79,1.5)],[(0,76,1),(1.5,73,.75),(3,69,.75)]]

def music(tempo,bars,mode):
 beat=60/tempo; dur=bars*4*beat; b=np.zeros((round(dur*SR),2))
 for bar in range(bars):
  start=bar*4*beat; chord=CHORDS[bar%8]; section=bar//8
  for k,m in enumerate(chord): add(b,tone(m,4.8*beat,'string'),start,.10 if mode!='core' else .14,(k-1.5)*.3)
  add(b,tone(chord[0]-12,3.8*beat,'bass'),start,.24,0)
  if mode=='core': add(b,tone(chord[0]-12,1.6*beat,'bass'),start+2*beat,.16)
  arp=[0,2,1,3,2,1,3,2] if mode!='road' else [0,2,1,3]
  for i,k in enumerate(arp):
   add(b,tone(chord[k]+12,2.3*beat,'pluck'),start+i*4*beat/len(arp),.21 if mode=='road' else .18,(-1 if i%2 else 1)*.35)
  # Sparse first phrase leaves room for voice/UI; later phrases answer it.
  if section>0 or bar%2==0:
   for off,m,length in MELODY[bar%8]:
    octave=0 if section%3!=2 else -12
    add(b,tone(m+octave,(length+1)*beat,'bell' if mode=='road' else 'pluck'),start+off*beat,.18 if mode=='road' else .24,.12)
  if bar%4==0: add(b,tone(86 if bar%8==0 else 81,3,'bell'),start+3.5*beat,.09,-.5)
  if mode!='road':
   for off in ([0,2] if mode=='hall' else [0,1.5,2,3.5]): add(b,drum(),start+off*beat,.075 if mode=='hall' else .17,-.08)
   for off in [1,3]: add(b,drum(.12,True),start+off*beat,.11 if mode=='hall' else .22,.4)
  if mode=='core' and bar%4==3: add(b,drum(.5),start+3.75*beat,.1)
 # Circular room echoes retain tails across the seam, unlike a silence fade.
 dry=b.copy()
 for delay,g in [(.113,.13),(.229,.10),(.367,.075),(.593,.045),(.887,.025)]: b+=np.roll(dry,int(delay*SR),axis=0)[:,::-1]*g
 b-=b.mean(axis=0); b*=10**(-24/20)/np.sqrt(np.mean(b*b)); return b

def sfx(kind):
 durations={'wick_ignite':.28,'chain_swing':.32,'thread_gather':.44,'ember_detonate':.24,'selin_basic':.26,'selin_skill':.48,'selin_ultimate':1.12,'lantern_reveal':.7}
 d=durations[kind]; t=np.arange(int(d*SR))/SR; b=np.zeros((len(t),2)); noise=RNG.normal(0,1,len(t))
 soft=sosfilt(butter(2,[300,4500],fs=SR,btype='bandpass',output='sos'),noise)
 if kind in ['wick_ignite','selin_basic','ember_detonate']:
  y=soft*np.exp(-t*18)*.22+np.sin(2*np.pi*(150*t-50*t*t))*np.exp(-t*24)*.2
  if kind=='wick_ignite': y+=np.sin(2*np.pi*1174*t)*np.exp(-t*22)*.08
 elif kind=='chain_swing':
  y=soft*np.sin(np.pi*t/d)**2*.08
  for off,f in [(0,1800),(.045,2300),(.11,1430)]:
   q=np.maximum(t-off,0); y+=np.sin(2*np.pi*f*q)*np.exp(-q*50)*(t>=off)*.12
 elif kind in ['thread_gather','selin_skill']:
  y=soft*np.sin(np.pi*t/d)**2*.07+np.sin(2*np.pi*(360*t+700*t*t))*np.sin(np.pi*t/d)**2*.09
  y+=np.sin(2*np.pi*880*t)*np.exp(-t*9)*.045
 else:
  y=soft*np.exp(-t*12)*.09
  for i,f in enumerate([293.665,440,587.33,880]): y+=np.sin(2*np.pi*f*t)*np.exp(-t*(4+i))*envelope(t,d,.025,.15)*(.09/(i+1))
  if kind=='selin_ultimate': y+=np.sin(2*np.pi*(70*t+20*(1-np.exp(-t*12))/12))*np.exp(-t*9)*.17
 y*=envelope(t,d,.004,.035)
 b[:,0]=y; b[:,1]=y*.96
 # Transients deliberately below established UI peaks; mix gains provided separately.
 b*=.32/max(np.max(np.abs(b)),1e-9); return b

def encode(name,b,meta):
 path=OUT/(name+'.ogg')
 with tempfile.TemporaryDirectory() as tmp:
  w=Path(tmp)/'in.wav'; write(w,SR,(np.clip(b,-1,1)*32767).astype(np.int16))
  subprocess.run(['ffmpeg','-v','error','-y','-i',str(w),'-ar','44100','-c:a','libvorbis','-q:a','5',str(path)],check=True)
  dec=Path(tmp)/'decoded.wav'; subprocess.run(['ffmpeg','-v','error','-y','-i',str(path),str(dec)],check=True)
  sr,x=read(dec); x=x.astype(float)/32768
  meta.update(duration_seconds=round(len(x)/sr,6),peak_dbfs=round(20*np.log10(np.max(np.abs(x))),2),rms_dbfs=round(20*np.log10(np.sqrt(np.mean(x*x))),2),boundary_jump=round(float(np.max(np.abs(x[0]-x[-1]))),7))
 meta.update(id=name,path='res://assets/audio/content_v270/'+name+'.ogg',source='Original deterministic score and procedural synthesis; no external samples',author='OpenAI assistant for gachaWeb',subjective_listening_verified=False)
 if meta['loop']: meta.update(loop_start_seconds=0,loop_end_seconds=meta['duration_seconds'])
 return meta

def main():
 OUT.mkdir(parents=True,exist_ok=True); manifest=[]
 for name,title,bpm,bars,mode in [('lantern_road','烬金灯途',80,24,'road'),('lantern_hall','铜廊流火',96,28,'hall'),('lantern_core','炉心长明',112,32,'core')]:
  manifest.append(encode(name,music(bpm,bars,mode),dict(title=title,tempo_bpm=bpm,key='D minor (modal colour)',meter='4/4',bars=bars,loop=True)))
 for name in ['wick_ignite','chain_swing','thread_gather','ember_detonate','selin_basic','selin_skill','selin_ultimate','lantern_reveal']:
  manifest.append(encode(name,sfx(name),dict(title=name,loop=False,recommended_gain_db=-10 if name=='ember_detonate' else -3,max_voices=1 if name=='ember_detonate' else 2)))
 (OUT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
 print(json.dumps(manifest,ensure_ascii=False,indent=2))
if __name__=='__main__': main()
