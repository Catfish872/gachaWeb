#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export XDG_CONFIG_HOME="${VOIDRIFT_TEST_CONFIG:-/tmp/character-audio-v293/config}"
export XDG_CACHE_HOME="${VOIDRIFT_TEST_CACHE:-/tmp/character-audio-v293/cache}"
export XDG_DATA_HOME="${VOIDRIFT_TEST_DATA:-/tmp/character-audio-v293/data}"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME" validation/v293-character-audio
engine="${GODOT_BIN:-godot}"
"$engine" --headless --editor --path . --import --quit > validation/v293-character-audio/import.log 2>&1
for suite in character_summon_audio_v293 selected_thunder_audio_v290 music_context redesign_audio; do
  "$engine" --headless --path . --script "tests/test_${suite}.gd" -- --test-session > "validation/v293-character-audio/${suite}.log" 2>&1
  cat "validation/v293-character-audio/${suite}.log"
  if grep -Eq 'SCRIPT ERROR|^ERROR:|^FAIL' "validation/v293-character-audio/${suite}.log"; then exit 1; fi
done
if grep -Eq 'SCRIPT ERROR|^ERROR:' validation/v293-character-audio/import.log; then exit 1; fi
