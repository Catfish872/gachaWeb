# Android 2.7.0 release

- Runtime/tag: `0fbdf64007d110cce59a4440f4ba31265b95600a` / `android-v2.7.0`.
- Published: 2026-11-02 04:26:33 UTC; latest stable release and tag verified.
- [CI](https://github.com/Catfish872/gachaWeb/actions/runs/41388287212): both jobs passed; package, version, SDK, permissions, ARM architectures, contents and signature verified. APK v2/v3 signatures passed.
- [APK](https://github.com/Catfish872/gachaWeb/releases/download/android-v2.7.0/universal.apk): 183619846 bytes.
- APK SHA256: `6dd01b50388ac8af0171735f5a881390f516554d24352973325995a17c701d88`.
- Version 2.7.0 / 20700; existing package and signing identity preserved.
- Reviewed production: 1003 files, SHA256 `3d2d96632c5971c252a10b80fb66929c87b6a96d35b143c168686217118d349d`.
- Focused review: 04:01:15–04:10:15 UTC, 540 seconds. Selin 92 checks, story passed, abyss budget 9 checks, expedition 78 checks, release gate 9 tests; two-size desktop OpenGL 117 checks plus 10 focused UI-delta checks. [Exact evidence](../v270-focused/release-evidence.json).
- The final main/battle_fx UI-only adjustment was verified at 960×540; unchanged model and prior 960×540/2048×945 UI evidence were retained. Prior unpublished v268 fixes retain their separate 125-second evidence; the old full suite was not rerun.
- Complete old assets were restored by fixed-commit Git blob identity before the new content review. CI independently recomputed the full production snapshot before signing.
- Desktop OpenGL llvmpipe checks are not a new native Android journey or physical-device certification. Audio decoding and technical metrics do not establish subjective listening quality.
- Public source includes the content design, recurring character release guide, art provenance, and representative synthetic QA screenshots. No private feedback images or signing material are included.
