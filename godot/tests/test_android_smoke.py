#!/usr/bin/env python3
"""Offline regression checks for the Android runtime driver (not emulator tests)."""
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('android_smoke', ROOT / 'tools/android/smoke_test.py')
smoke = importlib.util.module_from_spec(spec)
spec.loader.exec_module(smoke)


class AndroidSmokeDriverTests(unittest.TestCase):
    def test_reads_only_complete_probe_records(self):
        log = 'I godot: ANDROID_SMOKE {"screen":"home"}\nI godot: ANDROID_SMOKE {truncated\n'
        self.assertEqual(smoke.snapshots(log), [{'screen': 'home'}])

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
            return '\n'.join('ANDROID_SMOKE ' + json.dumps({'seq': seq, 'screen': 'home'}) for seq in seqs)
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

    def test_emulator_export_cannot_mutate_source_presets(self):
        script = (ROOT / 'tools/android/export_smoke.sh').read_text()
        self.assertIn("presets = target / 'export_presets.cfg'", script)
        self.assertIn("shutil.copytree(source, target", script)
        presets = (ROOT / 'export_presets.cfg').read_text()
        self.assertEqual(presets.count('architectures/x86_64=false'), 2)
        self.assertNotIn('android_runtime_probe', (ROOT / 'main.tscn').read_text())


if __name__ == '__main__':
    unittest.main(verbosity=2)
