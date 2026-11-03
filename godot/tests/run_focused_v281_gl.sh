#!/usr/bin/env bash
cd "$(dirname "$0")/.."
export XDG_CONFIG_HOME=/tmp/v281-gl/config XDG_CACHE_HOME=/tmp/v281-gl/cache XDG_DATA_HOME=/tmp/v281-gl/data
mkdir -p validation/v281-focused validation/v281-portraits
for t in wind_portraits_v281 wind_trials_ui_v280 wind_banner_delta_v280; do
 timeout 100 godot --path . --audio-driver Dummy --rendering-method gl_compatibility --script tests/test_$t.gd -- --test-session --mobile-ui --require-gl > validation/v281-focused/$t.log 2>&1
 echo "$t EXIT:$?"; tail -8 validation/v281-focused/$t.log
done
