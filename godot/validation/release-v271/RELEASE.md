# Android 2.7.1 release

- Runtime/tag: `e647a71f4d34de33cd691a371cb0df96fdb40440` / `android-v2.7.1`.
- Published: 2026-11-02 05:02:58 UTC; latest stable release and tag verified.
- [CI](https://github.com/Catfish872/gachaWeb/actions/runs/41391600494): both jobs passed; package, version, SDK, permissions, ARM architectures, contents and signature verified. APK v2/v3 signatures passed.
- [APK](https://github.com/Catfish872/gachaWeb/releases/download/android-v2.7.1/universal.apk): 183623942 bytes.
- SHA256: `2938b568d7634081ef4ce9cb0ca900a4b433cfc6c99cdb912070626fcfae2c23`.
- Version 2.7.1 / 20701; fixed package and signing identity preserved.
- Release production: 1003 files, SHA256 `97861c3b2a8482d9f236fbc2d3dd520db030e638917e1dc285e0f372d14ff85c`.
- Focused narrative review: 04:45:20–04:46:45 UTC, 85 seconds; schema whitelist and 23 desktop OpenGL 960×540 assertions, with two screenshots reviewed.
- Tested snapshot: `89a93b8c7f392c79cf1a66706059728d48c527e03976cadf8b2ad2c3f35800a2`. Only version.json and export_presets.cfg release metadata changed afterward; CI reverses these exact fields and requires the original tested hash before signing.
- [Exact evidence](../v271-focused/release-evidence.json). Existing gameplay coverage is reused; no full suite, new model test suite, native emulator journey or physical-device test was run.
- The GL harness reported XServer and shutdown resource warnings, with all scoped assertions passing.
