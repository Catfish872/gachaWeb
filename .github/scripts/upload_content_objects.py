#!/usr/bin/env python3
"""Resume an immutable object release with serial, rate-limit-aware uploads."""
import base64
import email.utils
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from release_preflight import production_tree, git

class Conflict(RuntimeError): pass
class HTTPFailure(RuntimeError):
    def __init__(self,code,headers,body):
        self.code,self.headers,self.body=code,headers,body
        super().__init__(f'GitHub HTTP {code}: {body[:250]}')

def retry_delay(error,attempt,now=None):
    now=time.time() if now is None else now
    if error.code not in (403,429,500,502,503,504): return None
    limited=error.code==429 or 'rate limit' in error.body.lower() or 'secondary' in error.body.lower() or error.headers.get('X-RateLimit-Remaining')=='0'
    if error.code==403 and not limited: return None
    delay=min(900,60*2**attempt)
    value=error.headers.get('Retry-After')
    if value:
        try: delay=max(delay,float(value))
        except ValueError:
            try: delay=max(delay,email.utils.parsedate_to_datetime(value).timestamp()-now)
            except (TypeError,ValueError): pass
    if error.headers.get('X-RateLimit-Remaining')=='0':
        try: delay=max(delay,float(error.headers.get('X-RateLimit-Reset','0'))-now+5)
        except ValueError: pass
    return max(1,delay)

class API:
    def __init__(self,repo,token,sleep=time.sleep): self.repo,self.token,self.sleep=repo,token,sleep
    def request(self,method,path,data=None,content_type='application/json'):
        url=path if path.startswith('https://uploads.github.com/') else 'https://api.github.com'+path
        headers={'Authorization':'Bearer '+self.token,'Accept':'application/vnd.github+json','X-GitHub-Api-Version':'2022-11-28','User-Agent':'VoidRift-Content-Publisher','Content-Type':content_type}
        request=urllib.request.Request(url,data=data,headers=headers,method=method)
        try:
            with urllib.request.urlopen(request,timeout=180) as response: return json.load(response)
        except urllib.error.HTTPError as error:
            raise HTTPFailure(error.code,error.headers,error.read().decode(errors='replace')) from None
    def read(self,path):
        for attempt in range(9):
            try: return self.request('GET',path)
            except HTTPFailure as error:
                delay=retry_delay(error,attempt)
                if delay is None or attempt==8: raise
                print(f'GitHub metadata backoff {delay:.0f}s',flush=True); self.sleep(delay)
    def releases(self):
        result=[];page=1
        while True:
            rows=self.read(f'/repos/{self.repo}/releases?per_page=100&page={page}')
            result.extend(rows)
            if len(rows)<100:return result
            page+=1
    def assets(self,release_id):
        result={}; page=1
        while True:
            rows=self.read(f'/repos/{self.repo}/releases/{release_id}/assets?per_page=100&page={page}')
            for asset in rows:
                if asset['name'] in result: raise Conflict('Duplicate remote asset name')
                result[asset['name']]=asset
            if len(rows)<100: return result
            page+=1

def identity(path):
    with path.open('rb') as stream: sha=hashlib.file_digest(stream,'sha256').hexdigest()
    return {'name':path.name,'size':path.stat().st_size,'digest':'sha256:'+sha,'state':'uploaded'}
def matches(remote,expected): return all(remote.get(k)==v for k,v in expected.items())
def validate_inventory(remote,expected,allow_extra_objects=False):
    extras=set(remote)-set(expected)
    for name in sorted(extras):
        asset=remote[name]
        match=re.fullmatch(r'obj-([0-9a-f]{64})\.zip',name)
        valid=allow_extra_objects and match is not None and asset.get('name')==name and asset.get('state')=='uploaded' and type(asset.get('size')) is int and asset['size']>=0 and asset.get('digest')=='sha256:'+match.group(1)
        if not valid:raise Conflict('Unexpected or invalid retained asset '+name+'; all drafts preserved')
    for name in set(remote)&set(expected):
        if not matches(remote[name],expected[name]):raise Conflict('Existing expected asset differs: '+name+'; all drafts preserved')
    if extras:print(f'Preserving {len(extras)} additional content-addressed objects from an equivalent build',flush=True)
    return set(remote)&set(expected)

