#!/usr/bin/env python3
"""Offline build guard tests. Mock SDK tools; real APK verification runs in CI."""
import contextlib
import io
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools/build'))
from validate_version import validate
from verify_apk import verify

class BuildValidationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'data').mkdir()
        for name in ['project.godot', 'export_presets.cfg', 'data/version.json']:
            shutil.copy(ROOT / name, self.root / name)
        self.metadata = validate(self.root)

    def test_matching_version_and_tag(self):
        self.assertEqual(validate(self.root, 'android-v2.0.0')['version_code'], 20000)

    def test_bad_tags(self):
        for tag in ['v2.0.0', 'android-v2.0.1', 'android-v2.0.0-beta', 'android-v2.0.0\n']:
            with self.subTest(tag=tag), self.assertRaises(AssertionError):
                validate(self.root, tag)

    def test_bad_metadata(self):
        for key, value in [('version_name', '2.100.0'), ('version_name', '02.0.0'), ('version_name', '0.0.0'), ('version_code', 20001), ('version_code', 20000.0), ('repository', 'evil/repo'), ('release_asset', 'evil.apk')]:
            (self.root / 'data/version.json').write_text(json.dumps({**self.metadata, key: value}))
            with self.subTest(key=key, value=value), self.assertRaises(AssertionError):
                validate(self.root)

    def test_android_texture_import_required(self):
        path = self.root / 'project.godot'
        path.write_text(path.read_text().replace('textures/vram_compression/import_etc2_astc=true', 'textures/vram_compression/import_etc2_astc=false'))
        with self.assertRaisesRegex(AssertionError, 'ETC2/ASTC'):
            validate(self.root)

    def test_export_preset_version_must_match(self):
        path = self.root / 'export_presets.cfg'
        path.write_text(path.read_text().replace('version/code=20000', 'version/code=20001', 1))
        with self.assertRaisesRegex(AssertionError, 'Preset version'):
            validate(self.root)

    def test_apk_valid_and_rejection_fixtures(self):
        fingerprint = 'a' * 64
        badge = "package: name='org.catfish872.voidrift.debug' versionCode='20000' versionName='2.0.0'\nsdkVersion:'24'\ntargetSdkVersion:'36'\nuses-permission: name='android.permission.INTERNET'\n"
        signature = 'Signer #1 certificate SHA-256 digest: ' + fingerprint + '\n'
        entries = {
            'assets/data/version.json': json.dumps(self.metadata),
            'assets/data/catalog.json': '{}',
            'assets/data/rogue_v2.json': '{}',
            'assets/assets/fonts/LICENSE-Noto.txt': 'license',
            'assets/assets/fonts/LICENSE-NotoSymbols.txt': 'license',
            'lib/armeabi-v7a/libgodot_android.so': 'fixture',
            'lib/arm64-v8a/libgodot_android.so': 'fixture',
        }
        for scenario in ['valid', 'secret', 'missing-license', 'wrong-signature', 'wrong-package', 'wrong-sdk', 'missing-arm64']:
            with self.subTest(scenario=scenario):
                files = entries.copy()
                if scenario == 'secret':
                    files['assets/private.key'] = 'fixture'
                if scenario == 'missing-license':
                    del files['assets/assets/fonts/LICENSE-Noto.txt']
                if scenario == 'missing-arm64':
                    del files['lib/arm64-v8a/libgodot_android.so']
                apk = self.root / 'fixture.apk'
                with zipfile.ZipFile(apk, 'w') as archive:
                    for name, body in files.items():
                        archive.writestr(name, body)
                current_badge = badge
                if scenario == 'wrong-package':
                    current_badge = badge.replace('voidrift.debug', 'evil')
                if scenario == 'wrong-sdk':
                    current_badge = badge.replace("sdkVersion:'24'", "sdkVersion:'23'")
                outputs = [current_badge, signature.replace(fingerprint, 'b' * 64) if scenario == 'wrong-signature' else signature]
                with patch('verify_apk.subprocess.check_output', side_effect=outputs), patch('verify_apk.subprocess.run'), contextlib.redirect_stdout(io.StringIO()):
                    if scenario == 'valid':
                        verify(apk, '/fixture/sdk', 'debug', fingerprint)
                    else:
                        with self.assertRaises(AssertionError):
                            verify(apk, '/fixture/sdk', 'debug', fingerprint)

if __name__ == '__main__':
    unittest.main(verbosity=2)
