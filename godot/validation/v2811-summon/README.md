# Summon preview close regression

Baseline: android-v2.8.10, commit 06cbf0f0b2189c57822620f6d6e1cbf7fb9a90e8.

The traveler-profile button sets the action cooldown to `sequence_time + 0.32`. Opening the profile pauses `sequence_time`; the return button then waits forever for that same clock. The focused native-input test reproduced the stuck return button before the fix (`reproduction.log`).

The fix exempts only `preview_close` from the paused-clock cooldown. Gesture serial and stage epoch checks remain active, and closing still applies the cooldown to subsequent actions. Draw logic, rewards, currency, animation timing and profile layout are unchanged.

`test_summon_preview_v2811.gd`: 31 checks passed. Covers native mouse input, touch plus emulated mouse, repeated reveal-profile open/return, pause/resume, landscape resize, preserved paused animation, preserved character index, summary-profile return, final accept, and unchanged committed currency/rewards.

`test_summon_presentation.gd`: 112 checks passed in headless Godot 4.6.3.

These are headless native-input tests. Android device and rendered visual verification remain separate release checks. The provided screenshot was inspected to identify the exact reveal-profile state.

`test_summon_sequence_v25.gd`: 228 checks passed, including continuous ten-pull playback, early/late input rejection, touch deduplication, skip/summary, Android Back notification, scene disposal, save-slot changes, persistence failure and insufficient funds. All three passing logs contain no script/runtime errors. Focused regression execution completed at approximately 04:16:11 UTC, within three minutes of its first baseline reproduction run.

## Rendered follow-up review

On 2026-11-05 from 04:17:10Z to 04:19:44Z (154 seconds), the fixed project was imported into the cloud desktop Godot 4.6.3 editor and run with its Compatibility renderer. Native desktop clicks at a 1233 × 771 viewport completed: summon page → single pull → revealed 冈 → traveler profile → 返回祈愿结果 → same revealed character → summary → accept → summon page. The profile return button visibly dismissed the modal. The final page showed diamonds 1440 (from 1600) and pity 1 (from 0). The affected rendered UI review passed. This was desktop rendering, rather than an Android-device run. Observations are in the CUA session history. The editor showed a preexisting Debugger(39) count before the summon test; those entries were not inspected in this focused review.

## Final restored-configuration review

The release integrator restored `project.godot` after the editor's initial default-setting normalization. From 2026-11-05 04:20:54Z to 04:22:57Z (123 seconds), the restored file was reloaded from disk, the previous game was stopped, and a fresh game process was launched. At a 1280 × 800 viewport, native clicks completed a single summon, opened 夏娜's revealed-profile modal, closed it with 返回祈愿结果, opened the summary, accepted the result and returned to the summon page. Diamonds changed once from 1440 to 1280 and pity from 1 to 2. Final rendered affected-flow review passed.

After completion, `project.godot` matched the baseline file exactly. The final production snapshot contained 1268 files with SHA256 `700763b38cbc3cbc50c43b9ddad360c9babbae7dfe8e03a4f43aece6ef427f46`, verified at 04:23:04Z. Known combined UI test segments total 437 seconds (160 + 154 + 123).