def upload_missing(api,release,files,interval=9,sleep=time.sleep,verify_only=False,allow_extra_objects=False):
    expected={p.name:identity(p) for p in files}
    remote=api.assets(release['id'])
    reusable=validate_inventory(remote,expected,allow_extra_objects)
    if len(set(remote)|set(expected))>1000:raise Conflict('Retained plus missing assets exceed GitHub 1000-asset limit; preserved')
    missing=[p for p in files if p.name not in remote]
    if missing and (verify_only or not release['draft']): raise Conflict('Object release is incomplete; preserved')
    print(f'Preserving {len(reusable)} expected verified objects; uploading {len(missing)} missing objects at >= {interval}s intervals',flush=True)
    for index,path in enumerate(missing):
        sleep(interval)
        for attempt in range(9):
            try:
                asset=api.request('POST',f'https://uploads.github.com/repos/{api.repo}/releases/{release["id"]}/assets?name='+urllib.parse.quote(path.name,safe=''),path.read_bytes(),'application/octet-stream')
                if not matches(asset,expected[path.name]): raise Conflict('Upload response failed digest verification: '+path.name)
                break
            except (HTTPFailure,urllib.error.URLError,TimeoutError,OSError) as error:
                if isinstance(error,HTTPFailure):
                    delay=retry_delay(error,attempt)
                    if error.code==422: delay=60
                    if delay is None: raise
                else: delay=min(900,60*2**attempt)
                if attempt==8: raise
                print(f'Upload interrupted; waiting {delay:.0f}s then reconciling exact asset before retry',flush=True); sleep(delay)
                found=api.assets(release['id']).get(path.name)
                if found:
                    if not matches(found,expected[path.name]): raise Conflict('Uncertain upload produced an incomplete or mismatched object; preserved: '+path.name)
                    break
        print(f'Verified new object {index+1}/{len(missing)}: {path.name}',flush=True)
    return len(missing)

def ensure_equivalent_target(repo,release,current,token):
    target=release.get('target_commitish','')
    if not re.fullmatch('[0-9a-f]{40}',target): raise Conflict('Existing draft requires an exact original target commit')
    if target==current:return
    auth=base64.b64encode(('x-access-token:'+token).encode()).decode()
    env=os.environ.copy();env.update(GIT_CONFIG_COUNT='1',GIT_CONFIG_KEY_0='http.https://github.com/.extraheader',GIT_CONFIG_VALUE_0='AUTHORIZATION: basic '+auth,GIT_TERMINAL_PROMPT='0')
    git('.', 'fetch','--no-tags','--depth=1',f'https://github.com/{repo}.git',target,env=env)
    if production_tree('.',target)!=production_tree('.',current): raise Conflict('Existing draft production source differs; preserved')

def select_release(api,tag,current,files,prerelease=True):
    expected={p.name:identity(p) for p in files}
    candidates=[]
    for release in api.releases():
        if release.get('tag_name')!=tag:continue
        if release.get('prerelease') is not prerelease:raise Conflict('Exact tag has conflicting release channel; preserved')
        ensure_equivalent_target(api.repo,release,current,api.token)
        assets=api.assets(release['id'])
        reusable=validate_inventory(assets,expected,allow_extra_objects=prerelease)
        if not release['draft'] and reusable!=set(expected):raise Conflict('Published exact-tag release lacks current expected objects; preserved')
        candidates.append((release,reusable))
    if not candidates:return None
    supersets=[release for release,names in candidates if all(names>=other for _,other in candidates)]
    if not supersets:
        if not prerelease:raise Conflict('Exact-tag drafts have incomparable asset sets; all preserved')
        count=max(len(names) for _,names in candidates)
        supersets=[release for release,names in candidates if len(names)==count]
    # Prefer an already published exact complete release, otherwise deterministic ID.
    selected=min(supersets,key=lambda r:(r['draft'],int(r['id'])))
    print(f'Selected release ID {selected["id"]} from {len(candidates)} verified exact-tag releases; other drafts preserved',flush=True)
    return selected

