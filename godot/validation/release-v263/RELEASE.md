# Android 2.6.3 release

- Runtime/tag: `e3ce9eff514124541d7dbce28f1dccf36fbb3fb6` / `android-v2.6.3`.
- Published: 2026-11-01 18:59:17 UTC; latest stable release verified.
- [CI](https://github.com/Catfish872/gachaWeb/actions/runs/41339256098): both jobs passed; package, version, SDK, permissions, ARM architectures, contents and signature verified. APK v2/v3 signatures passed.
- [APK](https://github.com/Catfish872/gachaWeb/releases/download/android-v2.6.3/universal.apk): 148357834 bytes.
- SHA256: `74ae10239f88010fba4d1c91b1badf5b04c48349093020882fc757aa8e3313d1`.
- Version 2.6.3 / 20603; same package and signing identity as preceding stable releases.
- Production: 828 files, SHA256 `eddc7fd0de1f548b8f243ff13a92c45bf45c9e2eb262ec26fd0efe8b66283031`.
- Gameplay/model/GL tests: **not run** for this constant-only adjustment. Prior 2.6.2 validation is background, not evidence of current gameplay testing.
- The release-specific static gate reverses only the exponent and version replacements, then requires an exact match to the verified 2.6.2 production hash. Any other production edit fails. Build and signature preflight remain mandatory.
- [Exact record](../v263-focused/release-evidence.json) and [constant diff](../v263-focused/constant-change.diff).
