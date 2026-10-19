#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
APK="${1:?Smoke APK required}"
OUTPUT="${2:?Evidence directory required}"
mkdir -p "$OUTPUT"
# setup_android.sh exposes a pinned build-tools SDK view. Resolve the original
# runner SDK so emulator package installation can reuse its existing licenses.
SDK=$(dirname "$(readlink -f "${ANDROID_HOME:?}/platform-tools")")
{ id; ls -l /dev/kvm; } > "$OUTPUT/host-access.txt" 2>&1 || true
[[ -r /dev/kvm && -w /dev/kvm ]] || { echo 'Android smoke blocked: runner needs existing read/write KVM access'; exit 1; }
[[ -d "$SDK/licenses" ]] || { echo 'Android SDK licenses must already be accepted'; exit 1; }
MANAGER="$SDK/cmdline-tools/latest/bin/sdkmanager"
IMAGE='system-images;android-35;default;x86_64'
"$MANAGER" --sdk_root="$SDK" 'emulator' "$IMAGE" < /dev/null
export ANDROID_HOME="$SDK" ANDROID_SDK_ROOT="$SDK"
export ANDROID_AVD_HOME="${RUNNER_TEMP:-/tmp}/voidrift-avd"
mkdir -p "$ANDROID_AVD_HOME"
printf 'no\n' | "$SDK/cmdline-tools/latest/bin/avdmanager" create avd --force --name voidrift-smoke --package "$IMAGE"
cat >> "$ANDROID_AVD_HOME/voidrift-smoke.avd/config.ini" <<'AVD'
hw.lcd.width=720
hw.lcd.height=1280
hw.lcd.density=320
hw.ramSize=2048
hw.keyboard=yes
AVD
export ADB="$SDK/platform-tools/adb"
export ANDROID_SERIAL=emulator-5554
"$SDK/emulator/emulator" -avd voidrift-smoke -port 5554 -no-window -no-audio -no-boot-anim -no-snapshot -gpu swiftshader_indirect -accel on -cores 2 > "$OUTPUT/emulator.log" 2>&1 &
EMULATOR_PID=$!
trap '"$ADB" emu kill >/dev/null 2>&1 || true; kill "$EMULATOR_PID" 2>/dev/null || true' EXIT
for ((i=0; i<150; i++)); do
  kill -0 "$EMULATOR_PID" || { cat "$OUTPUT/emulator.log"; exit 1; }
  if [[ $("$ADB" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r') == 1 ]]; then break; fi
  sleep 2
done
[[ $("$ADB" shell getprop sys.boot_completed | tr -d '\r') == 1 ]] || { echo 'Emulator boot timed out'; exit 1; }
"$ADB" shell input keyevent 82
python3 "$ROOT/tools/android/smoke_test.py" "$APK" "$OUTPUT"
