#!/usr/bin/env bash
cd "$(dirname "$0")/.."
export XDG_CONFIG_HOME=/tmp/v280-focused/config XDG_CACHE_HOME=/tmp/v280-focused/cache XDG_DATA_HOME=/tmp/v280-focused/data
for t in team_presets_ui_v280 wind_trials_ui_v280 event_preferences_v280; do
 timeout 90 godot --path . --audio-driver Dummy --rendering-method gl_compatibility --script tests/test_$t.gd -- --test-session --mobile-ui --require-gl > validation/v280-focused/$t.log 2>&1
 echo "$t EXIT:$?"; tail -8 validation/v280-focused/$t.log
done
