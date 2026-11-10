# Current pre-build status

Final affected acceptance is complete for the declared scope. See `godot/validation/v290-final-acceptance/README.md` and the current release-evidence.json for exact source identity, timing, clean reruns and coverage limits. Music approval records the user’s audition of selected source tracks; actual in-game sound transitions remain unverified. Build, signing, installation and publication are subsequent stages.

The following sections are the historical preparation record; later final evidence supersedes their pending statuses and older hashes.

# 2.9.0 release readiness

Review timestamp and source identity are recorded in `static-review.json`. This directory is preparation material. Active version metadata is now 2.9.0 / 20900 in version.json and both export presets, with status in `candidate-metadata.json`; the release package remains `org.catfish872.voidrift` and the artifact remains `universal.apk`.

## Story approval gate: integrated

The user-approved chapter five is integrated verbatim: 40 scenes, 425 dialogue lines and metadata, 16 battles, routing after ch4_12, rewards, three CGs and scene music. Existing chapter content is preserved. See `story/INTEGRATION_RESULT.md` for the approved source hash, 886 development checks, 96 battle simulations and explicit coverage limits. Final affected checks cover approved-source equivalence, chapter progression and dialogue. Fresh-process disk persistence now covers completed chapter progress, read records, rewards, ending state and retained inventory; final logs and the refreshed source identity are in `godot/validation/v290-release-focused`. Actual visual scope is recorded below.

## Content and acquisition: implemented, focused checks passed

The catalog contains Raisa, Vika and Eve, their skills, constellations, relic objectives and three new relic sets. All three limited pools exactly match `godot/data/thunder_acquisition_patch.json`. Each costs 160 diamonds, uses 1.6% base five-star odds, soft pity 73, hard pity 90 and a 75% featured five-star chance with the next five-star guaranteed after a miss. Banner backgrounds resolve to thunder_gate, storm_market and ward_clinic. These are existing scene images paired with character presentation, rather than three independently verified finished banner compositions.

`final-test_thunder_acquisition_v290.log` reports 308 checks with zero failures on the source hashes in `combat-handoff.json`, all of which matched this checkout during static review. It covers solo and trio trials, full armor rotation, three 160-diamond solo first rewards, zero trio reward, repeated settlement rejection, isolated trial inventory and old limited pity retention. This is historical focused execution evidence, not a fresh whole-release run. Chapter development coverage includes rewards, repeated claims, prior chapter progress and read records. Final integrated runtime and separate disk write/read processes now have passing evidence; simulated victories in the persistence harness establish storage continuity rather than an actual chapter playthrough.

The description/mechanics comparison is recorded in `DESCRIPTION_AUDIT.md`; it includes skill/passive/constellation/blessing/relic scope and parameter review. Later tuning requires an affected-description recheck. `test_thunder_visuals_v290.gd` covers six armor skill descriptions and the separation of Eve recovery from team damage; that alone covers only part of all player-facing text. Review every new description against actual trigger, target, value, duration, stacking and constellation effects. Preserve the six-blessing structure per new character and shared-ID deduplication required by the release pipeline.

## Assets, banners and audio: partial rendered review; listening pending

The static scan resolved 657 `res://` references across data JSON files with zero missing resources. The icon verifier passed all 42 unique RGBA files and patch references. All ten character/action/story illustration hashes and three music hashes matched their manifests. Existing world and character manifests retain prior source-art review evidence. This pass verified file integrity, not fresh pixel inspection or runtime resource delivery.

Actual cloud GUI review used Godot 4.6.3. Raisa, Vika and Eve banners rendered at 1233×771. The trio trial showed armored Raisa, Vika, Eve, two enemy waves, the guardian, manual casts, armor duration and return to the normal portrait. Compact battle controls were usable at 864×540. Chapter five's initial stage details rendered at 1168×730. The review found clipping at 864×540, which was fixed by wrapping chapter tabs. Follow-up GUI inspection at 862×539 confirmed the complete fifth chapter tab, contained details, fixed action button and scrollable cost/reward metrics. The reviewed screenshots and exact limitations are indexed by `cloud-ui-review.md` and `cloud-ui-screenshots.json` in the final evidence directory.

The affected headless layout regression exercises six physical window sizes, all five chapters, first/last stages, repeated selection, actual mouse input, scroll retention, detail containment and re-entry in desktop and forced-mobile modes. Physical window size and logical viewport can differ through viewport scaling. Existing touch-driven story-button tests cover fixed actions while details scroll. Earlier development passes remain separately identified in `validation/v290-review/story-responsive/README.md`.

Visual acceptance remains partial: all roster/party/archive/detail/reveal/action-avatar views, individual transient action illustrations, status tooltips, reduced-animation/speed-up/disappearing-target behavior, and a full rendered chapter/interlude/ending playthrough still need review. Actual Android-device rendering and the requested exact 960×540 / 2048×945 pixel review remain pending. Geometry results establish bounds and interactions; they are separate from pixel approval.

