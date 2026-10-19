extends SceneTree
const Game = preload("res://scripts/game_model.gd")
const Battle = preload("res://scripts/battle_model.gd")
const Balance = preload("res://scripts/abyss_balance.gd")
var checks := 0
var failures: Array = []
var catalog: Dictionary

func _init() -> void:
	catalog = JSON.parse_string(FileAccess.get_file_as_string("res://data/catalog.json"))
	test_curves_and_modifiers()
	test_replay_and_enrage()
	test_control_resolve()
	test_new_effects()
	test_auto_healing()
	test_carried_health()
	test_real_outcomes()
	print("BALANCE V2 TESTS: %d checks, %d failures" % [checks, failures.size()])
	for failure in failures: printerr("FAIL: ", failure)
	quit(0 if failures.is_empty() else 1)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func near(a: float, b: float, label: String, tolerance: float = 0.0001) -> void:
	check(absf(a - b) <= tolerance, "%s actual=%s expected=%s" % [label, a, b])

func hero(id: String, level: int = 1) -> Dictionary:
	var m = Game.new("")
	m.state.ownedCharacters[id] = m.default_character()
	m.state.ownedCharacters[id].level = level
	return {"id": id, "stats": m.computed_stats(id)}

func arena(effects: Array = [], enemy: String = "wolf") -> Variant:
	var b = Battle.new(catalog)
	b.start({"isAbyss": true, "floor": 10, "enemies": [enemy], "seed": 1901}, [hero("kaldi"), hero("tide"), hero("ayla")], effects)
	return b

func test_curves_and_modifiers() -> void:
	for id in catalog.EnemyData:
		var previous := Balance.scale(1, catalog.EnemyData[id])
		for floor_number in [2, 3, 5, 10, 15, 20, 50, 100, 10000, 2000000000]:
			var current := Balance.scale(floor_number, catalog.EnemyData[id])
			for key in ["hpMod", "atkMod", "defMod", "spdMod"]:
				check(is_finite(current[key]) and current[key] >= previous[key], "%s floor%d monotone finite %s" % [id, floor_number, key])
			previous = current
		var b = Battle.new(catalog)
		b.start({"isAbyss": true, "floor": 10000, "enemies": [id], "encounterModifier": Balance.modifier("swift")}, [hero("kaldi")])
		check(b.state.enemies[0].stats.spd <= Balance.MAX_ENEMY_SPEED, id + " final speed cap after encounter modifier")
	var low := Balance.scale(1)
	var high := Balance.scale(20)
	near(low.hpMod, 0.90, "floor1 HP budget")
	near(high.hpMod, 2.99, "floor20 HP budget")
	near(high.atkMod, 1.705, "floor20 attack budget")
	near(high.defMod, 1.192, "floor20 defense budget")
	near(high.spdMod, 1.152, "floor20 speed budget")
	check(high.hpMod / low.hpMod > high.atkMod / low.atkMod, "HP grows faster than attack")
	for mod in Balance.MODIFIERS:
		var b = Battle.new(catalog)
		b.start({"isAbyss": true, "floor": 10, "enemies": ["wolf"], "scaleMult": 5.0, "encounterModifier": Balance.modifier(mod)}, [hero("kaldi")])
		var expected := Balance.apply_modifier(Balance.scale(10, catalog.EnemyData.wolf), mod)
		check(b.state.enemies[0].maxHp == int(380 * expected.hpMod), mod + " floor budget applied exactly once")
		check(b.state.enemies[0].stats.atk == int(45 * expected.atkMod), mod + " attack modifier matches tooltip")
		check(b.state.enemies[0].stats.def == int(20 * expected.defMod), mod + " defense modifier matches tooltip")
	var story = Battle.new(catalog)
	story.start({"enemies": ["wolf"], "scaleMult": 2.0, "encounterModifier": Balance.modifier("frenzy")}, [hero("kaldi")])
	check(story.state.enemies[0].maxHp == 760 and story.state.enemies[0].stats.atk == 90, "story retains original scalar scaling")
	var boss := Balance.scale(10, catalog.EnemyData.boss_flame_lord)
	near(boss.hpMod, Balance.scale(10).hpMod * 0.68, "boss base budget converted once")
	var elite := Balance.scale(5, catalog.EnemyData.dark_knight)
	near(elite.hpMod, Balance.scale(5).hpMod, "elite catalog stats provide tier budget")

