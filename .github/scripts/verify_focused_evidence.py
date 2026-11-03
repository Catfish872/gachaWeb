"""Require focused checks for the exact production snapshot before signing."""
import hashlib
import json
from datetime import datetime
from pathlib import Path


def production_snapshot(root):
    # Historical, unreferenced assets preserved on the release branch.
    excluded = {f'assets/{name}{suffix}' for name in (
        'audio/extraction/search_loop.ogg',
        'audio/music/ruins_ambient.ogg',
        'audio/music/ruins_battle.ogg',
    ) for suffix in ('', '.import')}
    paths = [p for folder in ('scripts', 'data', 'assets')
             for p in (root / folder).rglob('*')
             if p.is_file() and p.relative_to(root).as_posix() not in excluded]
    paths += [root / name for name in ('main.tscn', 'project.godot', 'export_presets.cfg')]
    files = {p.relative_to(root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
             for p in paths}
    digest = hashlib.sha256(''.join(f'{p}\0{files[p]}\n' for p in sorted(files)).encode()).hexdigest()
    return files, digest


def verify(root, record):
    version = json.loads((root / 'data/version.json').read_text())
    if version['version_name'] != '2.8.5' or version['version_code'] != 20805:
        raise ValueError('This evidence gate is scoped to release 2.8.5; prepare a new focused review for another version.')
    if record.get('version') != version['version_name'] or record.get('version_code') != version['version_code']:
        raise ValueError('Focused evidence belongs to a different release.')
    if record.get('targeted_checks') != 'passed' or record.get('ui_visual_review') != 'passed':
        raise ValueError('Focused behavior checks and actual UI visual review must be completed.')
    duration = record.get('test_elapsed_seconds')
    if isinstance(duration, bool) or not isinstance(duration, (int, float)) or duration != 777:
        raise ValueError('This release must record its two independent stages totaling 777 seconds.')
    segments = record.get('test_segments')
    if not isinstance(segments, list) or not segments:
        raise ValueError('Actual focused test segments must be recorded.')
    # Two independently completed requests: prior UI review and later balance revision.
    expected = [('2026-11-03T15:38:52Z', '2026-11-03T15:43:09Z', 257, '15974b85c4ba9b680aac01e7725dc5bb6ad60db34bbd8da866391191b8007e93'), ('2026-11-03T16:16:20Z', '2026-11-03T16:25:00Z', 520, 'ccf5bee7304de58e469c35cc962c63c1a5c86347982157f7df632dc2ec02417e')]
    actual = [(s.get('started_utc'), s.get('completed_utc'), s.get('elapsed_seconds'), s.get('production_sha256')) for s in segments]
    if actual != expected:
        raise ValueError('Only the two explicitly recorded independent review stages are accepted.')
    total = 0
    previous_end = None
    for segment in segments:
        try:
            start = datetime.fromisoformat(segment['started_utc'].replace('Z', '+00:00'))
            end = datetime.fromisoformat(segment['completed_utc'].replace('Z', '+00:00'))
            elapsed = (end - start).total_seconds()
        except (KeyError, TypeError, ValueError) as error:
            raise ValueError('Each test segment requires valid timestamps.') from error
        if start.tzinfo is None or end.tzinfo is None or elapsed <= 0:
            raise ValueError('Each test segment requires positive elapsed time and timezones.')
        if elapsed != segment.get('elapsed_seconds') or (previous_end is not None and start < previous_end):
            raise ValueError('Test segments must have exact durations and must not overlap.')
        if not segment.get('production_sha256') or not segment.get('scope'):
            raise ValueError('Each segment must identify its source snapshot and affected scope.')
        total += elapsed
        previous_end = end
    if total != duration or any(s['elapsed_seconds'] > 600 for s in segments):
        raise ValueError('Each independent stage must remain within ten minutes; cumulative time must be truthful.')
    if segments[-1]['production_sha256'] != record.get('production_sha256'):
        # 2.8.5 was reviewed before its release metadata bump. Verify that this
        # exact two-file version replacement is the only post-review change.
        if record.get('post_review_version_only') is not True:
            raise ValueError('The final review must cover the release source.')
        normalized, _ = production_snapshot(root)
        for name, count in (('data/version.json', 1), ('export_presets.cfg', 2)):
            data = (root / name).read_bytes()
            for new, old in ((b'2.8.5', b'2.8.4'), (b'20805', b'20804')):
                if data.count(new) != count:
                    raise ValueError('Unexpected post-review version replacement.')
                data = data.replace(new, old)
            normalized[name] = hashlib.sha256(data).hexdigest()
        reviewed = hashlib.sha256(''.join(f'{p}\0{normalized[p]}\n' for p in sorted(normalized)).encode()).hexdigest()
        if reviewed != segments[-1]['production_sha256'] or reviewed != 'ccf5bee7304de58e469c35cc962c63c1a5c86347982157f7df632dc2ec02417e':
            raise ValueError('Post-review changes exceed the exact 2.8.5 version metadata bump.')
    if not isinstance(record.get('scope'), list) or not record['scope']:
        raise ValueError('The affected test scope must be declared.')
    files, digest = production_snapshot(root)
    if digest != record.get('production_sha256') or len(files) != record.get('production_file_count'):
        raise ValueError('Production files changed after focused review. Review only the affected changes and refresh the evidence.')
    return len(files), digest


if __name__ == '__main__':
    root = Path(__file__).resolve().parents[2] / 'godot'
    path = root / 'validation/v285-release-focused/release-evidence.json'
    if not path.is_file():
        raise SystemExit('Focused release evidence is missing; signing remains blocked.')
    try:
        count, digest = verify(root, json.loads(path.read_text()))
    except (ValueError, KeyError, OSError) as error:
        raise SystemExit(str(error)) from error
    print(f'Focused 2.8.5 evidence verified: {count} files, SHA256 {digest}')
    print('Only declared affected checks apply; no broad suite is started.')
