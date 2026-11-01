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


def tap(state, name, settle=.7):
    matches = [b for b in state['buttons'] if b['name'] == name]
    assert len(matches) == 1, f'Missing/duplicate visible button: {name}'
    x, y, w, h = matches[0]['rect']
    width, height = state['window']
    assert w > 0 and h > 0 and x >= -1 and y >= -1 and x + w <= width + 1 and y + h <= height + 1, (name, matches[0], state['window'])
    clip = matches[0].get('clip', [0, 0, width, height])
    assert inside(matches[0]['rect'], clip), f'Button clipped: {name}'
    adb('shell', 'input', 'tap', str(round(x + w / 2)), str(round(y + h / 2)))
    time.sleep(settle)


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



def page_swipe_x(state):
    """Use page content, avoiding both native scrollbar and gesture canvases."""
    x, _, w, _ = state['scroll_rect']
    bar_left = state.get('scrollbar_rect', [x + w, 0, 0, 0])[0]
    canvases = state.get('canvases', {})
    if canvases:
        canvas_right = max(c['rect'][0] + c['rect'][2] for c in canvases.values())
        assert bar_left - canvas_right >= 4, 'Page needs a touch gutter outside canvases and scrollbar'
        return (canvas_right + bar_left) / 2
    return min(x + w * .85, bar_left - 8)


def reveal_page_target(state, name):
    """Bring a real page control into view using bounded Android finger drags."""
    for _ in range(16):
        matches = [b for b in state['buttons'] if b['name'] == name]
        assert len(matches) == 1, f'Missing/duplicate page target: {name}'
        target = matches[0]
        if inside(target['rect'], target['clip']):
            return state
        local = next((item for item in state.get('page_scrolls', []) if item['id'] == target.get('scroll_owner') and item['max'] > 0), None)
        if local:
            x, y, w, h = local['rect']
            cx, cy, cw, ch = local.get('clip', [x, y, w, h])
            top, bottom = max(y, cy), min(y + h, cy + ch)
            before, scroll_id = local['value'], local['id']
            upwards = target['rect'][1] >= target['clip'][1]
            start, end = (.8, .2) if upwards else (.2, .8)
            finger_x = min(x + w * .85, cx + cw - 12)
            adb('shell', 'input', 'swipe', str(round(finger_x)), str(round(top + (bottom-top)*start)), str(round(finger_x)), str(round(top+(bottom-top)*end)), '600')
            state = wait_for(lambda q: any(item['id'] == scroll_id and item['value'] != before for item in q.get('page_scrolls', [])), name + ' local scrolling')
            continue
        assert state['scroll_max'] > 0, f'Clipped control without scroll range: {name}' 
        x, y, w, h = state['scroll_rect']
        before = state['scroll']
        _, ty, _, th = target['rect']
        _, cy, _, ch = target['clip']
        # Center rather than merely uncover the control; cap travel to avoid
        # overshoot, and never touch the native scrollbar's draggable thumb.
        distance = max(-h * .4, min(h * .4, ty + th / 2 - (cy + ch / 2)))
        finger_x = round(page_swipe_x(state))
        start_y = y + h / 2 + distance / 2
        end_y = y + h / 2 - distance / 2
        adb('shell', 'input', 'swipe', str(finger_x), str(round(start_y)), str(finger_x), str(round(end_y)), '900')
        state = wait_for(lambda s: s['scroll'] != before, name + ' page scrolling')
    raise AssertionError(f'Page target remains clipped: {name}')


def tap_page(state, name):
    state = reveal_page_target(state, name)
    tap(state, name)


def canvas_target(state, name, kind):
    """Pan a custom-drawn control to a real hit target, never invoke its signal."""
    viewport_name = 'ExtractionMapViewport' if kind == 'map' else 'ExtractionSceneViewport'
    state = reveal_page_target(state, viewport_name)
    for _ in range(16):
        target = next((b for b in state['buttons'] if b['name'] == name), None)
        assert target is not None, f'Missing canvas target {name}'
        if inside(target['rect'], target['clip']):
            return state
        canvas = state['canvases'][kind]
        x, y, w, h = canvas['clip']
        tx, ty, tw, th = target['rect']
        cx, cy = x + w / 2, y + h / 2
        dx = max(-w * .3, min(w * .3, cx - (tx + tw / 2)))
        dy = max(-h * .3, min(h * .3, cy - (ty + th / 2)))
        before = canvas['pan']
        adb('shell', 'input', 'swipe', str(round(cx - dx / 2)), str(round(cy - dy / 2)), str(round(cx + dx / 2)), str(round(cy + dy / 2)), '600')
        state = wait_for(lambda q: q.get('canvases', {}).get(kind, {}).get('pan') != before, kind + ' pan to target')
    raise AssertionError(f'Canvas target remains clipped: {name}')


def tap_overlay(state, name):
    state = reveal_menu_target(state, name)
    tap(state, name)


def safe_exploration_path(state):
    """Breadth-first route through ordinary safe rooms in the observed map."""
    data = state['extraction']
    rooms = {room['id']: room for room in data['map_rooms']}
    start = data['room_id']
    queue = [(start, [])]
    seen = {start}
    while queue:
        at, path = queue.pop(0)
        if path and not rooms[at]['visited']:
            return path
        for a, b in data['map_edges']:
            other = b if a == at else a if b == at else None
            if other is None or other in seen or rooms[other]['type'] in ('battle', 'elite', 'boss', 'vault'):
                continue
            seen.add(other)
            queue.append((other, path + [other]))
    return []


def enter_map_room(state, room_id):
    name = 'ExtractionMapNode_' + room_id
    state = canvas_target(state, name, 'map')
    target = next(b for b in state['buttons'] if b['name'] == name)
    current = state['extraction']['room_id']
    if not target.get('adjacent') and room_id != current:
        path = target.get('travel_path', [])
        assert target.get('reachable') and len(path) >= 3 and path[0] == current and path[-1] == room_id, 'Driver attempted a disconnected or unreachable distant room'
        edges = {frozenset(edge) for edge in state['extraction']['map_edges']}
        rooms = {room['id']: room for room in state['extraction']['map_rooms']}
        assert all(frozenset([left, right]) in edges for left, right in zip(path, path[1:])), 'Travel path skips an actual map edge'
        for intermediate in path[1:-1]:
            room = rooms[intermediate]
            safe = room['visited'] and (room['type'] not in ('battle','elite','vault','boss') or room.get('cleared',False))
            assert safe, 'Travel path bypasses an unvisited or uncleared combat room'
            # A locked key-vault interior does not block its visited exterior corridor.
    before_seq = state['seq']
    already_selected = state['canvases']['map']['selected_room'] == room_id
    tap(state, name)
    if not already_selected:
        state = wait_for(lambda q, since=before_seq: q.get('seq', -1) > since and q.get('extraction', {}).get('phase') == 'route' and q.get('canvases', {}).get('map', {}).get('selected_room') == room_id and any(b['name'] == name for b in q['buttons']), 'first map tap previews without travel')
        before_seq = state['seq']
        tap(state, name)
    return wait_for(lambda q, since=before_seq: q.get('seq', -1) > since and q.get('extraction', {}).get('room_id') == room_id and q['extraction']['phase'] in ('room','battle'), 'map node enters room')


