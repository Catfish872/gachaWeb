# Android 2.8.11 item appraisals

Base: android-v2.8.10, commit 06cbf0f0b2189c57822620f6d6e1cbf7fb9a90e8.

The catalog changes 145 resale values: 136 collectibles and nine equipment/supply items that shared exactly 300 gold per cell. Individual changes remain within 10%, including integer rounding for low-price items. Intact records, worked jewelry and precision instruments receive small premiums; worn materials and bulky display pieces generally receive small discounts. Regional collectibles have their own fixed appraisals. Every copy of one item retains the same price.

All purchase prices, drop weights, rarity distributions, item dimensions, effects, categories, IDs, migration metadata and other configuration match the base. All purchasable items retain positive buy/sell margins. Existing inventory automatically uses the same catalog appraisal as new items; this small tuning does not rerun the previous fixed-price migration or change the save schema.

`weighted-pools.json` checks 216 production theme/rarity/container-category pools. All weighted expected values are exactly equal before and after. This preserves the offered-loot expectation for every unchanged act, difficulty, quality, boss bonus and rarity floor.

`packed-comparison.json` uses seed 2811009 and 1,500 identical production-generated offer sets, spanning five themes and risks 0/3/5. Each case offers 24 items and packs by value density into 30 cells with production placement. Mean retained value changes from 6422.4647 to 6406.0953 gold, −0.254876%. This is a conditional loot-only check, not a full-run estimate of combat, survival, withdrawals or player decisions.

`test-runs.json` records the final focused runtime test timestamps, durations and outcomes. The new pricing test covers fixed prices across six risks, regional substitution, fresh items, sale credits and save/reload validity. Existing boss-loot and equipment regression suites are rerun. The reward regression replaces a stale hard-coded net gain with the actual catalog value of incoming minus removed items while requiring a positive upgrade and displaced surplus gear.

Reproduce with `python tests/verify_loot_price_variation_v2811.py`, `godot --headless --path . --script tests/test_loot_price_variation_v2811.gd -- --test-session`, and `godot --headless --path . --script tools/check_loot_price_balance_v2811.gd -- --test-session`. Set writable XDG_CONFIG_HOME, XDG_CACHE_HOME and XDG_DATA_HOME when using the restricted executor.
