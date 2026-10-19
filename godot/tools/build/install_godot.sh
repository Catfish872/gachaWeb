#!/usr/bin/env bash
set -euo pipefail
VERSION=4.6.3
BASE="https://github.com/godotengine/godot-builds/releases/download/${VERSION}-stable"
ENGINE="Godot_v${VERSION}-stable_linux.x86_64.zip"
TEMPLATES="Godot_v${VERSION}-stable_export_templates.tpz"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
for asset in SHA512-SUMS.txt "$ENGINE" "$TEMPLATES"; do
  curl --fail --location --retry 3 --proto '=https' --tlsv1.2 "$BASE/$asset" -o "$WORK/$asset"
done
python3 - "$WORK" "$ENGINE" "$TEMPLATES" <<'PY'
import hashlib, pathlib, sys
root = pathlib.Path(sys.argv[1])
pinned = {
    'Godot_v4.6.3-stable_linux.x86_64.zip': 'a035258da32b77f966a5376f9fa29c30a6adde826a85ba918e1605bd1fc9823eba7d85f1dd5e748956bd2ba72827c0025ffa11bb82aec91128c407a2e723c99c',
    'Godot_v4.6.3-stable_export_templates.tpz': 'da606b61c10157844f8300172df374472665f95015495cb1a7cd132c40ede404faa96cc1016a4b9662db9909ddea69632c4948b2cd11163438dad4808881fb68',
}
checksums = {}
for line in (root / 'SHA512-SUMS.txt').read_text().splitlines():
    parts = line.split()
    if len(parts) == 2:
        checksums[parts[1].lstrip('*')] = parts[0]
for name in sys.argv[2:]:
    expected = checksums.get(name)
    if expected != pinned[name] or hashlib.sha512((root / name).read_bytes()).hexdigest() != expected:
        raise SystemExit('Official SHA512 verification failed: ' + name)
print('Official engine and template SHA512 checks passed')
PY
BIN="$HOME/.local/bin"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/${VERSION}.stable"
mkdir -p "$BIN" "$DATA"
unzip -q "$WORK/$ENGINE" -d "$WORK/engine"
install -m 755 "$WORK/engine/Godot_v${VERSION}-stable_linux.x86_64" "$BIN/godot"
unzip -q "$WORK/$TEMPLATES" 'templates/android_debug.apk' 'templates/android_release.apk' -d "$WORK/templates"
install -m 644 "$WORK/templates/templates/"*.apk "$DATA/"
if [[ -n "${GITHUB_PATH:-}" ]]; then printf '%s\n' "$BIN" >> "$GITHUB_PATH"; fi
"$BIN/godot" --headless --version
