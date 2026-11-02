#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."
export XDG_CONFIG_HOME=/tmp/v270-focused/config XDG_CACHE_HOME=/tmp/v270-focused/cache XDG_DATA_HOME=/tmp/v270-focused/data
mkdir -p "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME" validation/lantern-ui-v270
 timeout 50 godot --path . --audio-driver Dummy --rendering-method gl_compatibility --script tests/test_lantern_journey_ui_v270.gd -- --test-session --mobile-ui --require-gl --delta-ui 2>&1 | tee validation/lantern-ui-v270/delta-gl.log
exit "${PIPESTATUS[0]}"
