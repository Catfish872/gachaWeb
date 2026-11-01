# Android 2.6.4 release

- Runtime/tag: `27073fcd1af1385dbf75d7cfa4f060188328a8a8` / `android-v2.6.4`.
- Published: 2026-11-01 19:42:35 UTC; latest stable release verified.
- [CI](https://github.com/Catfish872/gachaWeb/actions/runs/41342950482): both jobs passed; package, version, SDK, permissions, ARM architectures, contents and signature verified. APK v2/v3 signatures passed.
- [APK](https://github.com/Catfish872/gachaWeb/releases/download/android-v2.6.4/universal.apk): 148357834 bytes.
- SHA256: `d236ec02d8d8485037ce9a428457d2573514020751c4dae63f87ff02f735f47a`.
- Version 2.6.4 / 20604; fixed package and signing identity preserved.
- Reviewed production: 828 files, SHA256 `4649e81e59fcc371e48c4f0af89176caf63415fed4a601a05dc3ff14fe384571`.
- Focused review: 215 seconds; 41 model checks, 50 actual desktop OpenGL UI checks, nine evidence-gate tests. [Exact evidence](../v264-focused/release-evidence.json).
- No full gameplay suite, new Android emulator journey or physical-device validation. CI consumed exact reviewed-source evidence before required build/signature preflight.
