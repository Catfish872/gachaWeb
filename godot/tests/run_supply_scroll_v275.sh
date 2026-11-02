#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."
export XDG_CONFIG_HOME=/tmp/v270-focused/config XDG_CACHE_HOME=/tmp/v270-focused/cache XDG_DATA_HOME=/tmp/v270-focused/data
mkdir -p "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME" validation/supply-scroll-focused
 timeout 90 godot --path . --audio-driver Dummy --rendering-method gl_compatibility --script tests/test_supply_scroll_v275.gd -- --test-session --mobile-ui --require-gl 2>&1 | tee validation/supply-scroll-focused/gl.log
exit "${PIPESTATUS[0]}"
