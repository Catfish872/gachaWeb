#!/usr/bin/env python3
"""New wind-chapter score and synthesis, authored for gachaWeb in November 2026.
All notes and timbres are defined here. No prior audio, recordings, soundfonts or
external sample libraries are used. Dependency: numpy, scipy, ffmpeg/libvorbis.
"""
from functools import lru_cache
import argparse
import hashlib
import json
import math
from pathlib import Path
import subprocess
import tempfile
import numpy as np
from scipy.io.wavfile import write
from scipy.signal import butter, sosfilt

SR = 32000
OUT = Path(__file__).resolve().parents[2] / 'assets/audio/content_v280'
RNG = np.random.default_rng(280)

def hz(midi): return 440.0 * 2 ** ((midi - 69) / 12)
def db(value): return 10 ** (value / 20)
def shape(t, duration, attack=.03, release=.2):
    return np.minimum(t / attack, 1).clip(0, 1) ** .7 * np.minimum((duration - t) / release, 1).clip(0, 1) ** 1.5

@lru_cache(maxsize=256)
def note(midi, duration, kind):
    t = np.arange(round(SR * duration), dtype=np.float64) / SR
    frequency = hz(midi)
    # Delayed vibrato and a brief breath transient articulate a wind instrument.
    vibrato = .0025 * (1 - np.exp(-np.maximum(t - .22, 0) * 4)) * np.sin(2 * np.pi * 5.1 * t)
    phase = 2 * np.pi * frequency * (t + vibrato / (2 * np.pi * 5.1))
    if kind == 'flute':
        y = np.sin(phase) + .19 * np.sin(phase * 2 + .15) + .055 * np.sin(phase * 3)
        noise = np.random.default_rng(28000 + midi).normal(0, 1, len(t))
        breath = sosfilt(butter(2, [900, 4600], fs=SR, btype='bandpass', output='sos'), noise)
        y += breath * (.028 + .05 * np.exp(-t * 30))
        y *= shape(t, duration, .055, min(.21, duration / 3))
    elif kind == 'reed':
        y = sum(np.sin(phase * k + .08 * k) * math.exp(-k * .26) / k ** .55 for k in range(1, 10))
        y *= shape(t, duration, .035, .15) * (1 - .1 * np.exp(-t * 9))
    elif kind == 'soft_keys':
        # Keep the existing keyboard-like accompaniment unchanged. The lead
        # uses its struck-string model with a gentler attack, no breath/vibrato,
        # and fewer high partials. MIDI pitches and timing stay exactly intact.
        y = np.zeros_like(t)
        for k in range(1, 11):
            partial = frequency * k
            if partial >= SR * .45:
                continue
            colour = math.exp(-((partial / 3800) ** 2))
            y += np.sin(2 * np.pi * partial * t + .2 * k) * np.exp(-t * (1.9 + k * .65)) * colour / k ** 1.5
        y *= shape(t, duration, .012, .16)
    elif kind == 'harp':
        y = sum(np.sin(2 * np.pi * frequency * k * t + .2 * k) * np.exp(-t * (1.9 + k * .6)) / k ** 1.25 for k in range(1, 11))
        y *= shape(t, duration, .003, .12)
    elif kind == 'mallet':
        y = sum(a * np.sin(2 * np.pi * frequency * ratio * t) * np.exp(-t * decay) for ratio, a, decay in [(1, 1, 3), (2.01, .23, 7), (3.94, .065, 13)])
        y *= shape(t, duration, .006, .14)
    elif kind == 'string':
        y = np.zeros_like(t)
        for k in range(1, 8):
            y += (np.sin(phase * k * .9987 + .27) + np.sin(phase * k * 1.0013 - .19)) * .5 / k ** 1.6
        y *= shape(t, duration, .35, .6)
    else:
        y = np.sin(phase) + .18 * np.sin(phase * 2) + .04 * np.sin(phase * 3)
        y *= shape(t, duration, .025, .24)
    return (y * .5).astype(np.float32)

