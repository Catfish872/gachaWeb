# Android 2.6.6 release

- Runtime/tag: `574fcadadc8cfb60db63319c1ade2ab9e99ab1ca` / `android-v2.6.6`.
- Published: 2026-11-01 20:21:59 UTC; latest stable release verified.
- [CI](https://github.com/Catfish872/gachaWeb/actions/runs/41346328230): both jobs passed; package, version, SDK, permissions, ARM architectures, contents and signature verified. APK v2/v3 signatures passed.
- [APK](https://github.com/Catfish872/gachaWeb/releases/download/android-v2.6.6/universal.apk): 148357834 bytes.
- SHA256: `231d375968233deb0042b07b4073fc2c7d12918384acce113dc8c27f2c0963d0`.
- Version 2.6.6 / 20606; fixed package and signing identity preserved.
- Production: 828 files, SHA256 `7c0bb768d0a6949750056fe3ad7315d1329d186f97728a72b80a0609b8bcd853`.
- Gameplay/model/GL tests: **not run** for this numeric/text adjustment. No new gameplay test coverage is claimed.
- Release-specific static gate reverses only the exponent start, matching description and version replacements, then requires an exact match to the 2.6.5 production hash. Other production edits fail; build and signature preflight remain mandatory.
- [Exact record](../v266-focused/release-evidence.json) and [diff](../v266-focused/constant-change.diff).
