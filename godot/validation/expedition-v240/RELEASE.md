# Android 2.4.0 release checks

- Version: 2.4.0 / 20400; package `org.catfish872.voidrift`
- Published: 2026-11-01 10:09:18 UTC; draft=false, prerelease=false
- Runtime/tag commit: `e1275e3b37c0b8a5a6ab7ab848860c1c0c960f9e`
- Runtime tree: `ffadf88d93771161b02dda0310ecdcc98d7bd811`
- Workflow: https://github.com/Catfish872/gachaWeb/actions/runs/41295372451
- Release: https://github.com/Catfish872/gachaWeb/releases/tag/android-v2.4.0
- APK: https://github.com/Catfish872/gachaWeb/releases/download/android-v2.4.0/universal.apk
- APK size: 136085234 bytes
- APK SHA256: `53c6211e732ef3cbf3c142e48e921661d73f6bad52043943df7575b3c01ab30d`
- Fixed certificate SHA256: `10fae1fe7586e79e17dc925b42fcba5b2bfe2907729df113bce917cc521c8f56`

Both test-debug and signed-release completed successfully. APK signature schemes v2 and v3 verified; actual package, version, SDK, permissions, ARM architectures, contents and fixed certificate checks all passed. Latest release resolves to android-v2.4.0 and both assets are uploaded. No signing identity, package identity or runtime tag was changed during documentation closeout.

## Android evidence

API35 x86_64 emulator, Godot Mobile/Vulkan on SwiftShader. Full navigation, Back, inventory touch/placement/selection, scrolling with first tap after scrolling, map drag, room search, pickup and bag persistence passed. Three resume modes passed. Search-background was naturally covered on first attempt with the same item UID and unchanged paused/resumed progress 0.315789473684211.

The actual Android DownloadManager.Request accepted `metered_permitted=true` and `roaming_permitted=false`. This verifies request policy through the Android bridge, not an actual completed cellular APK download or installation. Physical S23+ hardware performance and cross-version installation are not claimed by the emulator checks.

Artifact `13079835097`, android-runtime-evidence-test-debug-25, ZIP SHA256 `d38d9e8627fcae8fa238f88c5f761bb7960cc96dd2279ac264635cdecdadb88a`. Ten raw result/probe JSON files are archived in `android-ci25/`; screenshots remain in the CI artifact.

## Frozen source and local checks

- 702 production files: `7bc2da653f34001b116e42ddabaa9ecc0e376fff0df1d4ff5996d55e9f499794`
- 76 verification files: `70c0a11b0a451e42c559f0ee8515527c76b86798eed0ce665f2f6a3ba8a99126`
- Final local 52-suite aggregate passed; mobile843, offline native driver54, actual warehouse-scroll GL34 passed.
- Final economy: 1920 routes / 80153 battles and 6144 key-room samples; see ECONOMY.md and economy-v240-final.md for accounting, limitations and reproducible data.

Chinese player-facing notes are in [CHANGELOG_2.4.md](../../CHANGELOG_2.4.md). The GitHub Release retains generated notes because the connected GitHub toolset provides no release-body edit action; no extra workflow or credential request was introduced solely to edit metadata.
