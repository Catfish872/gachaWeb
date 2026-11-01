#!/usr/bin/env python3
"""Offline regression checks for the Android runtime driver (not emulator tests)."""
import base64
import json
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('android_smoke', ROOT / 'tools/android/smoke_test.py')
smoke = importlib.util.module_from_spec(spec)
spec.loader.exec_module(smoke)


def chunk_lines(state):
    encoded = base64.b64encode(json.dumps(state, ensure_ascii=False).encode()).decode()
    count = (len(encoded) + 599) // 600
    return [f"I godot: ANDROID_SMOKE_CHUNK {state['seq']} {index} {count} {len(encoded)} {encoded[index * 600:(index + 1) * 600]}" for index in range(count)]


class AndroidSmokeDriverTests(unittest.TestCase):
    def loot_frame(self, seq, ms, source_uid='', bag_uid='', box='box'):
        def item(uid):return {'uid':uid,'revealed':True,'name':'晶片','icon_loaded':True,'rect':[10,10,40,40],'clip':[0,0,100,100]}
        return {'seq':seq,'monotonic_ms':ms,'loot':{'container_id':box,'source':[item(source_uid)] if source_uid else [],'bag':[item(bag_uid)] if bag_uid else []}}

    def test_pickup_visibility_tracks_same_uid_and_actual_destination(self):
        frames=[self.loot_frame(2,100,'a'),self.loot_frame(3,200,'a'),self.loot_frame(4,310,'a'),self.loot_frame(5,500,bag_uid='a')]
        self.assertEqual(smoke.visible_pickup_uids(frames,'box',1),{'a'})
        self.assertEqual(smoke.visible_pickup_uids(frames,'box',3),set())
        frames[-1]=self.loot_frame(5,500,bag_uid='b')
        self.assertEqual(smoke.visible_pickup_uids(frames,'box',1),set())

    def test_unrelated_icons_cannot_fake_continuous_visible_dwell(self):
        frames=[self.loot_frame(2,100,'a'),self.loot_frame(3,210,'b'),self.loot_frame(4,320,'c'),self.loot_frame(5,500,bag_uid='a')]
        self.assertEqual(smoke.visible_pickup_uids(frames,'box',1),set())

    def test_visibility_gap_does_not_count_as_same_uid_dwell(self):
        frames=[self.loot_frame(2,100,'a'),self.loot_frame(3,200),self.loot_frame(4,400,'a'),self.loot_frame(5,500,bag_uid='a')]
        self.assertEqual(smoke.visible_pickup_uids(frames,'box',1),set())

    def test_hidden_clipped_missing_icon_and_other_container_are_not_visible_proof(self):
        for mutation in ['hidden','clipped','missing','other']:
            frames=[self.loot_frame(2,100,'a'),self.loot_frame(3,310,'a'),self.loot_frame(4,500,bag_uid='a')]
            for frame in frames[:2]:
                item=frame['loot']['source'][0]
                if mutation=='hidden':item['revealed']=False
                elif mutation=='clipped':item['rect']=[90,10,40,40]
                elif mutation=='missing':item['icon_loaded']=False
                else:frame['loot']['container_id']='other'
            self.assertEqual(smoke.visible_pickup_uids(frames,'box',1),set(),mutation)

    def test_long_scan_detection_uses_observed_progress_not_hidden_rarity(self):
        a={'monotonic_ms':100,'loot':{'container_id':'box','scan_uid':'u','scan_progress':.1}}
        b={'monotonic_ms':200,'loot':{'container_id':'box','scan_uid':'u','scan_progress':.15}}
        self.assertTrue(smoke.scan_has_background_window(a,b))
        b['loot']['scan_progress']=.5
        self.assertFalse(smoke.scan_has_background_window(a,b))
        b['loot']['scan_progress']=.15;b['loot']['scan_uid']='other'
        self.assertFalse(smoke.scan_has_background_window(a,b))

    def test_paused_wall_clock_is_not_visible_dwell_evidence(self):
        a=self.loot_frame(2,100,'a')
        paused=self.loot_frame(3,200,'a');paused['application_paused']=True
        resumed=self.loot_frame(4,6000,'a')
        collected=self.loot_frame(5,6100,bag_uid='a')
        self.assertEqual(smoke.visible_pickup_uids([a,paused,resumed,collected],'box',1),set())

    def test_actual_pause_resume_requires_same_progress_and_ownership(self):
        from tempfile import TemporaryDirectory
        before={'seq':10}
        paused={'seq':11,'application_paused':True,'extraction':{'searching':True,'bag_ids':[]},'loot':{'scan_uid':'u','scan_progress':.3,'source':[{'uid':'u','revealed':False}]}}
        resumed=json.loads(json.dumps(paused));resumed['seq']=12;resumed['application_paused']=False
        with TemporaryDirectory() as directory,patch.object(smoke,'adb') as adb,patch.object(smoke,'wait_for_completed_background'),patch.object(smoke,'wait_probe_event',side_effect=[paused,resumed]):
            coverage={'reason':'No natural long scan observed'}
            smoke.check_search_background(before,'pkg/Activity',Path(directory),coverage)
            self.assertTrue(coverage['covered'])
            self.assertNotIn('reason', coverage)
            self.assertNotIn('reason', json.loads((Path(directory)/'search-background.json').read_text()))
            self.assertEqual(adb.call_args_list[0].args,('shell','input','keyevent','KEYCODE_HOME'))
            self.assertEqual(adb.call_args_list[1].args,('shell','am','start','-W','-n','pkg/Activity'))
        resumed['loot']['scan_progress']=.8
        with TemporaryDirectory() as directory,patch.object(smoke,'adb'),patch.object(smoke,'wait_for_completed_background'),patch.object(smoke,'wait_probe_event',side_effect=[paused,resumed]),self.assertRaisesRegex(AssertionError,'progress jumped'):
            smoke.check_search_background(before,'pkg/Activity',Path(directory),{})

    def map_drag_frame(self, zoom=.3, can_pan=False, pan=(10, 20), room='entry'):
        return {'seq': 1, 'extraction': {'room_id': room, 'phase': 'route'}, 'canvases': {'map': {'zoom': zoom, 'selected_room': room, 'can_pan_x': can_pan, 'pan': list(pan), 'clip': [32, 268, 734, 324]}}}

    def test_map_drag_zooms_real_overview_before_real_swipe(self):
        initial=self.map_drag_frame()
        zoomed=self.map_drag_frame(.5, True)
        moved=self.map_drag_frame(.5, True, (-30, 20))
        with patch.object(smoke, 'reveal_page_target', return_value=initial), patch.object(smoke, 'tap_page') as tap, patch.object(smoke, 'adb') as adb, patch.object(smoke, 'wait_for', side_effect=[initial, zoomed, moved]) as wait:
            self.assertEqual(smoke.verify_map_finger_drag(initial), moved)
            tap.assert_called_once_with(initial, 'AtlasZoomIn')
            self.assertFalse(wait.call_args_list[1].args[0](initial))
            self.assertTrue(wait.call_args_list[1].args[0](zoomed))
            self.assertFalse(wait.call_args_list[2].args[0](zoomed))
            self.assertFalse(wait.call_args_list[2].args[0](self.map_drag_frame(.5, True, (9.9, 20))))
            self.assertFalse(wait.call_args_list[2].args[0](self.map_drag_frame(.5, True, (30, 20))))
            self.assertTrue(wait.call_args_list[2].args[0](moved))
            self.assertEqual(adb.call_count, 2)
            adb.assert_called_with('shell', 'input', 'swipe', '582', '430', '216', '430', '600')

    def test_map_drag_already_zoomed_still_requires_pan_and_no_travel(self):
        initial=self.map_drag_frame(.8, True)
        moved=self.map_drag_frame(.8, True, (-30, 20), 'wrong-room')
        with patch.object(smoke, 'reveal_page_target', return_value=initial), patch.object(smoke, 'tap_page') as tap, patch.object(smoke, 'adb'), patch.object(smoke, 'wait_for', return_value=moved), self.assertRaisesRegex(AssertionError, 'unintentionally entered'):
            smoke.verify_map_finger_drag(initial)
        tap.assert_not_called()

    def test_map_preview_requires_fresh_selection_and_second_real_tap(self):
        initial = {'seq': 10, 'extraction': {'room_id': 'entry', 'phase': 'route'}, 'buttons': [{'name': 'ExtractionMapNode_cache', 'adjacent': True, 'rect': [1,2,3,4]}], 'canvases': {'map': {'selected_room': 'entry'}}}
        preview = json.loads(json.dumps(initial))
        preview['seq'] = 11
        preview['canvases']['map']['selected_room'] = 'cache'
        preview['buttons'][0]['rect'] = [30,40,3,4]
        entered = {'seq': 12, 'extraction': {'room_id': 'cache', 'phase': 'room'}}
        with patch.object(smoke, 'canvas_target', return_value=initial), patch.object(smoke, 'tap') as tap, patch.object(smoke, 'wait_for', side_effect=[preview, entered]) as wait:
            self.assertEqual(smoke.enter_map_room(initial, 'cache'), entered)
            self.assertEqual(tap.call_count, 2)
            self.assertEqual(tap.call_args_list[1].args, (preview, 'ExtractionMapNode_cache'))
            predicate=wait.call_args_list[0].args[0]
            self.assertFalse(predicate(initial))
            stale=json.loads(json.dumps(preview));stale['seq']=10
            self.assertFalse(predicate(stale))
            self.assertTrue(predicate(preview))
            self.assertFalse(predicate(entered))
            self.assertTrue(wait.call_args_list[1].args[0](entered))

    def test_map_revisit_selected_current_room_needs_one_real_tap(self):
        initial={'seq': 20, 'extraction': {'room_id': 'cache', 'phase': 'route'}, 'canvases': {'map': {'selected_room': 'cache'}}, 'buttons': [{'name': 'ExtractionMapNode_cache', 'adjacent': False}]}
        entered={'seq': 21, 'extraction': {'room_id': 'cache', 'phase': 'room'}}
        with patch.object(smoke, 'canvas_target', return_value=initial), patch.object(smoke, 'tap') as tap, patch.object(smoke, 'wait_for', return_value=entered) as wait:
            self.assertEqual(smoke.enter_map_room(initial,'cache'),entered)
            tap.assert_called_once_with(initial,'ExtractionMapNode_cache')
            self.assertEqual(wait.call_count,1)
            self.assertTrue(wait.call_args.args[0](entered))
            stale=dict(entered,seq=20)
            self.assertFalse(wait.call_args.args[0](stale))

    def far_travel_state(self):
        return {'seq':10,'extraction':{'room_id':'entry','phase':'route','map_edges':[['entry','middle'],['middle','far']],'map_rooms':[{'id':'entry','type':'entry','visited':True},{'id':'middle','type':'cache','visited':True},{'id':'far','type':'rest','visited':False}]},'canvases':{'map':{'selected_room':'far'}},'buttons':[{'name':'ExtractionMapNode_far','adjacent':False,'reachable':True,'travel_path':['entry','middle','far']}]}

    def test_distant_selected_room_uses_verified_safe_existing_edges(self):
        initial=self.far_travel_state()
        entered={'seq':11,'extraction':{'room_id':'far','phase':'room'}}
        with patch.object(smoke,'canvas_target',return_value=initial),patch.object(smoke,'tap') as tap,patch.object(smoke,'wait_for',return_value=entered):
            self.assertEqual(smoke.enter_map_room(initial,'far'),entered)
            tap.assert_called_once_with(initial,'ExtractionMapNode_far')

    def test_distant_travel_rejects_shortcut_unsafe_or_locked_intermediate(self):
        for case in ['shortcut','unvisited','battle','uncleared_vault']:
            state=self.far_travel_state()
            room=state['extraction']['map_rooms'][1]
            if case=='shortcut':state['extraction']['map_edges'].pop()
            elif case=='unvisited':room['visited']=False
            elif case=='battle':room['type']='battle';room['cleared']=False
            else:room['type']='vault';room['cleared']=False
            with patch.object(smoke,'canvas_target',return_value=state),patch.object(smoke,'tap') as tap,self.assertRaises(AssertionError):
                smoke.enter_map_room(state,'far')
            tap.assert_not_called()

    def test_locked_key_vault_exterior_is_a_valid_visited_corridor(self):
        initial=self.far_travel_state()
        initial['extraction']['map_rooms'][1].update(type='key_vault',unlocked=False)
        entered={'seq':11,'extraction':{'room_id':'far','phase':'room'}}
        with patch.object(smoke,'canvas_target',return_value=initial),patch.object(smoke,'tap') as tap,patch.object(smoke,'wait_for',return_value=entered):
            self.assertEqual(smoke.enter_map_room(initial,'far'),entered)
            tap.assert_called_once()

    def test_map_fit_wait_rejects_stale_and_unfitted_observation(self):
        initial={'seq': 4, 'canvases': {'map': {'auto_fit': False, 'zoom': .8, 'fit_zoom': .3}}}
        fitted={'seq': 5, 'canvases': {'map': {'auto_fit': True, 'zoom': .3, 'fit_zoom': .3}}}
        with patch.object(smoke, 'tap_page') as tap, patch.object(smoke, 'wait_for', return_value=fitted) as wait:
            self.assertEqual(smoke.restore_map_overview(initial),fitted)
            tap.assert_called_once_with(initial,'AtlasFit')
            predicate=wait.call_args.args[0]
            self.assertFalse(predicate(initial))
            stale=json.loads(json.dumps(fitted));stale['seq']=4
            self.assertFalse(predicate(stale))
            unfitted=json.loads(json.dumps(fitted));unfitted['canvases']['map']['zoom']=.7
            self.assertFalse(predicate(unfitted))
            self.assertTrue(predicate(fitted))

    def test_reads_only_complete_probe_records(self):
        state = {'seq': 1, 'screen': 'home'}
        log = '\n'.join(chunk_lines(state)) + '\nI godot: ANDROID_SMOKE_CHUNK broken'
        self.assertEqual(smoke.snapshots(log), [state])

    def menu_frame(self, seq=12):
        return {'seq': seq, 'screen': 'home', 'overlay': 2, 'buttons': [{'name': f'MenuNav_{index}', 'text': '星辰祈愿', 'rect': [1, 2, 3, 4], 'clip': [1, 2, 3, 4]} for index in range(11)]}

    def test_large_unicode_menu_reassembles_out_of_order(self):
        state = self.menu_frame()
        lines = chunk_lines(state)
        self.assertGreater(len(lines), 2)
        self.assertTrue(all(len(line.encode()) < 700 for line in lines))
        self.assertEqual(smoke.snapshots('\n'.join(reversed(lines))), [state])

    def test_missing_and_truncated_chunks_never_emit_frame(self):
        lines = chunk_lines(self.menu_frame())
        for broken in [lines[1:], lines[:-1], lines[:-1] + [lines[-1][:-4]]]:
            with self.subTest(broken=broken):
                self.assertEqual(smoke.snapshots('\n'.join(broken)), [])

    def test_identical_duplicates_emit_one_frame(self):
        state = self.menu_frame()
        lines = chunk_lines(state)
        self.assertEqual(smoke.snapshots('\n'.join(lines + lines)), [state])

    def test_conflicting_duplicate_rejects_whole_sequence(self):
        lines = chunk_lines(self.menu_frame())
        duplicate = lines[0][:-1] + ('A' if lines[0][-1] != 'A' else 'B')
        self.assertEqual(smoke.snapshots('\n'.join(lines + [duplicate])), [])

    def test_frames_do_not_mix_sequences(self):
        first, second = self.menu_frame(1), self.menu_frame(2)
        one, two = chunk_lines(first), chunk_lines(second)
        self.assertEqual(smoke.snapshots('\n'.join(one[:-1] + two)), [second])
        self.assertEqual(smoke.snapshots('\n'.join(two + one)), [first, second])

    def test_mismatched_envelope_sequence_rejected(self):
        lines = [line.replace('CHUNK 12 ', 'CHUNK 13 ') for line in chunk_lines(self.menu_frame())]
        self.assertEqual(smoke.snapshots('\n'.join(lines)), [])

    def test_taps_actual_button_center(self):
        state = {'window': [720, 1280], 'buttons': [{'name': 'MenuButton', 'rect': [500, 20, 100, 80]}]}
        with patch.object(smoke, 'adb') as adb, patch.object(smoke.time, 'sleep'):
            smoke.tap(state, 'MenuButton')
        adb.assert_called_once_with('shell', 'input', 'tap', '550', '60')

    def test_offscreen_button_fails_before_input(self):
        state = {'window': [720, 1280], 'buttons': [{'name': 'MenuButton', 'rect': [700, 20, 100, 80]}]}
        with patch.object(smoke, 'adb') as adb, self.assertRaises(AssertionError):
            smoke.tap(state, 'MenuButton')
        adb.assert_not_called()

    def test_missing_or_duplicate_button_fails(self):
        for buttons in [[], [{'name': 'MenuButton'}, {'name': 'MenuButton'}]]:
            with self.subTest(buttons=buttons), self.assertRaises(AssertionError):
                smoke.tap({'buttons': buttons}, 'MenuButton')

    def test_horizontal_overflow_fails(self):
        with self.assertRaises(AssertionError):
            smoke.geometry({'page_width': 600, 'scroll_width': 400, 'logical': [360, 640]})

    def test_width_that_fits_passes(self):
        smoke.geometry({'page_width': 400, 'scroll_width': 400, 'logical': [360, 640]})

    def test_clipped_button_fails_before_input(self):
        state = {'window': [1280, 720], 'buttons': [{'name': 'MenuButton', 'rect': [50, 500, 100, 80], 'clip': [0, 0, 500, 450]}]}
        with patch.object(smoke, 'adb') as adb, self.assertRaises(AssertionError):
            smoke.tap(state, 'MenuButton')
        adb.assert_not_called()

    def test_wait_requires_two_new_matching_records(self):
        import json
        def log(*seqs):
            return '\n'.join(line for seq in seqs for line in chunk_lines({'seq': seq, 'screen': 'home'}))
        with patch.object(smoke, 'adb', side_effect=[log(1), log(1), log(1, 2), log(1, 2, 3)]) as adb, patch.object(smoke.time, 'sleep'):
            state = smoke.wait_for(lambda s: s['screen'] == 'home', 'fresh home')
        self.assertEqual(state['seq'], 3)
        self.assertEqual(adb.call_count, 4)

    def test_menu_scroll_uses_android_input(self):
        state = {'buttons': [{'name': 'MenuNav_growth', 'rect': [20, 600, 100, 50], 'clip': [0, 100, 500, 400]}], 'modal_scrolls': [{'rect': [0, 100, 500, 400], 'value': 0, 'max': 500}]}
        shown = {'buttons': [{'name': 'MenuNav_growth', 'rect': [20, 300, 100, 50], 'clip': [0, 100, 500, 400]}]}
        with patch.object(smoke, 'adb') as adb, patch.object(smoke, 'wait_for', return_value=shown):
            self.assertEqual(smoke.reveal_menu_target(state, 'MenuNav_growth'), shown)
        adb.assert_called_once_with('shell', 'input', 'swipe', '450', '420', '450', '180', '600')

    def test_boot_configuration_waits_until_stable(self):
        import tempfile
        clock = [0.0]
        def sleep(seconds):
            clock[0] += seconds
        replies = ['All broadcast queues are idle!', 'config: initial', 'config: settled'] + ['config: settled'] * 5
        with tempfile.TemporaryDirectory() as directory, patch.object(smoke, 'adb', side_effect=replies) as adb, patch.object(smoke.time, 'monotonic', side_effect=lambda: clock[0]), patch.object(smoke.time, 'sleep', side_effect=sleep):
            smoke.settle_android_configuration(Path(directory))
            self.assertEqual((Path(directory) / 'boot-config.txt').read_text(), 'config: settled')
        self.assertEqual(clock[0], 6.0)
        self.assertEqual(adb.call_args_list[0].args, ('shell', 'am', 'wait-for-broadcast-idle'))

    def test_missing_boot_configuration_fails(self):
        import tempfile
        with tempfile.TemporaryDirectory() as directory, patch.object(smoke, 'adb', side_effect=['idle', 'Error: unsupported']), self.assertRaises(AssertionError):
            smoke.settle_android_configuration(Path(directory))

    def fullscreen_fixture(self, package='android', text='Got it', bounds='[532,330][672,428]'):
        import xml.etree.ElementTree as ET
        return ET.fromstring(f'<hierarchy><node package="{package}" resource-id="android:id/immersive_cling_title" text="Viewing full screen"/><node package="{package}" resource-id="android:id/ok" text="{text}" class="android.widget.Button" enabled="true" clickable="true" bounds="{bounds}"/></hierarchy>')

    def test_fullscreen_education_matches_exact_system_controls(self):
        self.assertEqual(smoke.immersive_hint_button(self.fullscreen_fixture(), [720, 1280]), (602, 379))

    def test_permission_dialog_is_never_a_dismissal_target(self):
        self.assertIsNone(smoke.immersive_hint_button(self.fullscreen_fixture(package='com.google.android.permissioncontroller', text='Allow'), [720, 1280]))
        self.assertIsNone(smoke.immersive_hint_button(self.fullscreen_fixture(package=smoke.PACKAGE), [720, 1280]))

    def test_invalid_fullscreen_button_is_rejected(self):
        for kwargs in [{'text': 'Allow'}, {'bounds': '[532,330][999,428]'}]:
            with self.subTest(kwargs=kwargs), self.assertRaises(AssertionError):
                smoke.immersive_hint_button(self.fullscreen_fixture(**kwargs), [720, 1280])

    def test_fullscreen_dismissal_taps_verified_bounds_then_checks_ui(self):
        import tempfile
        import xml.etree.ElementTree as ET
        with tempfile.TemporaryDirectory() as directory, patch.object(smoke, 'read_ui_hierarchy', side_effect=[self.fullscreen_fixture(), ET.fromstring('<hierarchy/>')]) as read, patch.object(smoke, 'adb') as adb:
            smoke.dismiss_fullscreen_education(Path(directory), [720, 1280])
        adb.assert_called_once_with('shell', 'input', 'tap', '602', '379')
        self.assertEqual(read.call_count, 2)

    def test_background_requires_stopped_app_and_other_foreground(self):
        activity = f'topResumedActivity=ActivityRecord{{abc com.android.launcher3/.Launcher}}\n * Hist #1: ActivityRecord{{def}}\npackageName={smoke.PACKAGE} processName={smoke.PACKAGE}\nstate=STOPPED'
        self.assertTrue(smoke.background_is_stopped(activity))
        self.assertFalse(smoke.background_is_stopped(activity.replace('state=STOPPED', 'state=STOPPING')))
        self.assertFalse(smoke.background_is_stopped(activity.replace('com.android.launcher3', smoke.PACKAGE)))

    def test_resume_order_starts_with_original_rapid_case(self):
        import tempfile
        events = []
        def wait(predicate, description, *args):
            events.append(description)
            return {'screen': 'home', 'overlay': 0}
        with tempfile.TemporaryDirectory() as directory, patch.object(smoke, 'adb'), patch.object(smoke, 'wait_for_completed_background', side_effect=lambda _: events.append('settled wait')), patch.object(smoke, 'wait_for', side_effect=wait), patch.object(smoke, 'tap'), patch.object(smoke, 'back'), patch.object(smoke, 'screenshot'), patch.object(smoke.time, 'sleep') as sleep:
            smoke.check_background_resume('pkg/Activity', Path(directory))
            results = json.loads((Path(directory) / 'resume-results.json').read_text())
            self.assertEqual([item['mode'] for item in results], ['rapid', 'settled', 'rapid_again'])
            self.assertTrue(all(item['passed'] for item in results))
            self.assertEqual(events[0], 'rapid resume')
            self.assertLess(events.index('rapid resume'), events.index('settled wait'))
            self.assertEqual([call.args for call in sleep.call_args_list], [(1,)] * 5)

    def test_each_resume_failure_is_retained_and_remaining_cases_run(self):
        import tempfile
        modes = ['rapid', 'settled', 'rapid_again']
        for failed_mode in modes:
            with self.subTest(failed_mode=failed_mode):
                events = []
                def wait(predicate, description, *args):
                    events.append(description)
                    if description == failed_mode + ' resume':
                        raise AssertionError('fresh-frame timeout')
                    return {'screen': 'home', 'overlay': 0}
                def adb(*args, **kwargs):
                    return b'PNG evidence' if kwargs.get('binary') else 'log evidence'
                with tempfile.TemporaryDirectory() as directory, patch.object(smoke, 'adb', side_effect=adb) as commands, patch.object(smoke, 'wait_for_completed_background'), patch.object(smoke, 'wait_for', side_effect=wait), patch.object(smoke, 'tap'), patch.object(smoke, 'back'), patch.object(smoke, 'screenshot'), patch.object(smoke.time, 'sleep'):
                    with self.assertRaisesRegex(AssertionError, 'Background/resume failed'):
                        smoke.check_background_resume('pkg/Activity', Path(directory))
                    results = json.loads((Path(directory) / 'resume-results.json').read_text())
                    self.assertEqual([item['mode'] for item in results], modes)
                    self.assertEqual([item['passed'] for item in results], [mode != failed_mode for mode in modes])
                    self.assertTrue((Path(directory) / (failed_mode + '-resume-logcat.txt')).exists())
                    restarts = [call for call in commands.call_args_list if call.args == ('shell', 'am', 'force-stop', smoke.PACKAGE)]
                    self.assertEqual(len(restarts), int(failed_mode != 'rapid_again'))
                    self.assertIn('rapid_again resume', events)

    def test_page_control_scroll_uses_android_input(self):
        state = {'buttons': [{'name': 'ExtractionCloseContainer', 'rect': [20, 600, 100, 50], 'clip': [0, 100, 500, 400]}], 'scroll': 0, 'scroll_max': 500, 'scroll_rect': [0, 100, 500, 400]}
        shown = {'buttons': [{'name': 'ExtractionCloseContainer', 'rect': [20, 300, 100, 50], 'clip': [0, 100, 500, 400]}], 'scroll': 200, 'scroll_max': 500, 'scroll_rect': [0, 100, 500, 400]}
        with patch.object(smoke, 'adb') as adb, patch.object(smoke, 'wait_for', return_value=shown):
            self.assertEqual(smoke.reveal_page_target(state, 'ExtractionCloseContainer'), shown)
        adb.assert_called_once_with('shell', 'input', 'swipe', '425', '380', '425', '220', '900')

    def test_page_swipe_avoids_native_scrollbar_and_map(self):
        state = {'scroll_rect': [24, 276, 672, 988], 'scrollbar_rect': [680, 276, 16, 988]}
        self.assertAlmostEqual(smoke.page_swipe_x(state), 595.2)
        state['canvases'] = {'map': {'rect': [24, 400, 624, 680]}}
        self.assertEqual(smoke.page_swipe_x(state), 664)
        self.assertLess(smoke.page_swipe_x(state), state['scrollbar_rect'][0])
        self.assertGreater(smoke.page_swipe_x(state), 648)

    def test_ci_start_button_geometry_converges_with_bounded_finger_drag(self):
        import copy
        state = {'scroll_rect': [24, 276, 672, 988], 'scrollbar_rect': [680, 276, 16, 988],
                 'scroll': 0, 'scroll_max': 1321, 'buttons': [{'name': 'ExtractionStart', 'rect': [24, 1804, 108, 102], 'clip': [24, 276, 672, 988]}]}
        gestures = []
        def input_drag(*args):
            self.assertEqual(args[:3], ('shell', 'input', 'swipe'))
            self.assertLess(int(args[3]), 680)
            delta = int(args[4]) - int(args[6])
            gestures.append(delta)
            state['scroll'] += delta / 2
            state['buttons'][0]['rect'][1] -= delta
        with patch.object(smoke, 'adb', side_effect=input_drag), patch.object(smoke, 'wait_for', side_effect=lambda *a: copy.deepcopy(state)):
            shown = smoke.reveal_page_target(copy.deepcopy(state), 'ExtractionStart')
        self.assertTrue(smoke.inside(shown['buttons'][0]['rect'], shown['buttons'][0]['clip']))
        self.assertEqual(len(gestures), 2)
        self.assertTrue(all(0 < value <= 396 for value in gestures))

    def test_page_target_missing_fails_before_scroll(self):
        with patch.object(smoke, 'adb') as adb, self.assertRaisesRegex(AssertionError, 'Missing/duplicate'):
            smoke.reveal_page_target({'buttons': []}, 'ExtractionStart')
        adb.assert_not_called()

    def test_safe_map_path_uses_only_connected_noncombat_rooms(self):
        state = {'extraction': {'room_id': 'a', 'map_rooms': [
            {'id': 'a', 'type': 'entry', 'visited': True},
            {'id': 'b', 'type': 'cache', 'visited': True},
            {'id': 'c', 'type': 'workshop', 'visited': False},
            {'id': 'd', 'type': 'battle', 'visited': False},
            {'id': 'e', 'type': 'vault', 'visited': False}],
            'map_edges': [['a', 'd'], ['d', 'e'], ['a', 'b'], ['b', 'c']]}}
        self.assertEqual(smoke.safe_exploration_path(state), ['b', 'c'])
        state['extraction']['map_rooms'][2]['visited'] = True
        self.assertEqual(smoke.safe_exploration_path(state), [])

    def test_canvas_target_pans_with_real_adb_input(self):
        state = {'buttons': [{'name': 'ExtractionMapNode_b', 'rect': [500, 200, 40, 40], 'clip': [0, 100, 400, 300]}],
                 'canvases': {'map': {'clip': [0, 100, 400, 300], 'pan': [0, 0]}}}
        shown = {'buttons': [{'name': 'ExtractionMapNode_b', 'rect': [200, 200, 40, 40], 'clip': [0, 100, 400, 300]}]}
        with patch.object(smoke, 'reveal_page_target', return_value=state), patch.object(smoke, 'adb') as adb, patch.object(smoke, 'wait_for', return_value=shown):
            self.assertEqual(smoke.canvas_target(state, 'ExtractionMapNode_b', 'map'), shown)
        adb.assert_called_once_with('shell', 'input', 'swipe', '260', '235', '140', '265', '600')

    def test_disconnected_room_cannot_be_tapped(self):
        state = {'buttons': [{'name': 'ExtractionMapNode_z', 'adjacent': False}], 'extraction': {'room_id': 'a'}}
        with patch.object(smoke, 'canvas_target', return_value=state), patch.object(smoke, 'tap') as tap, self.assertRaisesRegex(AssertionError, 'disconnected'):
            smoke.enter_map_room(state, 'z')
        tap.assert_not_called()

    def test_probe_is_observational_and_reports_extraction_state(self):
        probe = (ROOT / 'tools/android/runtime_probe.gd').read_text()
        for forbidden in ['start_run(', 'take_item(', 'reveal_next(', 'settle_battle(', 'start_battle(', 'choose_route(']:
            self.assertNotIn(forbidden, probe)
        self.assertIn('"extraction": _probe_extraction()', probe)
        self.assertIn('"bag_count"', probe)
        self.assertIn('updater.probe_android_bridge()', probe)
        self.assertNotIn('download_update(', probe)
        self.assertNotIn('install_download(', probe)
        self.assertIn('str(node.name).begins_with("Extraction")', probe)

    def test_emulator_export_cannot_mutate_source_presets(self):
        script = (ROOT / 'tools/android/export_smoke.sh').read_text()
        self.assertIn("presets = target / 'export_presets.cfg'", script)
        self.assertIn("shutil.copytree(source, target", script)
        presets = (ROOT / 'export_presets.cfg').read_text()
        self.assertEqual(presets.count('architectures/x86_64=false'), 2)
        self.assertNotIn('android_runtime_probe', (ROOT / 'main.tscn').read_text())


