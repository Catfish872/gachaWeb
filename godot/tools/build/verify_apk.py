#!/usr/bin/env python3
"""Check the actual APK manifest, native architectures, contents and certificate."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import zipfile
from validate_version import validate


def verify(apk, sdk, mode, fingerprint):
    data = validate()
    build = Path(sdk) / 'build-tools/35.0.1'
    subprocess.run([str(build / 'zipalign'), '-c', '-P', '16', '4', str(apk)], check=True, capture_output=True)
    badging = subprocess.check_output([str(build / 'aapt'), 'dump', 'badging', str(apk)], text=True)
    package = 'org.catfish872.voidrift' + ('.debug' if mode == 'debug' else '')
    expected = f"package: name='{package}' versionCode='{data['version_code']}' versionName='{data['version_name']}'"
    assert expected in badging, 'APK package or version mismatch'
    assert "sdkVersion:'24'" in badging, 'Unexpected minimum SDK'
    assert "targetSdkVersion:'36'" in badging, 'Unexpected target SDK'
    assert "uses-permission: name='android.permission.INTERNET'" in badging, 'Internet permission missing'
    assert 'android.permission.READ_EXTERNAL_STORAGE' not in badging and 'android.permission.WRITE_EXTERNAL_STORAGE' not in badging, 'Unexpected storage permission'
    signature = subprocess.check_output([str(build / 'apksigner'), 'verify', '--verbose', '--print-certs', str(apk)], text=True)
    actual = re.findall(r'^Signer #\d+ certificate SHA-256 digest: ([0-9a-fA-F]+)$', signature, re.M)
    wanted = fingerprint.replace(':', '').strip().lower()
    assert re.fullmatch(r'[0-9a-f]{64}', wanted), 'Invalid expected certificate fingerprint'
    assert len(actual) == 1 and actual[0].lower() == wanted, 'APK signing certificate mismatch'
    if mode == 'release':
        assert not re.search(r'CN\s*=\s*Android Debug', signature, re.I), 'Production release uses debug certificate'
        assert 'application-debuggable' not in badging, 'Production APK is debuggable'
    with zipfile.ZipFile(apk) as archive:
        names = archive.namelist()
        architectures = {name.split('/')[1] for name in names if name.startswith('lib/') and name.endswith('.so')}
        assert architectures == {'armeabi-v7a', 'arm64-v8a'}, 'Unexpected native architectures'
        for name in names:
            lower = name.lower()
            assert not lower.endswith(('.keystore', '.jks', '.p12', '.pfx', '.pem', '.key', '.log', '.md')), f'Forbidden file in APK: {name}'
            assert not re.search(r'(^|/)(tests|validation|tools|build)/', lower), f'Development files in APK: {name}'
        for required in ['data/version.json', 'data/catalog.json', 'data/rogue_v2.json', 'assets/fonts/LICENSE-Noto.txt', 'assets/fonts/LICENSE-NotoSymbols.txt']:
            assert 'assets/' + required in names and archive.getinfo('assets/' + required).file_size > 0, 'Required packaged resource missing: ' + required
        assert json.loads(archive.read('assets/data/version.json')) == data, 'Packaged version metadata differs'
    print('APK VERIFIED: package, version, SDK, permissions, ARM architectures, contents and signature')

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('apk', type=Path)
    parser.add_argument('--sdk', required=True)
    parser.add_argument('--mode', choices=['debug', 'release'], required=True)
    parser.add_argument('--fingerprint', required=True)
    args = parser.parse_args()
    try:
        verify(args.apk, args.sdk, args.mode, args.fingerprint)
    except (AssertionError, ValueError, OSError, subprocess.CalledProcessError, zipfile.BadZipFile) as exc:
        raise SystemExit(f'APK VALIDATION FAILED: {exc}')