func test_replay_and_enrage() -> void:
	var base := Balance.scale(20)
	for rank in range(4):
		var ranked := Balance.apply_difficulty(base, rank)
		near(ranked.hpMod, base.hpMod * (1.0 + 0.45 * rank), "rank%d HP once" % rank)
		near(ranked.atkMod, base.atkMod * [1.0, 2.0, 4.0, 10.0][rank], "rank%d attack budget" % rank)
		near(ranked.defMod, base.defMod * (1.0 + 0.1 * rank), "rank%d defense budget" % rank)
		near(ranked.spdMod, base.spdMod, "rank%d keeps speed budget" % rank)
	var b = arena([], "boss_flame_lord")
	var boss = b.state.enemies[0]
	b.state.turn = 20
	near(b.boss_enrage_mult(boss), 1.0, "boss20 rounds normal pressure")
	b.state.turn = 21
	near(b.boss_enrage_mult(boss), 1.05, "boss enrage startsround21")
	b.state.turn = 40
	near(b.boss_enrage_mult(boss), 2.0, "boss enrage maxround40")
	b.state.turn = 1000
	near(b.boss_enrage_mult(boss), 2.0, "enrage bounded after long battle")
	near(b.boss_enrage_mult(b.state.allies[0]), 1.0, "enrage applies only enemyboss")
	b.start({"enemies": ["boss_flame_lord"]}, [hero("kaldi")])
	b.state.turn = 1000
	near(b.boss_enrage_mult(b.state.enemies[0]), 1.0, "story damage unchanged by enrage")

func test_control_resolve() -> void:
	for id in ["wolf", "dark_knight", "boss_flame_lord"]:
		var b = arena([], id)
		var enemy = b.state.enemies[0]
		b.apply_status(enemy, "freeze", 99)
		b.apply_status(enemy, "freeze", 99)
		check(enemy.statuses[0].duration == (1 if enemy.isBoss else 2), id + " repeated control refreshes within cap")
		# Mechanics fixture positions the actor. Outcomes in real-outcome tests
		# below always use unmodified combat; this fixture is not balance evidence.
		for skip in range(1 if enemy.isBoss else 2):
			b._queue = [enemy] + b.state.allies
			b._cursor = 0
			b._seek_actor()
		check(enemy.controlGuard == 1, id + " gains resolve after bounded skips")
		check(not b.apply_status(enemy, "stun", 4), id + " resolve rejects new control")
		b._queue = [enemy] + b.state.allies
		b._cursor = 0
		b._seek_actor()
		check(b.current_actor().uid == enemy.uid, id + " gets guaranteed action after resolve")
		check(enemy.controlGuard == 0, id + " resolve expires on action")
		check(b.apply_status(enemy, "electrify", 2), id + " can be controlled again after guaranteed action")
	var poison = arena([], "boss_flame_lord")
	var target = poison.state.enemies[0]
	for i in range(30): poison.apply_status(target, "poison", 2)
	check(target.statuses.filter(func(s): return s.id == "poison").size() == 5, "poison capped at5 stacks")
	var before := int(target.currentHp)
	poison._end_round()
	check(before - target.currentHp == int(target.maxHp * 0.015) * 5, "boss poison deals1.5 percent per stack")

func test_new_effects() -> void:
	var b = arena([{"type": "lifesteal", "value": 5.0}, {"type": "energyOnKill", "value": 15}])
	var actor = b.state.allies[0]
	var enemy = b.state.enemies[0]
	actor.currentHp = 100
	actor.energy = 0
	enemy.currentHp = 20
	b._damage(actor, enemy, {"type": "normal"}, "test", {"trueDamage": true}, 100.0)
	check(actor.currentHp == 107, "lifesteal capped35 percent of actual HP removed, excludes overkill")
	check(actor.energy == 15, "kill grants energy once")
	b._damage(actor, enemy, {"type": "normal"}, "test", {"trueDamage": true}, 100.0)
	check(actor.energy == 15 and actor.currentHp == 107, "dead target grants neither repeated kill energy nor healing")
	b = arena([{"type": "damageWhileShielded", "value": 0.12}, {"type": "damageVsLowHp", "value": 0.18, "threshold": 0.35}])
	actor = b.state.allies[0]
	enemy = b.state.enemies[0]
	near(b._damage_multiplier(actor, enemy, "normal"), 1.0, "conditional bonuses inactive initially")
	b.apply_status(actor, "shield", 2, 0.2)
	near(b._damage_multiplier(actor, enemy, "normal"), 1.12, "shield-offense synergy active")
	enemy.currentHp = int(enemy.maxHp * 0.3)
	near(b._damage_multiplier(actor, enemy, "normal"), 1.12 * 1.18, "execution and shield synergy combine")
	b._absorb(actor, actor.shield)
	near(b._damage_multiplier(actor, enemy, "normal"), 1.18, "broken shield removes shield-offense bonus")
	b = arena([{"type": "skillTypeDamage", "skillType": "normal", "value": 1000.0}])
	near(b._damage_multiplier(b.state.allies[0], b.state.enemies[0], "normal"), 8.0, "abyss offensive bonus has documented8x ceiling")
	check(catalog.AbyssData.rogue.rewards.size() == 26, "26 authored blessings")