def resolve_service_guard(state, output):
    if state['extraction']['phase'] != 'battle':
        return state
    assert state['extraction'].get('guard_pending'), 'Safe route unexpectedly entered a non-service battle'
    room_id, kind = state['extraction']['room_id'], state['extraction']['room_type']
    assert not any(b['name'].startswith(('ExtractionRoomAction_', 'ExtractionOpenContainer_')) or b['name']=='ExtractionDepositPreview' for b in state['buttons']), 'Guarded service remains usable before victory'
    screenshot(output, 'service-guard-before', True)
    tap_page(state, 'ExtractionBattle')
    state = wait_for(lambda q: q['screen']=='battle', 'real service guard battle starts')
    if not state['battle_state']['auto']:
        tap(state, 'BattleAutoToggle')
    state = wait_for(lambda q: any(b['name']=='ExtractionBattleContinue' for b in q['buttons']), 'real automatic guard battle reaches settlement', timeout=180)
    assert state['battle_state']['phase']=='victory', 'Ordinary native party lost the actual service guard; do not bypass encounter'
    tap_overlay(state, 'ExtractionBattleContinue')
    state = wait_for(lambda q: q['screen']=='extraction' and q['extraction']['phase']=='room', 'guard victory restores service room')
    state = resolve_growth(state)
    assert state['extraction']['room_id']==room_id and state['extraction']['room_type']==kind and not state['extraction']['guard_pending'], 'Guard settlement replaced or failed to unlock original service'
    screenshot(output, 'service-guard-unlocked', True)
    return state


def resolve_growth(state):
    while state['extraction'].get('growth_choices'):
        choices = state['extraction']['growth_choices']
        tap_page(state, 'ExtractionGrowth_'+choices[0])
        state = wait_for(lambda q: q['extraction'].get('growth_choices',[]) != choices, 'actual blessing selection completes')
    return state


def workshop_input_flow(state, output):
    assert state['extraction']['room_type']=='workshop' and len(state['extraction']['room_actions'])==3, 'Natural workshop must retain all three service cards'
    saved_ids = sorted(state['extraction']['bag_ids'])
    room_id = state['extraction']['room_id']
    saved_run = state['extraction']['run_digest']
    footer = ('ExtractionSort_bag','ExtractionQuickSupplies','ExtractionBuild','ExtractionAbandon')
    def fixed(q):
        for name in footer:
            button=next(b for b in q['buttons'] if b['name']==name)
            assert inside(button['rect'],button['clip']) and inside(button['rect'],[0,0,*q['window']]), 'Workshop footer is clipped: '+name
            assert button['rect'][2]*q['logical'][0]/q['window'][0]>=43.9 and button['rect'][3]*q['logical'][1]/q['window'][1]>=43.9, 'Workshop footer target is smaller than 44'
    fixed(state)
    screenshot(output, 'workshop-three-services-before', True)
    tap(state,'ExtractionBuild')
    state=wait_for(lambda q: any(b['name']=='ExtractionTab_expedition' for b in q['buttons']) and not any(b['name']=='ExtractionBuild' for b in q['buttons']), 'direct build page opens')
    tap_page(state,'ExtractionTab_expedition')
    state=wait_for(lambda q: any(b['name']=='ExtractionAbandon' for b in q['buttons']), 'return to workshop footer')
    tap(state,'ExtractionAbandon')
    state=wait_for(lambda q: any(b['name']=='ExtractionAbandonCancel' for b in q['buttons']), 'abandon requires confirmation')
    tap_overlay(state,'ExtractionAbandonCancel')
    state=wait_for(lambda q: q['overlay']==0 and q['extraction']['room_id']==room_id, 'cancel keeps workshop run')
    assert state['extraction']['run_digest']==saved_run, 'Build navigation or abandon cancellation changed the run'
    assert sorted(state['extraction']['bag_ids'])==saved_ids and not any(a.get('used',False) for a in state['extraction']['room_actions']), 'Navigation or cancel consumed service or loot'
    name='ExtractionRoomAction_study'
    for _ in range(12):
        button=next(b for b in state['buttons'] if b['name']==name)
        if inside(button['rect'],button['clip']):break
        scroll=next(q for q in state['page_scrolls'] if q.get('name')=='ExtractionServiceScroll')
        x,y,w,h=scroll['rect']; old=scroll['value']; seq=state['seq']
        adb('shell','input','swipe',str(round(x+w*.65)),str(round(y+h-12)),str(round(x+w*.65)),str(round(y+12)),'600')
        state=wait_for(lambda q:q['seq']>seq and any(t.get('name')=='ExtractionServiceScroll' and t['value']>old for t in q['page_scrolls']), 'finger scroll reaches last workshop action')
        fixed(state)
    assert inside(next(b for b in state['buttons'] if b['name']==name)['rect'],next(b for b in state['buttons'] if b['name']==name)['clip']), 'Last service did not become fully visible'
    screenshot(output, 'workshop-last-service-reachable', True)
    tap(state,name)
    state=wait_for(lambda q: bool(q['extraction'].get('growth_choices')), 'last service opens real blessing choices')
    state=resolve_growth(state)
    assert all(a.get('used') for a in state['extraction']['room_actions']), 'Workshop real choice was not consumed exactly once'
    fixed(state)
    screenshot(output,'workshop-service-consumed',True)
    return state


def verify_completed_container_close(before, after):
    a, b = before['extraction'], after['extraction']
    expected = 'route' if a['interaction']['canAutoReturn'] else 'room'
    assert after['overlay'] == 0 and b['phase'] == expected, 'Closing must preserve remaining choices or return a truly completed room'
    assert b['room_id'] == a['room_id'] and sorted(b['bag_ids']) == sorted(a['bag_ids']), 'Automatic map return must not move player or mutate loot'
    assert b['containers'] == a['containers'], 'Closing or auto-return must not reroll or discard source containers'
    assert b.get('gold') == a.get('gold'), 'Automatic return must not spend or grant gold'
    if expected == 'route':
        assert 'map' in after.get('canvases', {}), 'Completed room must actually display the map'


