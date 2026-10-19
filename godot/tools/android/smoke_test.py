#!/usr/bin/env python3
"""Real Android input smoke test. Probe observes state; ADB performs every action.

This verifies launch, responsive geometry, menu touch targets, Android Back,
scrolling, rotation and resume. Screenshots/logs are evidence for visual review;
it is not a claim about physical-device performance or complete gameplay.
"""
import base64
import binascii
import json
import os
from pathlib import Path
import re
import struct
import subprocess
import sys
import time
import xml.etree.ElementTree as ET

PACKAGE = 'org.catfish872.voidrift.debug'
ADB = os.environ.get('ADB', 'adb')
MARKER = 'ANDROID_SMOKE_CHUNK '


def adb(*args, binary=False, check=True, timeout=40):
    result = subprocess.run([ADB, *args], check=check, capture_output=True, timeout=timeout)
    return result.stdout if binary else result.stdout.decode('utf-8', errors='replace')


def snapshots(log):
    """Reassemble complete, internally consistent sequence frames only."""
    frames = {}
    invalid = set()
    for line in log.splitlines():
        if MARKER not in line:
            continue
        record = line.split(MARKER, 1)[1]
        match = re.fullmatch(r'(\d+) (\d+) (\d+) (\d+) ([A-Za-z0-9+/=]+)', record)
        if not match:
            continue
        seq, index, count, length = map(int, match.groups()[:4])
        payload = match.group(5)
        if not (1 <= count <= 256 and 0 <= index < count and 600 * (count - 1) < length <= 600 * count):
            invalid.add(seq)
            continue
        expected_size = min(600, length - index * 600)
        if len(payload) != expected_size:
            invalid.add(seq)
            continue
        frame = frames.setdefault(seq, {'count': count, 'length': length, 'chunks': {}})
        if frame['count'] != count or frame['length'] != length:
            invalid.add(seq)
            continue
        existing = frame['chunks'].get(index)
        if existing is not None and existing != payload:
            invalid.add(seq)
        frame['chunks'][index] = payload
    result = []
    for seq, frame in sorted(frames.items()):
        if seq in invalid or len(frame['chunks']) != frame['count']:
            continue
        encoded = ''.join(frame['chunks'][index] for index in range(frame['count']))
        try:
            state = json.loads(base64.b64decode(encoded, validate=True).decode('utf-8'))
        except (ValueError, binascii.Error, UnicodeDecodeError):
            continue
        if isinstance(state, dict) and state.get('seq') == seq:
            result.append(state)
    return result


def wait_for(predicate, description, timeout=30):
    initial = snapshots(adb('logcat', '-d', '-v', 'brief'))
    initial_seq = initial[-1]['seq'] if initial else -1
    deadline = time.monotonic() + timeout
    last = None
    while time.monotonic() < deadline:
        states = snapshots(adb('logcat', '-d', '-v', 'brief'))
        if states:
            last = states[-1]
            fresh = [state for state in states if state['seq'] > initial_seq]
            if len(fresh) >= 2 and all(predicate(state) for state in fresh[-2:]):
                return last
        time.sleep(.5)
    raise AssertionError(f'Timed out: {description}; last state={last}')


def tap(state, name):
    matches = [b for b in state['buttons'] if b['name'] == name]
    assert len(matches) == 1, f'Missing/duplicate visible button: {name}'
    x, y, w, h = matches[0]['rect']
    width, height = state['window']
    assert w > 0 and h > 0 and x >= -1 and y >= -1 and x + w <= width + 1 and y + h <= height + 1, (name, matches[0], state['window'])
    clip = matches[0].get('clip', [0, 0, width, height])
    assert inside(matches[0]['rect'], clip), f'Button clipped: {name}'
    adb('shell', 'input', 'tap', str(round(x + w / 2)), str(round(y + h / 2)))
    time.sleep(.7)


def back():
    adb('shell', 'input', 'keyevent', 'KEYCODE_BACK')
    time.sleep(.7)


def screenshot(output, name, landscape):
    data = adb('exec-out', 'screencap', '-p', binary=True)
    assert data.startswith(b'\x89PNG\r\n\x1a\n'), 'Invalid screenshot'
    width, height = struct.unpack('>II', data[16:24])
    assert (width > height) == landscape, (name, width, height)
    (output / f'{name}.png').write_bytes(data)


