#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."
export XDG_CONFIG_HOME=/tmp/v260-polish-gl/config XDG_CACHE_HOME=/tmp/v260-polish-gl/cache XDG_DATA_HOME=/tmp/v260-polish-gl/data
mkdir -p "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME" validation/mobile-polish-v260
echo 'Actual GL visual and interaction check. Audio Dummy; no speaker test.'
timeout 240 godot --path . --audio-driver Dummy --rendering-method gl_compatibility --script tests/test_mobile_polish_v260.gd -- --test-session --mobile-ui --require-gl "$@" 2>&1 | tee validation/mobile-polish-v260/gl.log
status=${PIPESTATUS[0]}
printf '%s\n' "$status" > validation/mobile-polish-v260/gl-exit-code.txt
exit "$status"
