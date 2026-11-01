# Android 2.2.0 production release

- Published: 2026-11-01 06:02:20 UTC
- Version: 2.2.0 / 20200
- Runtime commit: `14b112da5cefcf5b0b6424866df087d62dcd4d3a`
- Runtime tree: `46c8e2966143de2fc191175ecef65452cc1128ba`
- Workflow: https://github.com/Catfish872/gachaWeb/actions/runs/41278681090
- Release: https://github.com/Catfish872/gachaWeb/releases/tag/android-v2.2.0
- APK: https://github.com/Catfish872/gachaWeb/releases/download/android-v2.2.0/universal.apk
- APK bytes: 110068697
- APK SHA256: `79615dca06f32349aa1936350191dfd3fdaa4e3b886a332b3a31b5d014a8dc3c`
- Fixed certificate SHA256: `10fae1fe7586e79e17dc925b42fcba5b2bfe2907729df113bce917cc521c8f56`
- Package: `org.catfish872.voidrift`

## Verified gates

Both `test-debug` and `signed-release` succeeded. Production verifier checked the actual APK package, version, SDK, permissions, ARM architectures, packaged contents and exact fixed certificate. APK signature schemes v2 and v3 verified. Signing identity, package identity and security settings were not changed.

Actual Android API 35 x86_64 emulator used Godot Mobile/Vulkan (SwiftShader). Real ADB tests passed, including full-page navigation, extraction map fit/zoom/drag, room search, bag collection, and three rapid/settled resume cycles. Machine results are archived under `android-ci22/`. Root independently reviewed native screenshots for map drag, room scene, bag after search and rapid resume menu; no SCRIPT ERROR, EGL or QueuePresentKHR failures were found.

Evidence artifact: `13072148691`, `android-runtime-evidence-test-debug-22`, ZIP SHA256 `932389bdaabbe96b76658cbef3d0b11276f5cc8f3e2e67005b83750225a6724e`. Screenshots remain in the CI artifact, not duplicated into the public repository.

The preceding run 41277651442 correctly blocked release when the old driver demanded panning in fitted overview. Follow-up fixed real content-centered clamping and initial layout auto-fit, then verified stable overview and actual zoomed drag >12 logical pixels without unintended room entry. No failing gate was skipped or weakened.

## Authorization and immutable release

The user requested one formal auto-update channel for iterative testing and comprehensive mobile polish. Root approved production submission after visual acceptance and strict test/model validation, and approved the focused native-regression fix after diagnosing the first CI failure. This documentation-only follow-up does not change runtime, release tag, assets or signing.

`SOURCE_SHA256.txt` lists only published source files; unused search/BGM candidates and two orphan local probe UID files were excluded. Local full snapshots remained outside the repository.
