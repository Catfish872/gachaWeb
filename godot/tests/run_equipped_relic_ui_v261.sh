#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."
export XDG_CONFIG_HOME=/tmp/v261-focused/config XDG_CACHE_HOME=/tmp/v261-focused/cache XDG_DATA_HOME=/tmp/v261-focused/data
mkdir -p "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME" validation/equipped-upgrade-v261
 timeout 100 godot --path . --audio-driver Dummy --rendering-method gl_compatibility --script tests/test_equipped_relic_upgrade_ui_v261.gd -- --test-session --mobile-ui --require-gl 2>&1 | tee validation/equipped-upgrade-v261/gl.log
exit "${PIPESTATUS[0]}"