def return_extraction_map(state):
    if state['extraction']['phase'] == 'route':
        assert 'map' in state.get('canvases', {}), 'Automatically returned route must render its actual map'
        return state
    tap_page(state, 'ExtractionAdvance')
    return wait_for(lambda q: q.get('extraction', {}).get('phase') == 'route' and 'map' in q.get('canvases', {}), 'room returns to persistent map')


def restore_map_overview(state):
    before_seq = state['seq']
    tap_page(state, 'AtlasFit')
    return wait_for(lambda q, since=before_seq: q.get('seq', -1) > since and q.get('canvases', {}).get('map', {}).get('auto_fit', False) and abs(q['canvases']['map']['zoom'] - q['canvases']['map']['fit_zoom']) < .0001, 'map overview restored by real button')


def verify_map_finger_drag(state):
    """Zoom with real controls before testing panning of a fitted overview."""
    state = reveal_page_target(state, 'ExtractionMapViewport')
    old_room = state['extraction']['room_id']
    canvas = state['canvases']['map']
    if not canvas['can_pan_x']:
        x, y, w, h = canvas['clip']
        old_pan, old_selected = canvas['pan'], canvas['selected_room']
        before_seq = state['seq']
        adb('shell', 'input', 'swipe', str(round(x + w * .75)), str(round(y + h * .5)), str(round(x + w * .25)), str(round(y + h * .5)), '600')
        state = wait_for(lambda q, since=before_seq: q.get('seq', -1) > since and q.get('extraction', {}).get('phase') == 'route' and q['extraction']['room_id'] == old_room, 'overview drag stays in current room')
        assert state['canvases']['map']['selected_room'] == old_selected, 'Overview drag selected a room'
        assert state['canvases']['map']['pan'] == old_pan, 'Fitted overview unexpectedly shifted horizontally'
    for _ in range(8):
        canvas = state['canvases']['map']
        if canvas['can_pan_x']:
            break
        old_zoom = canvas['zoom']
        tap_page(state, 'AtlasZoomIn')
        state = wait_for(lambda q: q.get('canvases', {}).get('map', {}).get('zoom', 0) > old_zoom, 'map real zoom button')
    assert state['canvases']['map']['can_pan_x'], 'Map never becomes horizontally pannable after real zoom taps'
    canvas = state['canvases']['map']
    x, y, w, h = canvas['clip']
    old_pan = canvas['pan']
    adb('shell', 'input', 'swipe', str(round(x + w * .75)), str(round(y + h * .5)), str(round(x + w * .25)), str(round(y + h * .5)), '600')
    state = wait_for(lambda q: q.get('canvases', {}).get('map', {}).get('pan', old_pan)[0] < old_pan[0] - 12, 'map finger drag visibly moves left')
    assert state['extraction']['phase'] == 'route' and state['extraction']['room_id'] == old_room, 'Dragging unintentionally entered a room'
    return state


def wait_probe_event(after_seq, event, timeout=20):
    deadline=time.monotonic()+timeout
    while time.monotonic()<deadline:
        states=snapshots(adb('logcat','-d','-v','brief'))
        for state in states:
            if state['seq']>after_seq and state.get('probe_event')==event:
                return state
        time.sleep(.1)
    raise AssertionError('Missing actual Android lifecycle notification: '+event)


def scan_has_background_window(previous, current):
    old, new = previous.get('loot',{}), current.get('loot',{})
    uid=new.get('scan_uid','')
    if not uid or uid!=old.get('scan_uid') or new.get('container_id')!=old.get('container_id'):
        return False
    elapsed=(current.get('monotonic_ms',0)-previous.get('monotonic_ms',0))/1000
    progress=new.get('scan_progress',0)-old.get('scan_progress',0)
    if elapsed<=0 or progress<=0:
        return False
    estimated_duration=elapsed/progress
    return estimated_duration>=1.3 and estimated_duration*(1-new.get('scan_progress',1))>=.8


def loot_ownership(state):
    extraction=state['extraction']
    return {'bag':sorted(extraction['bag_ids']), 'source':sorted((item['uid'],item['revealed']) for item in state.get('loot',{}).get('source',[]))}


def check_search_background(state, component, output, coverage):
    adb('shell','input','keyevent','KEYCODE_HOME')
    paused=wait_probe_event(state['seq'],'paused')
    wait_for_completed_background(output)
    adb('shell','am','start','-W','-n',component)
    resumed=wait_probe_event(paused['seq'],'resumed')
    coverage['attempts']=coverage.get('attempts',0)+1
    uid=paused.get('loot',{}).get('scan_uid','')
    if not uid or not paused['extraction']['searching']:
        coverage['reason']='Natural scan completed before Android pause notification; no slowdown was injected'
        return resumed
    assert paused.get('application_paused') and not resumed.get('application_paused'), 'Android pause flag did not follow actual lifecycle'
    assert resumed['loot']['scan_uid']==uid, 'Background resume skipped the active searched item'
    assert abs(resumed['loot']['scan_progress']-paused['loot']['scan_progress'])<=.02, 'Search progress jumped while backgrounded'
    assert loot_ownership(resumed)==loot_ownership(paused), 'Background search silently revealed or transferred loot'
    coverage.pop('reason', None)
    coverage.update({'covered':True,'uid':uid,'paused_progress':paused['loot']['scan_progress'],'resumed_progress':resumed['loot']['scan_progress']})
    (output/'search-background.json').write_text(json.dumps(coverage,indent=2))
    return resumed


def monitor_automatic_search(state, box_id, before_seq, component, output, coverage):
    deadline=time.monotonic()+70
    seen_seq=before_seq
    previous=state
    while time.monotonic()<deadline:
        states=snapshots(adb('logcat','-d','-v','brief'))
        fresh=[q for q in states if q['seq']>seen_seq and q.get('loot',{}).get('container_id')==box_id]
        if fresh:
            current=fresh[-1]
            preceding=fresh[-2] if len(fresh)>1 else previous
            seen_seq=current['seq']
            if not coverage.get('covered') and coverage.get('attempts',0)<2 and scan_has_background_window(preceding,current):
                current=check_search_background(current,component,output,coverage)
                seen_seq=current['seq']
            if not current['extraction']['searching'] and any(box['id']==box_id and box['unknown']==0 for box in current['extraction']['containers']):
                return current
            previous=current
        time.sleep(.1)
    raise AssertionError('Automatic search never reached a complete state')


