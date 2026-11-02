#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."
export XDG_CONFIG_HOME=/tmp/v270-focused/config XDG_CACHE_HOME=/tmp/v270-focused/cache XDG_DATA_HOME=/tmp/v270-focused/data
mkdir -p "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME" validation/v276-focused
 timeout 90 godot --path . --audio-driver Dummy --rendering-method gl_compatibility --script tests/test_tactical_ui_v276.gd -- --test-session --mobile-ui --require-gl 2>&1 | tee validation/v276-focused/gl.log
exit "${PIPESTATUS[0]}"
