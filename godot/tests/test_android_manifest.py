import importlib.util
from pathlib import Path
import struct
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('normalize_manifest', ROOT/'tools/build/normalize_manifest.py')
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


def fixture(utf8=True, override=None):
    strings = [mod.ANDROID, 'uses-feature', 'name', 'required', 'version', 'android.hardware.vulkan.level', 'android.hardware.vulkan.version', 'false', 'true', '1', '0x400003', 'unknown']
    encoded, offsets = b'', []
    for text in strings:
        offsets.append(len(encoded))
        if utf8:
            wire = text.encode()
            encoded += bytes([len(text), len(wire)])+wire+b'\0'
        else:
            encoded += struct.pack('<H',len(text))+text.encode('utf-16-le')+b'\0\0'
    encoded += b'\0'*(-len(encoded)%4)
    start = 28+4*len(strings)
    pool = struct.pack('<HHIIIIII',1,28,start+len(encoded),len(strings),0,0x100 if utf8 else 0,start,0)+struct.pack('<'+'I'*len(offsets),*offsets)+encoded
    chunks = [pool]
    positions = []
    for feature, required, version in ((5,7,9),(6,8,10)):
        attrs = [(0,2,feature,3,feature),(0,3,required,3,required),(0,4,version,3,version)]
        if override:
            attrs = override(feature, attrs)
        size = 36+20*len(attrs)
        chunk = struct.pack('<HHIII',0x102,16,size,0,0xffffffff)+struct.pack('<IIHHHHHH',0xffffffff,1,20,20,len(attrs),0,0,0)
        for ns,key,raw,typ,value in attrs:
            positions.append(8+sum(map(len,chunks))+len(chunk))
            chunk += struct.pack('<IIIHBBI',ns,key,raw,8,0,typ,value)
        chunks.append(chunk)
        chunks.append(struct.pack('<HHIIIII',0x103,16,24,0,0xffffffff,0xffffffff,1))
    data = b''.join(chunks)
    return struct.pack('<HHI',3,8,8+len(data))+data, positions


