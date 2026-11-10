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
    def test_creation_uncertain_success_resolves_tag(self):
        from unittest.mock import Mock
        api=Mock(repo='Catfish872/gachaWeb');api.read.side_effect=[u.HTTPFailure(404,{},'missing'),{'id':1}];api.request.side_effect=TimeoutError()
        self.assertEqual(u.get_or_create_release(api,'android-v2.9.3-assets','a'*40),{'id':1});self.assertEqual(api.request.call_count,1);api.sleep.assert_called_once_with(60)
    def test_creation_secondary_limit_resolves_before_retry(self):
        from unittest.mock import Mock
        api=Mock(repo='Catfish872/gachaWeb');api.read.side_effect=[u.HTTPFailure(404,{},'missing'),u.HTTPFailure(404,{},'missing')];api.request.side_effect=[u.HTTPFailure(429,{'Retry-After':'120'},'limited'),{'id':1}]
        self.assertEqual(u.get_or_create_release(api,'android-v2.9.3-assets','a'*40),{'id':1});self.assertEqual(api.read.call_count,2);api.sleep.assert_called_once_with(120)
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
if __name__=='__main__':unittest.main()