def read_ui_hierarchy(output, name):
    remote = '/sdcard/voidrift-smoke-ui.xml'
    adb('shell', 'uiautomator', 'dump', '--compressed', remote, timeout=30)
    xml = adb('shell', 'cat', remote)
    (output / f'{name}.xml').write_text(xml)
    return ET.fromstring(xml)


def immersive_hint_button(root, window):
    # Narrowly identify Android's fullscreen education, never a permission prompt.
    titles = [n for n in root.iter('node') if n.get('package') == 'android'
              and n.get('resource-id') == 'android:id/immersive_cling_title'
              and n.get('text') == 'Viewing full screen']
    if not titles:
        return None
    buttons = [n for n in root.iter('node') if n.get('package') == 'android'
               and n.get('resource-id') == 'android:id/ok'
               and n.get('text') == 'Got it'
               and n.get('class') == 'android.widget.Button'
               and n.get('enabled') == 'true' and n.get('clickable') == 'true']
    assert len(buttons) == 1, 'Fullscreen education has no unique verified dismissal button'
    match = re.fullmatch(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', buttons[0].get('bounds', ''))
    assert match, 'Invalid fullscreen education button bounds'
    left, top, right, bottom = map(int, match.groups())
    assert 0 <= left < right <= window[0] and 0 <= top < bottom <= window[1], 'Fullscreen education button lies outside display'
    return (round((left + right) / 2), round((top + bottom) / 2))


def dismiss_fullscreen_education(output, window):
    hierarchy = read_ui_hierarchy(output, 'first-launch-ui')
    point = immersive_hint_button(hierarchy, window)
    if point is None:
        return
    adb('shell', 'input', 'tap', str(point[0]), str(point[1]))
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        hierarchy = read_ui_hierarchy(output, 'after-fullscreen-education')
        if immersive_hint_button(hierarchy, window) is None:
            return
        time.sleep(.5)
    raise AssertionError('Android fullscreen education remained after verified dismissal')


def geometry(state):
    assert state['page_width'] <= state['scroll_width'] + 1, f'Page horizontal overflow: {state}'
    assert state['logical'][0] >= 320 and state['logical'][1] >= 320, state['logical']


def inside(rect, clip):
    x, y, w, h = rect
    cx, cy, cw, ch = clip
    return x >= cx - 1 and y >= cy - 1 and x + w <= cx + cw + 1 and y + h <= cy + ch + 1


def reveal_menu_target(state, name):
    # Scroll with actual Android gestures until the complete target is exposed.
    # A no-progress gesture fails rather than bypassing the UI through the probe.
    for _ in range(12):
        target = next(b for b in state['buttons'] if b['name'] == name)
        if inside(target['rect'], target['clip']):
            return state
        scroll = next(s for s in state['modal_scrolls'] if s['max'] > 0)
        x, y, w, h = scroll['rect']
        before = scroll['value']
        upward = target['rect'][1] >= target['clip'][1]
        start, end = (.8, .2) if upward else (.2, .8)
        adb('shell', 'input', 'swipe', str(round(x + w * .9)), str(round(y + h * start)), str(round(x + w * .9)), str(round(y + h * end)), '600')
        state = wait_for(lambda s: bool(s['modal_scrolls']) and s['modal_scrolls'][0]['value'] != before, 'menu target scrolling')
    raise AssertionError(f'Menu target remains clipped: {name}')


def visit(state, page):
    tap(state, 'MenuButton')
    state = wait_for(lambda s: s['overlay'] > 0 and any(b['name'] == 'MenuNav_' + page for b in s['buttons']), 'menu open')
    state = reveal_menu_target(state, 'MenuNav_' + page)
    tap(state, 'MenuNav_' + page)
    return wait_for(lambda s: s['screen'] == page and s['overlay'] == 0, page + ' navigation')


def settle_android_configuration(output):
    # sys.boot_completed precedes first-boot package/resource overlay updates.
    # Wait for broadcasts and a stable asset/display configuration before launch,
    # so first-run setup cannot destroy the activity while Godot initializes.
    idle = adb('shell', 'am', 'wait-for-broadcast-idle', timeout=120)
    (output / 'boot-idle.txt').write_text(idle)
    deadline = time.monotonic() + 60
    previous = None
    stable_since = time.monotonic()
    while time.monotonic() < deadline:
        config = adb('shell', 'am', 'get-config')
        signature = '\n'.join(line for line in config.splitlines() if line.startswith(('config:', 'abi:')))
        assert signature, f'Android configuration unavailable: {config}'
        if signature != previous:
            previous = signature
            stable_since = time.monotonic()
        elif time.monotonic() - stable_since >= 5:
            (output / 'boot-config.txt').write_text(config)
            return
        time.sleep(1)
    raise AssertionError('Android first-boot configuration did not settle')


def background_is_stopped(activity):
    blocks = re.split(r'\* Hist\s+#\d+:', activity)
    stopped = any(f'packageName={PACKAGE} ' in block and re.search(r'\bstate=STOPPED\b', block) for block in blocks[1:])
    resumed = re.findall(r'(?:topResumedActivity|mResumedActivity|ResumedActivity)=ActivityRecord\{[^}]+\}', activity)
    return stopped and bool(resumed) and all(PACKAGE not in item for item in resumed)


def wait_for_completed_background(output):
    deadline = time.monotonic() + 40
    previous = None
    stable_since = time.monotonic()
    while time.monotonic() < deadline:
        activity = adb('shell', 'dumpsys', 'activity', 'activities')
        config = adb('shell', 'am', 'get-config')
        signature = config if background_is_stopped(activity) else None
        if signature is None or signature != previous:
            previous = signature
            stable_since = time.monotonic()
        elif time.monotonic() - stable_since >= 5:
            (output / 'settled-background-activity.txt').write_text(activity)
            (output / 'settled-background-config.txt').write_text(config)
            return
        time.sleep(.5)
    raise AssertionError('App did not reach STOPPED with another foreground activity and stable display')


def check_background_resume(component, output):
    results = []
    modes = ['rapid', 'settled', 'rapid_again']
    for mode in modes:
        try:
            adb('shell', 'input', 'keyevent', 'KEYCODE_HOME')
            if mode == 'settled':
                wait_for_completed_background(output)
            else:
                # Preserve the original one-second rapid-return regression gate.
                time.sleep(1)
            adb('shell', 'am', 'start', '-W', '-n', component)
            time.sleep(1)
            state = wait_for(lambda s: s['screen'] == 'home', mode + ' resume')
            tap(state, 'MenuButton')
            wait_for(lambda s: s['overlay'] > 0, 'touch after ' + mode + ' resume')
            screenshot(output, mode + '-resume-menu', True)
            back()
            wait_for(lambda s: s['overlay'] == 0, 'dismiss after ' + mode + ' resume')
            results.append({'mode': mode, 'passed': True})
        except (AssertionError, subprocess.SubprocessError) as error:
            results.append({'mode': mode, 'passed': False, 'error': str(error)})
            image = adb('exec-out', 'screencap', '-p', binary=True, check=False)
            (output / (mode + '-resume-failure.png')).write_bytes(image)
            (output / (mode + '-resume-logcat.txt')).write_text(adb('logcat', '-d', '-v', 'threadtime'))
            (output / 'resume-results.json').write_text(json.dumps(results, indent=2))
            if mode != modes[-1]:
                # Restart solely to collect the remaining independent diagnostics.
                # The recorded failure remains a hard gate for this whole run.
                adb('shell', 'am', 'force-stop', PACKAGE)
                adb('logcat', '-c')
                adb('shell', 'am', 'start', '-W', '-n', component)
                wait_for(lambda s: s['screen'] == 'home', 'diagnostic restart', 90)
    (output / 'resume-results.json').write_text(json.dumps(results, indent=2))
    assert all(item['passed'] for item in results), 'Background/resume failed: ' + json.dumps(results)


def run(apk, output):
    adb('install', '-r', str(apk))
    adb('shell', 'pm', 'clear', PACKAGE)
    adb('shell', 'settings', 'put', 'system', 'accelerometer_rotation', '0')
    adb('shell', 'settings', 'put', 'system', 'user_rotation', '0')
    settle_android_configuration(output)
    adb('logcat', '-c')
    component = adb('shell', 'cmd', 'package', 'resolve-activity', '--brief', PACKAGE).strip().splitlines()[-1]
    assert '/' in component, f'Cannot resolve activity: {component}'
    adb('shell', 'am', 'start', '-W', '-n', component)
    state = wait_for(lambda s: s['screen'] == 'home' and s['overlay'] == 0, 'Android game startup', 90)
    assert state['window'][1] > state['window'][0], 'Portrait startup expected'
    geometry(state)
    dismiss_fullscreen_education(output, state['window'])
    state = wait_for(lambda s: s['screen'] == 'home' and s['overlay'] == 0, 'home after fullscreen education')
    screenshot(output, 'portrait-home', False)
    # Menu is dismissed by the real Android Back event and the game stays alive.
    tap(state, 'MenuButton')
    wait_for(lambda s: s['overlay'] > 0, 'menu before Back')
    screenshot(output, 'portrait-menu', False)
    back()
    state = wait_for(lambda s: s['screen'] == 'home' and s['overlay'] == 0, 'Back dismisses menu')
    pages = ['story', 'summon', 'party', 'growth', 'relics', 'abyss', 'shop', 'save']
    for page in pages:
        state = visit(state, page)
        geometry(state)
        screenshot(output, 'portrait-' + page, False)
        if state['scroll_max'] > 10:
            x, y, w, h = state['scroll_rect']
            before = state['scroll']
            adb('shell', 'input', 'swipe', str(round(x + w * .85)), str(round(y + h * .8)), str(round(x + w * .85)), str(round(y + h * .2)), '600')
            state = wait_for(lambda s: s['scroll'] > before + 5, page + ' finger scroll')
            screenshot(output, 'portrait-' + page + '-scrolled', False)
        back()
        state = wait_for(lambda s: s['screen'] == 'home' and s['overlay'] == 0, page + ' Android Back')
    adb('shell', 'settings', 'put', 'system', 'user_rotation', '1')
    adb('emu', 'sensor', 'set', 'acceleration', '9.8:0:0')
    state = wait_for(lambda s: s['window'][0] > s['window'][1] and s['logical'][0] > s['logical'][1], 'landscape adaptation')
    geometry(state)
    screenshot(output, 'landscape-home', True)
    tap(state, 'MenuButton')
    wait_for(lambda s: s['overlay'] > 0, 'landscape menu open')
    screenshot(output, 'landscape-menu', True)
    back()
    state = wait_for(lambda s: s['screen'] == 'home' and s['overlay'] == 0, 'landscape menu dismissed')
    state = visit(state, 'growth')
    geometry(state)
    screenshot(output, 'landscape-growth', True)
    assert state['scroll_max'] > 10, 'Landscape growth must expose its scrollable content'
    x, y, w, h = state['scroll_rect']
    before = state['scroll']
    adb('shell', 'input', 'swipe', str(round(x + w * .85)), str(round(y + h * .8)), str(round(x + w * .85)), str(round(y + h * .2)), '600')
    state = wait_for(lambda s: s['screen'] == 'growth' and s['scroll'] > before + 5, 'landscape growth finger scroll')
    screenshot(output, 'landscape-growth-scrolled', True)
    back()
    state = wait_for(lambda s: s['screen'] == 'home' and s['overlay'] == 0, 'landscape Back')
    check_background_resume(component, output)
    assert adb('shell', 'pidof', PACKAGE).strip(), 'Android app process disappeared'
    logs = adb('logcat', '-d', '-v', 'threadtime')
    errors = [line for line in logs.splitlines() if re.search(r'SCRIPT ERROR|Parse Error|FATAL EXCEPTION|Fatal signal|ANR in ' + re.escape(PACKAGE), line) or ('godot' in line.lower() and re.search(r'\bERROR:', line))]
    assert not errors, '\n'.join(errors)
    (output / 'result.json').write_text(json.dumps({'passed': True, 'android_api': adb('shell', 'getprop', 'ro.build.version.sdk').strip(), 'abi': adb('shell', 'getprop', 'ro.product.cpu.abi').strip(), 'pages': pages, 'checks': ['portrait launch', 'all menu tabs by touch', 'scrolling where content exceeds viewport', 'Android Back', 'landscape adaptation', 'background/resume', 'runtime error log']}, indent=2))
    print('ANDROID RUNTIME SMOKE PASSED')


if __name__ == '__main__':
    apk, output = map(Path, sys.argv[1:])
    output.mkdir(parents=True, exist_ok=True)
    try:
        run(apk, output)
    finally:
        try:
            read_ui_hierarchy(output, 'final-ui')
        except (subprocess.SubprocessError, ET.ParseError, OSError) as error:
            (output / 'final-ui-error.txt').write_text(str(error))
        image = adb('exec-out', 'screencap', '-p', binary=True, check=False)
        if image.startswith(b'\x89PNG\r\n\x1a\n'):
            (output / 'final-screen.png').write_bytes(image)
        (output / 'logcat.txt').write_text(adb('logcat', '-d', '-v', 'threadtime', check=False))
        (output / 'activity.txt').write_text(adb('shell', 'dumpsys', 'activity', 'activities', check=False))
        (output / 'window.txt').write_text(adb('shell', 'dumpsys', 'window', 'displays', check=False))