def add(buffer, signal, at, gain, pan=0):
    start = round(at * SR) % len(buffer)
    channels = np.array([math.sqrt((1 - pan) / 2), math.sqrt((1 + pan) / 2)], dtype=np.float32)
    sample = signal[:, None] * channels[None, :] * gain
    end = min(len(sample), len(buffer) - start)
    buffer[start:start + end] += sample[:end]
    if end < len(sample): buffer[:len(sample) - end] += sample[end:]

def drum(kind):
    duration = .38 if kind == 'frame' else .18
    t = np.arange(round(duration * SR)) / SR
    noise = RNG.normal(0, 1, len(t))
    if kind == 'frame':
        phase = 2 * np.pi * (74 * t + 38 * (1 - np.exp(-t * 20)) / 20)
        y = np.sin(phase) * np.exp(-t * 14) + .12 * np.sin(2 * np.pi * 167 * t) * np.exp(-t * 20)
        y += sosfilt(butter(1, 1800, fs=SR, output='sos'), noise) * np.exp(-t * 30) * .08
    elif kind == 'shaker':
        y = sosfilt(butter(2, [3000, 9500], fs=SR, btype='bandpass', output='sos'), noise) * np.exp(-t * 48) * .23
    else:
        y = (np.sin(2 * np.pi * 1130 * t) + .32 * np.sin(2 * np.pi * 2410 * t)) * np.exp(-t * 50) * .35
    return (y * shape(t, duration, .002, .06)).astype(np.float32)

# Each melody is an authored eight-bar phrase. Tuples are quarter-note offset,
# MIDI pitch and duration in quarter notes. Later sections contain an answer and
# a thinner reprise; the score is not a random arpeggio generator.
ROAD = [
 [(0,76,1), (1.5,78,.5), (2,79,.8)], [(0,83,1.4),(1.5,81,.5),(2,78,.8)],
 [(.5,76,1),(2,74,.8)], [(0,73,.5),(.75,74,.5),(1.5,78,1.2)],
 [(0,79,1),(1.5,83,.5),(2,86,.8)], [(0,85,1.4),(1.5,81,.5),(2,78,.8)],
 [(.5,79,1),(2,78,.6)], [(0,74,1),(1.5,71,1.1)]]
GALLERY = [
 [(0,78,.75),(1,81,.5),(2,85,.75)], [(.5,83,1),(2,81,.75)],
 [(0,79,1.5),(2,78,.75)], [(0,76,.5),(1,78,.5),(2,74,.75)],
 [(0,78,.75),(1,81,.5),(2,88,.75)], [(.5,86,1),(2,85,.75)],
 [(0,83,1),(1.5,81,.75)], [(0,78,1.2),(1.5,76,1.2)]]
CORE = [
 [(0,76,.7),(1,78,.4),(1.5,79,.4),(2.5,83,1)],
 [(0,81,1),(1.5,79,.5),(2.5,78,1)],
 [(0,74,.7),(1,78,.5),(2,81,.7),(3,79,.7)], [(0,78,1.5),(2,74,.7),(3,71,.7)],
 [(0,76,.7),(1,79,.4),(1.5,83,.4),(2.5,86,1)],
 [(0,85,1),(1.5,83,.5),(2.5,81,1)],
 [(0,79,.7),(1,78,.5),(2,76,.7),(3,74,.7)], [(0,73,1),(1.5,74,.5),(2.5,78,1)]]
TIYA = [
 [(0,79,.5),(.75,83,.5),(1.5,86,.5),(2.25,83,.5)],
 [(0,81,1), (1.5,79,.5),(2.25,78,.5)],
 [(0,76,.5),(.75,79,.5),(1.5,83,1.1)], [(0,81,1.25),(1.5,78,1.1)],
 [(0,79,.5),(.75,83,.5),(1.5,88,.5),(2.25,86,.5)],
 [(0,85,1),(1.5,83,.5),(2.25,81,.5)],
 [(0,79,.5),(.75,78,.5),(1.5,76,1.1)],[(0,74,1.25),(1.5,78,1.1)]]
