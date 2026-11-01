extends SceneTree
const Game = preload("res://scripts/game_model.gd")
const Battle = preload("res://scripts/battle_model.gd")
var catalog: Dictionary
var checks := 0
var failures: Array = []

func _init() -> void:
	catalog = JSON.parse_string(FileAccess.get_file_as_string("res://data/catalog.json"))
	test_config_and_source_bonuses()
	test_cache_and_queries()
	test_duration_and_lifecycle()
	test_paired_boss_probability()
	test_long_actual_builds()
	print("ELECTRIFY PROBABILITY V241: %d checks, %d failures" % [checks, failures.size()])
	for label in failures: printerr("FAIL: ", label)
	quit(0 if failures.is_empty() else 1)

func ck(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func near(a: float, b: float, label: String) -> void:
	ck(absf(a - b) < 0.000001, "%s actual=%s expected=%s" % [label, a, b])

func arena(chance: float = 0.35, enemy: String = "boss_flame_lord", effects: Array = []):
	var data := catalog.duplicate(true)
	data["CombatRules"] = {"electrifySkipChance":chance}
	var b = Battle.new(data)
	b.start({"enemies":[enemy], "isAbyss":true, "floor":1, "seed":241109}, [{"id":"ayla"}, {"id":"bolt"}], effects)
	return b

func aim(b, unit: Dictionary) -> void:
	b._queue = [unit] + (b.state.allies if not unit.isAlly else b.state.enemies)
	b._cursor = 0
	b.state.currentActor = unit.uid
	b.state.phase = "player_turn" if unit.isAlly else "enemy_turn"

func test_config_and_source_bonuses() -> void:
	near(Battle.electrify_chance_for_status(catalog), 0.35, "single catalog configuration sets default thirty-five percent")
	for chance in [0.0, 0.35, 1.0]:
		var b = arena(chance)
		var target: Dictionary = b.state.enemies[0]
		b.apply_status(target, "electrify", 2, null, b.state.allies[0])
		near(b.electrify_skip_chance(target), chance, "configured probability reaches actual status")
	var b = arena(0.35, "boss_flame_lord", [{"type":"electrifySkipChanceBonus", "value":0.1}, {"type":"electrifySkipChanceBonus", "value":0.05, "characterId":"bolt"}])
	var source: Dictionary = b.state.allies[0]
	var target: Dictionary = b.state.enemies[0]
	b.catalog.CharacterData.ayla.combatModifiers = {"electrifySkipChanceBonus":0.1}
	source.stats.electrifySkipChanceBonus = 0.15
	b.apply_status(target, "electrify", 2, null, source)
	near(b.electrify_skip_chance(target), 0.70, "future character plus stat plus matching effect bonuses add")
	for n in 10: b.apply_status(target, "electrify", 2, null, source)
	near(b.electrify_skip_chance(target), 0.70, "repeated same-source status extends duration without multiplying probability")
	ck(target.statuses.filter(func(s): return s.id == "electrify").size() == 1 and target.statuses[0].duration == 22, "reapplication keeps one full-duration status instance")
	b.apply_status(target, "electrify", 1, null, b.state.allies[1])
	near(b.electrify_skip_chance(target), 0.70, "weaker new source preserves stronger probability snapshot")
	b.state.allies[1].stats.electrifySkipChanceBonus = 0.6
	b.apply_status(target, "electrify", 1, null, b.state.allies[1])
	near(b.electrify_skip_chance(target), 1.0, "stronger source replaces snapshot with only natural hundred-percent probability bound")
	near(Battle.electrify_chance_for_status(catalog, {"electrifySkipChanceBonus":-0.8}), 0.0, "negative modifier uses only physical zero probability bound")

func test_cache_and_queries() -> void:
	var b = arena()
	var target: Dictionary = b.state.enemies[0]
	b.apply_status(target, "electrify", 3)
	aim(b, target)
	b.rng.seed = 241109
	var mirror := RandomNumberGenerator.new()
	mirror.state = b.rng.state
	var expected_skip := mirror.randf() < 0.35
	b._prepare_control_check(target)
	ck(b.rng.state == mirror.state and b._controlled(target) == expected_skip, "actual opportunity consumes exactly one RNG draw")
	var rng_state: int = b.rng.state
	var decision: Dictionary = b.control_decision(target)
	var counts: Dictionary = b.state.controlStats.duplicate(true)
	for n in 100:
		b.available_actions(); b._available(target); b._controlled(target)
		b.legal_targets(target.skills[0]); b.electrify_skip_chance(target); b.control_decision(target)
		Battle.electrify_chance_for_status(b.catalog, target.statuses[0])
		b._prepare_control_check(target)
	ck(b.rng.state == rng_state and b.control_decision(target) == decision and b.state.controlStats == counts, "all UI legality and probability queries plus repeated preparation preserve RNG and cached result")
	b.apply_status(target, "electrify", 5)
	b._prepare_control_check(target)
	ck(b.rng.state == rng_state and b.control_decision(target).electrifySkip == expected_skip and b.state.controlStats == counts, "refreshing status in same opportunity cannot reroll or count twice")
	b._steps += 1
	b._prepare_control_check(target)
	ck(b.control_decision(target).token != decision.token and b.state.controlStats.electrify.boss.opportunities == 2, "new actual opportunity receives a new cached decision")
	for chance in [0.0, 1.0]:
		b = arena(chance); target = b.state.enemies[0]
		b.apply_status(target, "electrify", 2); aim(b, target)
		rng_state = b.rng.state
		b._prepare_control_check(target)
		ck(b._controlled(target) == (chance == 1.0) and b.rng.state == rng_state, "zero and hundred percent are deterministic without unnecessary RNG draws")

func test_duration_and_lifecycle() -> void:
	var b = arena(0.0)
	var target: Dictionary = b.state.enemies[0]
	b.apply_status(target, "electrify", 1); aim(b, target); b._seek_actor()
	ck(b.current_actor().uid == target.uid and b.has_status(target, "electrify"), "missed shock roll allows ordinary action with status still present until completion")
	b.auto_step()
	ck(not b.has_status(target, "electrify") and b.state.controlStats.electrify.boss.opportunities == 1, "missed shock consumes one duration on successful action")
	b = arena(1.0); target = b.state.enemies[0]
	b.apply_status(target, "electrify", 2)
	for n in 2: aim(b, target); b._seek_actor()
	ck(not b.has_status(target, "electrify") and b.state.controlStats.electrify.boss.skips == 2, "successful shock consumes one duration per skipped action")
	aim(b, target); b._seek_actor()
	ck(b.current_actor().uid == target.uid and not b._controlled(target), "expired status cannot inherit a cached skipped result")
	b = arena(); target = b.state.enemies[0]
	b.apply_status(target, "electrify", 2); b.apply_status(target, "freeze", 1)
	aim(b, target)
	var rng_state: int = b.rng.state
	b._seek_actor()
	ck(b.rng.state == rng_state and b.state.controlStats.electrify.boss.opportunities == 0, "deterministic freeze resolves without an extra electrify roll")
	ck(not b.has_status(target, "freeze") and target.statuses.filter(func(s): return s.id == "electrify")[0].duration == 1, "mixed control consumes one complete action duration from each present status")
	b = arena(1.0); target = b.state.enemies[0]
	b.apply_status(target, "electrify", 2); aim(b, target); b._prepare_control_check(target)
	ck(b._controlled(target), "lifecycle fixture starts with cached skip")
	target.statuses = []; b._cleanup_statuses(target)
	ck(not b._controlled(target), "removing status immediately removes cached control effect without reroll")
	b.apply_status(target, "electrify", 1); target.currentHp = 0; b._report_deaths()
	ck(b.control_decision(target).is_empty() and not b._controlled(target), "death clears cached action result")
	target.currentHp = target.maxHp
	b._steps += 1
	b.catalog.CombatRules.electrifySkipChance = 0.0
	aim(b, target); b._prepare_control_check(target)
	ck(not b._controlled(target) and b.control_decision(target).chance == 0.0, "revived unit gets the new opportunity configuration rather than stale skip")
	b.start({"enemies":["wolf"], "seed":241110}, [{"id":"ayla"}])
	ck(b.state.controlStats.electrify.boss.opportunities == 0, "new battle resets counters and action cache")

func test_paired_boss_probability() -> void:
	var ordinary = arena(0.35, "wolf")
	var boss = arena(0.35, "boss_flame_lord")
	var a: Dictionary = ordinary.state.enemies[0]
	var z: Dictionary = boss.state.enemies[0]
	ordinary.apply_status(a, "electrify", 10001); boss.apply_status(z, "electrify", 10001)
	aim(ordinary, a); aim(boss, z)
	ordinary.rng.seed = 241100; boss.rng.seed = 241100
	var paired := true
	for n in 10000:
		ordinary._steps = n; boss._steps = n
		ordinary._prepare_control_check(a); boss._prepare_control_check(z)
		paired = paired and ordinary._controlled(a) == boss._controlled(z)
	ck(paired and ordinary.rng.state == boss.rng.state, "boss and normal targets have identical seeded per-opportunity probability")
	var stats: Dictionary = boss.state.controlStats.electrify.boss
	var rate: float = float(stats.skips) / stats.opportunities
	ck(rate > 0.33 and rate < 0.37 and stats.opportunities == 10000, "ten-thousand genuine cached decisions match thirty-five percent without resistance")
	print("ELECTRIFY PAIRED 10000 decisions skips=", stats.skips, " rate=", rate)

func reward_effects(id: String, count: int) -> Array:
	for reward in catalog.AbyssData.rogue.rewards:
		if reward.id == id:
			var result: Array = []
			for n in count: result.append_array(reward.effects.duplicate(true))
			return result
	return []

func test_long_actual_builds() -> void:
	for profile in ["critical_bolt", "ten_static"]:
		var totals := {"opportunities":0, "skips":0, "enemyActions":0, "battles":0, "maxRounds":0}
		for seed_value in range(241200, 241232):
			var g = Game.new("")
			var ids: Array = ["bolt"] if profile == "critical_bolt" else ["ember", "zeph", "kaldi"]
			for id in ids:
				g.state.ownedCharacters[id] = g.default_character()
				g.state.ownedCharacters[id].level = 10; g.state.ownedCharacters[id].constellation = 6
			g.set_team(ids)
			# Real uncapped reward definitions supply a survivable late-game build.
			var effects := reward_effects("common_hp_white", 100)
			effects.append_array(reward_effects("common_def_white", 100))
			effects.append_array(reward_effects("common_guard_gold", 10))
			effects.append_array(reward_effects("common_vampiric_blue", 10))
			effects.append_array(reward_effects("common_overdrive_gold", 6))
			if profile == "critical_bolt": effects.append_array(reward_effects("common_crit_blue", 11))
			else: effects.append_array(reward_effects("common_static_blue", 10))
			var b = Battle.new(catalog)
			b.start({"isAbyss":true, "floor":1000, "difficulty":3, "enemies":["boss_flame_lord"], "seed":seed_value}, g.battle_party(), effects)
			var calls := 0
			while b.state.phase not in ["victory", "defeat"] and calls < 10001:
				var step: Dictionary = b.auto_step()
				for event in step.events:
					if event.type == "skill" and str(event.actor).begins_with("enemy"): totals.enemyActions += 1
				calls += 1
			var stats: Dictionary = b.state.controlStats.electrify.boss
			totals.opportunities += stats.opportunities; totals.skips += stats.skips; totals.battles += 1; totals.maxRounds = maxi(totals.maxRounds, b.state.turn)
			ck(b.state.phase in ["victory", "defeat"] and calls < 10000, profile + " actual unmodified battle reaches terminal outcome")
		var rate: float = float(totals.skips) / maxi(1, totals.opportunities)
		ck(totals.opportunities >= 500 and rate > 0.30 and rate < 0.40 and totals.enemyActions > 0, profile + " actual long-build opportunities match probability and include enemy actions")
		print("ELECTRIFY LONG ACTUAL ", profile, " ", JSON.stringify(totals), " rate=", rate)
