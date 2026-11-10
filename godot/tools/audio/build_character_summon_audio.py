#!/usr/bin/env python3
"""Build the two user-selected character scores from checksum-verified previews.

Usage: python build_character_summon_audio.py --source-dir /path/to/previews
Full recordings retain their original timing and natural tail. Whole-piece
restart is intentional; these are not claimed to be seamless musical loops.
"""
import argparse
import json
from pathlib import Path
import numpy as np
from build_licensed_wind_audio import decode, sha, loudness, encode, SR

HERE = Path(__file__).resolve().parent
OUT = HERE.parents[1] / 'assets/audio/content_v293'

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source-dir', type=Path, required=True)
    args = parser.parse_args()
    sources = json.loads((HERE / 'character_summon_sources.json').read_text())
    OUT.mkdir(parents=True, exist_ok=True)
    results = []
    for source in sources:
        t = dict(source)
        src = args.source_dir / t['source']
        assert sha(src) == t['expected_source_sha256'], t['id'] + ' source hash'
        x = decode(src)
        frames = len(x)
        n = round(.005 * SR)
        x[:n] *= np.sin(np.linspace(0, np.pi / 2, n))[:, None] ** 2
        x[-n:] *= np.cos(np.linspace(0, np.pi / 2, n))[:, None] ** 2
        measured = loudness(x)
        gain = min(-22 - measured['input_i'], -2.1 - measured['input_tp'])
        x *= 10 ** (gain / 20)
        dest = OUT / (t['id'] + '.ogg')
        encode(x, dest, t)
        y = decode(dest)
        final = loudness(y)
        correction = min(-22 - final['input_i'], -2.1 - final['input_tp'])
        if abs(correction) > .1:
            x *= 10 ** (correction / 20)
            gain += correction
            encode(x, dest, t)
            y = decode(dest)
            final = loudness(y)
        jump = float(np.max(np.abs(y[0] - y[-1])))
        p999 = float(np.percentile(np.abs(np.diff(y, axis=0)), 99.9))
        changes = [
            'Preserved full recording, original tempo, instrumentation and natural tail; whole-piece restart at 0 seconds.',
            'Applied 5 ms fades at the file edges to suppress sample discontinuities; no claim of musically seamless loop.',
            f'Applied constant gain {gain:.6f} dB targeting -22 LUFS and a -2.1 dBTP ceiling; no dynamic compression.',
            'Encoded Ogg Vorbis quality 6, stereo 44100 Hz from the selected MP3 source.'
        ]
        rec = {**t, 'path': 'res://assets/audio/content_v293/' + dest.name,
               'source_sha256': sha(src), 'sha256': sha(dest), 'bytes': dest.stat().st_size,
               'frames': len(y), 'duration_seconds': len(y) / SR, 'sample_rate': SR,
               'channels': 2, 'gain_db': gain, 'measured_lufs': final['input_i'],
               'measured_true_peak_db': final['input_tp'], 'loop_boundary_jump': jump,
               'within_track_step_p999': p999, 'seam_jump_below_p999': jump <= p999,
               'mode': 'whole_piece_restart', 'subjective_listening_verified': False,
               'user_selection_confirmed': True, 'changes': changes}
        rec.pop('unchanged_full_mp3', None)
        assert len(y) == frames
        assert final['input_tp'] <= -2
        assert abs(final['input_i'] + 22) < .25
        assert jump <= p999
        results.append(rec)
        print(json.dumps({k: rec[k] for k in ['id', 'duration_seconds', 'measured_lufs', 'measured_true_peak_db']}), flush=True)
    (OUT / 'manifest.json').write_text(json.dumps(results, ensure_ascii=False, indent=2) + '\n')
    credits = ['User-selected character summon music. CC BY 4.0 attribution and modification record.', '']
    for t in results:
        credits += [t['id'] + '.ogg', t['attribution'], t['page'],
                    'Original download: ' + t['download'], 'Source SHA-256: ' + t['source_sha256'],
                    'Changes: ' + ' '.join(t['changes']), '']
    (OUT / 'LICENSES.txt').write_text('\n'.join(credits) + '\n')

if __name__ == '__main__':
    main()