class AndroidUpdateNetworkPolicyTests(unittest.TestCase):
    def test_actual_request_policy_must_allow_metered_but_not_roaming(self):
        policy={'metered_permitted':True,'roaming_permitted':False}
        self.assertEqual(smoke.validate_android_bridge({'success':True,'package':smoke.PACKAGE,'network_policy':policy}),policy)

    def test_wifi_only_or_missing_policy_is_not_a_native_pass(self):
        for policy in [{},{'metered_permitted':False,'roaming_permitted':False},{'metered_permitted':True,'roaming_permitted':True}]:
            with self.subTest(policy=policy),self.assertRaises(AssertionError):
                smoke.validate_android_bridge({'success':True,'package':smoke.PACKAGE,'network_policy':policy})

    def test_policy_cannot_hide_failed_native_bridge(self):
        with self.assertRaises(AssertionError):
            smoke.validate_android_bridge({'success':False,'package':smoke.PACKAGE,'network_policy':{'metered_permitted':True,'roaming_permitted':False}})


class WarehouseNativeFlowTests(unittest.TestCase):
    def states(self, bad_drag=False):
        import copy
        def state(count=2, multi=False, selected=(), placement=False, x=1, y=0):
            items=[{'uid':'bandage-uid','item_id':'bandage','x':0,'y':0,'rotated':False,'icon_loaded':True,'rect':[10,40,40,40],'clip':[0,0,500,300]},
                   {'uid':'medkit-uid','item_id':'medkit','x':x,'y':y,'rotated':False,'icon_loaded':True,'rect':[10,40,40,40],'clip':[0,0,500,300]}]
            names=['ExtractionShopFilter_consumable','ExtractionBuy_bandage','ExtractionMove_medkit-uid']
            buttons=[{'name':name,'rect':[20,20,40,40]} for name in names]
            buttons += [{'name':'ExtractionInventoryCell_4_0','rect':[200,40,40,40]}, {'name':'ExtractionInventoryCell_6_1','rect':[280,80,40,40]}]
            return {'extraction':{'stash_count':count},'buttons':buttons,'inventory':{'items':items,'multi_select':multi,'selected_uids':list(selected),'selected_uid':'medkit-uid','placement_mode':placement,'placement_uid':'medkit-uid','clip':[0,0,500,300],'rect':[0,0,500,600]}}
        return [state(0),state(0),state(1),state(2),state(),state(multi=True),
                state(multi=True,selected=['bandage-uid']),state(multi=True,selected=['bandage-uid','medkit-uid']),
                state(),state(),state(placement=True),state(placement=not bad_drag,x=4 if bad_drag else 1,y=1 if bad_drag else 0),state(x=4,y=1),
                dict(state(x=4,y=1),inventory=dict(state(x=4,y=1)['inventory'],selected_uid='bandage-uid')),
                dict(state(x=4,y=1),inventory=dict(state(x=4,y=1)['inventory'],selected_uid='bandage-uid')),state(x=4,y=1)]

    def run_flow(self, bad_drag=False):
        import tempfile
        frames=self.states(bad_drag)
        for frame in frames[-2:]:frame['inventory']['rect'][1]=-20
        states=iter(frames)
        actions=[]
        def wait(predicate, description, *args, **kwargs):
            current=next(states)
            if not predicate(current):raise AssertionError(description)
            return current
        def tap(state,name,*args,**kwargs):actions.append(name)
        with tempfile.TemporaryDirectory() as folder, patch.object(smoke,'wait_for',side_effect=wait), patch.object(smoke,'tap',side_effect=tap), patch.object(smoke,'tap_page',side_effect=tap), patch.object(smoke,'adb') as adb, patch.object(smoke,'screenshot'):
            result=smoke.warehouse_input_flow({'extraction':{'stash_count':0}},Path(folder))
            self.assertEqual(smoke.inventory_positions(result)['medkit-uid'],('medkit',4,1,False))
            self.assertTrue((Path(folder)/'warehouse-selection.json').exists())
            self.assertTrue((Path(folder)/'warehouse-drag-preserved.json').exists())
            self.assertTrue((Path(folder)/'warehouse-move.json').exists())
            self.assertEqual(actions.count('ExtractionInventoryItem_bandage-uid'),2)
            self.assertEqual(actions.count('ExtractionInventoryItem_medkit-uid'),3)
            self.assertEqual(actions.count('ExtractionInventoryCell_4_1'),1)
            self.assertTrue(any(c.args[:3]==('shell','input','swipe') for c in adb.call_args_list))

    def test_real_purchase_select_cancel_drag_and_target_tap_sequence(self):
        self.run_flow()

    def test_drag_cannot_pass_if_it_commits_placement(self):
        with self.assertRaisesRegex(AssertionError,'finger drag must not commit'):
            self.run_flow(True)

    def test_unrelated_selection_uid_cannot_pass_exact_two_item_check(self):
        frames=self.states()
        frames[7]['inventory']['selected_uids']=['bandage-uid','unrelated-uid']
        with patch.object(self,'states',return_value=frames), self.assertRaisesRegex(AssertionError,'exact touch selection medkit-uid'):
            self.run_flow()