LUMI = [
 [(0,78,1.5),(2,81,1.5)],[(.5,83,1),(2,81,1.5)],
 [(0,79,1.5),(2,78,1.5)],[(0,76,2.5),(3,74,.5)],
 [(0,78,1.5),(2,85,1.5)],[(.5,86,1),(2,83,1.5)],
 [(0,81,1),(1.5,79,1),(3,78,.5)],[(0,76,1.5),(2,74,1.5)]]

HARMONY = {
 'road': [(52,59,66,67),(50,57,62,66),(45,57,61,64),(47,54,62,66),(52,59,62,67),(55,59,62,66),(45,57,61,64),(47,54,61,66)],
 'gallery': [(50,57,64,66),(54,57,61,66),(55,59,62,66),(52,59,62,67),(50,57,61,66),(45,57,61,64),(55,59,62,66),(47,54,61,66)],
 'core': [(40,52,59,67),(43,55,62,71),(38,50,57,66),(47,54,59,66),(40,52,59,67),(45,57,61,69),(50,57,62,66),(47,54,61,66)],
 'tiya': [(55,62,67,71),(50,57,62,66),(52,59,64,67),(47,54,62,66),(55,62,67,71),(45,57,61,64),(52,59,64,67),(50,57,62,66)],
 'lumi': [(47,54,62,66),(50,57,62,66),(55,59,62,66),(52,59,62,67),(47,54,61,66),(45,57,61,64),(55,59,62,66),(50,57,62,66)]}

SCORES = [
 ('windpass_road','风过千层谷','road',80,32,3,'6/8',ROAD,'soft_keys','E Dorian'),
 ('windpass_gallery','回廊中的风信','gallery',84,32,3,'6/8',GALLERY,'mallet','D major / E Dorian'),
 ('windpass_core','逆风之翼','core',112,32,4,'4/4',CORE,'soft_keys','E minor / Dorian'),
 ('tiya_reveal','缇雅 · 越过山脊','tiya',78,32,3,'6/8',TIYA,'soft_keys','G major / E Dorian'),
 ('lumi_reveal','露弥 · 风把话带回来','lumi',104,32,4,'4/4',LUMI,'soft_keys','B minor / D major')]

