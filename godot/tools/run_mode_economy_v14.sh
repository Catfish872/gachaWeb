#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
output=validation/expedition-v241
mkdir -p "$output"
sha256sum -c "$output/FINAL_BEHAVIOR_SHA256.txt"
pids=()
for spec in starter:0 grown:2 limited_c6_gear25:4 limited_c6_gear25:5 damage_c6_gear25:5 optimized_c6:5; do
 profile=${spec%:*}; risk=${spec#*:}; label=${profile}-r${risk}; home=/tmp/economy-v241-final-${label}
 mkdir -p "$home/cache" "$home/config" "$home/data"
 (
  for policy in reserve_locked default_unlocked; do
   modes=all; if [[ "$policy" == default_unlocked ]]; then modes=extraction; fi
   { time env XDG_CONFIG_HOME="$home/config" XDG_DATA_HOME="$home/data" XDG_CACHE_HOME="$home/cache" godot --headless --path . --script res://tools/simulate_mode_economy_v14.gd -- --samples=64 --profile="$profile" --risk="$risk" --seed-base=34900000 --supply-policy="$policy" --modes="$modes" --output="economy-v241-holdout-${label}-${policy}.json"; } > "$output/holdout-${label}-${policy}.log" 2>&1
  done
 ) &
 pids+=("$!")
done
result=0
for pid in "${pids[@]}"; do wait "$pid" || result=1; done
sha256sum -c "$output/FINAL_BEHAVIOR_SHA256.txt" || result=1
exit "$result"
