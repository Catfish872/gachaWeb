#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
output=validation/expedition-v250
mkdir -p "$output"
sha256sum -c "$output/FINAL_BEHAVIOR_SHA256.txt"
seed_base=${ECONOMY_SEED_BASE:?Set a fresh holdout seed after production freeze}
farm_seed=${ECONOMY_FARM_SEED_BASE:?Set a separate fresh drop-efficiency seed}
pids=()
for spec in starter:0 grown:2 limited_c6_gear25:4 limited_c6_gear25:5 damage_c6_gear25:5 optimized_c6:5 theme_limited_c6_gear25:4 theme_limited_c6_gear25:5; do
 profile=${spec%:*}; risk=${spec#*:}; label=${profile}-r${risk}; home=/tmp/economy-v250-final-${label}
 mkdir -p "$home/cache" "$home/config" "$home/data"
 (
  for policy in reserve_locked default_unlocked; do
   modes=all; if [[ "$policy" == default_unlocked ]]; then modes=extraction; fi
   { time env XDG_CONFIG_HOME="$home/config" XDG_DATA_HOME="$home/data" XDG_CACHE_HOME="$home/cache" godot --headless --path . --script res://tools/simulate_mode_economy_v16.gd -- --samples=64 --profile="$profile" --risk="$risk" --seed-base="$seed_base" --supply-policy="$policy" --modes="$modes" --output="economy-v250-holdout-${label}-${policy}.json"; } > "$output/holdout-${label}-${policy}.log" 2>&1
  done
 ) &
 pids+=("$!")
done
farm_home=/tmp/economy-v250-drop-efficiency
mkdir -p "$farm_home/cache" "$farm_home/config" "$farm_home/data"
(
 { time env XDG_CONFIG_HOME="$farm_home/config" XDG_DATA_HOME="$farm_home/data" XDG_CACHE_HOME="$farm_home/cache" godot --headless --path . --script res://tools/simulate_mode_economy_v16.gd -- --samples=32 --profile=limited_c6_gear25 --seed-base="$farm_seed" --modes=abyss_sweep --output=economy-v250-drop-efficiency.json; } > "$output/drop-efficiency.log" 2>&1
) &
pids+=("$!")
result=0
for pid in "${pids[@]}"; do wait "$pid" || result=1; done
sha256sum -c "$output/FINAL_BEHAVIOR_SHA256.txt" || result=1
exit "$result"
