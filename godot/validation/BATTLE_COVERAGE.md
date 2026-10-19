> 历史记录：以下为 Godot v1 迁移验收。v2 有意调整的玩法以 README、BALANCE_V2 和 VERIFICATION 为准。

# Native battle port: implementation and verified coverage

## Runtime and API

`BattleModel` is a pure Godot 4.6.3 `RefCounted` simulation in `scripts/battle_model.gd`. It uses a per-instance seeded `RandomNumberGenerator`; there are no JS timers, browser calls, scene nodes, global saves, or recursive turn advancement. `start`, `act`, `auto_step`, `current_actor`, `available_actions`, and `legal_targets` provide the public combat API. The original config is deep-copied into state so settlement tokens survive. All supplied party data is copied rather than mutated.

Units expose stable unique `uid` values (including duplicate enemy templates), source character/enemy `id`, max/current HP, energy, stats, cooldowns, status instances, numeric remaining shield, boss phase, and skill IDs. Events carry `type`, `actor`, `target`, `amount`, and `text`, with skill, element, critical, status, and overflow details where applicable. The bounded rolling log keeps the last 300 events.

## Tested

Run from the project directory:

    XDG_DATA_HOME=/tmp/gacha-test-data XDG_CONFIG_HOME=/tmp/gacha-test-config XDG_CACHE_HOME=/tmp/gacha-test-cache godot --headless --path . --script res://tests/test_battle.gd

The suite runs actual simulation, not static string checks:

- All 30 source player skills: normal/skill/ultimate, ownership, energy consumption/cap, cooldowns, concrete guaranteed damage/heal/status effects.
- All 23 enemy skills, each through `auto_step`, with concrete damage/status assertions.
- All 12 statuses: burn, freeze, stun, poison, electrify, regen, attack/defense buffs, speed debuff, shield, invincibility, taunt. Status stacking, additive durations, expiry, absorption, DOT death, and control skips are checked.
- All 10 passives and all 10 character-specific C6 effects; generic C1/C2/C3/C5 modifiers. C4 numeric HP/DEF progression belongs to GameModel.
- All 20 rogue reward definitions exercised. The 19 in-battle rewards have concrete stat/status/heal/damage/energy assertions. `victoryHealPct` is deliberately delegated to GameModel settlement, and is not applied twice by BattleModel.
- Manual enemy/ally targeting; multi-effect target consistency; invalid-action atomicity; defensive/aggressive/boss AI behavior; enemy-first opening; phase-two boss skills; chain targets/decay; element advantage and defense piercing.
- All 10 source stages reach victory with a strong test party; three custom waves transition; ordinary defeat occurs; two runs with the same seed produce identical event trace hashes.
- A 1,000-action attrition battle terminates at its configured safety cap. Production default is 10,000 actions, configurable within 10–100,000. A separate 300-iteration guard prevents a single action's control/death bookkeeping from blocking the UI.
- Abyss stat curves; carried health ratio and full inflated HP across floors; dead carried units remain dead; fractional relic speed is preserved; story battles ignore rogue rewards; combined incoming damage multipliers retain the source 10% floor.

## Explicit intentional differences and completed source omissions

This is a native migration with deliberate corrections and completions, rather than byte-for-byte parity with accidental behavior:

1. The source implements Kaldi/Ayla/Gus/Shana passives but only describes Lorin/Ember/Zeph/Bolt/Tide/Cinder passives. All ten now work. New behavior follows character descriptions: Lorin probabilistic block, Ember normal-hit burn, Zeph above-average-speed ATK, Bolt critical electrify, Tide end-round recovery, Cinder burn-target ability damage.
2. The source implements only Kaldi/Ayla C6 hooks. Added the other eight from their descriptions: Gus bounded nonrecursive extra normal hit, Shana overheal shield, Lorin once-per-battle trigger-hit immunity, Ember increased burn chance/energy, Zeph slowest-teammate ATK, Bolt electrify damage, Tide doubled healing, and Cinder enhanced burn damage. Gus's extra hit cannot recursively generate more extra hits and does not consume another action or grant normal-action energy. Cinder's bonus applies to skill and ultimate abilities, not normal attacks. Lorin's C6 checks incoming direct damage before shield absorption and blocks the triggering hit.
3. Source shield absorption is followed by a minimum 10% raw damage floor. Native shields fully absorb their remaining capacity; the minimum 10% damage rule still applies to ordinary damage-reduction modifiers, separately from shields. This is a deliberate balance correction.
4. Native invincibility blocks both direct damage and DOT, matching its advertised immunity. The source's DOT routines bypassed invincibility.
5. Freeze, stun, and electrify each consume duration when the victim actually skips an action. First actors obey control effects. This fixes missed first-actor checks and one-turn control expiring before an already-acted target's next action. Stun's DEF penalty ends when its last skipped action is consumed. Other durations and cooldowns retain end-of-round settlement, including the source timing for Ayla's passive.
6. Electrify now prevents action, as its registered description states. A source comment mentions hurting the next actor, but contains no implemented coefficient or targeting rule; no arbitrary bounce-damage rule has been invented.
7. A selected single target is retained across an ability's damage and status effects, and a selected/lowest-health ally is retained across healing and its subsequent status. The source recalculates targets for every effect and can heal one ally but buff another.
8. Enemy single-target damage honors taunt. Area attacks remain area attacks; source redirected entire enemy AOE attacks to a lone taunter. The reversed `wolf_howl` target now buffs the wolf's own side.
9. Rogue effects only run during an Abyss battle; source hook lookup could leak active Abyss rewards into story battles. Declared rogue SPD boosts and relic energy gain now affect battle. Additive energy percentage bonuses from relics and rogue rewards form one energy-gain bucket.
10. HP carryover preserves the saved inflated maximum-HP ratio and never revives a dead unit merely because a stat reward exists. Battle input's saved maximum is used before clamping carried HP. Source stat reward application forced at least 1 HP.
11. All configured waves are supported; source battle initialization uses a single enemy list. The original ten stages currently contain one wave each.
12. Terminal states are stable and repeated `auto_step` is harmless. Safety-cap exhaustion produces an explicit defeat reason rather than an infinite battle.

## Preserved data limitations

The original `witch_summon` is an attack buff, not a real summon mechanic. Cinder's skill data applies nonstacking burn with additive duration despite its prose mentioning two layers. These data definitions are retained. `synergyIds` contain names but the source supplies no synergy effect definitions or executable subsystem; no new team-synergy numbers were invented. There is no resurrection skill in the original data. Rewards, progression, saves, and victory healing are GameModel responsibilities.
