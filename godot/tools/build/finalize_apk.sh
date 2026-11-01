#!/usr/bin/env bash
# Canonicalize known Godot Vulkan feature types, then align and re-sign.
# Signing values are inherited from the already-authorized export invocation.
set -euo pipefail
set +x
APK="${1:?APK required}"
MODE="${2:?debug or release required}"
[[ "$MODE" == debug || "$MODE" == release ]] || exit 1
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
: "${SDK:?Android SDK required}"
TOOLS="$SDK/build-tools/35.0.1"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
umask 077
python3 "$ROOT/tools/build/normalize_manifest.py" "$APK" "$WORK/normalized.apk"
"$TOOLS/zipalign" -P 16 -f 4 "$WORK/normalized.apk" "$WORK/aligned.apk"
if [[ "$MODE" == release ]]; then
  KEY="${GODOT_ANDROID_KEYSTORE_RELEASE_PATH:?}"
  ALIAS="${GODOT_ANDROID_KEYSTORE_RELEASE_USER:?}"
  PASSWORD_ENV=GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD
else
  KEY="${GODOT_ANDROID_KEYSTORE_DEBUG_PATH:?}"
  ALIAS="${GODOT_ANDROID_KEYSTORE_DEBUG_USER:?}"
  PASSWORD_ENV=GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD
fi
"$TOOLS/apksigner" sign --ks "$KEY" --ks-key-alias "$ALIAS" \
  --ks-pass "env:$PASSWORD_ENV" --key-pass "env:$PASSWORD_ENV" \
  --out "$WORK/signed.apk" "$WORK/aligned.apk"
"$TOOLS/zipalign" -c -P 16 4 "$WORK/signed.apk"
"$TOOLS/apksigner" verify --verbose "$WORK/signed.apk"
# Retain a complete SDK-parsed manifest check for both emulator and production.
if ! "$TOOLS/aapt" dump badging "$WORK/signed.apk" > "$WORK/badging.txt"; then
  echo 'Manifest parser rejected canonical APK; bounded public XML diagnostics:' >&2
  "$TOOLS/aapt" dump xmltree "$WORK/signed.apk" AndroidManifest.xml 2>&1 | head -n 200 >&2 || true
  exit 1
fi
mv "$WORK/signed.apk" "$APK"
echo 'APK manifest canonicalized, aligned and signature verified'