class AndroidManifestTests(unittest.TestCase):
    def test_utf8_and_utf16_precise_typed_values_and_unchanged_rest(self):
        for utf8 in (True,False):
            with self.subTest(utf8=utf8):
                data, positions = fixture(utf8)
                result = mod.normalize_axml(data)
                self.assertEqual(len(result),len(data))
                allowed = set()
                for index,typ,value in ((1,0x12,0),(2,0x10,1),(4,0x12,0xffffffff),(5,0x11,0x400003)):
                    p=positions[index]
                    self.assertEqual(result[p+15],typ)
                    self.assertEqual(struct.unpack_from('<I',result,p+16)[0],value)
                    allowed.update(range(p+15,p+20))
                self.assertTrue(all(a==b or i in allowed for i,(a,b) in enumerate(zip(data,result))))
                self.assertEqual(mod.normalize_axml(result),result)

    def test_unknown_raw_literal_rejected(self):
        def edit(f, attrs):
            attrs[1]=(0,3,11,3,11)
            return attrs
        with self.assertRaises(ValueError): mod.normalize_axml(fixture(override=edit)[0])

    def test_string_payload_must_equal_raw_pool_index(self):
        def edit(f,attrs):
            ns,key,raw,typ,value=attrs[1]
            attrs[1]=(ns,key,raw,typ,8 if raw==7 else 7)
            return attrs
        with self.assertRaises(ValueError): mod.normalize_axml(fixture(override=edit)[0])

    def test_unexpected_attribute_rejected(self):
        def edit(f,attrs):
            attrs.append((0,11,7,3,7))
            return attrs
        with self.assertRaises(ValueError): mod.normalize_axml(fixture(override=edit)[0])

    def test_wrong_attribute_namespace_rejected(self):
        def edit(f,attrs):
            a=list(attrs[1]);a[0]=11;attrs[1]=tuple(a);return attrs
        with self.assertRaises(ValueError): mod.normalize_axml(fixture(override=edit)[0])

    def test_unexpected_numeric_value_rejected(self):
        def edit(f,attrs):
            ns,key,raw,typ,value=attrs[2]
            attrs[2]=(ns,key,raw,0x10,42);return attrs
        with self.assertRaises(ValueError): mod.normalize_axml(fixture(override=edit)[0])

    def test_truncated_and_invalid_chunks_rejected(self):
        data,_=fixture()
        for cut in (0,4,8,len(data)-1):
            with self.subTest(cut=cut), self.assertRaises(ValueError): mod.normalize_axml(data[:cut])
        bad=bytearray(data);struct.pack_into('<I',bad,12,0)
        with self.assertRaises(ValueError): mod.normalize_axml(bytes(bad))

    def test_duplicate_feature_rejected(self):
        def edit(f,attrs):
            attrs[0]=(0,2,5,3,5);return attrs
        with self.assertRaises(ValueError): mod.normalize_axml(fixture(override=edit)[0])

    def test_apk_entry_bytes_preserved_and_old_signatures_removed(self):
        data,_=fixture()
        with tempfile.TemporaryDirectory() as d:
            source,target=Path(d)/'in.apk',Path(d)/'out.apk'
            with zipfile.ZipFile(source,'w') as z:
                z.writestr('AndroidManifest.xml',data)
                z.writestr('assets/game.pck',b'original\x00payload')
                z.writestr('META-INF/services/example',b'not a signature')
                for name in ('MANIFEST.MF','CERT.SF','CERT.RSA','CERT.DSA','CERT.EC'):
                    z.writestr('META-INF/'+name,b'old signature')
            mod.normalize_apk(source,target)
            with zipfile.ZipFile(target) as z:
                self.assertEqual(set(z.namelist()),{'AndroidManifest.xml','assets/game.pck','META-INF/services/example'})
                self.assertEqual(z.read('assets/game.pck'),b'original\x00payload')
                self.assertEqual(z.read('META-INF/services/example'),b'not a signature')
                self.assertEqual(z.read('AndroidManifest.xml'),mod.normalize_axml(data))

    def test_missing_feature_and_invalid_metadata_rejected(self):
        def missing(f,attrs):
            if f == 6: attrs[0]=(0,2,11,3,11)
            return attrs
        with self.assertRaises(ValueError): mod.normalize_axml(fixture(override=missing)[0])
        data,positions=fixture()
        for offset,value in ((positions[1]+12,7),(positions[1]+14,1)):
            bad=bytearray(data);bad[offset]=value
            with self.subTest(offset=offset), self.assertRaises(ValueError): mod.normalize_axml(bytes(bad))

    def test_bad_string_index_and_pool_bounds_rejected(self):
        data,positions=fixture()
        bad=bytearray(data);struct.pack_into('<I',bad,positions[1]+8,0xffffffff)
        with self.assertRaises(ValueError): mod.normalize_axml(bytes(bad))
        bad=bytearray(data);struct.pack_into('<I',bad,8+20,len(data)+100)
        with self.assertRaises(ValueError): mod.normalize_axml(bytes(bad))

    def test_failure_does_not_replace_existing_output(self):
        with tempfile.TemporaryDirectory() as d:
            source,target=Path(d)/'bad.apk',Path(d)/'existing.apk'
            target.write_bytes(b'unchanged output')
            with zipfile.ZipFile(source,'w') as z: z.writestr('AndroidManifest.xml',b'bad')
            with self.assertRaises(ValueError): mod.normalize_apk(source,target)
            self.assertEqual(target.read_bytes(),b'unchanged output')

    def test_same_input_output_rejected(self):
        with self.assertRaises(ValueError): mod.normalize_apk('same.apk','same.apk')

if __name__=='__main__': unittest.main()
