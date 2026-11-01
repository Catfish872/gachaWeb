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
    if version['version_name'] != '2.6.5' or version['version_code'] != 20605:
        raise ValueError('This evidence gate is scoped to release 2.6.5; prepare a new focused review for another version.')
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
        raise ValueError('The last review segment must cover the final production snapshot.')
    if not isinstance(record.get('scope'), list) or not record['scope']:
        raise ValueError('The affected test scope must be declared.')
    files, digest = production_snapshot(root)
    if digest != record.get('production_sha256') or len(files) != record.get('production_file_count'):
        raise ValueError('Production files changed after focused review. Review only the affected changes and refresh the evidence.')
    return len(files), digest


def verify_v266_constant_only(root, record):
    # Narrow 2.6.6 release exception: no gameplay test result is asserted.
    if record.get('version') != '2.6.6' or record.get('version_code') != 20606:
        raise ValueError('Constant-only review is restricted to 2.6.6 / 20606.')
    if record.get('targeted_checks') != 'not_run_requested' or record.get('test_elapsed_seconds') != 0:
        raise ValueError('This release must accurately report that gameplay tests were not run.')
    if record.get('review_mode') != 'exact_v265_to_v266_constant_diff':
        raise ValueError('The exact constant-only review is required.')
    files, digest = production_snapshot(root)
    if len(files) != 828 or digest != record.get('production_sha256'):
        raise ValueError('Current production snapshot differs from the reviewed constant change.')
    normalized = dict(files)
    replacements = {
        'scripts/abyss_balance.gd': [('maxf(0.0, floor_value - 25.0)', 'maxf(0.0, floor_value - 50.0)', 1)],
        'scripts/game_model.gd': [('25层后指数成长', '50层后指数成长', 1)],
        'data/version.json': [('2.6.6', '2.6.5', 1), ('20606', '20605', 1)],
        'export_presets.cfg': [('2.6.6', '2.6.5', 2), ('20606', '20605', 2)],
    }
    for path, edits in replacements.items():
        data = (root / path).read_bytes()
        for new, old, count in edits:
            if data.count(new.encode()) != count:
                raise ValueError('Unexpected constant or version edit: ' + path)
            data = data.replace(new.encode(), old.encode())
        normalized[path] = hashlib.sha256(data).hexdigest()
    previous_digest = hashlib.sha256(''.join(f'{p}\0{normalized[p]}\n' for p in sorted(normalized)).encode()).hexdigest()
    if previous_digest != '19dfd698a86b98c334231d8ce05cb7949ce1cbbdb6994efb8afc8da201bc5575':
        raise ValueError('Changes exceed the exact verified 2.6.5 baseline plus exponent/version replacements.')
    return len(files), digest


if __name__ == '__main__':
    root = Path(__file__).resolve().parents[2] / 'godot'
    path = root / 'validation/v266-focused/release-evidence.json'
    if not path.is_file():
        raise SystemExit('Constant-only release record is missing; signing remains blocked.')
    try:
        count, digest = verify_v266_constant_only(root, json.loads(path.read_text()))
    except (ValueError, KeyError, OSError) as error:
        raise SystemExit(str(error)) from error
    print(f'Exact 2.6.6 constant-only source diff verified: {count} files, SHA256 {digest}')
    print('Gameplay tests: NOT RUN as requested. Prior 2.6.5 results are background only, not current test results.')
