#!/usr/bin/env python3
"""Fetch and authenticate the latest published content inventory for reuse."""
import json, os, re, subprocess, sys
from pathlib import Path
root,work=map(Path,sys.argv[1:]); repo='Catfish872/gachaWeb'
r=subprocess.run(['gh','api',f'repos/{repo}/releases/latest'],capture_output=True,text=True)
if r.returncode:
    if 'HTTP 404' in r.stderr: sys.exit(0)
    raise RuntimeError('Unable to inspect prior release: '+r.stderr)
release=json.loads(r.stdout)
if release.get('draft') or release.get('prerelease'): raise ValueError('Expected stable release')
assets={a['name']:a for a in release['assets']}
required=['content-manifest.json','content-manifest.sig']
if not all(name in assets for name in required): sys.exit(0)  # legacy APK release
for name in required:
    subprocess.run(['gh','release','download',release['tag_name'],'--repo',repo,'--pattern',name,'--dir',str(work)],check=True)
subprocess.run(['openssl','dgst','-sha256','-verify',str(root/'data/content_public_key.pem'),'-signature',str(work/'content-manifest.sig'),str(work/'content-manifest.json')],check=True)
manifest=json.loads((work/'content-manifest.json').read_text())
if manifest['repository']!=repo or release['tag_name']!='android-v'+manifest['version_name']: raise ValueError('Prior manifest identity mismatch')
# A signed inventory is reusable only while its exact immutable assets remain published.
cache={}
for obj in [manifest['logic']]+manifest['assets']:
    match=re.fullmatch(r'https://github\.com/Catfish872/gachaWeb/releases/download/(android-v[0-9]+\.[0-9]+\.[0-9]+(?:-assets)?)/(obj-[0-9a-f]{64}\.zip)',obj['url'])
    if not match: raise ValueError('Untrusted prior object URL')
    tag,name=match.groups()
    if tag not in cache:
        data=json.loads(subprocess.check_output(['gh','api',f'repos/{repo}/releases/tags/{tag}']))
        if data.get('draft'): raise ValueError('Prior object release is unpublished')
        cache[tag]={a['name']:a for a in data['assets']}
    actual=cache[tag].get(name,{})
    if actual.get('state')!='uploaded' or actual.get('size')!=obj['size'] or actual.get('digest')!='sha256:'+obj['sha256']:
        raise ValueError('Prior content object is missing or changed: '+name)
(work/'previous.json').write_bytes((work/'content-manifest.json').read_bytes())
