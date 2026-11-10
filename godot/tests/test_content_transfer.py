#!/usr/bin/env python3
"""Real HTTP/Godot transfer integration with isolated test-only signing identity."""
import hashlib, http.server, io, json, os, pathlib, shutil, subprocess, tempfile, threading, zipfile, urllib.parse
ROOT = pathlib.Path(__file__).resolve().parents[1]
def sha(b): return hashlib.sha256(b).hexdigest()
def run():
    with tempfile.TemporaryDirectory(prefix='content-transfer-') as temporary:
        base = pathlib.Path(temporary)
        project = base / 'project'; project.mkdir()
        for directory in ['scripts','data','assets']:
            (project / directory).mkdir()
        for name in ['content_store.gd','content_downloader.gd']:
            shutil.copy(ROOT / 'scripts' / name, project / 'scripts' / name)
        (project/'project.godot').write_text('config_version=5\n[application]\nconfig/name="Content transfer isolated test"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n')
        subprocess.run(['openssl','genpkey','-algorithm','RSA','-pkeyopt','rsa_keygen_bits:2048','-out',str(base/'test.key')],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        subprocess.run(['openssl','pkey','-in',str(base/'test.key'),'-pubout','-out',str(project/'data/content_public_key.pem')],check=True,stdout=subprocess.DEVNULL)
        platform = 'a'*64
        (project/'data/content_platform.json').write_text(json.dumps({'platform_id':platform}))
        (project/'data/version.json').write_text(json.dumps({'version_name':'2.9.3','version_code':20903}))
        responses = {}; requests = []
        tag = 'android-v2.9.6'; prefix = f'https://github.com/Catfish872/gachaWeb/releases/download/{tag}/'
        def obj(path, content, asset=False):
            stream=io.BytesIO()
            with zipfile.ZipFile(stream,'w') as z: z.writestr(path,content)
            data=stream.getvalue(); digest=sha(data); name='obj-'+digest+'.zip'; responses[name]=data
            value={'sha256':digest,'size':len(data),'url':prefix+name}
            if asset: value.update(path='res://'+path,content_sha256=sha(content),content_size=len(content))
            return value
        apk=pathlib.Path(os.environ.get('BASELINE_APK','/workspace/shared/v292-published/universal.apk'))
        if not apk.is_file(): raise RuntimeError('BASELINE_APK must point to the verified 2.9.2 universal.apk')
        with zipfile.ZipFile(apk) as archive:
            entry=min((i for i in archive.infolist() if i.filename.startswith('assets/.godot/imported/') and i.filename.endswith('.ctex')),key=lambda i:i.file_size)
            embedded_bytes=archive.read(entry); embedded_path=entry.filename.removeprefix('assets/')
        embedded=obj(embedded_path,embedded_bytes,True)
        disk=project/embedded_path; disk.parent.mkdir(parents=True,exist_ok=True); disk.write_bytes(embedded_bytes)
        changed=obj('assets/changed.bin',b'new resource'*2048,True)
        logic=obj('data/version.json',json.dumps({'version_name':'2.9.6','version_code':20906}).encode())
        manifest={'schema':1,'repository':'Catfish872/gachaWeb','version_code':20906,'version_name':'2.9.6','platform_id':platform,'entry_scene':'res://main.tscn','logic':logic,'assets':[embedded,changed]}
        manifest_bytes=json.dumps(manifest,sort_keys=True).encode(); (base/'manifest').write_bytes(manifest_bytes)
        subprocess.run(['openssl','dgst','-sha256','-sign',str(base/'test.key'),'-out',str(base/'signature'),str(base/'manifest')],check=True)
        responses['content-manifest.json']=manifest_bytes; responses['content-manifest.sig']=(base/'signature').read_bytes()
        changed_name=changed['url'].split('/')[-1]
        other_manifest=dict(manifest,platform_id='b'*64)
        other_bytes=json.dumps(other_manifest,sort_keys=True).encode(); (base/'other-manifest').write_bytes(other_bytes)
        subprocess.run(['openssl','dgst','-sha256','-sign',str(base/'test.key'),'-out',str(base/'other-signature'),str(base/'other-manifest')],check=True)
        platform_responses={'content-manifest.json':other_bytes,'content-manifest.sig':(base/'other-signature').read_bytes()}
        class Handler(http.server.BaseHTTPRequestHandler):
            def log_message(self,*args): pass
            def do_GET(self):
                parsed=urllib.parse.urlparse(self.path); name=parsed.path.rsplit('/',1)[-1]; scenario=urllib.parse.parse_qs(parsed.query).get('scenario',['normal'])[0]; requests.append((scenario,name))
                data=(platform_responses if scenario=='platform' else responses).get(name)
                if scenario=='signature' and name=='content-manifest.sig': data=b'x'*256
                if data is None: self.send_error(404); return
                if name == changed_name and requests.count((scenario,name))==1: data=b'x'*len(data)
                self.send_response(200); self.send_header('Content-Length',str(len(data))); self.end_headers(); self.wfile.write(data)
        server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler)
        threading.Thread(target=server.serve_forever,daemon=True).start()
        script='''extends SceneTree
const D = preload("res://scripts/content_downloader.gd")
const S = preload("res://scripts/content_store.gd")
class LocalDownloader extends D:
 var port: int
 var scenario := "normal"
 func _fetch(url: String, limit: int, destination: String = "") -> Dictionary:
  return await super._fetch("http://127.0.0.1:%d/" % port + url.get_file() + "?scenario=" + scenario, limit, destination)
func _initialize():
 call_deferred("run")
func run():
 var d = LocalDownloader.new()
 d.port = PORT
 root.add_child(d)
 var candidate = {"tag":"android-v2.9.6","version_code":20906,"content_manifest":"PREFIXcontent-manifest.json","content_signature":"PREFIXcontent-manifest.sig"}
 if "--restart" in OS.get_cmdline_user_args():
  var persisted = S.read_state()
  var saved = S.load_manifest(persisted.get("pending", ""))
  if saved.is_empty() or not S.missing_objects(saved).is_empty() or not S.mount(saved):
   quit(5)
   return
  var version = JSON.parse_string(FileAccess.get_file_as_string("res://data/version.json"))
  if int(version.version_code) != 20906:
   quit(6)
   return
  print("HTTP_TRANSFER: persistent cache survived process restart; downloaded ZIP mounted actual target data")
  d.queue_free()
  quit(0)
  return
 for scenario in ["signature", "version", "platform"]:
  d.scenario = scenario
  candidate.version_code = 20905 if scenario == "version" else 20906
  if scenario == "platform":
   d.begin(candidate)
   await d.apk_required
  else:
   d.begin(candidate)
   var failed = await d.changed
   while failed.status == "downloading":
    failed = await d.changed
   if failed.status != "download_error":
    quit(7)
    return
 d.scenario = "normal"
 candidate.version_code = 20906
 for expected in ["download_error", "content_ready"]:
  if d.begin(candidate) != OK:
   quit(2)
   return
  var state = await d.changed
  while state.status == "downloading":
   state = await d.changed
  if state.status != expected:
   push_error(str(state))
   quit(3)
   return
  var journal = S.read_state()
  if expected == "download_error":
   var interrupted = S.load_manifest(journal.get("downloading", ""))
   if interrupted.is_empty() or int(interrupted.version_code) != 20906:
    quit(8)
    return
  elif journal.has("downloading"):
   quit(9)
   return
 var state = S.read_state()
 if not state.has("pending") or S.load_manifest(state.pending).version_code != 20906:
  quit(4)
  return
 var saved_state = state.duplicate(true)
 var target = S.load_manifest(state.pending)
 var orphan = S.object_path("f".repeat(64))
 var abandoned = orphan + ".part"
 var part = S.object_path(target.logic.sha256) + ".part"
 var unknown = S.ROOT + "/objects/unrecognized.part"
 for field in ["active", "previous", "pending", "downloading"]:
  var keep_state = {}
  keep_state[field] = saved_state.pending
  if S.write_state(keep_state) != OK or S.atomic_write(orphan, "unused".to_utf8_buffer()) != OK or S.atomic_write(part, "interrupted".to_utf8_buffer()) != OK or S.atomic_write(abandoned, "abandoned".to_utf8_buffer()) != OK or S.atomic_write(unknown,"unknown".to_utf8_buffer()) != OK:
   quit(10)
   return
  var collected = S.collect_garbage()
  if collected.get("removed", 0) != 2 or FileAccess.file_exists(orphan) or FileAccess.file_exists(abandoned) or not FileAccess.file_exists(part) or not FileAccess.file_exists(unknown) or not S.missing_objects(target).is_empty():
   push_error("GC lost retained target: " + field)
   quit(11)
   return
 for corrupt in [{"booting":true}, {"active":"0".repeat(64)}, {"pending":"invalid"}]:
  S.write_state(corrupt)
  S.atomic_write(orphan, "unused".to_utf8_buffer())
  var collected = S.collect_garbage()
  if not collected.get("retained",false) or not FileAccess.file_exists(orphan):
   quit(12)
   return
 S.atomic_write(S.STATE,"{malformed journal".to_utf8_buffer())
 if not S.collect_garbage().get("retained", false) or not FileAccess.file_exists(orphan):
  quit(13)
  return
 var manifest_path = S.ROOT + "/manifests/" + saved_state.pending + ".json"
 var manifest_original = FileAccess.get_file_as_bytes(manifest_path)
 S.write_state(saved_state)
 S.atomic_write(manifest_path,"{tampered manifest}".to_utf8_buffer())
 if not S.collect_garbage().get("retained", false) or not FileAccess.file_exists(orphan):
  quit(14)
  return
 S.atomic_write(manifest_path,manifest_original)
 S.write_state(saved_state)
 print("HTTP_TRANSFER: GC retains active/previous/pending/downloading objects and referenced partial transfers; orphan partials removed; corrupt state/signature or booting blocks deletion")
 print("HTTP_TRANSFER: corruption rejected, cached retry, embedded reuse, multi-version jump staged")
 d.queue_free()
 quit(0)
'''.replace('PORT',str(server.server_port)).replace('PREFIX',prefix)
        (project/'test.gd').write_text(script)
        env=os.environ.copy()
        for name in ['CONFIG','DATA','CACHE']:
            path=base/name;path.mkdir();env['XDG_'+name+'_HOME']=str(path)
        try:
            result=subprocess.run(['godot','--headless','--path',str(project),'--script','res://test.gd'],env=env,text=True,capture_output=True,timeout=45)
            if result.returncode==0:
                restarted=subprocess.run(['godot','--headless','--path',str(project),'--script','res://test.gd','--','--restart'],env=env,text=True,capture_output=True,timeout=20)
                print(restarted.stdout,end=''); print(restarted.stderr,end=''); assert restarted.returncode==0
        finally: server.shutdown()
        print(result.stdout,end=''); print(result.stderr,end='')
        assert result.returncode==0, result.returncode
        assert requests.count(('normal',logic['url'].split('/')[-1]))==1,requests
        assert requests.count(('normal',changed_name))==2,requests
        assert all(name != embedded['url'].split('/')[-1] for _,name in requests),requests
        assert requests.count(('normal','content-manifest.json'))==2,requests
        assert all(not name.startswith('obj-') for scenario,name in requests if scenario != 'normal'),requests
        print('HTTP_TRANSFER: exact server request counts verified; 0 unchanged bytes transferred')
if __name__=='__main__': run()
