#!/usr/bin/env python3
"""Deterministic, signed-manifest content packs from exact exported runtime bytes."""
import argparse, hashlib, io, json, os, re, subprocess, zipfile
from pathlib import Path
REPOSITORY = 'Catfish872/gachaWeb'
PROTECTED = ('scripts/content_store.gd', 'scripts/content_bootstrap.gd', 'scripts/content_save_guard.gd')
EXCLUDED = {'content_bootstrap.tscn', 'content_bootstrap.tscn.remap', 'data/content_public_key.pem', 'data/content_platform.json', 'project.binary', 'project.godot', '.godot/extension_list.cfg', 'assets.sparsepck', '_cl_'}
def digest(data): return hashlib.sha256(data).hexdigest()
def canonical(value): return (json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=False)+'\n').encode()
def protected(path):
    return path in EXCLUDED or path.startswith('content_bootstrap.tscn.') or any(path == p or path.startswith(p + '.') or path == p[:-3]+'.gdc' for p in PROTECTED)
def pack(entries):
    out=io.BytesIO()
    with zipfile.ZipFile(out,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=9) as z:
        for path,data in sorted(entries.items()):
            if path.startswith('/') or '..' in path.split('/') or '\\' in path: raise ValueError('Unsafe resource path')
            info=zipfile.ZipInfo(path,(1980,1,1,0,0,0)); info.compress_type=zipfile.ZIP_DEFLATED; info.external_attr=0o100644<<16
            z.writestr(info,data,compresslevel=9)
    return out.getvalue()
def platform(root):
    """Conservative native/bootstrap ABI; content and version changes excluded."""
    entries={}
    for name in ('project.godot','export_presets.cfg','tools/build/install_godot.sh','tools/build/setup_android.sh','tools/build/normalize_manifest.py','tools/build/finalize_apk.sh'):
        data=(root/name).read_text()
        if name=='export_presets.cfg': data=re.sub(r'^version/(?:code|name)=.*\n','',data,flags=re.M)
        entries[name]=digest(data.encode())
    for name in ('content_bootstrap.tscn','scripts/content_store.gd','scripts/content_bootstrap.gd','scripts/content_save_guard.gd','data/content_public_key.pem'):
        path=root/name
        if not path.is_file(): raise ValueError('Missing protected bootstrap input: '+name)
        entries[name]=digest(path.read_bytes())
    for path in sorted((root/'android').rglob('*')) if (root/'android').exists() else []:
        if path.is_file() and not any(p in ('.gradle','build') for p in path.parts): entries[str(path.relative_to(root))]=digest(path.read_bytes())
    for path in sorted(root.rglob('*')):
        if path.is_file() and path.suffix.lower() in {'.gdextension','.so','.aar','.jar','.dll','.dylib'} and not any(p in ('.godot','build','validation') for p in path.relative_to(root).parts):
            entries[str(path.relative_to(root))]=digest(path.read_bytes())
    return {'schema':1,'platform_id':digest(canonical(entries))}
def build(apk, output, previous=None):
    output.mkdir(parents=True,exist_ok=True)
    with zipfile.ZipFile(apk) as z:
        entries={i.filename[7:]:z.read(i) for i in z.infolist() if i.filename.startswith('assets/') and not i.is_dir()}
    if len(entries)<2: raise ValueError('APK has no runtime resources')
    version=json.loads(entries['data/version.json']); native=json.loads(entries['data/content_platform.json'])
    tag='android-v'+version['version_name']; prefix=f'https://github.com/{REPOSITORY}/releases/download/{tag}-assets/'
    reusable={}
    if previous:
        for obj in [previous['logic']]+previous['assets']:
            if re.fullmatch(r'https://github\.com/Catfish872/gachaWeb/releases/download/android-v[0-9]+\.[0-9]+\.[0-9]+(?:-assets)?/obj-'+obj['sha256']+r'\.zip',obj['url']): reusable[obj['sha256']]=obj
    created=[]
    def emit(data):
        sha=digest(data); name='obj-'+sha+'.zip'
        old=reusable.get(sha)
        if old and old['size']==len(data): return {k:old[k] for k in ('sha256','size','url')}
        (output/name).write_bytes(data); created.append(name)
        return {'sha256':sha,'size':len(data),'url':prefix+name}
    bootstrap_remap=entries.get('content_bootstrap.tscn.remap', b'').decode('utf-8')
    bootstrap_targets=set(re.findall(r'path="res://([^"]+)"', bootstrap_remap))
    logic={}; assets=[]
    for path,data in sorted(entries.items()):
        if protected(path) or path in bootstrap_targets: continue
        # Imported runtime media and directly exported media are independent objects.
        media=path.startswith('.godot/imported/') or (path.startswith('assets/') and not path.endswith(('.import','.remap')))
        if media:
            obj=emit(pack({path:data})); obj.update(path='res://'+path,content_sha256=digest(data),content_size=len(data)); assets.append(obj)
        else: logic[path]=data
    if not any(p in logic for p in ('main.tscn','main.tscn.remap')): raise ValueError('Main scene missing')
    manifest={'schema':1,'repository':REPOSITORY,'version_name':version['version_name'],'version_code':version['version_code'],'platform_id':native['platform_id'],'entry_scene':'res://main.tscn','logic':emit(pack(logic)),'assets':assets}
    # Hash objects use a separate prerelease so legacy latest-release responses stay small.
    if len(set(created)) > 1000: raise ValueError('GitHub release asset limit exceeded; split bootstrap into a reviewed asset release')
    (output/'content-manifest.json').write_bytes(canonical(manifest))
    (output/'content-upload-list.txt').write_text('\n'.join(created)+'\n')
    return manifest

def main():
    p=argparse.ArgumentParser(); sub=p.add_subparsers(dest='command',required=True)
    a=sub.add_parser('platform'); a.add_argument('root',type=Path)
    a=sub.add_parser('build'); a.add_argument('apk',type=Path); a.add_argument('output',type=Path); a.add_argument('--previous',type=Path)
    args=p.parse_args()
    if args.command=='platform': (args.root/'data/content_platform.json').write_bytes(canonical(platform(args.root)))
    else:
        previous=json.loads(args.previous.read_text()) if args.previous else None
        result=build(args.apk,args.output,previous); print(json.dumps({'version':result['version_name'],'objects':len(result['assets']),'logic_bytes':result['logic']['size']}))
if __name__=='__main__': main()