def score(bpm, bars, quarter_beats, melody, lead, mode):
    beat = 60 / bpm
    b = np.zeros((round(bars * quarter_beats * beat * SR), 2), dtype=np.float32)
    for bar in range(bars):
        chord = HARMONY[mode][bar % 8]; at = bar * quarter_beats * beat
        section = bar // 8
        # A, A with countermelody, B (register exchange), quiet A return.
        density = [.88, 1, 1.12, .87][section]
        for j, pitch in enumerate(chord[1:]):
            add(b, note(pitch, round((quarter_beats + .6) * beat, 4), 'string'), at, .064 * density, [-.5,.12,.5][j])
        add(b, note(chord[0] - (0 if mode == 'core' else 12), round((quarter_beats - .15) * beat, 4), 'bass'), at, .17, 0)
        pattern = [0,2,1,3,2,1] if quarter_beats == 3 else [0,2,1,3,2,1,3,2]
        for i, k in enumerate(pattern):
            if section == 3 and i % 2 and bar % 4 != 3: continue
            add(b, note(chord[k] + (12 if k == 0 else 0), round(2.1 * beat, 4), 'harp'), at + i * .5 * beat, .105 * (1 if i % 3 else 1.2), .38 * (-1 if i % 2 else 1))
        for offset, pitch, length in melody[bar % 8]:
            if section == 0 and mode == 'road' and bar % 4 == 3: continue
            register = -12 if section == 2 and mode in ('gallery','lumi') else 0
            if section == 2 and mode == 'core' and bar % 2 == 0: register = 12
            lead_gain = .185 if lead == 'soft_keys' else .235
            add(b, note(pitch + register, round(length * beat, 4), lead), at + offset * beat, lead_gain * density, -.12)
        if section in (1,2) and bar % 2 == 1:
            # Companion replies after the lead; separate contour and lower register.
            for offset,pitch in [(quarter_beats - 1.2,chord[2]),(quarter_beats - .5,chord[1])]:
                add(b, note(pitch + 12, round(.75 * beat,4), 'mallet' if mode != 'gallery' else 'soft_keys'), at + offset * beat, .10,.45)
        if mode in ('core','tiya','gallery') or (mode == 'road' and section == 2):
            offsets = [0,1.5] if quarter_beats == 3 else [0,1.5,2,3.5]
            for off in offsets:
                add(b, drum('frame'), at + off * beat, .11 if mode == 'core' else .045, -.08)
            for off in np.arange(.5,quarter_beats,.5):
                add(b, drum('shaker'),at+off*beat,.075 if mode == 'core' else .035,.5)
        if mode == 'lumi' and bar % 2 == 1:
            add(b, note(chord[-1] + 12,round(2 * beat,4),'mallet'),at+2.5*beat,.04,.55)
        if mode == 'core' and bar % 8 == 7:
            for j in range(4): add(b,drum('frame'),at+(3+j*.25)*beat,.045+j*.012,-.2+j*.1)
    # Circular diffuse room: tails wrap over the barline; no silence seam.
    dry = b.copy()
    for delay,level in [(.071,.07),(.127,.095),(.193,.08),(.283,.07),(.419,.05),(.613,.038),(.887,.02)]:
        b += np.roll(dry,round(delay*SR),axis=0)[:,::-1]*level
    # Extremely quiet, periodic band-limited wind, rather than a recorded loop.
    t=np.arange(len(b))/SR; wind=np.zeros(len(b),dtype=np.float32)
    for i in range(48):
        harmonic=round((280+i*31.3)*len(b)/SR)
        wind += np.sin(2*np.pi*harmonic*np.arange(len(b))/len(b)+i*1.73).astype(np.float32)*.00006
    b[:,0]+=wind; b[:,1]+=np.roll(wind,1127)
    b-=b.mean(axis=0); b*=db(-25)/max(float(np.sqrt(np.mean(b*b))),1e-9)
    return b

SFX_DURATIONS = {'tiya_basic':.24,'tiya_skill':.45,'tiya_ultimate':1.15,
 'lumi_basic':.26,'lumi_skill':.48,'lumi_ultimate':1.25,'wind_pierce':.18,
 'wind_field_open':.44,'wind_field_pulse':.25,'wind_field_release':.38,
 'roc_warning':.65,'roc_gust':.46,'wind_mechanism_turn':.42,'windpass_reveal':1.1}

def effect(name,duration):
    t=np.arange(round(duration*SR))/SR
    rng=np.random.default_rng(280+sum(ord(c) for c in name))
    noise=sosfilt(butter(2,[430,5300],fs=SR,btype='bandpass',output='sos'),rng.normal(0,1,len(t)))
    y=np.zeros(len(t)); sweep=np.sin(np.pi*t/duration)**1.5
    if name.startswith('tiya') or name=='wind_pierce':
        y=noise*sweep*.14+np.sin(2*np.pi*(740*t+950*t*t))*sweep*.08
        if name=='tiya_ultimate':
            y+=np.sin(2*np.pi*(94*t+44*t*t))*np.exp(-t*6)*.12
            for i,midi in enumerate((76,83,88)):
                q=t-i*.07; y+=np.sin(2*np.pi*hz(midi)*q)*np.exp(-np.maximum(q,0)*7)*(q>=0)*.055
    elif name.startswith('lumi') or name in ('wind_field_open','windpass_reveal'):
        y=noise*sweep*.045
        for i,midi in enumerate((74,78,81,86)):
            q=t-i*.035; y+=np.sin(2*np.pi*hz(midi)*q)*np.exp(-np.maximum(q,0)*(5+i))*(q>=0)*.09/(i+1)
        if name=='lumi_ultimate': y+=np.sin(2*np.pi*(180*t+90*t*t))*sweep*.07
    elif name=='roc_warning':
        y=np.sin(2*np.pi*(240*t+160*t*t+7*np.sin(t*12)))*sweep*.1+noise*sweep*.1
    elif name=='roc_gust':
        y=noise*sweep*.2+np.sin(2*np.pi*(92*t-35*t*t))*np.exp(-t*9)*.15
    elif name=='wind_mechanism_turn':
        y=noise*sweep*.06
        for delay,freq in [(0,650),(.09,910),(.17,1270)]:
            q=t-delay; y+=np.sin(2*np.pi*freq*q)*np.exp(-np.maximum(q,0)*32)*(q>=0)*.13
    elif name=='wind_field_release':
        y=noise*np.sin(np.pi*t/duration)**2*.13+np.sin(2*np.pi*(700*t-500*t*t))*sweep*.055
    else:
        y=noise*sweep*.1+np.sin(2*np.pi*660*t)*sweep*.045
    y*=shape(t,duration,.005,.04)
    b=np.column_stack((y,np.roll(y,round(.00022*SR))*.97)).astype(np.float32)
    b*=db(-10 if name in ('wind_field_pulse','wind_pierce') else -8)/max(float(np.max(np.abs(b))),1e-9)
    return b

