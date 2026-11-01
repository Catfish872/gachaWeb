# Android 2.3.0 release checks

- Version: 2.3.0 / 20300
- Package: `org.catfish872.voidrift`
- Released commit: `93fb06407f7307159a928ec892fe19fb02e534d0`
- Released tree: `f24359cb786755b169695c7866618a73cc1d2b45`
- Workflow: https://github.com/Catfish872/gachaWeb/actions/runs/41286657316
- Release: https://github.com/Catfish872/gachaWeb/releases/tag/android-v2.3.0
- APK: https://github.com/Catfish872/gachaWeb/releases/download/android-v2.3.0/universal.apk
- APK bytes: 123133702
- APK SHA256: `79763836be8f38c63feb0d9b8ff4ccc77513e8a523109c03244122f4a4009c47`
- Fixed signing certificate SHA256: `10fae1fe7586e79e17dc925b42fcba5b2bfe2907729df113bce917cc521c8f56`

Both test-debug and signed-release completed successfully. The production APK verifier checked package, version, SDK, permissions, ARM architectures, contents and the exact fixed signing certificate. APK v2 and v3 signatures verified. Package and signing identity remain unchanged for the existing formal update channel.

## Actual Android validation

Android API35 x86_64 emulator, Godot Mobile/Vulkan, SwiftShader. Native navigation, touch/scroll, connected-map drag, scene-container auto-search, automatic collection and bag persistence passed. Three background/resume scenarios (rapid, settled, rapid_again) passed. Android Back closed the menu with overlay=0 and exactly one observed notification. These are emulator results, not claims of physical S23+ testing or a completed real cross-version installation.

Search-background validation was actually covered on its first attempt. The same item UID retained progress 0.315789473684211 across background/resume. Raw `search-background.json` and `result.json` contain a stale default `reason` string saying no window was observed; this text was not cleared on success. The `covered=true`, UID and unchanged progress fields, together with lifecycle evidence, establish actual coverage. Raw JSON is preserved without rewriting the evidence.

Artifact `13074944964` / `android-runtime-evidence-test-debug-24`: ZIP SHA256 `7f5db47ddb0ddbe7ecda997650768a6a26b492c6a10dbc70bf6dbae7edf65d94`. Five machine-result JSON files are archived in `android-ci24/`; screenshots remain in the CI artifact.

## Correctly blocked earlier attempt

Run 41285550698 blocked signing/publishing when the debug runtime probe duplicated parent `_notification` dispatch and the single Back opened exit confirmation after closing the menu. Godot already dispatches notifications through the inheritance chain. Removing the probe's redundant super call and testing actual Object.notification fixed the test harness. No production input throttling was retained, and the original overlay=0 assertion was not relaxed.

All 624 production files remained identical between the initial candidate and the successful run: aggregate SHA256 `cdb15441bd9f33c215787c8946c5c735288aa17c15aa7b72035631c41fd7e6d7`. The updated 56-file verification range is `8f0425e27c6686499fd84205b2ad02dd9ee8c2089ae8d349c7ccdefc416d99d6`.

This evidence-only follow-up does not move the release tag or change runtime, signed APK or signing identity.
