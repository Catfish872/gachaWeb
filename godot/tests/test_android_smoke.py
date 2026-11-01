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
        state = {'buttons': [{'name': 'ExtractionSearch', 'rect': [20, 600, 100, 50], 'clip': [0, 100, 500, 400]}], 'scroll': 0, 'scroll_max': 500, 'scroll_rect': [0, 100, 500, 400]}
        shown = {'buttons': [{'name': 'ExtractionSearch', 'rect': [20, 300, 100, 50], 'clip': [0, 100, 500, 400]}], 'scroll': 200, 'scroll_max': 500, 'scroll_rect': [0, 100, 500, 400]}
        with patch.object(smoke, 'adb') as adb, patch.object(smoke, 'wait_for', return_value=shown):
            self.assertEqual(smoke.reveal_page_target(state, 'ExtractionSearch'), shown)
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


if __name__ == '__main__':
    unittest.main(verbosity=2)
