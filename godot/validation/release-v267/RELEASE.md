# Android 2.6.7 release

- Runtime/tag: `309fee1a89b02e5806d9a0ef900ff4d1e55895e0` / `android-v2.6.7`.
- Published: 2026-11-01 20:29:45 UTC; latest stable release verified.
- [CI](https://github.com/Catfish872/gachaWeb/actions/runs/41346965677): both jobs passed; package, version, SDK, permissions, ARM architectures, contents and signature verified. APK v2/v3 signatures passed.
- [APK](https://github.com/Catfish872/gachaWeb/releases/download/android-v2.6.7/universal.apk): 148357834 bytes.
- SHA256: `5dd51c093ba1a3b9bc0c23fa40fb2bfaccccefb41977c98148bc049772af7199`.
- Version 2.6.7 / 20607; fixed package and signing identity preserved.
- Production: 828 files, SHA256 `240a44b289fcaf665dfe55b6f42f912e17c67444b05eddbd30d48901be73ff65`.
- Gameplay/model/GL tests: **not run** for this numeric/text adjustment. No new gameplay test coverage is claimed.
- Release-specific static gate reverses only exponent base/start, matching description and version replacements, then requires an exact match to 2.6.6 production. Other production edits fail; build and signature preflight remain mandatory.
- [Exact record](../v267-focused/release-evidence.json) and [diff](../v267-focused/constant-change.diff).