func test_auto_healing() -> void:
	for id in ["ayla", "shana"]:
		var b = Battle.new(catalog)
		var healer := hero(id)
		healer.stats.spd = 200
		healer.energy = 100
		b.start({"enemies": ["boss_flame_lord"], "seed": 1}, [healer, hero("tide")])
		var result = b.auto_step()
		check(not result.events.any(func(e): return e.type == "skill" and e.get("skill_id", "") == id + "_ult"), id + " holds full-HP healing ultimate")
		check(result.events.any(func(e): return e.type == "damage"), id + " contributes damage when party healthy")
		b.state.allies[1].currentHp = int(b.state.allies[1].maxHp * 0.2)
		b.state.currentActor = b.state.allies[0].uid
		b.state.phase = "player_turn"
		result = b.auto_step()
		check(result.events.any(func(e): return e.type == "skill" and e.get("skill_id", "") == id + "_ult"), id + " heals injured party")
	var e = arena([], "fire_imp")
	var chosen = e._enemy_choice(e.state.enemies[0], e._available(e.state.enemies[0]))
	check(chosen == "imp_fireball", "abyss aggressive enemy chooses damaging skill")

func test_carried_health() -> void:
	var carried := hero("ember")
	carried.currentHp = 510
	carried._abyssSavedMaxHp = 1020
	var effects: Array = [{"type": "stat", "stat": "maxHpMult", "value": 0.40}]
	var b = Battle.new(catalog)
	b.start({"isAbyss": true, "floor": 5, "enemies": ["wolf"]}, [carried, hero("tide")], effects)
	check(b.state.allies[0].maxHp == 1190 and b.state.allies[0].currentHp == 595, "new blessing preserves HP ratio from prior buffed maximum")
	carried.currentHp = 0
	b.start({"isAbyss": true, "floor": 5, "enemies": ["wolf"]}, [carried, hero("tide")], effects)
	check(b.state.allies[0].currentHp == 0, "stat blessing preserves fallen state")

func test_real_outcomes() -> void:
	var early_wins := 0
	var late_wins := 0
	var trained_wins := 0
	var party: Array = [hero("ember"), hero("zeph")]
	var trained: Array = [hero("ember", 5), hero("zeph", 5)]
	for seed_value in range(32):
		for floor_number in [1, 10, 20]:
			var config := {"isAbyss": true, "floor": floor_number, "seed": 41000 + seed_value,
				"enemies": ["wolf", "fire_imp"] if floor_number == 1 else ["boss_flame_lord" if seed_value % 2 == 0 else "boss_storm_witch"], "maxSteps": 2000}
			var b = Battle.new(catalog)
			b.start(config, party)
			while b.state.phase not in ["victory", "defeat"]: b.auto_step()
			check(not str(b.state.reason).contains("上限"), "seed%d floor%d genuine termination" % [seed_value, floor_number])
			if floor_number == 1: early_wins += int(b.state.phase == "victory")
			if floor_number == 20: late_wins += int(b.state.phase == "victory")
			if floor_number == 10:
				b = Battle.new(catalog)
				b.start(config, trained)
				while b.state.phase not in ["victory", "defeat"]: b.auto_step()
				trained_wins += int(b.state.phase == "victory")
	check(early_wins >= 29, "starter floor1 attainable across32 seeds")
	check(late_wins <= 3, "starter stats cannot trivialize final boss")
	check(trained_wins >= 24, "training materially opens first boss")
	print("REAL COMBAT REGRESSIONS: starter floor1 %d/32; starter floor20 %d/32; trained floor10 %d/32" % [early_wins, late_wins, trained_wins])
