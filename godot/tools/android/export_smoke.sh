#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
OUTPUT="${1:?Output directory required}"
mkdir -p "$OUTPUT"
OUTPUT=$(cd "$OUTPUT" && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
# All mutations are confined to an ephemeral copy; delivery presets stay ARM-only.
python3 - "$ROOT" "$WORK/project" <<'PY'
import pathlib, shutil, sys
source, target = map(pathlib.Path, sys.argv[1:])
shutil.copytree(source, target, ignore=shutil.ignore_patterns('.godot', '__pycache__', 'validation', 'build'))
shutil.copy(source / 'tools/android/runtime_probe.gd', target / 'scripts/android_runtime_probe.gd')
scene = target / 'main.tscn'
scene.write_text(scene.read_text().replace('res://scripts/main.gd', 'res://scripts/android_runtime_probe.gd'))
presets = target / 'export_presets.cfg'
text = presets.read_text().replace('architectures/armeabi-v7a=true', 'architectures/armeabi-v7a=false').replace('architectures/arm64-v8a=true', 'architectures/arm64-v8a=false').replace('architectures/x86_64=false', 'architectures/x86_64=true')
text = text.replace('command_line/extra_args=""', 'command_line/extra_args="-- --test-session"')
presets.write_text(text)
PY
export GODOT_ANDROID_KEYSTORE_DEBUG_PATH="$WORK/debug.keystore"
export GODOT_ANDROID_KEYSTORE_DEBUG_USER=androiddebugkey
export GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD=android
"$JAVA_HOME/bin/keytool" -genkeypair -noprompt -keystore "$WORK/debug.keystore" -storepass android -keypass android -alias androiddebugkey -dname 'CN=Android Debug,O=Android,C=US' -keyalg RSA -validity 30 >/dev/null 2>&1
ENGINE="${GODOT_BIN:-godot}"
"$ENGINE" --headless --editor --path "$WORK/project" --import --quit > "$OUTPUT/import.log" 2>&1 || { cat "$OUTPUT/import.log"; exit 1; }
"$ENGINE" --headless --path "$WORK/project" --export-debug 'Android Debug' "$OUTPUT/smoke.apk" > "$OUTPUT/export.log" 2>&1 || { cat "$OUTPUT/export.log"; exit 1; }
if grep -E 'SCRIPT ERROR|^ERROR:' "$OUTPUT/import.log" "$OUTPUT/export.log"; then exit 1; fi
python3 - "$OUTPUT/smoke.apk" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as apk:
    architectures = {n.split('/')[1] for n in apk.namelist() if n.startswith('lib/') and n.endswith('.so')}
    assert architectures == {'x86_64'}, architectures
PY