def analyze_loudness(path):
    p=subprocess.run(['ffmpeg','-hide_banner','-i',str(path),'-af','loudnorm=print_format=json','-f','null','-'],capture_output=True,text=True,check=True)
    return json.loads(p.stderr[p.stderr.rfind('{'):p.stderr.rfind('}')+1])

def encode(name,data,metadata):
    path=OUT/(name+'.ogg')
    with tempfile.TemporaryDirectory() as tmp:
        wav=Path(tmp)/'source.wav';write(wav,SR,data.astype(np.float32))
        gain=0.0
        if metadata['loop']:
            loud=analyze_loudness(wav)
            gain=min(-22-float(loud['input_i']),-7-float(loud['input_tp']))
        subprocess.run(['ffmpeg','-v','error','-y','-i',str(wav),'-af',f'volume={gain:.6f}dB','-ar','44100','-c:a','libvorbis','-q:a','5','-metadata',f'title={metadata["title"]}','-metadata','artist=gachaWeb original procedural score',str(path)],check=True)
    metadata.update(id=name,path=f'res://assets/audio/content_v280/{name}.ogg',sample_rate=44100,channels=2,
      duration_seconds=round(len(data)/SR,6),sha256=hashlib.sha256(path.read_bytes()).hexdigest(),bytes=path.stat().st_size,
      source='New score and procedural additive/noise synthesis in build_windpass_audio.py; no external samples or existing audio reused',
      creator='OpenAI assistant for gachaWeb',created_utc='2026-11-03',subjective_listening_verified=False)
    if metadata['loop']:metadata.update(loop_start_seconds=0,loop_end_seconds=metadata['duration_seconds'],recommended_gain_db=0)
    return metadata

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--music-only', action='store_true', help='Regenerate the five scores and preserve all existing effect bytes and metadata.')
    args = parser.parse_args()
    previous = json.loads((OUT / 'manifest.json').read_text()) if args.music_only else []
    OUT.mkdir(parents=True,exist_ok=True); manifest=[]
    for name,title,mode,bpm,bars,beats,meter,melody,lead,key in SCORES:
        manifest.append(encode(name,score(bpm,bars,beats,melody,lead,mode),dict(title=title,tempo_quarter_bpm=bpm,meter=meter,bars=bars,key=key,loop=True,lead_instrument=lead,music_mix_revision='soft-keys-v1',melody_revision='unchanged-v280')))
        print('Rendered',name,flush=True)
        note.cache_clear()
    if args.music_only:
        manifest.extend(item for item in previous if not item['loop'])
    else:
        for name,duration in SFX_DURATIONS.items():
            gain=-15 if name in ('wind_field_pulse','wind_pierce') else -9
            manifest.append(encode(name,effect(name,duration),dict(title=name,loop=False,recommended_gain_db=gain,max_voices=1 if name in ('wind_field_pulse','wind_pierce') else 2)))
    (OUT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    print(f'Completed {len(manifest)} original assets.',flush=True)
if __name__=='__main__':main()
