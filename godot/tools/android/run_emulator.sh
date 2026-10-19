#!/usr/bin/env bash
set -euo pipefail
# Helpers are sourceable for mocked lifecycle tests; sourcing never starts Android.
KVM_ACL_BACKUP=""
EMULATOR_PID=""
kvm_accessible() { [[ -r /dev/kvm && -w /dev/kvm ]]; }
kvm_device_exists() { [[ -c /dev/kvm ]]; }
acquire_kvm_access() {
  if kvm_accessible; then return; fi
  [[ "${ALLOW_TEMP_KVM_ACL:-}" == 1 && "${GITHUB_ACTIONS:-}" == true && "${RUNNER_ENVIRONMENT:-}" == github-hosted && "${RUNNER_OS:-}" == Linux ]] || {
    echo 'Android smoke blocked: temporary KVM ACL requires explicit opt-in on a GitHub-hosted Linux runner' >&2; return 1;
  }
  kvm_device_exists || { echo 'Android smoke blocked: /dev/kvm character device is missing' >&2; return 1; }
  for tool in getfacl setfacl sudo; do
    command -v "$tool" >/dev/null || { echo "Required ACL tool missing: $tool" >&2; return 1; }
  done
  KVM_ACL_BACKUP=$(mktemp "${RUNNER_TEMP:-/tmp}/voidrift-kvm-acl.XXXXXX")
  if ! getfacl --absolute-names --numeric /dev/kvm > "$KVM_ACL_BACKUP"; then
    rm -f "$KVM_ACL_BACKUP"; KVM_ACL_BACKUP=""; return 1;
  fi
  # The EXIT trap is installed before acquisition. Preserve the entire ACL/mask,
  # including any pre-existing named entry, even if the grant partially fails.
  sudo -n setfacl -m "u:$(id -u):rw" /dev/kvm || return 1
  kvm_accessible || { echo 'Named-user KVM access verification failed' >&2; return 1; }
}
restore_kvm_access() {
  [[ -n "$KVM_ACL_BACKUP" ]] || return 0
  sudo -n setfacl --restore="$KVM_ACL_BACKUP" || return 1
  getfacl --absolute-names --numeric /dev/kvm | cmp -s "$KVM_ACL_BACKUP" - || {
    echo 'Original KVM ACL restoration could not be verified' >&2; return 1;
  }
  rm -f "$KVM_ACL_BACKUP"
  KVM_ACL_BACKUP=""
}
cleanup_android() {
  local status=$?
  trap - EXIT INT TERM
  if [[ -n "$EMULATOR_PID" ]]; then
    # Stop the process before revoking its temporary device access.
    "${ADB:-adb}" emu kill >/dev/null 2>&1 || true
    kill "$EMULATOR_PID" 2>/dev/null || true
    for ((attempt=0; attempt<50; attempt++)); do
      kill -0 "$EMULATOR_PID" 2>/dev/null || break
      sleep .2
    done
    kill -KILL "$EMULATOR_PID" 2>/dev/null || true
    wait "$EMULATOR_PID" 2>/dev/null || true
  fi
  if ! restore_kvm_access; then
    echo 'Failed to restore original KVM ACL' >&2
    status=1
  fi
  exit "$status"
}
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then return 0; fi
trap cleanup_android EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
APK="${1:?Smoke APK required}"
OUTPUT="${2:?Evidence directory required}"
mkdir -p "$OUTPUT"
# setup_android.sh exposes a pinned build-tools SDK view. Resolve the original
# runner SDK so emulator package installation can reuse its existing licenses.
SDK=$(dirname "$(readlink -f "${ANDROID_HOME:?}/platform-tools")")
{ id; ls -l /dev/kvm; } > "$OUTPUT/host-access.txt" 2>&1 || true
acquire_kvm_access
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
for ((i=0; i<150; i++)); do
  kill -0 "$EMULATOR_PID" || { cat "$OUTPUT/emulator.log"; exit 1; }
  if [[ $("$ADB" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r') == 1 ]]; then break; fi
  sleep 2
done
[[ $("$ADB" shell getprop sys.boot_completed | tr -d '\r') == 1 ]] || { echo 'Emulator boot timed out'; exit 1; }
"$ADB" shell input keyevent 82
python3 "$ROOT/tools/android/smoke_test.py" "$APK" "$OUTPUT"
