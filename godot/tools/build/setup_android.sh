#!/usr/bin/env bash
set -euo pipefail
: "${JAVA_HOME:?JDK 17 must be configured before this step}"
"$JAVA_HOME/bin/java" -version 2>&1 | grep -Eq 'version "17[.]' || { echo 'JDK 17 is required' >&2; exit 1; }
SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
: "${SDK:?Android SDK must be provided by the runner}"
MANAGER="$SDK/cmdline-tools/latest/bin/sdkmanager"
[[ -x "$MANAGER" ]] || { echo 'Android sdkmanager is missing' >&2; exit 1; }
# GitHub hosted runners provide accepted SDK licenses. Never accept new agreements here.
[[ -d "$SDK/licenses" ]] || { echo 'Owner must install and accept Android SDK licenses first' >&2; exit 1; }
"$MANAGER" --sdk_root="$SDK" 'platform-tools' 'build-tools;35.0.1' 'platforms;android-36' < /dev/null
for tool in aapt apksigner zipalign; do
  [[ -x "$SDK/build-tools/35.0.1/$tool" ]] || { echo "Missing Android tool: $tool" >&2; exit 1; }
done
# Godot prefers build-tools matching target SDK, even when another version was
# installed explicitly. Expose only our pinned build-tools in a fresh SDK view.
SOURCE_SDK="$SDK"
SDK=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/voidrift-android-sdk.XXXXXX")
mkdir -p "$SDK/build-tools"
ln -s "$SOURCE_SDK/build-tools/35.0.1" "$SDK/build-tools/35.0.1"
for directory in platform-tools platforms cmdline-tools licenses; do
  ln -s "$SOURCE_SDK/$directory" "$SDK/$directory"
done
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/godot"
mkdir -p "$CONFIG"
python3 - "$CONFIG/editor_settings-4.6.tres" "$SDK" "$JAVA_HOME" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
# CI configuration is isolated through XDG_CONFIG_HOME in the workflow.
path.write_text('[gd_resource type="EditorSettings" format=3]\n\n[resource]\n' +
    'export/android/android_sdk_path = ' + json.dumps(sys.argv[2]) + '\n' +
    'export/android/java_sdk_path = ' + json.dumps(sys.argv[3]) + '\n')
PY
if [[ -n "${GITHUB_ENV:-}" ]]; then printf 'ANDROID_HOME=%s\nANDROID_SDK_ROOT=%s\n' "$SDK" "$SDK" >> "$GITHUB_ENV"; fi
