# Extraction UI 2.4 verification

Production ownership: `scripts/ui/extraction_view.gd`, `scripts/ui/inventory_grid.gd`.
Model/economy, global UI/audio and native QA are owned separately. This checkout contained released dirty work before this round; no reset or push was performed.

## Changes

Search details now retire the exact consumed/moved UID and its buttons. Equipped-item replacement shows each old item's own texture and full effect, including atomic bag-to-equipped swaps. Shop categories, persistent carried value (bag plus tactical equipment), a three-card run value breakdown, and quick consumables provide direct access. Detail columns scroll independently; modal close/confirm bars are fixed where applicable.

Explicit move mode supports rotate, colored valid/blocked footprint, then tapping the exact target cell. Normal touch drags remain scrolling, and canceled/blocked placements leave the model untouched. Exact container pickup and manual exchange use transactional model APIs; manual exchange permits lower value. Automatic optimization remains separate.

The independent keyring displays type stacks and purchases at permitted stations. Recycling uses an explicit preview and selection; the low-rarity shortcut selects only ordinary loot. Collection now counts and displays only gold/red definitions, with lit art plus check marks versus dark silhouettes plus locks. Old lower-rarity collection records remain untouched. One-click collection previews one lowest-appraisal item per new eligible type; sell-all previews the entire warehouse and total value, keeping equipped items and keyring outside its scope.

Inventory hit-testing follows the visible animated rectangle in reverse draw order. Batch mode clears the old single-item focus and handles native touch once (its emulated mouse companion is ignored by the grid). A visible-UID proof uses a scrolled warehouse with a one-cell gold item and a book, both checked after native ScreenTouch input.

## Evidence

Headless focused suites: `test_looting_feedback.gd` 79 checks and `test_redesign_inventory.gd` 138 checks clean. New interaction suite is maintained by the QA agent and its final run is reported separately.

Actual cloud GL screenshots: `/workspace/scratch/8f1fc457a062/loot-v240/`, rendered at 960×540, 1170×540 and 1600×720. This includes search selection/consumption/replacement/manual placement, quick supplies, keys, exchange with negative value, value breakdown and recycling. Stash proof screenshots include `stash-multi-gold-book.png`, `stash-collect-preview.png`, `stash-sell-all-preview.png`, and `stash-collection-lit-silhouette.png`.

These are deterministic test fixtures rendered by production UI, not a user's save. `stash-gl.log` identifies both checked UIDs. During review a quick-supply return button was initially clipped; it was moved to the fixed modal footer and the actual GL screenshot was rechecked. Exchange confirm/cancel were placed together to avoid the extra clipped row. Godot's unsupported V-Sync warning under Mesa is environmental; final logs are checked for script/runtime errors.

Physical Android verification and publishing belong to the parent task.

Final actual-GL suites passed: interaction 280, touch 23, services 87, collection 174 checks, all with zero failures. The updated interaction assertion verifies the same incoming UID's appraised value in its manual-exchange title, not only the transaction result. Review found and corrected a base-definition/instance-price mismatch in manual exchange, placement and equipped-item details. `RewardRarity.decorate` is now applied to extraction blessing choices and acquired builds; actual 960×540 screenshots verify rarity badges, outlines and decorative corners without covering text.

Latest follow-up is still under verification: recycling gained explicit space-making (lowest unit value, eligible loot only, target 30% free) and all-loot preview shortcuts plus a full-value/discounted-value comparison at the boss exit. Headless services reached 161 checks. A later GL interaction run exposed a touch-placement timing failure and an animation-observation timing issue; these are being instrumented, so the historical passes above are not the final release gate. One attempted service rerun encountered another owner's incomplete game-model edit and was stopped at initialization; its log is retained separately in the scratch workspace.

The instrumented final GL interaction rerun passed 283 checks, including three consecutive full touch-drag sequences with exact UID coordinates unchanged and placement mode retained. No production delay or relaxed drag condition was introduced. The earlier one-off drag failure was not reproduced; its root cause remains unconfirmed and the original log is retained as `loot-v240-interaction-timing-investigation.log` in scratch. Flight observation now listens for the newly added TextureRect being assigned its exact transfer UID, since production adds the icon before naming it; this avoids both frame-count expiry and pre-name observation false negatives.

## Final closeout

Latest actual GL passes supersede earlier counts: interactions 283, inventory touch 23, services 161, collection/shop categories 572, all zero failures. The boss-exit comparison uses two distinct non-overlapping labels and shows the chosen full value beside the 60% payout; the amount shares a line with its coin icon, keeping the selected-art preview and fixed footer visible. Screenshots `v24-loot-salvage-space-preview.png` and `v24-loot-salvage-boss-exit-comparison.png` were personally inspected after the final run. The former selects nine low-unit-value loot cells from a full thirty-cell bag; the latter explicitly flags the selected gold item and leaves medicine/equipment unselected. Only confirmation commits either shortcut.

The latest four GL logs are archived in this directory. The original transient failure and first detailed touch trace remain in scratch for diagnosis; the final three consecutive drag checks passed without changing the production drag condition.

### 2026-11-01 09:38 UTC — vertical scroll ownership correction

QA reproduced a separate deterministic gesture bug: a vertical drag originating inside the warehouse grid was consumed by the main scroller, including release, leaving the grid's pointer ownership active. The next tap merely released stale state. The before-fix trace is retained in `native-scroll-before-fix.log`.

The main scroller now cancels the matching child pointer gesture immediately when vertical scroll ownership is established. `InventoryGrid.cancel_pointer_gesture(touch_index)` clears only transient press/drag state; it performs no selection or placement. Horizontal gestures and explicitly owned multiselect gestures retain their existing routing. `native-scroll-headless.log` records 34 passing checks, including released state before the next tap and that tap selecting the exact visible UID. Regressions: input dispatch 15/0, mobile UI 533/0, inventory touch 23/0. Actual GL verification is pending as of this entry.

Actual cloud OpenGL rerun completed at 09:39 UTC: `native-scroll-gl.log` records all 34 checks passing, with touch ownership cleared before the first post-scroll tap and that tap selecting its exact UID.
