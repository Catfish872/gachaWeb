# Android 2.7.7 release

- Runtime/tag: `5f5d7e6cd451621456d17c7d5c621db5f0b8183f` / `android-v2.7.7`.
- Published: 2026-11-02 09:24:07 UTC; latest release verified.
- [CI](https://github.com/Catfish872/gachaWeb/actions/runs/41420008630): both jobs passed. Package, version, SDK, permissions, ARM architectures, contents and signature verified; APK v2/v3 passed.
- [APK](https://github.com/Catfish872/gachaWeb/releases/download/android-v2.7.7/universal.apk): 183652783 bytes.
- SHA256: `40831bc3b41e0069c442cb282e107e29aa31e7d9d1a4f4aae8667c139d9ffe48`.
- Version 2.7.7 / 20707; fixed package and signing identity preserved.
- Production: 1004 files, SHA256 `070c9d113e9d1484e9c5e37c9d1ccc78f796c1a6f6bf7b3b118615206a7267b9`.
- Focused review 09:16:30–09:17:15 UTC, 45 seconds: 67 targeted mechanism assertions passed.
- UI unchanged: prior visual evidence reused, no new GL. No broad simulation or old suite.
- Static comparison of _status_damage against actual 2.7.6 runtime is identical; function SHA256 `3e45c096654a74942689cdee7a546ed4653cb69b0c7bf66054db3b92d06c233e`. This is not a new test.
- Exact version metadata normalization links the reviewed snapshot to release. [Evidence](../v277-focused/release-evidence.json).
