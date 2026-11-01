#!/usr/bin/env bash
set -euo pipefail
cd /workspace/scratch/8f1fc457a062/gacha-android-next/godot
export XDG_CONFIG_HOME="$PWD/validation/room-return-v250/config"
export XDG_CACHE_HOME="$PWD/validation/room-return-v250/cache"
export XDG_DATA_HOME="$PWD/validation/room-return-v250/data"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME"
if [[ "${1:-}" == native ]]; then
  godot --path . --audio-driver Dummy --rendering-method gl_compatibility --script tests/manual_room_return_v250.gd -- --test-session --mobile-ui 2>&1 | tee validation/room-return-v250/native-gl.log
  if grep -Eq 'SCRIPT ERROR|^ERROR:|^FAIL' validation/room-return-v250/native-gl.log; then exit 1; fi
  echo 'ROOM RETURN NATIVE GL PASSED'
  exit 0
fi
godot --path . --audio-driver Dummy --rendering-method gl_compatibility --script tests/test_room_return_v250.gd -- --test-session --mobile-ui 2>&1 | tee validation/room-return-v250/real-gl.log
if grep -Eq 'SCRIPT ERROR|^ERROR:|^FAIL' validation/room-return-v250/real-gl.log; then exit 1; fi
echo 'ROOM RETURN REAL GL PASSED'
