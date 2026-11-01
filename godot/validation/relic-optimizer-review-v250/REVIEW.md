# Independent optimizer review — 2.5.0

This review writes only tests and evidence. The optimizer owner implements production corrections. The combat source remains at SHA-256 `814925778c78fc3a0dc9df38f02dbb5440c0d8ea39bc093db34705c20d8e73ee` throughout this review.

## Review scope

The certificate concerns the declared, fixed reference scenario. Its default action policy follows the game's ultimate/skill/normal selection. Target status coverage, neutral elements, enemy defense, speed and missing-HP assumptions remain explicit reference inputs. A separate Bellman optimization over all legal skill choices supplies an upper bound for the automatic policy. The review checks that separation, every physical candidate, the integer hit/heal formula, per-action and per-hit energy triggers, future source declarations, and preview state/RNG isolation.

## Correlated upper-bound reasoning

For nonnegative legal relic attributes, write the unrounded source as `X × Y`, where `X` is the permanent base plus flat attributes and `Y` is one plus percentage attributes. Let `C` be the bounded critical probability and `D` the excess critical multiplier. The common direct-damage scale is bounded by `XY + XYCD`. Each tree node stores the maximum weighted sum of these candidate attributes. Adding the five slot supports and constants bounds the weighted sum for every descendant. The arithmetic–geometric mean inequality then bounds the corresponding product. The additional `XYD` shape uses `C ≤ 1`. Taking the minimum of these independently valid product bounds preserves a bound; adding the base and critical terms preserves it again.

The fast skill coefficient comes from the same battle helpers at a large source value, with exact critical/energy transition probabilities and an optimal manual policy. Uniform source scaling lets the coefficient multiply the correlated attribute bound. The source/skill-floor safety check and the integer-domain checks are required for this step. Scenarios crossing a minimum-one floor or the artificial normalizer's integer conversion range use the exact Bellman path. The real candidate arithmetic range is checked before a proof can be issued.

Same-set Pareto elimination preserves different automatic-action energy schedules and critical trigger distributions. Within that preserved schedule, the retained source, critical damage and speed-condition dimensions are monotone under the fixed reference. Current-equipment and deterministic tie rules remain part of domination. The search has a complete candidate tree, cooperative cancellation and a certificate after the frontier is exhausted.

## Concrete issues found and resolved by the optimizer owner

The initial normalization scaled the minimum-one hit floor toward zero. Ember at enemy defense 100,000 had a true six-action value of 6 while its upper bound was 1.08253014154. The floor-safety predicate now selects exact Bellman evaluation for that domain. `probe.gd` reproduces this case for three current characters.

Future characters reusing Gus's energy passive exposed a mismatch between ID-based cache dependencies and passive-based battle logic. A high-critical case scored 1,937 against an upper bound of 1,732.38115857784. Dependency detection now follows the passive declaration. An independently reordered future skill array also selected 280 damage in the objective while live auto selected a 1,260-damage ultimate; explicit type-priority ordering now matches the live action policy. `edge_probe.gd` retains the fixtures.

A future survival character declaring an ATK-based shield exposed omitted survival source dimensions: an increased-ATK shield yielded 11,397.0588235294 while the cache returned 5,269.60784313726. Survival dimensions and cache dependencies now include the declared shield source. `future_shield_probe.gd` reproduces the comparison.

The original relic validator accepts large finite values. An item with `atk_flat = 10^15` and `atk_pct = 10^15` crossed the existing signed integer conversion and computed ATK 1. Attribute-only dominance removed a legal ATK-1,140 alternative, returning 541.35 with a false certificate despite a 4,411.35 alternative. The optimizer now reports an unsupported proof domain and keeps application unavailable; the original save and battle formulas remain intact. `overflow_probe.gd` preserves this fixture.

The artificial normalizer also needs its own arithmetic check. A future coefficient of `10^12` has a real score of 451,500,000,000,000 within the actual actor's integer range, while the larger artificial source overflowed and produced an upper bound near 1,535,100. The normalizer-domain guard now selects the exact path. `normalizer_probe.gd` exercises it.

