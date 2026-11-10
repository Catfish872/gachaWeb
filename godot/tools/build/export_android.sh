#!/usr/bin/env bash
set -euo pipefail
# Keep signing material out of shell tracing and project/export directories.
set +x
MODE="${1:?Usage: export_android.sh debug|release OUTPUT_DIRECTORY}"
[[ "$MODE" == debug || "$MODE" == release ]] || { echo 'Mode must be debug or release' >&2; exit 1; }
OUTPUT="${2:?Output directory required}"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
: "${SDK:?Android SDK is required}"
: "${JAVA_HOME:?JDK is required}"
ENGINE="${GODOT_BIN:-godot}"
"$ENGINE" --headless --version | grep -q '^4\.6\.3\.stable\.'
python3 "$ROOT/tools/build/validate_version.py"
mkdir -p "$OUTPUT"
OUTPUT=$(cd "$OUTPUT" && pwd)
# Signing files must remain outside all project resources.
case "$OUTPUT/" in "$ROOT/"*) echo 'Output must be outside the Godot project' >&2; exit 1;; esac
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
umask 077
if [[ "$MODE" == release ]]; then
  : "${ANDROID_KEYSTORE_BASE64:?Production signing key must be configured by owner}"
  : "${ANDROID_KEY_ALIAS:?Production signing alias is required}"
  : "${ANDROID_KEY_PASSWORD:?Production signing password is required}"
  : "${ANDROID_SIGNING_CERT_SHA256:?Expected production certificate fingerprint is required}"
  python3 - "$WORK/release.keystore" <<'PY'
import base64, os, pathlib, sys
pathlib.Path(sys.argv[1]).write_bytes(base64.b64decode(os.environ['ANDROID_KEYSTORE_BASE64'], validate=True))
PY
  export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$WORK/release.keystore"
  export GODOT_ANDROID_KEYSTORE_RELEASE_USER="$ANDROID_KEY_ALIAS"
  export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="$ANDROID_KEY_PASSWORD"
  FINGERPRINT="$ANDROID_SIGNING_CERT_SHA256"
  PRESET='Android Release'
  FLAG=--export-release
else
  # This throwaway identity is solely for CI test packages, never for production.
  export GODOT_ANDROID_KEYSTORE_DEBUG_PATH="$WORK/debug.keystore"
  export GODOT_ANDROID_KEYSTORE_DEBUG_USER=androiddebugkey
  export GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD=android
  "$JAVA_HOME/bin/keytool" -genkeypair -noprompt -keystore "$GODOT_ANDROID_KEYSTORE_DEBUG_PATH" \
    -storepass:env GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD -keypass:env GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD \
    -alias androiddebugkey -dname 'CN=Android Debug,O=Android,C=US' -keyalg RSA -keysize 2048 -validity 10000 > "$WORK/keytool.log" 2>&1
  "$JAVA_HOME/bin/keytool" -exportcert -keystore "$GODOT_ANDROID_KEYSTORE_DEBUG_PATH" \
    -storepass:env GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD -alias androiddebugkey -file "$WORK/debug.der" > /dev/null 2>&1
  FINGERPRINT=$(sha256sum "$WORK/debug.der" | cut -d ' ' -f 1)
  PRESET='Android Debug'
  FLAG=--export-debug
fi
# Derived trust/ABI files belong to the reviewed source snapshot. Check them
# without rewriting project bytes after the focused evidence gate.
if [[ "$MODE" == release ]]; then
  "$JAVA_HOME/bin/java" "$ROOT/tools/build/SignContent.java" public "$WORK/content_public_key.pem"
  cmp -- "$WORK/content_public_key.pem" "$ROOT/data/content_public_key.pem" || {
    echo 'Signing public key differs from reviewed source; refresh and review before export' >&2
    exit 1
  }
fi
python3 - "$ROOT" <<'PYVERIFY'
import importlib.util
from pathlib import Path
import sys
root = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("content_release", root / "tools/build/content_release.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
expected = module.canonical(module.platform(root))
if (root / "data/content_platform.json").read_bytes() != expected:
    raise SystemExit("Platform identity differs from reviewed source; refresh and review before export")
PYVERIFY
"$ENGINE" --headless --editor --path "$ROOT" --import --quit > "$WORK/import.log" 2>&1 || { cat "$WORK/import.log"; exit 1; }
if grep -Eq 'SCRIPT ERROR|^ERROR:' "$WORK/import.log"; then cat "$WORK/import.log"; exit 1; fi
"$ENGINE" --headless --path "$ROOT" "$FLAG" "$PRESET" "$OUTPUT/universal.apk" > "$WORK/export.log" 2>&1 || { cat "$WORK/export.log"; exit 1; }
if grep -Eq 'SCRIPT ERROR|^ERROR:' "$WORK/export.log"; then cat "$WORK/export.log"; exit 1; fi
[[ -s "$OUTPUT/universal.apk" ]]
bash "$ROOT/tools/build/finalize_apk.sh" "$OUTPUT/universal.apk" "$MODE"
python3 "$ROOT/tools/build/verify_apk.py" "$OUTPUT/universal.apk" --sdk "$SDK" --mode "$MODE" --fingerprint "$FINGERPRINT"
if [[ "$MODE" == release ]]; then
  mkdir -p "$WORK/previous" "$OUTPUT/content"
  python3 "$ROOT/tools/build/reuse_content_manifest.py" "$ROOT" "$WORK/previous"
  PREVIOUS=()
  [[ ! -f "$WORK/previous/previous.json" ]] || PREVIOUS=(--previous "$WORK/previous/previous.json")
  python3 "$ROOT/tools/build/content_release.py" build "$OUTPUT/universal.apk" "$OUTPUT/content" "${PREVIOUS[@]}"
  "$JAVA_HOME/bin/java" "$ROOT/tools/build/SignContent.java" sign "$OUTPUT/content/content-manifest.json" "$OUTPUT/content/content-manifest.sig"
  openssl dgst -sha256 -verify "$ROOT/data/content_public_key.pem" -signature "$OUTPUT/content/content-manifest.sig" "$OUTPUT/content/content-manifest.json"
fi
(cd "$OUTPUT" && sha256sum universal.apk > SHA256SUMS.txt)
echo "Verified $MODE APK and SHA256SUMS.txt ready in $OUTPUT"