def visible_pickup_uids(states, container_id, after_seq):
    """Evidence is per visible UID, not a continuous stream of unrelated icons."""
    seen = {}
    durations = {}
    collected = set()
    for state in states:
        if state.get('seq', -1) <= after_seq:
            continue
        if state.get('application_paused',False):
            seen={}
            continue
        loot = state.get('loot', {})
        if loot.get('container_id') != container_id:
            continue
        now = state.get('monotonic_ms', 0)
        visible_now = set()
        for item in loot.get('source', []):
            if item.get('revealed') and item.get('icon_loaded') and item.get('name') and min(item['rect'][2:]) >= 24 and inside(item['rect'], item['clip']):
                first, _ = seen.get(item['uid'], (now, now))
                seen[item['uid']] = (first, now)
                visible_now.add(item['uid'])
                durations[item['uid']] = max(durations.get(item['uid'], 0), now - first)
        seen = {uid: span for uid, span in seen.items() if uid in visible_now}
        for item in loot.get('bag', []):
            uid = item['uid']
            if durations.get(uid, 0) >= 200 and item.get('icon_loaded') and min(item['rect'][2:]) >= 24 and inside(item['rect'], item['clip']):
                collected.add(uid)
    return collected


def inventory_positions(state):
    return {item['uid']: (item['item_id'], item['x'], item['y'], item['rotated'])
            for item in state.get('inventory', {}).get('items', [])}


def warehouse_input_flow(state, output):
    """Purchase real supplies, then verify real ADB selection and deliberate placement."""
    tap_page(state, 'ExtractionTab_shop')
    state = wait_for(lambda q: any(b['name'] == 'ExtractionShopFilter_consumable' for b in q['buttons']), 'supply shop')
    tap_page(state, 'ExtractionShopFilter_consumable')
    state = wait_for(lambda q: any(b['name'] == 'ExtractionBuy_bandage' for b in q['buttons']), 'consumables filter')
    for item_id in ('bandage', 'medkit'):
        before = state['extraction']['stash_count']
        tap_page(state, 'ExtractionBuy_' + item_id)
        state = wait_for(lambda q: q['extraction']['stash_count'] == before + 1, 'real purchase ' + item_id)
    tap_page(state, 'ExtractionTab_stash')
    state = wait_for(lambda q: len(q.get('inventory', {}).get('items', [])) == 2, 'purchased warehouse supplies')
    items = state['inventory']['items']
    assert {item['item_id'] for item in items} == {'bandage', 'medkit'}
    assert all(item['icon_loaded'] for item in items), 'Purchased supply icons must be loaded'
    original = inventory_positions(state)
    uids = {item['uid'] for item in items}
    tap_page(state, 'ExtractionStashMulti')
    state = wait_for(lambda q: q.get('inventory', {}).get('multi_select') and not q['inventory']['selected_uids'], 'empty explicit multiselect')
    selected = set()
    for item in items:
        tap(state, 'ExtractionInventoryItem_' + item['uid'])
        selected.add(item['uid'])
        expected = selected.copy()
        state = wait_for(lambda q: set(q.get('inventory', {}).get('selected_uids', [])) == expected, 'exact touch selection ' + item['uid'])
        assert inventory_positions(state) == original, 'Selection may not mutate warehouse items'
    screenshot(output, 'warehouse-two-exact-uids', True)
    (output / 'warehouse-selection.json').write_text(json.dumps(state, ensure_ascii=False, indent=2))
    tap_page(state, 'ExtractionStashMulti')
    state = wait_for(lambda q: not q.get('inventory', {}).get('multi_select', True) and not q['inventory']['selected_uids'], 'cancel warehouse multiselect')
    assert inventory_positions(state) == original
    medkit = next(item for item in items if item['item_id'] == 'medkit')
    uid = medkit['uid']
    tap(state, 'ExtractionInventoryItem_' + uid)
    state = wait_for(lambda q: q.get('inventory', {}).get('selected_uid') == uid and any(b['name'] == 'ExtractionMove_' + uid for b in q['buttons']), 'select exact medicine for movement')
    tap_page(state, 'ExtractionMove_' + uid)
    state = wait_for(lambda q: q.get('inventory', {}).get('placement_mode') and q['inventory']['placement_uid'] == uid, 'explicit medicine placement mode')
    cells = {b['name']: b for b in state['buttons']}
    start = cells['ExtractionInventoryCell_4_0']['rect']
    end = cells['ExtractionInventoryCell_6_1']['rect']
    adb('shell', 'input', 'swipe', str(round(start[0]+start[2]/2)), str(round(start[1]+start[3]/2)), str(round(end[0]+end[2]/2)), str(round(end[1]+end[3]/2)), '650')
    state = wait_for(lambda q: q.get('inventory', {}).get('placement_mode') and inventory_positions(q) == original, 'real warehouse finger drag must not commit movement')
    (output / 'warehouse-drag-preserved.json').write_text(json.dumps(state, ensure_ascii=False, indent=2))
    tap(state, 'ExtractionInventoryCell_4_1')
    state = wait_for(lambda q: not q.get('inventory', {}).get('placement_mode', True) and inventory_positions(q).get(uid) == ('medkit', 4, 1, medkit['rotated']), 'explicit target tap commits exact medicine position')
    actual = inventory_positions(state)
    assert set(actual) == uids and all(actual[key] == original[key] for key in uids if key != uid), 'Moving one UID preserves all others'
    screenshot(output, 'warehouse-deliberate-move', True)
    (output / 'warehouse-move.json').write_text(json.dumps(state, ensure_ascii=False, indent=2))
    # A real vertical page drag must release the inventory's gesture ownership;
    # the very next tap, not a second retry, selects the visible medicine.
    bandage_uid = next(item['uid'] for item in items if item['item_id'] == 'bandage')
    tap(state, 'ExtractionInventoryItem_' + bandage_uid)
    state = wait_for(lambda q: q.get('inventory', {}).get('selected_uid') == bandage_uid, 'select other item before scrolling')
    cx, cy, cw, ch = state['inventory']['clip']
    before_scroll_top = state['inventory']['rect'][1]
    adb('shell', 'input', 'swipe', str(round(cx+cw*.8)), str(round(cy+ch*.6)), str(round(cx+cw*.8)), str(round(cy+ch*.6-30)), '500')
    state = wait_for(lambda q: q.get('inventory', {}).get('selected_uid') == bandage_uid and q['inventory']['rect'][1] < before_scroll_top - 5 and any(item['uid'] == uid and inside(item['rect'], item['clip']) for item in q['inventory']['items']), 'medicine remains visible after inventory scrolling')
    tap(state, 'ExtractionInventoryItem_' + uid)
    state = wait_for(lambda q: q.get('inventory', {}).get('selected_uid') == uid, 'first tap after inventory scroll selects immediately')
    assert inventory_positions(state) == actual, 'Scrolling and selection cannot move assets'
    (output / 'warehouse-scroll-first-tap.json').write_text(json.dumps(state, ensure_ascii=False, indent=2))
    return state


