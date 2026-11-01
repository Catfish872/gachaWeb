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
        (self.root / 'data/version.json').write_text(json.dumps({'version_name': '2.6.2', 'version_code': 20602}))
        for name in ('main.tscn', 'project.godot', 'export_presets.cfg'):
            (self.root / name).write_text(name)
        files, digest = production_snapshot(self.root)
        self.record = {'version': '2.6.2', 'version_code': 20602,
                       'targeted_checks': 'passed', 'ui_visual_review': 'passed',
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

    def test_changed_source_stops(self):
        (self.root / 'main.tscn').write_text('changed')
        with self.assertRaises(ValueError):
            verify(self.root, self.record)

    def test_added_asset_stops(self):
        (self.root / 'assets/new.png').write_bytes(b'new')
        with self.assertRaises(ValueError):
            verify(self.root, self.record)

    def test_other_version_stops(self):
        (self.root / 'data/version.json').write_text(json.dumps({'version_name': '2.7.0', 'version_code': 20700}))
        with self.assertRaises(ValueError):
            verify(self.root, self.record)

    def test_incomplete_visual_review_stops(self):
        self.record['ui_visual_review'] = 'pending'
        with self.assertRaises(ValueError):
            verify(self.root, self.record)

    def test_over_budget_stops(self):
        self.record['test_elapsed_seconds'] = 601
        with self.assertRaises(ValueError):
            verify(self.root, self.record)


if __name__ == '__main__':
    unittest.main()
