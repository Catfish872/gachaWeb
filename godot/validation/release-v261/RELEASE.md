# Android 2.6.1 release

- Runtime commit/tag: `e1d9f37eea2d0f58d79eb289ecbe48c673435b18` / `android-v2.6.1`.
- Published: 2026-11-01 17:44:37 UTC; latest stable release verified.
- [CI](https://github.com/Catfish872/gachaWeb/actions/runs/41332860035): both jobs passed; package, version, SDK, permissions, ARM architectures, contents and signature verified. APK v2/v3 signatures passed.
- [APK](https://github.com/Catfish872/gachaWeb/releases/download/android-v2.6.1/universal.apk): 148353738 bytes.
- SHA256: `c018fd2307104b4530758dc4c1819c52c6897a74b3b403b79fb987638058bd1e`.
- Version 2.6.1 / 20601; same package and signing identity as previous stable releases.
- Reviewed production: 828 files, SHA256 `50dc8344246603f50f8e563f3b9a21a107eb3aaa6d0da832bd1113a0926ddfde`.
- Focused review: two actual segments, 100 + 160 = 260 seconds. [Exact evidence](../v261-focused/release-evidence.json) maps each snapshot to its affected checks. No full gameplay suite or native emulator journey was started.
- Desktop OpenGL visual/input checks cover the changed relic interfaces; no new physical-phone validation is claimed.
