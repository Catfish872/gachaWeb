"""Original procedural fantasy ambience and interaction sounds. No external samples.
Search loop is separately derived from the user's supplied sound, originals unchanged.
"""
import subprocess
from pathlib import Path
import numpy as np
ROOT = Path(__file__).resolve().parents[2]
SR = 44100
rng = np.random.default_rng(872)
def save(path, samples):
    samples=np.asarray(samples,dtype=np.float64)
    peak=float(np.max(np.abs(samples)))
    if peak: samples=samples/peak*.46
    subprocess.run(['ffmpeg','-v','error','-y','-f','f32le','-ar',str(SR),'-ac',str(1 if samples.ndim==1 else samples.shape[1]),'-i','-','-c:a','libvorbis','-q:a','5',str(ROOT/path)],input=samples.astype('<f4').tobytes(),check=True)
def hz(n):return 440*2**((n-69)/12)
def soundscape(combat=False):
    dur=32.;n=int(dur*SR);t=np.arange(n)/SR;out=np.zeros((n,2))
    chords=[[45,52,60,64],[41,48,57,60],[48,55,60,64],[43,50,57,62]]
    for i,notes in enumerate(chords):
        # 2s overlaps with circular indexing yield continuous loop joins.
        length=10.;u=np.arange(int(length*SR))/SR
        env=np.minimum(u/2,1)*np.minimum((length-u)/2,1)
        voice=np.zeros(len(u))
        for j,note in enumerate(notes):
            f=hz(note)
            voice+=(np.sin(2*np.pi*f*u)+.15*np.sin(2*np.pi*f*2*u))*.07/(1+j*.3)
        voice*=env*(.9+.1*np.sin(2*np.pi*u/7))
        idx=(np.arange(len(u))+int((i*8-1)*SR))%n
        out[idx,0]+=voice;out[idx,1]+=voice*(.96+.04*np.sin(2*np.pi*u/5))
    # Sparse pentatonic bell motif leaves space for the reveal sounds.
    for i,note in enumerate([76,79,83,81,79,76,74,72]):
        u=np.arange(3*SR)/SR;env=(1-np.exp(-u*25))*np.exp(-u*1.8)
        bell=(np.sin(2*np.pi*hz(note)*u)+.14*np.sin(2*np.pi*hz(note)*2*u))*env*.035
        idx=(np.arange(len(u))+int((i*4+2)*SR))%n
        out[idx,0]+=bell*(.65 if i%2 else 1);out[idx,1]+=bell*(1 if i%2 else .65)
    if combat:
        for i in range(64):
            u=np.arange(int(.27*SR))/SR
            pulse=np.sin(2*np.pi*(70*u-23*u*u))*np.exp(-u*20)*.045
            idx=(np.arange(len(u))+int(i*.5*SR))%n
            out[idx]+=pulse[:,None]
    return out
save('assets/audio/music/ruins_ambient.ogg',soundscape())
save('assets/audio/music/ruins_battle.ogg',soundscape(True))
for name,dur,f0,f1 in [('tap',.07,600,420),('equip',.22,420,840),('use',.30,520,1040),('back',.09,420,260)]:
 t=np.arange(int(dur*SR))/SR;phase=2*np.pi*(f0*t+(f1-f0)*t*t/(2*dur));env=np.sin(np.pi*t/dur)**2*np.exp(-t/dur*2)
 save('assets/audio/ui/'+name+'.ogg',np.sin(phase)*env)
from build_coin_sound import build as build_coin_sound
build_coin_sound()
print('Generated 2 original music loops and 5 interface sounds')

# Restrict searching to the low-energy transition between the opening impact
# and the later audio shared with the reward clip. Original MP3 is immutable.
subprocess.run(['ffmpeg','-v','error','-y','-ss','0.42','-t','0.30','-i',str(ROOT/'assets/audio/extraction/search.mp3'),'-af','highpass=f=350,lowpass=f=5200,afade=t=in:st=0:d=0.025,afade=t=out:st=0.275:d=0.025,volume=8','-ar','44100','-ac','1','-c:a','libvorbis','-q:a','5',str(ROOT/'assets/audio/extraction/search_loop.ogg')],check=True)
