# Android runtime smoke

The Android workflow runs an API 35 x86_64 emulator with KVM, software graphics,
and a 720 × 1280 display before exporting the ARM delivery APK. It requires
existing accepted Android SDK licenses. With the explicitly approved workflow
opt-in, it temporarily grants only the current UID read/write access to KVM on
a GitHub-hosted Linux runner, preserves the original ACL, and restores and
verifies it after stopping the emulator. Existing access needs no ACL change.
Local and self-hosted runs require existing KVM access. The script accepts no
new license agreements. Setup or cleanup failure fails the workflow and
preserves available logs.

`export_smoke.sh OUTPUT` creates an isolated project copy, changes only that
copy to x86_64, and installs an observation-only subclass of the production
main scene. The probe reports actual Android control positions and application
state. All tested interactions come from Android `adb shell input`, rather
than invoking game navigation methods. The regular ARM export excludes this
tools directory; its production scene and preset are unchanged.

`run_emulator.sh APK EVIDENCE` boots the emulator and runs `smoke_test.py`.
Checks cover portrait launch, menu dismissal by Android Back, touch navigation
to eight pages, horizontal page bounds, finger scrolling where necessary,
Back to home, landscape adaptation, and touch after background/resume. Android
and Godot runtime errors fail the test. Screenshots, logcat and window/activity
diagnostics are uploaded even on failure. Delivery APK publication is gated
on success.

This test exercises Android lifecycle, rendering and input on an emulator.
It does not establish physical-device frame rate, GPU compatibility, battery
use, every gameplay flow, or visual quality. Inspect the screenshot evidence
and retain physical-device validation for those claims. The x86_64 probe APK
is test-only and is never uploaded as a user delivery APK.
