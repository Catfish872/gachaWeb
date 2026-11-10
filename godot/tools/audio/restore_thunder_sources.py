#!/usr/bin/env python3
"""Verify local originals, or explicitly retrieve them from recorded public sources."""
import argparse
import hashlib
import json
import urllib.request
from pathlib import Path


def restore(source_dir, output_dir=None, download=False):
    source_dir = Path(source_dir)
    output_dir = Path(output_dir) if output_dir else source_dir
    records = json.loads((source_dir / 'sources.json').read_text())
    output_dir.mkdir(parents=True, exist_ok=True)
    restored = []
    for record in records:
        name = record['source']
        if Path(name).name != name:
            raise ValueError('Invalid source filename')
        target = output_dir / name
        expected = record['expected_source_sha256']
        if target.exists():
            data = target.read_bytes()
        elif download:
            url = record['download']
            if not url.startswith('https://opengameart.org/'):
                raise ValueError('Source URL must use the recorded HTTPS provider')
            with urllib.request.urlopen(url, timeout=60) as response:
                data = response.read(100 * 1024 * 1024 + 1)
            if len(data) > 100 * 1024 * 1024:
                raise ValueError('Source exceeds download budget: ' + name)
        else:
            raise FileNotFoundError('Original audio is not distributed in this repository. '
                'Run restore_thunder_sources.py --download, or save ' + record['download']
                + ' as ' + str(target) + ' with SHA-256 ' + expected)
        if hashlib.sha256(data).hexdigest() != expected:
            raise ValueError('Source checksum mismatch; existing file preserved: ' + name)
        if not target.exists():
            target.write_bytes(data)
        restored.append(name)
    return restored


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--download', action='store_true', help='Fetch originals from recorded public URLs and verify SHA-256')
    args = parser.parse_args()
    for name in restore(Path(__file__).resolve().parent / 'thunder_selected_sources', args.output, args.download):
        print('Verified ' + name)
