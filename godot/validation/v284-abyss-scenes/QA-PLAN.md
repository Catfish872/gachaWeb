# Abyss scene rotation targeted QA (prepared, not executed)

Wait for parent freeze before runtime. One combined window <=600 seconds; stop early on completion. No campaign simulations or old full suites.

1. Pure scene selection: floors 1 and 10 default; block starts 11/21; floor20 retains11. Check roll just below .25, exactly .25, each of 15 non-default bin midpoints and last bin. No frequency sampling needed.
2. Persistence: prepare once, repeat/resume retains complete issued config, scene/background/enemies/token/seed and RNG. JSON encode/decode comparisons use decoded payload to avoid numeric Variant artifacts. Legacy activeEncounter stays exact; next newly issued encounter adopts new scene fields.
3. Each theme/depth: pool normal/elite/Boss membership, background belongs to selected scene, no missing texture. Original Battle/AbyssBalance formulas and EnemyData stats unchanged by source diff; representative actual Battle spawns verify same stats with/without scene metadata.
4. Music/UI: actual app routing for default and five themes, normal/Boss explicit track, side pages retain context. Short real-GL screenshots only representative default + lantern/wind scene, 960x540 and2048x945; no new layout redesign.
5. Record true start/end, assertions, failures/fixes, screenshots reviewed, exclusions and final production manifest. No Android hardware or subjective listening claim.
