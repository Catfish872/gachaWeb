# Android 2.6.0 release

- Runtime commit and tag: `3c8dfd1ceb21b46bd431ba45f377433da041745d`, `android-v2.6.0`.
- Published: 2026-11-01 16:57:39 UTC; latest non-prerelease verified.
- [Build and fixed-signature verification](https://github.com/Catfish872/gachaWeb/actions/runs/41328813745): both jobs successful.
- [APK](https://github.com/Catfish872/gachaWeb/releases/download/android-v2.6.0/universal.apk): 148353738 bytes.
- APK SHA256: `c15b428cce4239d2690623471733a3333baae6507bd3f4bbbcf435405e3f65f2`.
- Version: 2.6.0 / 20600; existing package and signing identity preserved. Build verifier passed package, version, SDK, permissions, ARM architectures, packaged contents and signature; APK signature schemes v2 and v3 verified.
- Reviewed production: 828 files; SHA256 `759377b06c7d41255a05e7628db48c58c3f0a9bf11f339a1f63f61ac23d78a43`.
- Focused local review: first segment 307 seconds, delta segment 188 seconds, total 495 seconds. Development time between segments excluded. Exact snapshots, timestamps and scopes: [evidence](../v260-focused/release-evidence.json).
- Actual desktop OpenGL layouts and input events were reviewed. No new full native journey or physical Android device coverage is claimed. Audio review verified decoding and interaction routes, not human listening quality.
- CI reused exact reviewed source evidence and ran only necessary release/build prerequisites; no broad gameplay suite or native emulator loop.
