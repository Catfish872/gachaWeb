#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."
export XDG_CONFIG_HOME=/tmp/v264-focused/config XDG_CACHE_HOME=/tmp/v264-focused/cache XDG_DATA_HOME=/tmp/v264-focused/data
mkdir -p "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME" validation/caster-dot-v264
 timeout 90 godot --path . --audio-driver Dummy --rendering-method gl_compatibility --script tests/test_caster_dot_ui_v264.gd -- --test-session --mobile-ui --require-gl 2>&1 | tee validation/caster-dot-v264/gl.log
exit "${PIPESTATUS[0]}"
