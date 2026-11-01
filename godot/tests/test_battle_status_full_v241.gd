extends SceneTree
const Game = preload("res://scripts/game_model.gd")
const Battle = preload("res://scripts/battle_model.gd")
var catalog: Dictionary
var checks := 0
var failures: Array = []

func _init() -> void:
	catalog = JSON.parse_string(FileAccess.get_file_as_string("res://data/catalog.json"))
	test_complete_control()
	test_equal_poison()
	test_final_boss_speed()
	test_real_control_cycles()
	print("BATTLE FULL STATUS V241: %d checks, %d failures" % [checks, failures.size()])
	for label in failures: printerr("FAIL: ", label)
	quit(0 if failures.is_empty() else 1)

func ck(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func test_complete_control() -> void:
	for mode in ["story", "abyss", "extraction"]:
		for id in ["wolf", "dark_knight", "boss_flame_lord"]:
			for status in Battle.CONTROL_STATUSES:
				var data := catalog.duplicate(true)
				if status == "electrify": data["CombatRules"] = {"electrifySkipChance":1.0}
				var b = Battle.new(data)
				b.start({"enemies":[id], "isAbyss":mode == "abyss", "isExtraction":mode == "extraction", "seed":241101}, [{"id":"ayla"}])
				var target: Dictionary = b.state.enemies[0]
				ck(b.apply_status(target, status, 3) and b.apply_status(target, status, 4), "%s %s accepts full %s duration" % [mode, id, status])
				ck(target.statuses.filter(func(s): return s.id == status)[0].duration == 7, "same control duration adds to seven without boss-specific refresh")
				for step in 7:
					b._queue = [target] + b.state.allies
					b._cursor = 0
					b._events = []
					b._seek_actor()
					ck(b._events.filter(func(e): return e.type == "skip" and e.actor == target.uid).size() == 1, "%s receives control action %d" % [id, step + 1])
				ck(not b.has_status(target, status), "control expires exactly after full seven actions")
				ck(b.apply_status(target, status, 2), "new control applies immediately after expiry without forced immunity")
				ck(not b._events.any(func(e): return e.type == "resist"), "no hidden resistance event")

func test_equal_poison() -> void:
	for mode in ["story", "abyss", "extraction"]:
		var losses: Array = []
		for id in ["wolf", "boss_flame_lord"]:
			var b = Battle.new(catalog)
			b.start({"enemies":[id], "isAbyss":mode == "abyss", "isExtraction":mode == "extraction", "seed":241101}, [{"id":"ayla"}])
			# Equal-HP mechanics fixture compares status semantics, not enemy budgets.
			var target: Dictionary = b.state.enemies[0]
			target.maxHp = 1000; target.currentHp = 1000; target.stats.maxHp = 1000
			for n in 6: b.apply_status(target, "poison", 2)
			b._end_round()
			losses.append(1000 - target.currentHp)
			ck(target.statuses.filter(func(s): return s.id == "poison").size() == 6, "all six poison instances remain after first tick")
		ck(losses == [300, 300], "%s normal and boss each take six full five-percent poison ticks" % mode)

func speed(config: Dictionary, id: String = "boss_flame_lord") -> float:
	var b = Battle.new(catalog)
	var c := config.duplicate(true)
	c.enemies = [id]
	c.scaleMult = {"hpMod":1.0, "atkMod":1.0, "defMod":1.0, "spdMod":10.0}
	b.start(c, [{"id":"ayla"}])
	return b.state.enemies[0].stats.spd

func test_final_boss_speed() -> void:
	var config := {"isExtraction":true, "isBoss":true, "act":3, "finalBossStatMultiplier":1.15}
	ck(is_equal_approx(speed(config), 138.0), "marked final boss retains full fifteen-percent speed increase")
	config.erase("finalBossStatMultiplier")
	ck(is_equal_approx(speed(config), 120.0), "previously issued final-boss config retains original speed")
	config.finalBossStatMultiplier = 1.15
	for act in [1, 2]:
		config.act = act
		ck(is_equal_approx(speed(config), 120.0), "earlier-act bosses retain original speed")
	config.act = 3
	ck(is_equal_approx(speed(config, "wolf"), 120.0), "non-boss enemy ignores final-boss marker")
	config.isBoss = false
	ck(is_equal_approx(speed(config), 120.0), "non-boss encounter ignores final-boss marker")
	config.isBoss = true; config.finalBossStatMultiplier = 9.0
	ck(is_equal_approx(speed(config), 120.0), "arbitrary multiplier marker cannot raise speed boundary")
	ck(is_equal_approx(speed({"isAbyss":true}), 145.0), "abyss speed budget stays independent")
	var b = Battle.new(catalog)
	var encounter := {"isExtraction":true, "isBoss":true, "act":3, "finalBossStatMultiplier":1.15, "enemies":["boss_flame_lord", "wolf"], "scaleMult":{"hpMod":2.0, "atkMod":2.0, "defMod":2.0, "spdMod":1.0}}
	b.start(encounter, [{"id":"ayla"}])
	for index in 2:
		var enemy: Dictionary = b.state.enemies[index]
		var base: Dictionary = catalog.EnemyData[enemy.id].baseStats
		var factor := 1.15 if index == 0 else 1.0
		ck(enemy.maxHp == int(base.hp * 2.0 * factor) and enemy.stats.atk == int(base.atk * 2.0 * factor) and enemy.stats.def == int(base.def * 2.0 * factor), "only final boss body receives fifteen-percent HP attack and defense budget")
		ck(is_equal_approx(enemy.stats.spd, base.spd * factor), "only final boss body receives fifteen-percent raw speed")
	ck(b.state.config.scaleMult == encounter.scaleMult, "per-unit boss factor keeps shared encounter scales unchanged for guards")

func reward_effects(id: String, count: int) -> Array:
	for reward in catalog.AbyssData.rogue.rewards:
		if reward.id == id:
			var result: Array = []
			for n in count: result.append_array(reward.effects.duplicate(true))
			return result
	return []

func actual(ids: Array, c: int, effects: Array, floor_number: int, seed_value: int) -> Dictionary:
	var g = Game.new("")
	for id in ids:
		g.state.ownedCharacters[id] = g.default_character()
		g.state.ownedCharacters[id].level = 10
		g.state.ownedCharacters[id].constellation = c
	g.set_team(ids)
	var b = Battle.new(catalog)
	b.start({"isAbyss":true, "floor":floor_number, "difficulty":3 if floor_number > 20 else 0, "enemies":["boss_flame_lord"], "seed":seed_value}, g.battle_party(), effects)
	var result := {"phase":"", "calls":0, "rounds":0, "enemyActions":0, "enemySkips":0, "allyActions":0, "resists":0, "maxControlDuration":0, "skills":{}, "allyStats":b.state.allies.map(func(u): return u.stats.duplicate(true)), "enemySpeed":b.state.enemies[0].stats.spd, "electrifyChecks":{}}
	while b.state.phase not in ["victory", "defeat"] and result.calls < 10001:
		var step: Dictionary = b.auto_step()
		result.calls += 1
		for event in step.events:
			if event.type == "resist": result.resists += 1
			if event.type == "skip" and str(event.actor).begins_with("enemy"): result.enemySkips += 1
			if event.type == "skill":
				if str(event.actor).begins_with("enemy"): result.enemyActions += 1
				else:
					result.allyActions += 1
					result.skills[event.skill_id] = int(result.skills.get(event.skill_id, 0)) + 1
		for status in b.state.enemies[0].statuses:
			if status.id in Battle.CONTROL_STATUSES: result.maxControlDuration = maxi(result.maxControlDuration, status.duration)
	result.phase = b.state.phase; result.rounds = b.state.turn; result.electrifyChecks = b.state.controlStats.electrify.duplicate(true)
	return result

func test_real_control_cycles() -> void:
	for c in [0, 2, 6]:
		var a := actual(["ayla"], c, [], 1, 241101)
		ck(a.enemyActions > 0, "Ayla C%d actual cooldown leaves enemy actions" % c)
		ck(a.resists == 0 and a.phase in ["victory", "defeat"], "Ayla outcome occurs without immunity intervention")
		print("CONTROL ACTUAL AYLA C", c, " ", JSON.stringify(a))
	var effects := reward_effects("common_crit_blue", 11)
	effects.append_array(reward_effects("common_overdrive_gold", 6))
	var bolt := actual(["bolt"], 6, effects, 1000, 241101)
	ck(bolt.allyStats[0].cri == 1.0 and bolt.allyStats[0].spd > bolt.enemySpeed, "legal repeatable blessings provide guaranteed crit and faster initiative")
	ck(bolt.enemyActions > 0, "guaranteed-crit Bolt cannot make electrify deny every enemy action")
	ck(bolt.phase in ["victory", "defeat"] and bolt.calls < 10000, "probabilistic control battle reaches a natural terminal outcome")
	ck(bolt.resists == 0, "continuous-control witness contains no immunity workaround")
	print("CONTROL ACTUAL BOLT ", JSON.stringify(bolt))
	var static_effects := reward_effects("common_static_blue", 10)
	var static_run := actual(["ember", "zeph", "kaldi"], 6, static_effects, 100, 241102)
	ck(static_run.phase in ["victory", "defeat"] and static_run.calls < 10000, "many proc blessings resolve each action with finite event work")
	ck(static_run.resists == 0 and static_run.enemyActions > 0, "stacked proc-duration build leaves legal enemy actions without immunity")
	print("CONTROL ACTUAL STATIC ", JSON.stringify(static_run))
	var opening := actual(["ayla"], 6, reward_effects("ayla_open_freeze_gold", 10), 1, 241103)
	ck(opening.phase in ["victory", "defeat"] and opening.calls < 10000, "finite opening freeze and energy procs terminate naturally")
	print("CONTROL ACTUAL OPENING ", JSON.stringify(opening))
