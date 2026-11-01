# Android 2.6.5 release

- Runtime/tag: `cba8bfab2b5f5397cdcf3013976222e639a9f289` / `android-v2.6.5`.
- Published: 2026-11-01 19:52:49 UTC; latest stable release verified.
- [CI](https://github.com/Catfish872/gachaWeb/actions/runs/41343830164): both jobs passed; package, version, SDK, permissions, ARM architectures, contents and signature verified. APK v2/v3 signatures passed.
- [APK](https://github.com/Catfish872/gachaWeb/releases/download/android-v2.6.5/universal.apk): 148357834 bytes.
- SHA256: `0086cbfd928c6715ce60dcefe70da09ff2fe021a1446793ead1ad6928dcc3da4`.
- Version 2.6.5 / 20605; fixed package and signing identity preserved.
- Production: 828 files, SHA256 `19dfd698a86b98c334231d8ce05cb7949ce1cbbdb6994efb8afc8da201bc5575`.
- Gameplay/model/GL tests: **not run** for this constant-only adjustment. Prior 2.6.4 validation is background, not current gameplay test coverage.
- Release-specific static gate reverses only exponent and version replacements and requires an exact match to the verified 2.6.4 production hash. Other production edits fail; required build and signature preflight remain enabled.
- [Exact record](../v265-focused/release-evidence.json) and [constant diff](../v265-focused/constant-change.diff).
