#!/usr/bin/env python3
"""Fail closed when Android version metadata and export presets diverge."""
import argparse
import configparser
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]

def validate(root=ROOT, tag=None):
    data = json.loads((root / 'data/version.json').read_text())
    name = data['version_name']
    assert isinstance(name, str) and re.fullmatch(r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]?)\.(0|[1-9][0-9]?)', name), 'Invalid version name'
    major, minor, patch = map(int, name.split('.'))
    code = major * 10000 + minor * 100 + patch
    assert 0 < code <= 2100000000, 'Android version code out of range'
    assert type(data['version_code']) is int and data['version_code'] == code, 'Version code mismatch'
    assert data['repository'] == 'Catfish872/gachaWeb', 'Wrong update repository'
    assert data['release_asset'] == 'universal.apk', 'Wrong release asset'
    if tag is not None:
        assert tag == 'android-v' + name, 'Release tag must exactly match version metadata'
    cfg = configparser.ConfigParser(interpolation=None)
    cfg.read(root / 'export_presets.cfg')
    for i, label, package in [(0, 'Android Debug', 'org.catfish872.voidrift.debug'), (1, 'Android Release', 'org.catfish872.voidrift')]:
        preset = cfg[f'preset.{i}']
        opts = cfg[f'preset.{i}.options']
        assert json.loads(preset['name']) == label, 'Wrong preset name'
        assert int(opts['version/code']) == code and json.loads(opts['version/name']) == name, 'Preset version mismatch'
        assert json.loads(opts['package/unique_name']) == package, 'Wrong package name'
        for setting in ['package/signed', 'architectures/armeabi-v7a', 'architectures/arm64-v8a', 'permissions/internet']:
            assert opts[setting] == 'true', f'Required setting disabled: {setting}'
        for setting in ['architectures/x86', 'architectures/x86_64', 'permissions/read_external_storage', 'permissions/write_external_storage', 'gradle_build/use_gradle_build']:
            assert opts[setting] == 'false', f'Unexpected setting enabled: {setting}'
        for pattern in ['tests/*', 'validation/*', 'tools/*', '*.keystore', '*.jks', '*.key']:
            assert pattern in json.loads(preset['exclude_filter']).split(','), f'Missing exclusion: {pattern}'
    return data

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--tag')
    args = parser.parse_args()
    try:
        metadata = validate(tag=args.tag)
    except (AssertionError, KeyError, ValueError, OSError, configparser.Error) as exc:
        raise SystemExit(f'VERSION VALIDATION FAILED: {exc}')
    print(f"VERSION VALIDATION PASSED: {metadata['version_name']} ({metadata['version_code']})")