def get_or_create_release(api,tag,current,files,prerelease=True):
    for attempt in range(9):
        existing=select_release(api,tag,current,files,prerelease)
        if existing is not None:return existing
        payload={'tag_name':tag,'target_commitish':current,'draft':True,'prerelease':prerelease,'name':tag,'body':'Verified Android content release. Immutable assets are validated against the signed content manifest.'}
        try:return api.request('POST',f'/repos/{api.repo}/releases',json.dumps(payload).encode())
        except (HTTPFailure,urllib.error.URLError,TimeoutError,OSError) as error:
            if isinstance(error,HTTPFailure):
                delay=retry_delay(error,attempt)
                if error.code==422:delay=60
                if delay is None:raise
            else:delay=min(900,60*2**attempt)
            if attempt==8:raise
            print(f'Release creation interrupted; waiting {delay:.0f}s before authenticated list reconciliation',flush=True)
            api.sleep(delay)
    raise Conflict('Release creation retry budget exhausted')

def validate_release(api,release,tag,current,prerelease):
    if release.get('tag_name')!=tag or release.get('prerelease') is not prerelease:raise Conflict('Stored release ID identity differs')
    ensure_equivalent_target(api.repo,release,current,api.token)

def publish_by_id(api,release,tag,current,files,prerelease):
    # Verification and mutation address exactly the same immutable numeric identity.
    release_id=release['id']
    for attempt in range(9):
        latest=api.read(f'/repos/{api.repo}/releases/{release_id}')
        validate_release(api,latest,tag,current,prerelease)
        upload_missing(api,latest,files,verify_only=True,allow_extra_objects=prerelease)
        if not latest['draft']:return latest
        payload={'draft':False,'prerelease':prerelease,'make_latest':'false' if prerelease else 'true'}
        try:
            result=api.request('PATCH',f'/repos/{api.repo}/releases/{release_id}',json.dumps(payload).encode())
            validate_release(api,result,tag,current,prerelease)
            if result['draft']:raise Conflict('Publication response remains draft')
            return result
        except (HTTPFailure,urllib.error.URLError,TimeoutError,OSError) as error:
            if isinstance(error,HTTPFailure):
                delay=retry_delay(error,attempt)
                if delay is None:raise
            else:delay=min(900,60*2**attempt)
            if attempt==8:raise
            api.sleep(delay)  # next iteration reads ID before any retry
    raise Conflict('Publication retry budget exhausted')

def main():
    output=Path(sys.argv[1]);repo=os.environ['GITHUB_REPOSITORY'];stable='--stable' in sys.argv[2:]
    tag=os.environ['RELEASE_TAG']+('' if stable else '-assets');current=os.environ['GITHUB_SHA'];token=os.environ['GH_TOKEN']
    if repo!='Catfish872/gachaWeb' or not re.fullmatch(r'android-v[0-9]+\.[0-9]+\.[0-9]+(?:-assets)?',tag):raise Conflict('Unexpected release destination')
    api=API(repo,token);verify_only='--verify-only' in sys.argv[2:];publish='--publish' in sys.argv[2:];prerelease=not stable
    if stable:
        files=[output/'universal.apk',output/'SHA256SUMS.txt',output/'content/content-manifest.json',output/'content/content-manifest.sig']
    else:
        names=(output/'content-upload-list.txt').read_text().splitlines()
        if len(names)!=len(set(names)) or not all(re.fullmatch(r'obj-[0-9a-f]{64}\.zip',n) for n in names):raise Conflict('Invalid upload inventory')
        if len(names)>1000:raise Conflict('GitHub object count limit exceeded')
        files=[output/n for n in names]
    record=output/('stable-release-id.json' if stable else 'objects-release-id.json')
    if record.is_file():
        saved=json.loads(record.read_text())
        if saved.get('tag')!=tag or not isinstance(saved.get('id'),int):raise Conflict('Invalid persisted release identity')
        release=api.read(f'/repos/{repo}/releases/{saved["id"]}')
    elif verify_only or publish:
        release=select_release(api,tag,current,files,prerelease)
        if release is None:raise Conflict('Expected existing release was not found; no creation during verification/publication')
    else:release=get_or_create_release(api,tag,current,files,prerelease)
    validate_release(api,release,tag,current,prerelease)
    record.write_text(json.dumps({'tag':tag,'id':release['id']})+'\n')
    print(f'Pinned {tag} to release ID {release["id"]}',flush=True)
    upload_missing(api,release,files,verify_only=verify_only or publish,allow_extra_objects=prerelease)
    if stable and len(json.dumps(api.read(f'/repos/{repo}/releases/{release["id"]}')).encode())>524288:raise Conflict('Stable release metadata exceeds legacy compatibility budget')
    if publish:publish_by_id(api,release,tag,current,files,prerelease)
if __name__=='__main__':main()
