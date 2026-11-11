import json
import tempfile
import unittest
from pathlib import Path

from verify_focused_evidence import production_snapshot, verify


class FocusedEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for folder in ('data', 'scripts', 'assets'):
            (self.root / folder).mkdir()
        (self.root / 'data/version.json').write_text(json.dumps({'version_name': '3.0.0', 'version_code': 30000}))
        for name in ('main.tscn', 'content_bootstrap.tscn', 'project.godot', 'export_presets.cfg'):
            (self.root / name).write_text(name)
        files, digest = production_snapshot(self.root)
        self.record = {'version': '3.0.0', 'version_code': 30000,
                       'targeted_checks': 'passed', 'ui_visual_review': 'passed',
                       'loot_diversity_review': 'passed', 'loot_resource_checks': 'passed',
                       'content_update_checks': 'passed',
                       'test_elapsed_seconds': 120, 'scope': ['changed room UI'],
                       'production_sha256': digest, 'production_file_count': len(files),
                       'test_segments': [{'started_utc': '2026-11-01T16:00:00Z',
                                          'completed_utc': '2026-11-01T16:02:00Z',
                                          'elapsed_seconds': 120, 'production_sha256': digest,
                                          'scope': ['changed room UI']}]} 

    def test_exact_reviewed_snapshot(self):
        self.assertEqual(verify(self.root, self.record)[1], self.record['production_sha256'])

    def test_segment_duration_mismatch_stops(self):
        self.record['test_segments'][0]['elapsed_seconds'] = 100
        with self.assertRaises(ValueError):
            verify(self.root, self.record)

    def test_segment_overlap_stops(self):
        self.record['test_segments'] *= 2
        self.record['test_elapsed_seconds'] = 240
        with self.assertRaises(ValueError):
            verify(self.root, self.record)

    def test_development_gap_is_not_test_time(self):
        segment = dict(self.record['test_segments'][0])
        segment.update(started_utc='2026-11-01T16:10:00Z', completed_utc='2026-11-01T16:12:00Z')
        self.record['test_segments'].append(segment)
        self.record['test_elapsed_seconds'] = 240
        self.assertEqual(verify(self.root, self.record)[1], self.record['production_sha256'])

    def test_historical_reference_requires_final_exact_hash(self):
        historical = dict(self.record['test_segments'][0])
        historical.pop('production_sha256')
        historical['source_reference'] = 'Development checks; whole-source hash was not recorded.'
        self.record['test_segments'] = [historical]
        with self.assertRaises((ValueError, KeyError)):
            verify(self.root, self.record)

    def test_changed_source_stops(self):
        (self.root / 'main.tscn').write_text('changed')
        with self.assertRaises(ValueError):
            verify(self.root, self.record)

    def test_changed_bootstrap_stops(self):
        (self.root / 'content_bootstrap.tscn').write_text('changed')
        with self.assertRaises(ValueError):
            verify(self.root, self.record)

    def test_pending_content_updates_stops(self):
        self.record['content_update_checks'] = 'pending'
        with self.assertRaises(ValueError):
            verify(self.root, self.record)

    def test_added_asset_stops(self):
        (self.root / 'assets/new.png').write_bytes(b'new')
        with self.assertRaises(ValueError):
            verify(self.root, self.record)

    def test_other_version_stops(self):
        (self.root / 'data/version.json').write_text(json.dumps({'version_name': '2.8.13', 'version_code': 20813}))
        with self.assertRaises(ValueError):
            verify(self.root, self.record)

    def test_incomplete_visual_review_stops(self):
        self.record['ui_visual_review'] = 'pending'
        with self.assertRaises(ValueError):
            verify(self.root, self.record)

    def test_pending_music_selection_stops(self):
        self.record['loot_diversity_review'] = 'pending'
        with self.assertRaises(ValueError):
            verify(self.root, self.record)

    def test_pending_audio_runtime_stops(self):
        self.record['loot_resource_checks'] = 'pending'
        with self.assertRaises(ValueError):
            verify(self.root, self.record)

    def test_subjective_in_game_audio_is_separate(self):
        self.record['in_game_subjective_listening'] = 'not_performed'
        self.assertEqual(verify(self.root, self.record)[1], self.record['production_sha256'])

    def test_old_release_record_stops(self):
        self.record.update(version='2.8.12', version_code=20812)
        with self.assertRaises(ValueError):
            verify(self.root, self.record)

    def test_unnamed_scope_stops(self):
        self.record['scope'] = ['']
        with self.assertRaises(ValueError):
            verify(self.root, self.record)

    def test_invalid_segment_scope_stops(self):
        self.record['test_segments'][0]['scope'] = 'vague'
        with self.assertRaises(ValueError):
            verify(self.root, self.record)

    def test_over_budget_stops(self):
        self.record['test_elapsed_seconds'] = 601
        with self.assertRaises(ValueError):
            verify(self.root, self.record)


if __name__ == '__main__':
    unittest.main()