def carry_purchased_supply(state):
    medicine=next(item for item in state['inventory']['items'] if item['item_id']=='medkit')
    uid=medicine['uid']
    assert state['inventory']['selected_uid']==uid, 'Carry must follow the already verified first post-scroll exact selection'
    tap_page(state,'ExtractionBring_'+uid)
    state=wait_for(lambda q:uid in q['extraction']['loadout_ids'] and all(item['uid']!=uid for item in q.get('inventory',{}).get('items',[])), 'carry purchased medicine into departure supplies')
    return state,uid


def supply_lock_input_flow(state, uid, output):
    assert any(item['uid']==uid and item['item_id']=='medkit' for item in state['extraction']['supplies']), 'Purchased carried medicine must retain exact UID on departure'
    bag_ids=sorted(state['extraction']['bag_ids'])
    tap_page(state,'ExtractionQuickSupplies')
    state=wait_for(lambda q:any(b['name']=='ExtractionSupplyLock_'+uid for b in q['buttons']), 'real carried supply lock is visible')
    for locked in (True,False,True):
        seq=state['seq']
        tap_overlay(state,'ExtractionSupplyLock_'+uid)
        state=wait_for(lambda q:q['seq']>seq and any(item['uid']==uid and item['exchange_locked']==locked for item in q['extraction']['supplies']), 'real supply lock toggles to '+str(locked))
        assert sorted(state['extraction']['bag_ids'])==bag_ids, 'Supply lock consumed or moved an item'
    screenshot(output,'supply-exact-uid-locked',True)
    tap_overlay(state,'ExtractionSupplyClose')
    state=wait_for(lambda q:q['overlay']==0, 'locked supplies close')
    tap_page(state,'ExtractionQuickSupplies')
    state=wait_for(lambda q:any(b['name']=='ExtractionSupplyLock_'+uid for b in q['buttons']), 'reopen same locked supply')
    assert any(item['uid']==uid and item['exchange_locked'] for item in state['extraction']['supplies']), 'Supply lock was lost on reopening'
    (output/'supply-lock-persistence.json').write_text(json.dumps(state,ensure_ascii=False,indent=2))
    tap_overlay(state,'ExtractionSupplyClose')
    return wait_for(lambda q:q['overlay']==0, 'supply lock inspection returns to expedition')


def extraction_flow(state, output, component, search_background):
    """Use ordinary deterministic loot, real scene taps and ADB gestures only."""
    state = visit(state, 'extraction')
    geometry(state)
    tap_page(state, 'ExtractionTab_stash')
    state = wait_for(lambda q: any(b['name'] == 'ExtractionSort_stash' for b in q['buttons']), 'extraction stash tab')
    screenshot(output, 'extraction-stash', True)
    state = warehouse_input_flow(state, output)
    state, carried_supply_uid = carry_purchased_supply(state)
    tap_page(state, 'ExtractionTab_expedition')
    state = wait_for(lambda q: any(b['name'] == 'ExtractionStart' for b in q['buttons']), 'extraction departure')
    tap_page(state, 'ExtractionStart')
    state = wait_for(lambda q: q.get('extraction', {}).get('phase') == 'route' and 'map' in q.get('canvases', {}), 'extraction connected map')
    canvas = state['canvases']['map']
    assert canvas['auto_fit'] and abs(canvas['zoom'] - canvas['fit_zoom']) < .0001, 'New expedition map must start fitted without manual repair'
    state = verify_map_finger_drag(state)
    geometry(state)
    screenshot(output, 'extraction-map-drag', True)
    state = restore_map_overview(state)
    filled = False
    collected = False
    visited_count = 0
    workshop_covered = False
    supply_lock_covered = False
    for _ in range(12):
        path = safe_exploration_path(state)
        if not path and collected and workshop_covered:
            return visit(state,'home')
        assert path, 'Deterministic ordinary-loot route ended before collecting an item'
        for index, room_id in enumerate(path):
            state = enter_map_room(state, room_id)
            state = resolve_service_guard(state, output)
            if index < len(path) - 1:
                state = return_extraction_map(state)
        visited_count += 1
        if not supply_lock_covered:
            state=supply_lock_input_flow(state,carried_supply_uid,output)
            supply_lock_covered=True
        if state['extraction']['room_type']=='workshop' and not workshop_covered:
            state=workshop_input_flow(state,output)
            workshop_covered=True
        # Exercise a real rest-room choice to obtain ordinary supplies, without
        # granting fixture loot or changing rarity/search speed through the probe.
        supply_action='ExtractionRoomAction_scavenge'
        if state['extraction'].get('room_type') in ('rest','hospital') and any(button['name']==supply_action for button in state['buttons']):
            before_supply_seq=state['seq']
            carried_before=sorted(state['extraction']['bag_ids'])
            tap_page(state,supply_action)
            state=wait_for(lambda q: q['seq']>before_supply_seq and q['extraction']['phase']=='room' and bool(q['extraction']['containers']), 'rest supply choice creates an ordinary searchable container')
            assert sorted(state['extraction']['bag_ids'])==carried_before, 'Rest supply choice bypassed searching and granted bag loot'
        geometry(state)
        if visited_count == 1:
            screenshot(output, 'extraction-room-scene', True)
        if visited_count == 1 and 'scene' in state.get('canvases', {}):
            state = reveal_page_target(state, 'ExtractionSceneViewport')
            cx, cy, cw, ch = state['canvases']['scene']['clip']
            room_before = state['extraction']['room_id']
            adb('shell', 'input', 'swipe', str(round(cx + cw * .7)), str(round(cy + ch * .5)), str(round(cx + cw * .3)), str(round(cy + ch * .5)), '600')
            state = wait_for(lambda q: q['overlay'] == 0 and q['extraction']['room_id'] == room_before, 'scene drag does not open a container')
        box_ids = [box['id'] for box in state['extraction']['containers'] if box['items']]
        for box_id in box_ids:
            name = 'ExtractionSceneContainer_' + box_id
            state = canvas_target(state, name, 'scene')
            before_ids = set(state['extraction']['bag_ids'])
            before_seq = state['seq']
            tap(state, name, settle=.05)
            state = wait_for(lambda q: q['seq'] > before_seq and q['overlay'] > 0 and q.get('loot', {}).get('container_id') == box_id and any(b['name'] == 'ExtractionCloseContainer' for b in q['buttons']), 'scene sprite opens its own automatically searched container')
            assert not any(b['name'] in ('ExtractionSearch', 'ExtractionStopSearch') for b in state['buttons']), 'Container still requires an extra search action'
            state = monitor_automatic_search(state, box_id, before_seq, component, output, search_background)
            after_ids = set(state['extraction']['bag_ids'])
            assert before_ids.issubset(after_ids), 'Automatic packing discarded a carried item'
            if after_ids - before_ids:
                evidence = visible_pickup_uids(snapshots(adb('logcat', '-d', '-v', 'brief')), box_id, before_seq)
                assert evidence.intersection(after_ids - before_ids), 'No exact picked-up UID was visibly identifiable for 200ms in its container'
                collected = True
            remaining = next(box['items'] for box in state['extraction']['containers'] if box['id'] == box_id)
            if remaining:
                # Fully revealed loot remains because it cannot fit. Retrying
                # automatic pickup must preserve both inventories exactly.
                tap_overlay(state, 'ExtractionTakeAll')
                stable_ids, stable_left = sorted(after_ids), sorted(remaining)
                state = wait_for(lambda q: sorted(q['extraction']['bag_ids']) == stable_ids and any(box['id'] == box_id and sorted(box['items']) == stable_left for box in q['extraction']['containers']), 'full bag preserves overflow loot')
                screenshot(output, 'extraction-full-bag-container', True)
                filled = True
            before_close = state
            expected_phase = 'route' if state['extraction']['interaction']['canAutoReturn'] else 'room'
            tap_overlay(state, 'ExtractionCloseContainer')
            state = wait_for(lambda q: q['overlay'] == 0 and q['extraction']['phase'] == expected_phase, 'container closes according to remaining real interactions')
            verify_completed_container_close(before_close, state)
            if expected_phase == 'route':
                assert 'map' in state.get('canvases', {}), 'Completed room must actually display the map'
                (output / 'completed-room-auto-return.json').write_text(json.dumps({'before': before_close['extraction'], 'after': state['extraction']}, indent=2))
                screenshot(output, 'completed-room-auto-return', True)
            if filled or expected_phase == 'route':
                break
        if collected:
            assert collected, 'No real loot was collected'
            saved_ids = sorted(state['extraction']['bag_ids'])
            saved_room = state['extraction']['room_id']
            saved_boxes = {box['id']: sorted(box['items']) for box in state['extraction']['containers']}
            state = return_extraction_map(state)
            far = next((button for button in state['buttons'] if button.get('reachable') and not button.get('adjacent') and button.get('type') in ('entry','rest','cache','hospital','workshop','shrine') and len(button.get('travel_path', [])) >= 3), None)
            if far is not None:
                state = enter_map_room(state, far['room_id'])
                state = resolve_service_guard(state, output)
                assert sorted(state['extraction']['bag_ids']) == saved_ids, 'Safe route automatically consumed or granted items'
                state = return_extraction_map(state)
            state = enter_map_room(state, saved_room)
            assert sorted(state['extraction']['bag_ids']) == saved_ids, 'Map return changed backpack'
            assert {box['id']: sorted(box['items']) for box in state['extraction']['containers']} == saved_boxes, 'Room revisit rerolled or lost overflow loot'
            tap_page(state, 'ExtractionTab_bag')
            state = wait_for(lambda q: any(b['name'] == 'ExtractionSort_bag' for b in q['buttons']), 'bag panel')
            tap_page(state, 'ExtractionSort_bag')
            state = wait_for(lambda q: sorted(q['extraction']['bag_ids']) == saved_ids, 'manual sort preserves inventory')
            geometry(state)
            screenshot(output, 'extraction-bag-after-search', True)
            state = visit(state, 'home')
            state = visit(state, 'extraction')
            assert sorted(state['extraction']['bag_ids']) == saved_ids, 'Navigation changed inventory'
            assert state['extraction']['room_id'] == saved_room, 'Navigation moved player'
            search_background['rooms_observed']=visited_count
            if workshop_covered and (search_background.get('covered') or visited_count>=4):
                return visit(state, 'home')
            state = return_extraction_map(state)
            continue
        state = return_extraction_map(state)
    raise AssertionError('Natural-loot run did not collect any searchable items')


