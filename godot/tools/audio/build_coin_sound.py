"""Original short metallic coin jingle, synthesized without external recordings.
Run directly to rebuild only assets/audio/ui/coin.ogg. No music is regenerated.
"""
from pathlib import Path
import math
import struct
import subprocess

ROOT = Path(__file__).resolve().parents[2]
SR = 44100
DURATION = 0.48

def build():
    samples = [0.0] * int(SR * DURATION)
    # Three light coin contacts, with inharmonic metal resonances rather than a UI chirp.
    for onset, pitch, gain in [(0.0, 2350, 1.0), (0.065, 2870, 0.72), (0.135, 2600, 0.52)]:
        start = int(onset * SR)
        for i in range(start, len(samples)):
            t = (i - start) / SR
            attack = min(1.0, t / 0.0007)
            ring = sum(amp * math.sin(2 * math.pi * pitch * ratio * t) * math.exp(-t / decay)
                       for ratio, amp, decay in [(1, 1, .055), (1.47, .48, .035), (2.09, .22, .022)])
            samples[i] += gain * attack * ring
    peak = max(abs(x) for x in samples)
    pcm = b''.join(struct.pack('<f', x / peak * .46 * min(1, (DURATION - i/SR)/.035)) for i, x in enumerate(samples))
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-f', 'f32le', '-ar', str(SR), '-ac', '1', '-i', '-',
                    '-c:a', 'libvorbis', '-q:a', '5', str(ROOT/'assets/audio/ui/coin.ogg')], input=pcm, check=True)

if __name__ == '__main__':
    build()
