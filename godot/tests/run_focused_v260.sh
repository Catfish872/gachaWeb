#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."
export XDG_CONFIG_HOME=/tmp/v260-focused/config XDG_CACHE_HOME=/tmp/v260-focused/cache XDG_DATA_HOME=/tmp/v260-focused/data
mkdir -p "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME" validation/v260-focused
for test in test_searched_room_v260 test_themed_maps_v260; do
 timeout 90 godot --headless --path . --audio-driver Dummy --script tests/$test.gd -- --test-session --mobile-ui > validation/v260-focused/$test.log 2>&1
 echo "$test exit=$?" | tee -a validation/v260-focused/status.txt
done
python ../.github/scripts/test_focused_evidence.py > validation/v260-focused/evidence-gate.log 2>&1
echo "evidence-gate exit=$?" | tee -a validation/v260-focused/status.txt