def visit(state, page):
    tap(state, 'MenuButton')
    state = wait_for(lambda s: s['overlay'] > 0 and any(b['name'] == 'MenuNav_' + page for b in s['buttons']), 'menu open')
    state = reveal_menu_target(state, 'MenuNav_' + page)
    tap(state, 'MenuNav_' + page)
    return wait_for(lambda s: s['screen'] == page and s['overlay'] == 0, page + ' navigation')


def verify_summon_commit(before, after, count):
    old, new = before['summon'], after['summon']
    assert new['total_pulls'] == old['total_pulls'] + count, 'Summon must commit exactly the requested pull count'
    assert new['diamonds'] == old['diamonds'] - 160 * count, 'Summon must charge exactly once'
    assert len(new['results']) == count, 'Animation must consume the actual committed results'
    assert all(item['charId'] in new['owned_ids'] for item in new['results']), 'Revealed results must already be owned'


def verify_summon_pause(paused, resumed):
    a, b = paused['summon'], resumed['summon']
    assert paused['application_paused'] and not resumed['application_paused'], 'Actual summon lifecycle flags must change'
    assert a['active'] and b['active'], 'Backgrounding must not dismiss the committed sequence'
    assert a['stage'] == b['stage'] and a['index'] == b['index'], 'Backgrounding must not advance unseen reveal stages'
    assert abs(a['sequence_time'] - b['sequence_time']) <= .02, 'Visible-frame summon clock must freeze in background'
    assert a['transaction_digest'] == b['transaction_digest'] and a['results'] == b['results'], 'Resume must not charge, reroll, or grant twice'


def verify_summon_history(state):
    summon = state['summon']
    stages = [row['stage'] for row in summon['history']]
    expected = ['opening', 'constellation', 'seal', 'unseal']
    if summon['rarity'] == 5:
        expected.append('legendary')
    expected += ['portrait', 'result']
    assert stages == expected, ('Actual single reveal omitted/reordered a stage', stages, expected)
    assert summon['ready_frames'] >= 2 and summon['sequence_time'] >= 3.7, 'Rendering must actually progress through the visible-frame reveal clock'


