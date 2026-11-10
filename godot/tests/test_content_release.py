#!/usr/bin/env python3
import importlib.util, json, tempfile, unittest, zipfile
from pathlib import Path
spec=importlib.util.spec_from_file_location('content_release',Path(__file__).resolve().parents[1]/'tools/build/content_release.py'); c=importlib.util.module_from_spec(spec); spec.loader.exec_module(c)
class ContentBuildTests(unittest.TestCase):
    def fixture(self,root,version='2.9.3',asset=b'unchanged'):
        apk=root/(version+'.apk')
        with zipfile.ZipFile(apk,'w') as z:
            for p,b in {'data/version.json':json.dumps({'version_name':version,'version_code':int(version.split('.')[-1])+20900}),'data/content_platform.json':json.dumps({'platform_id':'a'*64}),'.godot/imported/art.ctex':asset,'scripts/main.gdc':b'logic','main.tscn.remap':'[remap]\npath="res://.godot/exported/main.scn"','.godot/exported/main.scn':b'scene','content_bootstrap.tscn.remap':'[remap]\npath="res://.godot/exported/bootstrap.scn"','.godot/exported/bootstrap.scn':b'protected','scripts/content_store.gdc':b'protected'}.items(): z.writestr('assets/'+p,b)
        return apk
    def test_deterministic_and_protected(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d); apk=self.fixture(root)
            a=c.build(apk,root/'a'); b=c.build(apk,root/'b'); self.assertEqual(a,b)
            logic=(root/'a'/('obj-'+a['logic']['sha256']+'.zip'))
            with zipfile.ZipFile(logic) as z:
                self.assertNotIn('scripts/content_store.gdc',z.namelist()); self.assertNotIn('.godot/exported/bootstrap.scn',z.namelist()); self.assertIn('.godot/exported/main.scn',z.namelist())
    def test_multi_version_jump(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d); a=c.build(self.fixture(root),root/'a')
            b=c.build(self.fixture(root,'2.9.7'),root/'b',a)
            self.assertEqual(a['assets'],b['assets']); self.assertNotEqual(a['logic']['sha256'],b['logic']['sha256'])
            self.assertEqual(len(list((root/'b').glob('obj-*.zip'))),1)
            newer=c.build(self.fixture(root,'2.9.8',b'changed'),root/'c',b)
            self.assertNotEqual(b['assets'][0]['sha256'],newer['assets'][0]['sha256'])
    def test_path_rejection(self):
        with self.assertRaises(ValueError): c.pack({'../bad':b'x'})
    def test_previous_host_not_trusted(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d); apk=self.fixture(root); a=c.build(apk,root/'a'); a['assets'][0]['url']='https://example.com/obj-'+a['assets'][0]['sha256']+'.zip'
            b=c.build(apk,root/'b',a); self.assertTrue(b['assets'][0]['url'].startswith('https://github.com/'))
if __name__=='__main__': unittest.main()
