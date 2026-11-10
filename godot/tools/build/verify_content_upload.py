#!/usr/bin/env python3
"""Verify GitHub accepted exactly the immutable files before making a release live."""
import hashlib, json, subprocess, sys
from pathlib import Path
output,tag,kind=Path(sys.argv[1]),sys.argv[2],sys.argv[3]
raw=subprocess.check_output(['gh','api',f'repos/Catfish872/gachaWeb/releases/tags/{tag}'])
release=json.loads(raw)
if release['tag_name']!=tag: raise ValueError('Release identity changed')
if kind=='objects': files=[output/'content'/n for n in (output/'content/content-upload-list.txt').read_text().splitlines()]
elif kind=='stable':
    files=[output/'universal.apk',output/'SHA256SUMS.txt',output/'content/content-manifest.json',output/'content/content-manifest.sig']
    if len(raw)>524288: raise ValueError('Stable latest-release metadata exceeds legacy compatibility budget')
else: raise ValueError('Expected objects or stable')
assets={a['name']:a for a in release['assets']}
if len(assets)!=len(release['assets']) or set(assets)!={p.name for p in files}: raise ValueError('Unexpected or incomplete uploaded asset set')
for path in files:
    asset=assets[path.name]
    with path.open('rb') as stream: digest=hashlib.file_digest(stream,'sha256').hexdigest()
    if asset['state']!='uploaded' or asset['size']!=path.stat().st_size or asset.get('digest')!='sha256:'+digest: raise ValueError('Uploaded asset differs: '+path.name)
print(f'Verified {len(files)} {kind} release assets')