def summon_input_flow(state, component, output):
    state = visit(state, 'summon')
    before = state
    tap(state, 'SummonPull_1', settle=.05)
    state = wait_for(lambda q: q.get('summon', {}).get('active') and q['summon']['stage'] != 'preparing', 'actual single summon begins')
    verify_summon_commit(before, state, 1)
    committed = state['summon']['transaction_digest']
    adb('shell', 'input', 'keyevent', 'KEYCODE_HOME')
    paused = wait_probe_event(state['seq'], 'paused')
    wait_for_completed_background(output)
    adb('shell', 'am', 'start', '-W', '-n', component)
    resumed = wait_probe_event(paused['seq'], 'resumed')
    verify_summon_pause(paused, resumed)
    assert paused['summon']['stage'] not in ('preparing', 'result', 'summary'), 'Pause coverage must interrupt a real moving reveal phase, not an idle result'
    screenshot(output, 'summon-resumed-reveal-frame', True)
    state = wait_for(lambda q: q.get('summon', {}).get('stage') == 'result', 'actual full single reveal sequence', 45)
    verify_summon_history(state)
    assert state['summon']['transaction_digest'] == committed, 'Animation must never repeat the pull transaction'
    screenshot(output, 'summon-single-full-result', True)
    (output / 'summon-single-lifecycle.json').write_text(json.dumps({'before': before['summon'], 'paused': paused['summon'], 'resumed': resumed['summon'], 'result': state['summon']}, indent=2))
    tap(state, 'SummonSkip')
    state = wait_for(lambda q: q.get('summon', {}).get('stage') == 'summary' and q['summon'].get('visible_cards') == 1, 'single summary fully visible')
    tap(state, 'SummonAccept')
    state = wait_for(lambda q: q['screen'] == 'summon' and not q.get('summon', {}).get('active'), 'accept actual single result')
    assert state['summon']['transaction_digest'] == committed, 'Accept must not duplicate any reward'
    # This game's recharge button calls only the local simulated purchase model,
    # not a payment service. Buy the actual visible 60-diamond virtual supply.
    if state['summon']['diamonds'] < 1600:
        state = visit(state, 'shop')
        while state['summon']['diamonds'] < 1600:
            old = state['summon']['diamonds']
            tap_page(state, 'ShopPurchase_recharge_traveler')
            state = wait_for(lambda q: q['summon']['diamonds'] == old + 60, 'actual virtual supply credits sixty diamonds')
        state = visit(state, 'summon')
    before_ten = state
    tap(state, 'SummonPull_10', settle=.05)
    state = wait_for(lambda q: q.get('summon', {}).get('active') and q['summon'].get('sequence_time', 0) >= .65, 'actual ten-pull opening')
    verify_summon_commit(before_ten, state, 10)
    committed_ten = state['summon']['transaction_digest']
    tap(state, 'SummonSkip')
    state = wait_for(lambda q: q.get('summon', {}).get('stage') == 'summary' and q['summon'].get('visible_cards') == 10, 'ten real results revealed after skip')
    assert state['summon']['transaction_digest'] == committed_ten, 'Skip must not charge or reroll ten-pull results'
    screenshot(output, 'summon-ten-skip-summary', True)
    (output / 'summon-ten-transaction.json').write_text(json.dumps({'before': before_ten['summon'], 'summary': state['summon']}, indent=2))
    tap(state, 'SummonAccept')
    state = wait_for(lambda q: q['screen'] == 'summon' and not q.get('summon', {}).get('active'), 'accept ten results')
    assert state['summon']['transaction_digest'] == committed_ten, 'Ten-pull accept must preserve exact transaction'
    return visit(state, 'home')


def relic_input_flow(state, output):
    state = visit(state, 'growth')
    tap_page(state, 'GrowthSelect_zeph')
    state = wait_for(lambda q: any(b['name'] == 'CharacterRecommendedRelics' for b in q['buttons']), 'owned character recommendation entry')
    tap_page(state, 'CharacterRecommendedRelics')
    state = wait_for(lambda q: q.get('relics', {}).get('recommendations_visible'), 'actual character set recommendations')
    choices = [b for b in state['buttons'] if b['name'].startswith('CharacterSetTarget_')]
    assert choices, 'Actual character guidance must expose another target set'
    target_name = choices[0]['name']
    target_id = target_name.removeprefix('CharacterSetTarget_')
    tap_overlay(state, target_name)
    state = wait_for(lambda q: q['relics']['target']['targetSetId'] == target_id and q['relics']['recommendations_visible'], 'recommendation selects actual abyss target')
    assert any(a['set_id'] == target_id and a['resource'].endswith('.tres') and inside(a['rect'], a['clip']) for a in state['relics']['art']), 'Visible recommendation must load its real set artwork'
    screenshot(output, 'character-set-recommendations', True)
    (output / 'character-set-target.json').write_text(json.dumps(state['relics'], indent=2))
    tap_overlay(state, 'CharacterRecommendationsAbyss')
    state = wait_for(lambda q: q['screen'] == 'abyss' and q['overlay'] == 0, 'recommendation opens abyss')
    assert state['relics']['target']['targetSetId'] == target_id, 'Chosen target must survive actual navigation'
    tap_page(state, 'AbyssChooseRelicSet')
    state = wait_for(lambda q: any(b['name'] == 'AbyssSetPickerClose' for b in q['buttons']), 'actual set-picker modal')
    screenshot(output, 'abyss-set-picker', True)
    tap_overlay(state, 'AbyssSetPickerClose')
    state = wait_for(lambda q: q['overlay'] == 0, 'set-picker closes')
    state = visit(state, 'story')
    old_ids = {item['uid'] for item in state['relics']['inventory']}
    tap_page(state, 'StageCard_ch1_1')
    state = wait_for(lambda q: any(b['name'] == 'StoryEnter' for b in q['buttons']), 'actual first story stage selection')
    tap_page(state, 'StoryEnter')
    state = wait_for(lambda q: q['screen'] == 'battle' or any(b['name'] == 'DialogueSkip' for b in q['buttons']), 'actual prebattle story or combat')
    if state['screen'] != 'battle':
        tap(state, 'DialogueSkip')
        state = wait_for(lambda q: q['screen'] == 'battle', 'story dialogue starts real combat')
    if not state['battle_state']['auto']:
        tap(state, 'BattleAutoToggle')
    state = wait_for(lambda q: q['battle_state']['phase'] in ('victory', 'defeat') and any(b['name'] == 'BattleSettlementContinue' for b in q['buttons']), 'real story battle settles earned relic', 180)
    assert state['battle_state']['phase'] == 'victory', 'Actual story defeat cannot be replaced with a granted relic'
    earned = [item for item in state['relics']['inventory'] if item['uid'] not in old_ids]
    assert len(earned) == 1 and state['relics']['inventory_count'] == len(old_ids) + 1, 'Real story win must award exactly one new relic UID'
    screenshot(output, 'story-earned-relic', True)
    tap_overlay(state, 'BattleSettlementContinue')
    state = wait_for(lambda q: q['screen'] == 'story' or any(b['name'] == 'DialogueSkip' for b in q['buttons']), 'story settlement continues')
    if any(b['name'] == 'DialogueSkip' for b in state['buttons']):
        tap(state, 'DialogueSkip')
        state = wait_for(lambda q: q['screen'] == 'story' and q['overlay'] == 0, 'actual postbattle dialogue closes')
    state = visit(state, 'relics')
    before = state['relics']
    assert any(a['set_id'] == earned[0].get('setId') and a['resource'].endswith('.tres') and inside(a['rect'], a['clip']) for a in before['art']), 'Earned set relic must show its real texture in the inventory'
    screenshot(output, 'relic-earned-set-art', True)
    tap_page(state, 'RelicAutoEquip')
    state = wait_for(lambda q: bool(q.get('relics', {}).get('displayed_plan', {}).get('after')), 'actual optimizer displays a real plan', 60)
    plan = state['relics']['displayed_plan']
    assert plan.get('success', True), 'Actual optimizer preview cannot silently fail'
    assert state['relics']['inventory_digest'] == before['inventory_digest'] and state['relics']['equipped'] == before['equipped'], 'Preview must never apply equipment implicitly'
    screenshot(output, 'relic-actual-optimizer-preview', True)
    (output / 'relic-earned-preview.json').write_text(json.dumps({'earned': earned, 'preview': plan, 'before': before}, indent=2))
    tap_overlay(state, 'RelicLoadoutCancel')
    state = wait_for(lambda q: q['screen'] == 'relics' and q['overlay'] == 0, 'optimizer actual cancellation')
    assert state['relics']['inventory_digest'] == before['inventory_digest'] and state['relics']['equipped'] == before['equipped'], 'Cancel preserves exact owned relics and all character equipment'
    return visit(state, 'home')


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


