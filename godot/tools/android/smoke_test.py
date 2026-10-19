#!/usr/bin/env python3
"""Real Android input smoke test. Probe observes state; ADB performs every action.

This verifies launch, responsive geometry, menu touch targets, Android Back,
scrolling, rotation and resume. Screenshots/logs are evidence for visual review;
it is not a claim about physical-device performance or complete gameplay.
"""
import json
import os
from pathlib import Path
import re
import struct
import subprocess
import sys
import time

PACKAGE = 'org.catfish872.voidrift.debug'
ADB = os.environ.get('ADB', 'adb')
MARKER = 'ANDROID_SMOKE '


def adb(*args, binary=False, check=True, timeout=40):
    result = subprocess.run([ADB, *args], check=check, capture_output=True, timeout=timeout)
    return result.stdout if binary else result.stdout.decode('utf-8', errors='replace')


def snapshots(log):
    result = []
    for line in log.splitlines():
        if MARKER in line:
            try:
                result.append(json.loads(line.split(MARKER, 1)[1]))
            except json.JSONDecodeError:
                pass
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
    screenshot(output, 'portrait-home', False)
    # Menu is dismissed by the real Android Back event and the game stays alive.
    tap(state, 'MenuButton')
    wait_for(lambda s: s['overlay'] > 0, 'menu before Back')
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
    state = visit(state, 'growth')
    geometry(state)
    screenshot(output, 'landscape-growth', True)
    back()
    state = wait_for(lambda s: s['screen'] == 'home' and s['overlay'] == 0, 'landscape Back')
    adb('shell', 'input', 'keyevent', 'KEYCODE_HOME')
    time.sleep(1)
    adb('shell', 'am', 'start', '-W', '-n', component)
    time.sleep(1)
    state = wait_for(lambda s: s['screen'] == 'home', 'resume')
    tap(state, 'MenuButton')
    wait_for(lambda s: s['overlay'] > 0, 'touch after resume')
    back()
    wait_for(lambda s: s['overlay'] == 0, 'dismiss after resume')
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
        image = adb('exec-out', 'screencap', '-p', binary=True, check=False)
        if image.startswith(b'\x89PNG\r\n\x1a\n'):
            (output / 'final-screen.png').write_bytes(image)
        (output / 'logcat.txt').write_text(adb('logcat', '-d', '-v', 'threadtime', check=False))
        (output / 'activity.txt').write_text(adb('shell', 'dumpsys', 'activity', 'activities', check=False))
        (output / 'window.txt').write_text(adb('shell', 'dumpsys', 'window', 'displays', check=False))
