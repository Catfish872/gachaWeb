#!/usr/bin/env bash
set -euo pipefail
cd /workspace/scratch/8f1fc457a062/gacha-android-next/godot
export XDG_CONFIG_HOME=/tmp/relic-ui-gl-v250/config
export XDG_CACHE_HOME=/tmp/relic-ui-gl-v250/cache
export XDG_DATA_HOME=/tmp/relic-ui-gl-v250/data
mkdir -p "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME" validation/relic-ui-v250
godot --path . --audio-driver Dummy --rendering-method gl_compatibility --script tests/capture_relic_set_art_gpu_v250.gd 2>&1 | tee validation/relic-ui-v250/art-real-gl.log
godot --path . --audio-driver Dummy --rendering-method gl_compatibility --script tests/test_relic_loadout_ui_v250.gd -- --test-session --mobile-ui --require-gl 2>&1 | tee validation/relic-ui-v250/real-gl.log
test "${PIPESTATUS[0]}" -eq 0
if grep -Eq 'SCRIPT ERROR|^ERROR:|^FAIL' validation/relic-ui-v250/real-gl.log; then exit 1; fi
godot --path . --audio-driver Dummy --rendering-method gl_compatibility --script tests/test_relic_collection_ui_v250.gd -- --test-session --mobile-ui --require-gl 2>&1 | tee validation/relic-ui-v250/collection-real-gl.log
if grep -Eq 'SCRIPT ERROR|^ERROR:|^FAIL' validation/relic-ui-v250/collection-real-gl.log; then exit 1; fi
godot --path . --audio-driver Dummy --rendering-method gl_compatibility --script tests/test_relic_unproven_ui_v250.gd -- --test-session --mobile-ui --require-gl 2>&1 | tee validation/relic-ui-v250/unproven-real-gl.log
if grep -Eq 'SCRIPT ERROR|^ERROR:|^FAIL' validation/relic-ui-v250/unproven-real-gl.log; then exit 1; fi
echo 'RELIC UI REAL GL PASSED'
