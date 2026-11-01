"""Reuse the exact, frozen 2.5 production evidence; all other sources run native CI."""
import hashlib
import json
import os
from pathlib import Path

root = Path(__file__).resolve().parents[2] / 'godot'
expected = '99c8bfc8c85ab678dfb5ab9bab7814f172600bffc0495fa30f011b0c7804962b'
excluded = {f'assets/{name}{suffix}' for name in ('audio/extraction/search_loop.ogg', 'audio/music/ruins_ambient.ogg', 'audio/music/ruins_battle.ogg') for suffix in ('', '.import')}
paths = [p for folder in ('scripts', 'data', 'assets') for p in (root / folder).rglob('*') if p.is_file() and p.relative_to(root).as_posix() not in excluded]
paths += [root / p for p in ('main.tscn', 'project.godot', 'export_presets.cfg')]
files = {p.relative_to(root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
digest = hashlib.sha256(''.join(f'{p}\0{files[p]}\n' for p in sorted(files)).encode()).hexdigest()
version = json.loads((root / 'data/version.json').read_text())
reuse = digest == expected and len(files) == 753 and version['version_name'] == '2.5.0' and version['version_code'] == 20500
print(f'Production evidence reuse={reuse}; files={len(files)}; SHA256={digest}')
print('Evidence: validation/v250-final; CI27 run 41320178121 passed expedition and summon paths; remaining native relic path is not certified.')
if os.environ.get('GITHUB_OUTPUT'):
    with open(os.environ['GITHUB_OUTPUT'], 'a') as out:
        out.write(f'reuse={str(reuse).lower()}\n')
