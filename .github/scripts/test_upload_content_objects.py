#!/usr/bin/env python3
import importlib.util
from pathlib import Path
import tempfile
import unittest
import urllib.error
from unittest.mock import patch
import upload_content_objects as u
class FakeAPI:
    repo='Catfish872/gachaWeb'
    def __init__(self,existing=None,failures=None):self.remote=existing or {};self.failures=failures or [];self.calls=[];self.reads=0
    def assets(self,_id):self.reads+=1;return self.remote.copy()
    def request(self,method,url,data,kind):
        name=url.split('name=')[1];self.calls.append(name)
        expected={'name':name,'size':len(data),'digest':'sha256:'+u.hashlib.sha256(data).hexdigest(),'state':'uploaded'}
        if self.failures:
            failure=self.failures.pop(0)
            if failure=='accepted-timeout':self.remote[name]=expected;raise TimeoutError()
            if failure=='bad-timeout':self.remote[name]=dict(expected,state='starter');raise TimeoutError()
            raise failure
        self.remote[name]=expected;return expected
class UploadTests(unittest.TestCase):
    def setUp(self):self.tmp=tempfile.TemporaryDirectory();self.root=Path(self.tmp.name);self.a=self.root/'obj-a.zip';self.b=self.root/'obj-b.zip';self.a.write_bytes(b'a');self.b.write_bytes(b'b');self.release={'id':1,'draft':True};self.wait=[]
    def tearDown(self):self.tmp.cleanup()
    def run_upload(self,api):return u.upload_missing(api,self.release,[self.a,self.b],sleep=self.wait.append)
    def test_partial_preserves_and_uploads_only_missing(self):
        api=FakeAPI({self.a.name:u.identity(self.a)});self.assertEqual(self.run_upload(api),1);self.assertEqual(api.calls,[self.b.name]);self.assertEqual(self.wait,[9])
    def test_mismatch_fails_without_upload(self):
        api=FakeAPI({self.a.name:dict(u.identity(self.a),size=3)})
        with self.assertRaises(u.Conflict):self.run_upload(api)
        self.assertEqual(api.calls,[])
    def test_throttle_honors_retry_after_and_reconciles(self):
        api=FakeAPI({self.a.name:u.identity(self.a)},[u.HTTPFailure(403,{'Retry-After':'121'},'secondary rate limit')]);self.run_upload(api);self.assertEqual(self.wait,[9,121]);self.assertEqual(api.reads,2);self.assertEqual(api.calls,[self.b.name,self.b.name])
    def test_uncertain_success_is_not_reuploaded(self):
        api=FakeAPI({self.a.name:u.identity(self.a)},['accepted-timeout']);self.run_upload(api);self.assertEqual(api.calls,[self.b.name]);self.assertEqual(api.reads,2)
    def test_uncertain_bad_asset_preserved(self):
        api=FakeAPI({self.a.name:u.identity(self.a)},['bad-timeout'])
        with self.assertRaises(u.Conflict):self.run_upload(api)
        self.assertEqual(len(api.calls),1)
    def test_non_rate_denial_is_not_retried(self):
        api=FakeAPI({self.a.name:u.identity(self.a)},[u.HTTPFailure(403,{},'permission denied')])
        with self.assertRaises(u.HTTPFailure):self.run_upload(api)
        self.assertEqual(self.wait,[9]);self.assertEqual(api.reads,1)
    def test_published_complete_is_read_only(self):
        self.release['draft']=False;api=FakeAPI({p.name:u.identity(p) for p in (self.a,self.b)});self.assertEqual(self.run_upload(api),0);self.assertEqual(api.calls,[])
    def test_published_incomplete_stops(self):
        self.release['draft']=False
        with self.assertRaises(u.Conflict):self.run_upload(FakeAPI())
    def test_extra_asset_stops(self):
        with self.assertRaises(u.Conflict):self.run_upload(FakeAPI({'unknown':{}}))
    def test_backoff_bounds_and_primary_reset(self):
        self.assertEqual(u.retry_delay(u.HTTPFailure(429,{},''),0),60);self.assertEqual(u.retry_delay(u.HTTPFailure(503,{},''),8),900)
        self.assertEqual(u.retry_delay(u.HTTPFailure(403,{'X-RateLimit-Remaining':'0','X-RateLimit-Reset':'1000'},''),0,now=100),905)
    @patch.object(u,'production_tree')
    @patch.object(u,'git')
    def test_target_tooling_only_change_allowed(self,git,trees):
        trees.side_effect=[{'runtime':'hash'},{'runtime':'hash'}];u.ensure_equivalent_target('Catfish872/gachaWeb',{'target_commitish':'a'*40},'b'*40,'fixture');self.assertEqual(trees.call_count,2)
    @patch.object(u,'production_tree')
    @patch.object(u,'git')
    def test_target_runtime_change_rejected(self,git,trees):
        trees.side_effect=[{'runtime':'old'},{'runtime':'new'}]
        with self.assertRaises(u.Conflict):u.ensure_equivalent_target('Catfish872/gachaWeb',{'target_commitish':'a'*40},'b'*40,'fixture')
    @patch.object(u,'select_release')
    def test_creation_uncertain_success_resolves_list(self,select):
        from unittest.mock import Mock
        api=Mock(repo='Catfish872/gachaWeb');select.side_effect=[None,{'id':1}];api.request.side_effect=TimeoutError()
        self.assertEqual(u.get_or_create_release(api,'android-v2.9.3-assets','a'*40,[]),{'id':1});self.assertEqual(api.request.call_count,1);api.sleep.assert_called_once_with(60)
    @patch.object(u,'select_release')
    def test_creation_secondary_limit_lists_before_retry(self,select):
        from unittest.mock import Mock
        api=Mock(repo='Catfish872/gachaWeb');select.side_effect=[None,None];api.request.side_effect=[u.HTTPFailure(429,{'Retry-After':'120'},'limited'),{'id':1}]
        self.assertEqual(u.get_or_create_release(api,'android-v2.9.3-assets','a'*40,[]),{'id':1});self.assertEqual(select.call_count,2);api.sleep.assert_called_once_with(120)
    def test_verify_only_draft_missing_never_uploads(self):
        api=FakeAPI({self.a.name:u.identity(self.a)})
        with self.assertRaises(u.Conflict):u.upload_missing(api,self.release,[self.a,self.b],verify_only=True,sleep=self.wait.append)
        self.assertEqual(api.calls,[])
    def test_paginated_inventory_reads_every_page(self):
        from unittest.mock import Mock
        api=u.API('Catfish872/gachaWeb','fixture');api.read=Mock(side_effect=[[{'name':str(i)} for i in range(100)],[{'name':'last'}]])
        result=api.assets(1);self.assertEqual(len(result),101);self.assertIn('last',result);self.assertIn('page=2',api.read.call_args.args[0])
    def test_nonexact_target_rejected(self):
        with self.assertRaises(u.Conflict):u.ensure_equivalent_target('Catfish872/gachaWeb',{'target_commitish':'main'},'b'*40,'fixture')
