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
    if version['version_name'] != '2.9.1' or version['version_code'] != 20901:
        raise ValueError('This evidence gate is scoped to release 2.9.1; prepare a new focused review for another version.')
    if record.get('version') != version['version_name'] or record.get('version_code') != version['version_code']:
        raise ValueError('Focused evidence belongs to a different release.')
    if record.get('targeted_checks') != 'passed' or record.get('ui_visual_review') != 'passed':
        raise ValueError('Focused behavior checks and actual UI visual review must be completed.')
    if record.get('music_selection_review') != 'passed':
        raise ValueError('User audition and approval of selected music must be recorded.')
    if record.get('audio_runtime_checks') != 'passed':
        raise ValueError('Selected music decoding, routing and loop-signal checks must pass.')
    duration = record.get('test_elapsed_seconds')
    if isinstance(duration, bool) or not isinstance(duration, (int, float)) or not 0 < duration <= 600:
        raise ValueError('Focused review must remain within ten minutes.')
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
        if not isinstance(segment.get('scope'), list) or not all(isinstance(item, str) and item.strip() for item in segment['scope']):
            raise ValueError('Segment scope must contain named affected checks.')
        if not (segment.get('production_sha256') or segment.get('source_reference')) or not segment.get('scope'):
            raise ValueError('Each segment must identify its source snapshot and affected scope.')
        total += elapsed
        previous_end = end
    if total != duration or total > 600:
        raise ValueError('Each independent stage must remain within ten minutes; cumulative time must be truthful.')
    if segments[-1].get('production_sha256') != record.get('production_sha256'):
        raise ValueError('The final review must cover the exact release source, including version metadata.')
    if not isinstance(record.get('scope'), list) or not record['scope'] or not all(isinstance(item, str) and item.strip() for item in record['scope']):
        raise ValueError('The affected test scope must be declared.')
    files, digest = production_snapshot(root)
    if digest != record.get('production_sha256') or len(files) != record.get('production_file_count'):
        raise ValueError('Production files changed after focused review. Review only the affected changes and refresh the evidence.')
    return len(files), digest


if __name__ == '__main__':
    root = Path(__file__).resolve().parents[2] / 'godot'
    path = root / 'validation/v291-release-focused/release-evidence.json'
    if not path.is_file():
        raise SystemExit('Focused release evidence is missing; signing remains blocked.')
    try:
        count, digest = verify(root, json.loads(path.read_text()))
    except (ValueError, KeyError, OSError) as error:
        raise SystemExit(str(error)) from error
    print(f'Focused 2.9.1 evidence verified: {count} files, SHA256 {digest}')
    print('Only declared affected checks apply; no broad suite is started.')
