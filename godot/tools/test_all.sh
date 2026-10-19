#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export XDG_CONFIG_HOME="${VOIDRIFT_TEST_CONFIG:-/tmp/voidrift-tests/config}"
export XDG_CACHE_HOME="${VOIDRIFT_TEST_CACHE:-/tmp/voidrift-tests/cache}"
export XDG_DATA_HOME="${VOIDRIFT_TEST_DATA:-/tmp/voidrift-tests/data}"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME" validation
ENGINE="${GODOT_BIN:-godot}"
"$ENGINE" --headless --editor --path . --import --quit > validation/import.log 2>&1
for suite in model battle integration storage progression_v2 balance_v2 regression_v2 ui ui_v2; do
  file="tests/test_${suite}.gd"
  if [ ! -f "$file" ]; then echo "Missing required test suite: $file"; exit 1; fi
  if ! "$ENGINE" --headless --path . --script "$file" -- --test-session > "validation/${suite}.log" 2>&1; then
    cat "validation/${suite}.log"
    exit 1
  fi
  cat "validation/${suite}.log"
  if grep -Eq 'SCRIPT ERROR|^ERROR:|^FAIL' "validation/${suite}.log"; then exit 1; fi
done
"$ENGINE" --headless --path . --quit-after 10 -- --test-session > validation/scene-smoke.log 2>&1
if grep -Eq 'SCRIPT ERROR|^ERROR:' validation/import.log validation/scene-smoke.log; then cat validation/import.log validation/scene-smoke.log; exit 1; fi
echo 'ALL V2 GAMEPLAY TEST SUITES PASSED'
