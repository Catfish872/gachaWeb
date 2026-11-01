# Android 2.6.2 release

- Runtime/tag: `88fef3915c8ee51b8d22598fd3aedf12f3f82d87` / `android-v2.6.2`.
- Published: 2026-11-01 18:41:13 UTC; latest stable release verified.
- [CI](https://github.com/Catfish872/gachaWeb/actions/runs/41337738832): both jobs passed; package, version, SDK, permissions, ARM architectures, contents and signature verified. APK v2/v3 signatures passed.
- [APK](https://github.com/Catfish872/gachaWeb/releases/download/android-v2.6.2/universal.apk): 148357834 bytes.
- SHA256: `966ea137f59a798c23e25d31f483f5e02d9a9fa75462a1d61fd3955cabb702c1`.
- Version 2.6.2 / 20602; same package and signing identity as preceding stable releases.
- Reviewed production: 828 files, SHA256 `8cc958b00466e81692628a626fdd0c06c6fe90368c0764469d5674ff8122966a`.
- Focused review: 74 seconds, 34 numerical checks and nine evidence-gate cases; [exact evidence](../v262-focused/release-evidence.json).
- No layout changes: short text reviewed statically, existing UI layout evidence reused. No new GL, full gameplay suite, native emulator journey or physical-device validation was run.
