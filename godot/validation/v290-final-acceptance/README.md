# Final publication scope

Optional original audio archives and parts are excluded from this release commit. Runtime resources remain byte-identical. Source URLs, licenses and expected SHA-256 values are retained. To rebuild audio, run `python3 godot/tools/audio/restore_thunder_sources.py --download`; each original is fetched from its recorded public source and validated before use. The helper also explains manual retrieval when an original is missing. Tests cover existing source verification, explicit retrieval with mocked transport, missing-source guidance and safe mismatch handling. The archive-related section below is historical, superseded by this narrowed scope.

# Final pre-build acceptance

Version 2.9.0 / 20900. Production snapshot: 1462 files, SHA-256 `f1ad9ee526183e7f6b88b9454e947b51c4c0538f5257cb0477389aef9ddab600`. The working tree is uncommitted; HEAD is the prior 2.8.12 baseline, so this content hash identifies the candidate.

The unified run executed 27 commands in 131.634461 seconds. All gameplay assertions passed. One desktop CG exit-only resource diagnostic was retained and resolved by a test-only audio-mixer cleanup wait; both CG modes then reran cleanly. Separate-process chapter persistence passed 36 write and 31 read checks. The updated evidence gate passed 16 unit tests. Timed final segments including earlier affected acceptance total 329.789754 seconds; with the prior conservative persistence allocation, 333.439754 seconds, below 600.

The graphical report covers character pages, archive and party portraits, armor actions, status details, opening/final/interlude/ending samples, reveal lifecycle, animation interruption and full ten-pull input. Exact-size captures include 960×540 and 2048×945. Full 40-scene rendered playthrough and every tooltip were not tested. Chapter correctness and progression have separate runtime/data evidence.

Music selection is approved by the user after source auditions. The five selected recordings pass decoding, identity, signal metrics and runtime routing checks. Actual audible in-game loop transitions/crossfades remain unverified because cloud audio output is unavailable. Gate fields explicitly separate approved selection and programmatic audio checks from subjective in-game listening.

No build, signing, packaging, push or upload occurred. Actual APK resource inclusion, package/version/certificate/architecture checks, installation and covering upgrades remain subsequent build/delivery verification. Historical broad-suite failures remain disclosed in READINESS.md.

Full commands, times, outputs, original failure and clean reruns are in this directory. Previous acceptance is archived as previous-release-evidence.json; current gate record is mirrored in v290-release-focused/release-evidence.json.

## Source archive transport verification

Three large original recordings are preserved as lossless 8 MiB parts. Reconstruction matched original bytes, repeat restoration passed, and an existing mismatched file was preserved and rejected. Runtime assets and production SHA-256 remain identical. This affected check took 1.76983 seconds; updated cumulative acceptance including the prior allocation is 335.209584 seconds.