def validate_android_bridge(bridge):
    assert bridge.get('success') is True, f'Android download/install bridge unavailable: {bridge}'
    assert bridge.get('package') == PACKAGE, f'Android bridge resolved wrong package: {bridge}'
    policy = bridge.get('network_policy', {})
    assert policy.get('metered_permitted') is True, f'Actual DownloadManager request must permit cellular/metered data: {policy}'
    assert policy.get('roaming_permitted') is False, f'International roaming remains separately protected: {policy}'
    return policy


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
    assert state['window'][0] > state['window'][1], 'Landscape startup required even with portrait OS setting'
    renderer = state.get('renderer', {})
    (output / 'renderer.json').write_text(json.dumps(renderer, indent=2))
    assert renderer.get('method') == 'mobile' and renderer.get('driver') == 'vulkan', f'Expected actual Mobile/Vulkan renderer, not silent fallback: {renderer}'
    assert renderer.get('adapter'), f'Missing actual graphics adapter: {renderer}'
    bridge = state.get('android_bridge', {})
    policy = validate_android_bridge(bridge)
    (output / 'android-network-policy.json').write_text(json.dumps({'policy': policy, 'evidence': 'Actual Android DownloadManager.Request setter accepted metered data; this is not a completed cellular APK download.'}, indent=2))
    geometry(state)
    dismiss_fullscreen_education(output, state['window'])
    state = wait_for(lambda s: s['screen'] == 'home' and s['overlay'] == 0, 'home after fullscreen education')
    screenshot(output, 'landscape-locked-home', True)
    # Menu is dismissed by the real Android Back event and the game stays alive.
    tap(state, 'MenuButton')
    wait_for(lambda s: s['overlay'] > 0, 'menu before Back')
    screenshot(output, 'landscape-locked-menu', True)
    back()
    state = wait_for(lambda s: s['screen'] == 'home' and s['overlay'] == 0, 'Back dismisses menu')
    (output / 'back-menu.json').write_text(json.dumps({'screen': state['screen'], 'overlay': state['overlay'], 'events': state.get('system_back_events', [])}, indent=2))
    pages = ['story', 'summon', 'party', 'growth', 'relics', 'abyss', 'extraction', 'shop', 'save']
    for page in pages:
        state = visit(state, page)
        geometry(state)
        screenshot(output, 'landscape-locked-' + page, True)
        if state['scroll_max'] > 10:
            x, y, w, h = state['scroll_rect']
            before = state['scroll']
            adb('shell', 'input', 'swipe', str(round(x + w * .85)), str(round(y + h * .8)), str(round(x + w * .85)), str(round(y + h * .2)), '600')
            state = wait_for(lambda s: s['scroll'] > before + 5, page + ' finger scroll')
            screenshot(output, 'landscape-locked-' + page + '-scrolled', True)
        back()
        state = wait_for(lambda s: s['screen'] == 'home' and s['overlay'] == 0, page + ' Android Back')
    search_background={"covered":False,"attempts":0,"reason":"No natural long scan with a safe remaining interval was observed"}
    state = extraction_flow(state, output, component, search_background)
    state = summon_input_flow(state, component, output)
    state = relic_input_flow(state, output)
    (output/"search-background.json").write_text(json.dumps(search_background,indent=2))
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
    candidates = [scroll for scroll in state.get('page_scrolls', []) if scroll['max'] > 10]
    assert candidates, 'Landscape growth must expose local scrollable details'
    target_scroll = max(candidates, key=lambda item: item['rect'][2])
    x, y, w, h = target_scroll['rect']
    before = target_scroll['value']
    scroll_id = target_scroll['id']
    adb('shell', 'input', 'swipe', str(round(x + w * .85)), str(round(y + h * .8)), str(round(x + w * .85)), str(round(y + h * .2)), '600')
    state = wait_for(lambda s: s['screen'] == 'growth' and any(item['id'] == scroll_id and item['value'] > before + 5 for item in s.get('page_scrolls', [])), 'landscape growth local finger scroll')
    screenshot(output, 'landscape-growth-scrolled', True)
    back()
    state = wait_for(lambda s: s['screen'] == 'home' and s['overlay'] == 0, 'landscape Back')
    check_background_resume(component, output)
    assert adb('shell', 'pidof', PACKAGE).strip(), 'Android app process disappeared'
    logs = adb('logcat', '-d', '-v', 'threadtime')
    errors = [line for line in logs.splitlines() if re.search(r'SCRIPT ERROR|Parse Error|FATAL EXCEPTION|Fatal signal|ANR in ' + re.escape(PACKAGE), line) or ('godot' in line.lower() and re.search(r'\bERROR:', line))]
    assert not errors, '\n'.join(errors)
    (output / 'result.json').write_text(json.dumps({'passed': True, 'search_background': search_background, 'android_api': adb('shell', 'getprop', 'ro.build.version.sdk').strip(), 'abi': adb('shell', 'getprop', 'ro.product.cpu.abi').strip(), 'pages': pages, 'checks': ['landscape launch while system portrait', 'all menu tabs by touch', 'scrolling where content exceeds viewport', 'Android Back', 'landscape adaptation', 'background/resume', 'extraction map drag/connected navigation/scene-container auto-search/auto-pickup/room and bag persistence', 'Android download bridge capability (no download/install)', 'single summon rendered stage history/frame clock/native pause-resume/exact transaction', 'ten summon real virtual-supply purchase/skip/ten visible cards/no duplicate rewards', 'character recommendations/abyss target/real story-earned relic/art/optimizer preview cancellation', 'completed room auto-return preserves exact loot and remaining interactions', 'runtime error log']}, indent=2))
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
