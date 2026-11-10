#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
ENGINE="${GODOT_BIN:-godot}"
OUT=validation/v293-avatar-review
mkdir -p "$OUT"
"$ENGINE" --headless --editor --path . --import --quit > "$OUT/import.log" 2>&1
"$ENGINE" --audio-driver Dummy --path . --script tests/test_thunder_avatar_framing_v293.gd -- --test-session --mobile-ui > "$OUT/render.log" 2>&1
cat "$OUT/render.log"
if grep -Eq 'SCRIPT ERROR|^ERROR:|^FAIL' "$OUT/render.log" "$OUT/import.log"; then exit 1; fi
