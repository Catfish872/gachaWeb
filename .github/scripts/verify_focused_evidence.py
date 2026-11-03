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
    if version['version_name'] != '2.8.1' or version['version_code'] != 20801:
        raise ValueError('This evidence gate is scoped to release 2.8.1; prepare a new focused review for another version.')
    if record.get('version') != version['version_name'] or record.get('version_code') != version['version_code']:
        raise ValueError('Focused evidence belongs to a different release.')
    if record.get('targeted_checks') != 'passed' or record.get('ui_visual_review') != 'passed':
        raise ValueError('Focused behavior checks and actual UI visual review must be completed.')
    duration = record.get('test_elapsed_seconds')
    if isinstance(duration, bool) or not isinstance(duration, (int, float)) or not 0 < duration <= 600:
        raise ValueError('Focused review must record its duration within the ten-minute test budget.')
    segments = record.get('test_segments')
    if not isinstance(segments, list) or not segments:
        raise ValueError('Actual focused test segments must be recorded.')
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
    if total != duration or total > 600:
        raise ValueError('Total focused duration must equal the sum of actual segments within ten minutes.')
    if segments[-1]['production_sha256'] != record.get('production_sha256'):
        # 2.8.1 was reviewed before its release metadata bump. Verify that this
        # exact two-file version replacement is the only post-review change.
        if record.get('post_review_version_only') is not True:
            raise ValueError('The final review must cover the release source.')
        normalized, _ = production_snapshot(root)
        for name, count in (('data/version.json', 1), ('export_presets.cfg', 2)):
            data = (root / name).read_bytes()
            for new, old in ((b'2.8.1', b'2.8.0'), (b'20801', b'20800')):
                if data.count(new) != count:
                    raise ValueError('Unexpected post-review version replacement.')
                data = data.replace(new, old)
            normalized[name] = hashlib.sha256(data).hexdigest()
        reviewed = hashlib.sha256(''.join(f'{p}\0{normalized[p]}\n' for p in sorted(normalized)).encode()).hexdigest()
        if reviewed != segments[-1]['production_sha256'] or reviewed != 'd13991c33ac006bca96ecbdacae0fc9ecd727233ee403016b52b18e3befcd2c4':
            raise ValueError('Post-review changes exceed the exact 2.8.1 version metadata bump.')
    if not isinstance(record.get('scope'), list) or not record['scope']:
        raise ValueError('The affected test scope must be declared.')
    files, digest = production_snapshot(root)
    if digest != record.get('production_sha256') or len(files) != record.get('production_file_count'):
        raise ValueError('Production files changed after focused review. Review only the affected changes and refresh the evidence.')
    return len(files), digest


if __name__ == '__main__':
    root = Path(__file__).resolve().parents[2] / 'godot'
    path = root / 'validation/v281-focused/release-evidence.json'
    if not path.is_file():
        raise SystemExit('Focused release evidence is missing; signing remains blocked.')
    try:
        count, digest = verify(root, json.loads(path.read_text()))
    except (ValueError, KeyError, OSError) as error:
        raise SystemExit(str(error)) from error
    print(f'Focused 2.8.1 evidence verified: {count} files, SHA256 {digest}')
    print('Only declared affected checks apply; no broad suite is started.')
