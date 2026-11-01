#!/usr/bin/env python3
"""Repair only Godot 4.6.3's two Vulkan feature AXML typed values.

No XML reserialization: only the type byte and four-byte data field change.
Signing is deliberately external; this command never accesses credentials.
"""
import argparse
import copy
from pathlib import Path
import re
import struct
import tempfile
import zipfile

ANDROID = 'http://schemas.android.com/apk/res/android'
EXPECTED = {
    'android.hardware.vulkan.level': ('false', '1', 0, 0x10, 1),
    'android.hardware.vulkan.version': ('true', '0x400003', 0xffffffff, 0x11, 0x400003),
}

def require(condition, message):
    if not condition:
        raise ValueError(message)


def normalize_axml(data):
    def u16(pos):
        require(0 <= pos <= len(data)-2, 'Truncated uint16')
        return struct.unpack_from('<H', data, pos)[0]
    def u32(pos):
        require(0 <= pos <= len(data)-4, 'Truncated uint32')
        return struct.unpack_from('<I', data, pos)[0]
    require(len(data) >= 8 and u16(0) == 3 and u16(2) == 8 and u32(4) == len(data), 'Invalid AXML header')
    strings = None
    out = bytearray(data)
    allowed = set()
    seen = set()
    pos = 8
    while pos < len(data):
        kind, header, length = u16(pos), u16(pos+2), u32(pos+4)
        end = pos + length
        require(header >= 8 and length >= header and end <= len(data), 'Invalid AXML chunk bounds')
        if kind == 1:
            require(strings is None and header >= 28, 'Invalid/duplicate string pool')
            count, styles, flags, start, style_start = [u32(pos+i) for i in (8,12,16,20,24)]
            require(header + 4*(count+styles) <= start <= length, 'Invalid string table bounds')
            limit = pos + (style_start or length)
            require(pos+start <= limit <= end, 'Invalid string payload bounds')
            strings = []
            def size_at(p, utf8):
                unit = 1 if utf8 else 2
                require(p+unit <= limit, 'Truncated string length')
                value = data[p] if utf8 else u16(p)
                high = 0x80 if utf8 else 0x8000
                p += unit
                if value & high:
                    require(p+unit <= limit, 'Truncated extended string length')
                    tail = data[p] if utf8 else u16(p)
                    value = ((value & (high-1)) << (8 if utf8 else 16)) | tail
                    p += unit
                return value, p
            for index in range(count):
                p = pos + start + u32(pos+header+4*index)
                require(pos+start <= p < limit, 'Invalid string offset')
                chars, p = size_at(p, bool(flags & 0x100))
                if flags & 0x100:
                    size, p = size_at(p, True)
                    require(p+size+1 <= limit and data[p+size] == 0, 'Invalid UTF8 terminator')
                    value = data[p:p+size].decode('utf-8')
                    require(len(value.encode('utf-16-le'))//2 == chars, 'UTF8 character length mismatch')
                else:
                    size = chars*2
                    require(p+size+2 <= limit and data[p+size:p+size+2] == b'\0\0', 'Invalid UTF16 terminator')
                    value = data[p:p+size].decode('utf-16-le')
                strings.append(value)
        elif kind == 0x102:
            require(strings is not None and header == 16 and length >= 36, 'Invalid start element')
            def string(index):
                require(index < len(strings), 'Invalid string index')
                return strings[index]
            name = string(u32(pos+20))
            attr_start, attr_size, count = u16(pos+24), u16(pos+26), u16(pos+28)
            require(attr_size >= 20 and pos+16+attr_start+attr_size*count <= end, 'Invalid attribute bounds')
            if name == 'uses-feature':
                attrs = []
                for n in range(count):
                    p = pos+16+attr_start+n*attr_size
                    attrs.append((p, u32(p), string(u32(p+4)), u32(p+8), data[p+15], u32(p+16)))
                names = [a for a in attrs if a[2] == 'name']
                require(len(names) <= 1, 'Duplicate feature name')
                if names:
                    p, ns, key, raw, typ, value = names[0]
                    feature = string(value) if typ == 3 else (string(raw) if raw != 0xffffffff else '')
                    if feature in EXPECTED:
                        require(feature not in seen, 'Duplicate Vulkan feature')
                        seen.add(feature)
                        require(attr_start == 20 and attr_size == 20 and count == 3, 'Unexpected Vulkan feature layout')
                        require([a[2] for a in attrs] == ['name', 'required', 'version'], 'Unexpected Vulkan attributes')
                        for a in attrs:
                            require(string(a[1]) == ANDROID and u16(a[0]+12) == 8 and data[a[0]+14] == 0, 'Invalid Vulkan attribute metadata')
                        require(typ == 3 and raw == value and string(raw) == feature, 'Invalid Vulkan feature name value')
                        required, version, bool_value, int_type, int_value = EXPECTED[feature]
                        for a, literal, new_type, new_value in ((attrs[1], required, 0x12, bool_value), (attrs[2], version, int_type, int_value)):
                            p, ns, key, raw, typ, value = a
                            require(string(raw) == literal, 'Unexpected Vulkan raw value')
                            if typ == 3:
                                require(value == raw, 'Vulkan raw/typed string mismatch')
                            else:
                                require(typ == new_type and value == new_value, 'Unexpected Vulkan typed value')
                            out[p+15] = new_type
                            struct.pack_into('<I', out, p+16, new_value)
                            allowed.update(range(p+15, p+20))
        pos = end
    require(pos == len(data) and seen == set(EXPECTED), 'Expected exactly both Godot Vulkan features')
    require(len(out) == len(data) and all(a == b or i in allowed for i,(a,b) in enumerate(zip(data,out))), 'Non-target AXML byte changed')
    return bytes(out)


def is_signature(name):
    return bool(re.fullmatch(r'META-INF/(?:MANIFEST\.MF|[^/]+\.(?:SF|RSA|DSA|EC))', name, re.I))


def normalize_apk(source, destination):
    source, destination = Path(source), Path(destination)
    require(source.resolve() != destination.resolve(), 'Input and output must differ')
    with zipfile.ZipFile(source) as archive:
        infos = archive.infolist()
        require(len({i.filename for i in infos}) == len(infos), 'Duplicate ZIP entry')
        require(sum(i.filename == 'AndroidManifest.xml' for i in infos) == 1, 'Manifest missing')
        original = archive.read('AndroidManifest.xml')
        normalized = normalize_axml(original)
        with tempfile.NamedTemporaryFile(dir=destination.parent, suffix='.apk', delete=False) as handle:
            temporary = Path(handle.name)
        try:
            with zipfile.ZipFile(temporary, 'w') as output:
                output.comment = archive.comment
                for info in infos:
                    if not is_signature(info.filename):
                        output.writestr(copy.copy(info), normalized if info.filename == 'AndroidManifest.xml' else archive.read(info))
            with zipfile.ZipFile(temporary) as check:
                expected = {i.filename for i in infos if not is_signature(i.filename)}
                require(set(check.namelist()) == expected and check.testzip() is None, 'ZIP copy verification failed')
                for name in expected:
                    require(check.read(name) == (normalized if name == 'AndroidManifest.xml' else archive.read(name)), 'APK entry changed: '+name)
            temporary.replace(destination)
        finally:
            temporary.unlink(missing_ok=True)

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('destination', type=Path)
    args = parser.parse_args()
    normalize_apk(args.source, args.destination)
    print('Normalized exact Godot Vulkan manifest typed values; unsigned APK ready for alignment/signing')