JSON decimal formatting collapsed two representable speeds, 100 and 100 plus `10^-13`, into the same cache key. The actual strict speed condition changed the score from 541.35 to 648 while the old cache returned 541.35. The same representation issue applies to stat-change fingerprints. `precision_probe.gd` and the independent test cover both the objective cache and the plan snapshot boundary.

## Independent regression coverage

`tests/test_relic_optimizer_review_v250.gd` exhaustively evaluates the raw three-option-per-slot inventory for every current character at zero and six constellations. It also covers future HP/DEF damage, HP/DEF healing and ATK shield-survival characters held only in local test catalogs. It checks all 6,075 retained leaf bounds and exhaustively evaluates the descendants of 400 sampled internal boxes, including the production correlated bound path. It compares each finished certificate with the raw-inventory exhaustive oracle, so an unsafe candidate removal is visible separately from a bound error.

The focused fixtures include zero/full critical probability, energy thresholds, complete set thresholds, source rounding, minimum-one damage, integer overflow, artificial-normalizer overflow, alternate future skill ordering, passive-driven critical energy, exact cache dependencies and state/RNG purity. Final run counts and source hashes are recorded below after the final production freeze.

The precision regression also covers an explicit target slowdown. At reference speed 180, `spd_down` makes the effective target speed 126. Zeph's speeds 115 and 135 straddle the actual passive threshold even though both are below the unmodified reference speed. Raw speed is retained in lossless cache keys and in the shared normalized battle evaluation, covering this status-sensitive condition.

Additional same-set Gus and Ayla inventories each contain four raw choices per slot. Their 1,024-combination exhaustive oracles match the search after actual Pareto removals. Direct checks verify that a stronger source with the same critical/energy schedule can dominate, while changed energy or critical schedules survive pruning. This complements the correlated-bound fixtures, whose alternatives intentionally retain different set categories.

The resolved precision implementation uses lossless Variant-byte encodings for objective caches, coefficient caches, schedule groups and plan fingerprints. Fingerprint dictionaries use canonical key order, and the incremental inventory digest uses the same canonical item representation as final validation. Existing save/display JSON retains its established format. The cache and fingerprint regression cases now pass.

A singleton box may still carry a conservative upper bound while queued. Visiting that leaf computes its actual automatic-policy score through `_snapshot`; only that actual score can update the lower bound. A certificate is issued after the search frontier is exhausted through valid bound pruning or real leaf evaluation. This distinction is deliberate and mathematically sufficient; a queued singleton's optimistic value is never presented as a realized candidate score.

## Final frozen verification

The independent suite passes **6,578 checks**, including **6,075 leaf bounds**, **400 internal-box exhaustive comparisons**, and the additional same-set Pareto exhaustive oracles. Its smallest observed upper-minus-actual margin is exactly zero; every audited bound covers its actual descendant values. The optimizer's official suite passes **398 checks**, its live-battle reference suite passes **37 checks**, and the personal-set combat suite passes **685 checks**, including the 60 exact legacy event/state/RNG fingerprints. These four suites total **7,698 passing checks**.

The final optimizer SHA-256 is `5cb2805c9c007de78fde2741768ad3dac91adaa65eb6fe339d619ee47c603a1b`. The battle SHA-256 remains `814925778c78fc3a0dc9df38f02dbb5440c0d8ea39bc093db34705c20d8e73ee`. `FINAL_SOURCE_SHA256.txt` was checked against both files after the final runs. The complete final logs are `relic_optimizer_review_v250-final.log`, `relic_optimizer_v250-final.log`, `relic_optimizer_battle_v250-final.log` and `battle_relic_sets_v250-final.log` in this directory.

All concrete findings described above are resolved at these hashes. The historical counterexamples document the repair scope. The guarantee remains the declared reference objective and supported numeric domain; comparisons across different live encounters or team compositions remain separate objectives. Device interaction and release validation remain separate root-task responsibilities.
