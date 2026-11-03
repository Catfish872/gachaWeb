#!/usr/bin/env bash
cd "$(dirname "$0")/.."
export XDG_CONFIG_HOME=/tmp/v283-ui/config XDG_CACHE_HOME=/tmp/v283-ui/cache XDG_DATA_HOME=/tmp/v283-ui/data
mkdir -p validation/v283-ui validation/v283-limited-fx
for t in mobile_layout_v283 extraction_presentation_v283 limited_fx_v283; do
 timeout 95 godot --path . --audio-driver Dummy --rendering-method gl_compatibility --script tests/test_$t.gd -- --test-session --mobile-ui --require-gl > validation/v283-ui/$t.log 2>&1
 echo "$t EXIT:$?"; tail -8 validation/v283-ui/$t.log
done
