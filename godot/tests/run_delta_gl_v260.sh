#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."
export XDG_CONFIG_HOME=/tmp/v260-polish-gl/config XDG_CACHE_HOME=/tmp/v260-polish-gl/cache XDG_DATA_HOME=/tmp/v260-polish-gl/data
mkdir -p validation/v260-focused
 timeout 75 godot --path . --audio-driver Dummy --rendering-method gl_compatibility --script tests/test_loot_expansion_gl_v260.gd -- --test-session --mobile-ui --require-gl 2>&1 | tee validation/v260-focused/delta-gl.log
exit "${PIPESTATUS[0]}"
