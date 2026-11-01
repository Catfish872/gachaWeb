#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."
export XDG_CONFIG_HOME=/tmp/v261-focused/config XDG_CACHE_HOME=/tmp/v261-focused/cache XDG_DATA_HOME=/tmp/v261-focused/data
mkdir -p validation/v261-focused
 timeout 75 godot --path . --audio-driver Dummy --rendering-method gl_compatibility --script tests/test_rarity_priority_ui_v261.gd -- --test-session --mobile-ui --require-gl 2>&1 | tee validation/v261-focused/rarity-gl.log
exit "${PIPESTATUS[0]}"