class ServiceGuardDriverTests(unittest.TestCase):
    def test_map_entry_accepts_guard_battle_only_after_real_arrival(self):
        initial={'seq':10,'extraction':{'room_id':'entry','phase':'route'},'canvases':{'map':{'selected_room':'w'}},'buttons':[{'name':'ExtractionMapNode_w','adjacent':True}]}
        entered={'seq':11,'extraction':{'room_id':'w','phase':'battle'}}
        with patch.object(smoke,'canvas_target',return_value=initial),patch.object(smoke,'tap') as tap,patch.object(smoke,'wait_for',return_value=entered) as wait:
            self.assertEqual(smoke.enter_map_room(initial,'w'),entered)
            tap.assert_called_once_with(initial,'ExtractionMapNode_w')
            predicate=wait.call_args.args[0]
            self.assertTrue(predicate(entered))
            self.assertFalse(predicate(dict(entered,seq=10)))
            self.assertFalse(predicate({'seq':11,'extraction':{'room_id':'entry','phase':'battle'}}))
            self.assertFalse(predicate({'seq':11,'extraction':{'room_id':'w','phase':'route'}}))

    def test_carry_uses_exact_previously_selected_purchased_uid(self):
        state={'inventory':{'selected_uid':'medicine','items':[{'uid':'medicine','item_id':'medkit'}]}}
        carried={'extraction':{'loadout_ids':['medicine']},'inventory':{'items':[]}}
        with patch.object(smoke,'tap_page') as tap,patch.object(smoke,'wait_for',return_value=carried) as wait:
            self.assertEqual(smoke.carry_purchased_supply(state),(carried,'medicine'))
            tap.assert_called_once_with(state,'ExtractionBring_medicine')
            self.assertTrue(wait.call_args.args[0](carried))
            self.assertFalse(wait.call_args.args[0]({'extraction':{'loadout_ids':['other']},'inventory':{'items':[]}}))

    def test_supply_lock_real_three_taps_and_reopen_preserve_uid(self):
        import copy,tempfile
        state={'seq':1,'overlay':0,'buttons':[],'extraction':{'bag_ids':['medicine'],'supplies':[{'uid':'medicine','item_id':'medkit','exchange_locked':False}]}}
        events=[]
        def tap(q,name,*args,**kwargs):
            events.append(name);state['seq']+=1
            if name=='ExtractionQuickSupplies':state['overlay']=2;state['buttons']=[{'name':'ExtractionSupplyLock_medicine'}]
            elif name=='ExtractionSupplyLock_medicine':state['extraction']['supplies'][0]['exchange_locked']=not state['extraction']['supplies'][0]['exchange_locked']
            elif name=='ExtractionSupplyClose':state['overlay']=0;state['buttons']=[]
        def wait(predicate,label,**kwargs):
            self.assertTrue(predicate(state),label)
            return copy.deepcopy(state)
        with tempfile.TemporaryDirectory() as folder,patch.object(smoke,'tap_page',side_effect=tap),patch.object(smoke,'tap_overlay',side_effect=tap),patch.object(smoke,'wait_for',side_effect=wait),patch.object(smoke,'screenshot'):
            final=smoke.supply_lock_input_flow(copy.deepcopy(state),'medicine',Path(folder))
            self.assertTrue((Path(folder)/'supply-lock-persistence.json').exists())
        self.assertEqual(events,['ExtractionQuickSupplies']+['ExtractionSupplyLock_medicine']*3+['ExtractionSupplyClose','ExtractionQuickSupplies','ExtractionSupplyClose'])
        self.assertEqual(final['extraction']['bag_ids'],['medicine'])
        self.assertTrue(final['extraction']['supplies'][0]['exchange_locked'])

    def test_safe_room_does_not_start_battle(self):
        state={'extraction':{'phase':'room'}}
        with patch.object(smoke,'tap_page') as tap:
            self.assertIs(smoke.resolve_service_guard(state,None),state)
            tap.assert_not_called()

    def test_nonservice_battle_is_not_bypassed(self):
        with self.assertRaisesRegex(AssertionError,'non-service'):
            smoke.resolve_service_guard({'extraction':{'phase':'battle','guard_pending':False}},None)

    def test_guard_routes_through_real_battle_and_growth_controls(self):
        start={'buttons':[],'extraction':{'phase':'battle','guard_pending':True,'room_id':'w','room_type':'workshop'}}
        fight={'screen':'battle','battle_state':{'auto':False}}
        won={'battle_state':{'phase':'victory'},'buttons':[{'name':'ExtractionBattleContinue'}]}
        service={'screen':'extraction','extraction':{'phase':'room','room_id':'w','room_type':'workshop','guard_pending':False,'growth_choices':['blessing']}}
        done={'screen':'extraction','extraction':dict(service['extraction'],growth_choices=[])}
        frames=iter([fight,won,service,done])
        events=[]
        def wait(predicate,label,**kwargs):
            q=next(frames)
            self.assertTrue(predicate(q),label)
            return q
        def tap(q,name,*args,**kwargs):events.append(name)
        with patch.object(smoke,'wait_for',side_effect=wait),patch.object(smoke,'tap_page',side_effect=tap),patch.object(smoke,'tap',side_effect=tap),patch.object(smoke,'tap_overlay',side_effect=tap),patch.object(smoke,'screenshot'):
            self.assertEqual(smoke.resolve_service_guard(start,None),done)
        self.assertEqual(events,['ExtractionBattle','BattleAutoToggle','ExtractionBattleContinue','ExtractionGrowth_blessing'])

    def test_workshop_real_input_order_includes_local_scroll_and_cancel(self):
        import copy
        names=['ExtractionSort_bag','ExtractionQuickSupplies','ExtractionBuild','ExtractionAbandon','ExtractionRoomAction_study']
        buttons=[{'name':name,'rect':[10+i*55,400,50,44],'clip':[0,0,960,540]} for i,name in enumerate(names)]
        buttons[-1]['rect']=[20,620,100,44]
        state={'seq':1,'window':[960,540],'logical':[960,540],'buttons':buttons,'overlay':0,'extraction':{'room_type':'workshop','room_id':'w','run_digest':'stable-run','bag_ids':['gold'],'room_actions':[{'used':False} for _ in range(3)]},'page_scrolls':[{'name':'ExtractionServiceScroll','rect':[10,180,300,170],'value':0}]}
        events=[]
        def tap(q,name,*args,**kwargs):
            events.append(name);state['seq']+=1
            if name=='ExtractionBuild':state['buttons']=[{'name':'ExtractionTab_expedition'}]
            elif name=='ExtractionTab_expedition':state['buttons']=copy.deepcopy(buttons)
            elif name=='ExtractionAbandon':state['overlay']=2;state['buttons']=[{'name':'ExtractionAbandonCancel'}]
            elif name=='ExtractionAbandonCancel':state['overlay']=0;state['buttons']=copy.deepcopy(buttons)
            elif name=='ExtractionRoomAction_study':state['extraction']['growth_choices']=['g']
            elif name=='ExtractionGrowth_g':
                state['extraction']['growth_choices']=[]
                for action in state['extraction']['room_actions']:action['used']=True
        def adb(*args):
            self.assertEqual(args[:3],('shell','input','swipe'));events.append('finger-scroll')
            state['seq']+=1;state['page_scrolls'][0]['value']=430
            state['buttons'][-1]['rect']=[20,190,100,44]
        def wait(predicate,label,**kwargs):
            self.assertTrue(predicate(state),label)
            return copy.deepcopy(state)
        with patch.object(smoke,'tap',side_effect=tap),patch.object(smoke,'tap_page',side_effect=tap),patch.object(smoke,'tap_overlay',side_effect=tap),patch.object(smoke,'adb',side_effect=adb),patch.object(smoke,'wait_for',side_effect=wait),patch.object(smoke,'screenshot'):
            final=smoke.workshop_input_flow(copy.deepcopy(state),None)
        self.assertEqual(events,['ExtractionBuild','ExtractionTab_expedition','ExtractionAbandon','ExtractionAbandonCancel','finger-scroll','ExtractionRoomAction_study','ExtractionGrowth_g'])
        self.assertEqual(final['extraction']['bag_ids'],['gold'])

    def test_guard_defeat_cannot_restore_service_by_driver(self):
        start={'buttons':[],'extraction':{'phase':'battle','guard_pending':True,'room_id':'w','room_type':'workshop'}}
        with patch.object(smoke,'wait_for',side_effect=[{'battle_state':{'auto':True}},{'battle_state':{'phase':'defeat'}}]),patch.object(smoke,'tap_page'),patch.object(smoke,'tap_overlay') as continuation,patch.object(smoke,'screenshot'),self.assertRaisesRegex(AssertionError,'lost the actual'):
            smoke.resolve_service_guard(start,None)
        continuation.assert_not_called()


if __name__ == '__main__':
    unittest.main(verbosity=2)
