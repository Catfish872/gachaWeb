#!/usr/bin/env bash
cd "$(dirname "$0")/.."
export XDG_CONFIG_HOME=/tmp/v278-recovered/config XDG_CACHE_HOME=/tmp/v278-recovered/cache XDG_DATA_HOME=/tmp/v278-recovered/data
mkdir -p validation/recovered-events-v278-focused
set -o pipefail
timeout 90 godot --path . --audio-driver Dummy --rendering-method gl_compatibility --script tests/test_recovered_event_ui_v278.gd -- --test-session --mobile-ui --require-gl 2>&1 | tee validation/recovered-events-v278-focused/gl.log