class DraftDiscoveryTests(unittest.TestCase):
    setUp=UploadTests.setUp
    tearDown=UploadTests.tearDown
    tag='android-v2.9.3-assets'
    current='a'*40
    def make_release(self,id,draft=True):return {'id':id,'tag_name':self.tag,'prerelease':True,'draft':draft,'target_commitish':self.current}
    def api(self,releases,inventories):
        from unittest.mock import Mock
        api=Mock(repo='Catfish872/gachaWeb',token='fixture');api.releases.return_value=releases;api.assets.side_effect=lambda id:inventories[id].copy();return api
    @patch.object(u,'ensure_equivalent_target')
    def test_tag404_avoided_list_finds_complete_and_zero_uploads(self,equivalence):
        complete={p.name:u.identity(p) for p in (self.a,self.b)}
        api=self.api([self.make_release(1),self.make_release(2)],{1:{self.a.name:u.identity(self.a)},2:complete})
        api.read.side_effect=u.HTTPFailure(404,{},'tag lookup cannot see drafts')
        selected=u.get_or_create_release(api,self.tag,self.current,[self.a,self.b]);self.assertEqual(selected['id'],2)
        self.assertEqual(u.upload_missing(api,selected,[self.a,self.b],verify_only=True),0)
        api.request.assert_not_called();api.read.assert_not_called();self.assertEqual(equivalence.call_count,2)
    @patch.object(u,'ensure_equivalent_target')
    def test_conflicting_duplicate_fails_even_complete_exists(self,_):
        complete={p.name:u.identity(p) for p in (self.a,self.b)}
        api=self.api([self.make_release(1),self.make_release(2)],{1:{self.a.name:dict(u.identity(self.a),digest='bad')},2:complete})
        with self.assertRaises(u.Conflict):u.select_release(api,self.tag,self.current,[self.a,self.b])
        api.request.assert_not_called()
    @patch.object(u,'ensure_equivalent_target')
    def test_incomparable_partial_drafts_fail(self,_):
        api=self.api([self.make_release(1),self.make_release(2)],{1:{self.a.name:u.identity(self.a)},2:{self.b.name:u.identity(self.b)}})
        with self.assertRaises(u.Conflict):u.select_release(api,self.tag,self.current,[self.a,self.b])
    @patch.object(u,'ensure_equivalent_target')
    def test_publish_uses_numeric_id_only(self,_):
        release=self.make_release(42);api=self.api([release],{42:{p.name:u.identity(p) for p in (self.a,self.b)}})
        api.read.return_value=release;api.request.return_value=dict(release,draft=False)
        result=u.publish_by_id(api,release,self.tag,self.current,[self.a,self.b],True)
        self.assertFalse(result['draft']);method,path,payload=api.request.call_args.args
        self.assertEqual((method,path),('PATCH','/repos/Catfish872/gachaWeb/releases/42'));self.assertEqual(u.json.loads(payload)['make_latest'],'false');self.assertIs(u.json.loads(payload)['draft'],False);self.assertIs(u.json.loads(payload)['prerelease'],True)
        self.assertNotIn('/tags/',api.read.call_args.args[0])
    @patch.object(u,'ensure_equivalent_target')
    def test_stable_publish_by_id_sets_latest(self,_):
        release=dict(self.make_release(77),tag_name='android-v2.9.3',prerelease=False)
        api=self.api([release],{77:{p.name:u.identity(p) for p in (self.a,self.b)}});api.read.return_value=release;api.request.return_value=dict(release,draft=False)
        u.publish_by_id(api,release,release['tag_name'],self.current,[self.a,self.b],False)
        self.assertEqual(u.json.loads(api.request.call_args.args[2])['make_latest'],'true')
    @patch.object(u,'ensure_equivalent_target')
    def test_uncertain_publish_reads_id_before_any_retry(self,_):
        release=self.make_release(42);api=self.api([release],{42:{p.name:u.identity(p) for p in (self.a,self.b)}})
        api.read.side_effect=[release,dict(release,draft=False)];api.request.side_effect=TimeoutError()
        self.assertFalse(u.publish_by_id(api,release,self.tag,self.current,[self.a,self.b],True)['draft']);self.assertEqual(api.request.call_count,1)
    def test_release_list_paginates_and_never_tag_lookup(self):
        from unittest.mock import Mock
        api=u.API('Catfish872/gachaWeb','fixture');api.read=Mock(side_effect=[[self.make_release(i) for i in range(100)],[self.make_release(999)]])
        self.assertEqual(len(api.releases()),101);self.assertTrue(all('/releases?' in c.args[0] for c in api.read.call_args_list))
    @patch.object(u,'ensure_equivalent_target')
    def test_unrelated_release_preserved(self,equivalence):
        unrelated=dict(self.make_release(1),tag_name='other');release=self.make_release(2)
        api=self.api([unrelated,release],{2:{}});self.assertEqual(u.select_release(api,self.tag,self.current,[self.a,self.b])['id'],2);equivalence.assert_called_once()
    @patch.object(u,'ensure_equivalent_target')
    def test_target_conflict_stops_discovery(self,equivalence):
        equivalence.side_effect=u.Conflict('different production');api=self.api([self.make_release(2)],{2:{}})
        with self.assertRaises(u.Conflict):u.select_release(api,self.tag,self.current,[self.a,self.b])
        api.request.assert_not_called()
    @patch.object(u,'ensure_equivalent_target')
    def test_cli_pins_id_across_upload_verify_publish(self,_):
        from unittest.mock import Mock
        path=self.root/('obj-'+'a'*64+'.zip');path.write_bytes(b'fixture');(self.root/'content-upload-list.txt').write_text(path.name+'\n')
        release=self.make_release(42);api=self.api([self.make_release(1),release],{1:{},42:{path.name:u.identity(path)}})
        api.read.side_effect=lambda route:dict(release)
        def patch_release(method,route,data):
            self.assertEqual(method,'PATCH');self.assertTrue(route.endswith('/42'));release.update(u.json.loads(data));return dict(release)
        api.request.side_effect=patch_release
        environment={'GITHUB_REPOSITORY':'Catfish872/gachaWeb','RELEASE_TAG':'android-v2.9.3','GITHUB_SHA':self.current,'GH_TOKEN':'fixture'}
        with patch.object(u,'API',return_value=api),patch.dict(u.os.environ,environment):
            for flags in ([],['--verify-only'],['--publish']):
                with patch.object(u.sys,'argv',['uploader',str(self.root)]+flags):u.main()
        saved=u.json.loads((self.root/'objects-release-id.json').read_text());self.assertEqual(saved['id'],42);self.assertEqual(api.releases.call_count,1)
        self.assertEqual(api.request.call_count,1);self.assertTrue(all('/tags/' not in call.args[0] for call in api.read.call_args_list))
    @patch.object(u,'ensure_equivalent_target')
    def test_cli_stable_draft_pins_and_publishes_id(self,_):
        from unittest.mock import Mock
        (self.root/'content').mkdir()
        files=[self.root/'universal.apk',self.root/'SHA256SUMS.txt',self.root/'content/content-manifest.json',self.root/'content/content-manifest.sig']
        for file in files:file.write_bytes(b'fixture')
        release=dict(self.make_release(77),tag_name='android-v2.9.3',prerelease=False)
        api=self.api([release],{77:{p.name:u.identity(p) for p in files}});api.read.side_effect=lambda route:dict(release)
        def patch_release(method,route,data):
            self.assertEqual(method,'PATCH');self.assertTrue(route.endswith('/77'));release.update(u.json.loads(data));return dict(release)
        api.request.side_effect=patch_release
        env={'GITHUB_REPOSITORY':'Catfish872/gachaWeb','RELEASE_TAG':'android-v2.9.3','GITHUB_SHA':self.current,'GH_TOKEN':'fixture'}
        with patch.object(u,'API',return_value=api),patch.dict(u.os.environ,env):
            for flags in ([],['--verify-only'],['--publish']):
                with patch.object(u.sys,'argv',['uploader',str(self.root),'--stable']+flags):u.main()
        self.assertEqual(u.json.loads((self.root/'stable-release-id.json').read_text())['id'],77);self.assertEqual(api.request.call_count,1)
        self.assertEqual(release['make_latest'],'true');self.assertIs(release['draft'],False);self.assertIs(release['prerelease'],False)
if __name__=='__main__':unittest.main()
