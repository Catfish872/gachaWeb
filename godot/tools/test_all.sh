#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export XDG_CONFIG_HOME="${VOIDRIFT_TEST_CONFIG:-/tmp/voidrift-tests/config}"
export XDG_CACHE_HOME="${VOIDRIFT_TEST_CACHE:-/tmp/voidrift-tests/cache}"
export XDG_DATA_HOME="${VOIDRIFT_TEST_DATA:-/tmp/voidrift-tests/data}"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME" validation
ENGINE="${GODOT_BIN:-godot}"
"$ENGINE" --headless --editor --path . --import --quit > validation/import.log 2>&1
for suite in model battle integration storage progression_v2 balance_v2 regression_v2 ui ui_v2 art_assets character_avatars avatar_ui_v24 extraction extraction_ui extraction_balance loot_economy redesign_layout redesign_inventory redesign_audio redesign_loot_interactions redesign_deposit battle_presentation encounter_feedback story_presentation character_navigation summon_presentation ui_semantic_coverage relic_presentation android_probe_notifications battle_geometry_v24 battle_status_effects_v24 combat_audio_v24 loot_v24_interactions inventory_v24_touch native_warehouse_v24 services_v24 collection_v24 v24_layout reward_rarity_v24 v240_media_assets extraction_map extraction_v6 extraction_v7 extraction_v8 economy_v9 abyss_endless_ui_v24 rune_theme music_context expedition_assets looting_feedback updates update_layout; do
  file="tests/test_${suite}.gd"
  if [ ! -f "$file" ]; then echo "Missing required test suite: $file"; exit 1; fi
  extra_args=()
  if [[ "$suite" == redesign_* || "$suite" == battle_presentation || "$suite" == encounter_feedback || "$suite" == story_presentation || "$suite" == character_navigation || "$suite" == summon_presentation || "$suite" == ui_semantic_coverage || "$suite" == relic_presentation || "$suite" == android_probe_notifications || "$suite" == battle_geometry_v24 || "$suite" == loot_v24_interactions || "$suite" == inventory_v24_touch || "$suite" == native_warehouse_v24 || "$suite" == avatar_ui_v24 || "$suite" == services_v24 || "$suite" == collection_v24 || "$suite" == v24_layout || "$suite" == reward_rarity_v24 || "$suite" == abyss_endless_ui_v24 || "$suite" == looting_feedback || "$suite" == update_layout ]]; then extra_args+=(--mobile-ui); fi
  if ! "$ENGINE" --headless --path . --script "$file" -- --test-session "${extra_args[@]}" > "validation/${suite}.log" 2>&1; then
    cat "validation/${suite}.log"
    exit 1
  fi
  cat "validation/${suite}.log"
  if grep -Eq 'SCRIPT ERROR|^ERROR:|^FAIL' "validation/${suite}.log"; then exit 1; fi
done
"$ENGINE" --headless --path . --script tests/test_scene_lifecycle.gd -- --test-session > validation/scene-smoke.log 2>&1
if grep -Eq 'SCRIPT ERROR|^ERROR:' validation/import.log validation/scene-smoke.log; then cat validation/import.log validation/scene-smoke.log; exit 1; fi
echo 'ALL GAMEPLAY AND EXTRACTION TEST SUITES PASSED'