The GUI debugger's reviewed pre-fix 39 entries contained an audio-device initialization error and warnings for dummy-audio fallback, V-Sync, shadowing, integer division, unused values and ternary types. The post-fix launch showed 38 entries, with that last list not individually re-audited. The observed battle/navigation flows completed without a runtime crash.
Music attribution and license files are present, and the export include filters already include `assets/audio/*/LICENSE*.txt`. Existing music notice review says subjective listening remains unverified for all three tracks. The cloud GUI failed to open its audio device and used the dummy driver, so subjective listening remains blocked. Listen through loop seams and audible transitions when an audio-capable environment is available. Runtime routing and teardown checks are separately recorded; they cannot establish sound quality. The core loop is 104.025 seconds and gate loop 90.464 seconds, exceeding the pipeline's nominal 60–90-second target; the world design records the complete-phrase rationale. Carry that exception explicitly into final acceptance. Packaging must later prove the notices and resources are actually included.

## Tests and balance: refreshed affected passes; acceptance pending

The current combat handoff records 80 combat, 308 acquisition, 72 optimizer, 81 automatic-ultimate, 41 wind-duo, 3,080 constructed-balance, 25,010 natural-extraction and 33,111 natural-abyss assertions. Its twelve source/test/tool hashes all match this review snapshot. Other world review logs report 491 world, 85 enemy budget, 42 world UI and 134 visual checks with zero failures, but these individual logs do not establish the exact final release snapshot. Different older logs have different check counts; use their recorded source identity rather than filename recency alone.

The same handoff discloses 19 legacy `test_battle.gd` failures and a pre-existing array-index runtime error reproduced on the pre-tuning baseline. Preserve that disclosure. The broad suite is not green; the applicable release gate uses declared affected checks. Final acceptance retains explicit scope, partial GUI coverage and the remaining listening/visual gates; the legacy failures remain disclosed.

Use the parent-coordinated affected-function and rendered-review window, recording actual segments and cumulative time up to the pipeline's ten-minute budget. The refreshed final record includes the coordinated affected story, responsive-layout, persistence and audio-teardown checks, with exact timestamps and cumulative duration. Historical development runs remain separate from the final window. After story integration or any later content change, refresh only affected checks and include the final metadata in the reviewed source hash. Retain remaining items as pending when the allowed window is exhausted.

## Release metadata and CI: prepared; acceptance pending

The integrated candidate uses 2.9.0 / 20900 in `godot/data/version.json` and both Android export presets. `godot/CHANGELOG_2.9.0.md` records the integrated scope, including chapter five. `godot/ANDROID_RELEASE.md` now describes current metadata and focused-evidence CI behavior.

`.github/scripts/verify_focused_evidence.py` is scoped to 2.9.0 / 20900 and `validation/v290-release-focused/release-evidence.json`. It requires passed targeted runtime, actual UI visual and music listening review, named affected scopes, ordered nonoverlapping timed segments, cumulative time at most 600 seconds, exact final production count and hash including version metadata. A pending record deliberately keeps signing blocked. Historical passes, headless geometry and file integrity cannot satisfy rendered or listening review.

The metadata preparation ran version validation, 14 evidence-gate tests, 8 release-preflight tests, 9 offline Android-build tests, 14 manifest tests and 7 mocked KVM lifecycle tests, all passing. Actual times and outputs are in `godot/validation/v290-release-focused/metadata-checks.json`. These are offline checks, separate from actual Android export/resource/install validation. The workflow can publish on a release-branch push when ANDROID_RELEASE_ENABLED is true; this stage stays local.

## Build and publication: later authorized stage

After approval and final acceptance, the separate build stage must verify Godot/template/toolchain prerequisites, immutable version/tag identity, production package name, fixed signing certificate, ARMv7/ARM64, permissions, resource inclusion, size and SHA-256. Confirm an existing published version cannot be overwritten. Verify the final artifact's update discovery, download, digest and covering-install behavior with the actual release when publication is authorized. This preparation performed no export, signing, packaging, upload, push or publication.

## Final refresh record

Timestamped final automated segments total 183.084822 seconds. Including the conservative 3.650-second prior persistence allocation, accounted automated time is 186.734822 seconds out of 600. GUI review durations were not supplied, so combined visual/listening acceptance timing remains pending. The current production snapshot has 1458 files with SHA-256 `ef5e41517c760b83cedf8011e54a9e8a71bed43712f0af144c6dd99ed483088a`. The story-button test initially exposed an Ogg playback resource leak at process exit after all assertions passed; a test-only mixer cleanup wait produced a clean affected rerun. Original and diagnostic logs remain preserved. No export, signing, package, push or publication was performed.
