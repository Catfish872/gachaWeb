extends SceneTree
const Game = preload("res://scripts/game_model.gd")
const Battle = preload("res://scripts/battle_model.gd")
var catalog: Dictionary
var checks := 0
var failures: Array = []

func _init() -> void:
	catalog = JSON.parse_string(FileAccess.get_file_as_string("res://data/catalog.json"))
	test_growth()
	test_outgoing_buckets()
	test_recovery()
	test_total_reduction_and_shields()
	test_poison_instances()
	print("BATTLE BLESSING CAPS V241: %d checks, %d failures" % [checks, failures.size()])
	for label in failures: printerr("FAIL: ", label)
	quit(0 if failures.is_empty() else 1)

func ck(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func near(a: float, b: float, label: String) -> void:
	ck(absf(a - b) < 0.000001, "%s actual=%s expected=%s" % [label, a, b])

func copies(effect: Dictionary, count: int) -> Array:
	var result: Array = []
	for n in count: result.append(effect.duplicate(true))
	return result

func arena(effects: Array = [], id: String = "ayla"):
	var g = Game.new("")
	g.state.ownedCharacters[id] = g.default_character()
	g.set_team([id])
	var b = Battle.new(catalog)
	b.start({"isAbyss": true, "floor": 1, "enemies": ["boss_flame_lord"], "seed": 241101}, g.battle_party(), effects)
	return b

func test_growth() -> void:
	for count in [1, 3, 4, 10, 100]:
		var effects := copies({"type":"stat", "stat":"atkMult", "value":0.08}, count)
		effects.append_array(copies({"type":"stat", "stat":"maxHpMult", "value":0.1}, count))
		effects.append_array(copies({"type":"stat", "stat":"defMult", "value":0.1}, count))
		effects.append_array(copies({"type":"stat", "stat":"spdMult", "value":0.08}, count))
		effects.append_array(copies({"type":"stat", "stat":"criDmgAdd", "value":0.15}, count))
		effects.append_array(copies({"type":"stat", "stat":"criAdd", "value":0.08}, count))
		var b = arena(effects)
		var a: Dictionary = b.state.allies[0]
		var base: Dictionary = catalog.CharacterData.ayla.baseStats
		ck(absf(float(a.stats.atk) - base.atk * (1.0 + count * 0.08)) < 1.01, "%d attack copies contribute" % count)
		ck(absf(float(a.maxHp) - base.hp * (1.0 + count * 0.1)) < 1.01, "%d maximum-HP copies contribute" % count)
		ck(absf(float(a.stats.def) - base.def * (1.0 + count * 0.1)) < 1.01, "%d defense copies contribute" % count)
		near(a.stats.spd, base.spd * (1.0 + count * 0.08), "%d speed copies contribute" % count)
		near(a.stats.criDmg, base.criDmg + count * 0.15, "%d critical damage copies contribute" % count)
		near(a.stats.cri, minf(1.0, base.cri + count * 0.08), "critical probability retains natural hundred-percent range")
		ck(is_finite(a.stats.spd) and is_finite(a.stats.criDmg) and a.currentHp == a.maxHp, "grown battle stats remain finite and healthy")

func test_outgoing_buckets() -> void:
	var effects := copies({"type":"skillTypeDamage", "skillType":"normal", "value":1.0}, 10)
	var b = arena(effects)
	var a: Dictionary = b.state.allies[0]
	var target: Dictionary = b.state.enemies[0]
	near(b._damage_multiplier(a, target, "normal"), 11.0, "ten additive damage copies exceed old eightfold cap")
	a.stats.atk = 100; a.stats.cri = 0
	target.stats.def = 0; target.element = a.element
	ck(b._damage(a, target, {"type":"normal"}, "test", {}, 1.0) == 1100, "above-eightfold multiplier reaches actual HP damage")
	effects.append_array(copies({"type":"damageVsStatus", "statusId":"burn", "value":1.0}, 4))
	b = arena(effects)
	b.apply_status(b.state.enemies[0], "burn", 2)
	near(b._damage_multiplier(b.state.allies[0], b.state.enemies[0], "normal"), 55.0, "same bucket adds while separate buckets multiply without ceiling")

func test_recovery() -> void:
	for count in [4, 10, 100]:
		var b = arena(copies({"type":"healMult", "value":0.16}, count))
		b._events = []
		b._execute_skill(b.state.allies[0], "ayla_ult")
		var heals: Array = b._events.filter(func(e): return e.type == "heal" and e.get("skill_id", "") == "ayla_ult")
		var expected := int(155 * 1.8 * (1.0 + count * 0.16))
		ck(absi(int(heals[0].requestedAmount) - expected) <= 1, "%d healing copies reach actual requested heal" % count)
		b = arena(copies({"type":"battleStartStatus", "statusId":"shield", "duration":2, "value":0.22}, count))
		ck(b.state.allies[0].shield == int(b.state.allies[0].maxHp * 0.22) * count, "%d opening shields accumulate actual capacity" % count)
	for count in [4, 10]:
		var b = arena(copies({"type":"lifesteal", "value":0.06}, count))
		var a: Dictionary = b.state.allies[0]
		a.currentHp = 1; a.stats.atk = 100; a.stats.cri = 0
		b._damage(a, b.state.enemies[0], {"type":"normal"}, "test", {"trueDamage":true}, 1.0)
		ck(a.currentHp == 1 + int(100 * count * 0.06), "%d lifesteal copies heal actual rate beyond old thirty-five percent" % count)
	for count in [4, 5, 10]:
		var b = arena(copies({"type":"energyOnKill", "value":15.0}, count))
		var a: Dictionary = b.state.allies[0]
		a.energy = 0
		b.state.enemies[0].currentHp = 1
		b._damage(a, b.state.enemies[0], {"type":"normal"}, "test", {"trueDamage":true}, 1.0)
		ck(a.energy == mini(100, 15 * count), "%d kill-energy copies exceed old sixty limit until natural hundred energy" % count)

func incoming(b, critical: bool = false, shield: float = 0.0) -> int:
	var source: Dictionary = b.state.enemies[0]
	var target: Dictionary = b.state.allies[0]
	source.stats.atk = 1000; source.stats.cri = 1.0 if critical else 0.0; source.stats.criDmg = 2.0
	target.stats.def = 0; target.element = "wind"
	if shield > 0: b.apply_status(target, "shield", 2, shield)
	return b._damage(source, target, {"type":"enemy", "element":"wind"}, "incoming", {}, 1.0)

func test_total_reduction_and_shields() -> void:
	var effects := copies({"type":"damageTakenMult", "value":-0.1}, 4)
	effects.append_array(copies({"type":"damageTakenWhileStatus", "statusId":"regen", "value":-0.15}, 4))
	var b = arena(effects)
	b.apply_status(b.state.allies[0], "regen", 3)
	near(b._damage_taken_multiplier(b.state.allies[0]), 0.24, "independent sixty and forty-percent remaining-damage buckets multiply")
	ck(incoming(b) == 240, "combined reductions reach actual direct HP damage")
	effects = copies({"type":"damageTakenMult", "value":-0.1}, 10)
	effects.append_array(copies({"type":"damageTakenWhileStatus", "statusId":"regen", "value":-0.15}, 10))
	b = arena(effects)
	b.apply_status(b.state.allies[0], "regen", 3)
	near(b._damage_taken_multiplier(b.state.allies[0]), 0.1, "two saturated reduction buckets retain ten-percent total floor")
	ck(incoming(b) == 100, "total ninety-percent reduction leaves hundred from thousand")
	var beyond := copies({"type":"damageTakenMult", "value":-0.1}, 20)
	beyond.append_array(copies({"type":"damageTakenWhileStatus", "statusId":"regen", "value":-0.15}, 20))
	b = arena(beyond)
	b.apply_status(b.state.allies[0], "regen", 3)
	near(b._damage_taken_multiplier(b.state.allies[0]), 0.1, "two negative raw buckets beyond hundred-percent reduction never multiply back into increased damage")
	ck(incoming(b) == 100, "over-hundred-percent stacks retain total ninety-percent direct reduction")
	b = arena(effects)
	b.apply_status(b.state.allies[0], "regen", 3)
	var hp := int(b.state.allies[0].currentHp)
	ck(incoming(b, false, 0.5) == 0 and b.state.allies[0].currentHp == hp, "shield fully absorbs post-reduction damage with zero forced penetration")
	b = arena(effects)
	b.apply_status(b.state.allies[0], "invincible", 1)
	ck(incoming(b) == 0, "invincibility stays independent complete immunity")
	b = arena(effects)
	b.apply_status(b.state.allies[0], "regen", 3)
	b.state.enemies[0].stats.atk = 1000
	b.state.enemies[0].stats.cri = 1.0; b.state.enemies[0].stats.criDmg = 2.0
	b.state.allies[0].stats.def = 100; b.state.allies[0].element = "wind"
	ck(b._damage(b.state.enemies[0], b.state.allies[0], {"type":"enemy", "element":"fire"}, "formula", {}, 1.0) == 150, "defense half times element one-and-half times critical two remains separate from total reduction")
	var blocked := false
	for seed_value in range(20):
		b = arena(effects, "lorin")
		b.rng.seed = seed_value
		b.apply_status(b.state.allies[0], "regen", 3)
		var damage := incoming(b)
		if b._events.any(func(e): return e.type == "block"):
			blocked = true
			ck(damage == 100, "Lorin block joins total reduction instead of turning ninety into ninety-five percent")
	ck(blocked, "deterministic sample exercises Lorin block boundary")

func test_poison_instances() -> void:
	for count in [4, 6, 10, 30]:
		var b = arena()
		var target: Dictionary = b.state.enemies[0]
		for n in count: b.apply_status(target, "poison", 2)
		ck(target.statuses.filter(func(s): return s.id == "poison").size() == count, "%d poison applications all remain" % count)
		var before := int(target.currentHp)
		b._end_round()
		ck(before - target.currentHp == mini(before, int(target.maxHp * 0.05) * count), "%d poison stacks use full five-percent coefficient until target falls" % count)
	var normal = Battle.new(catalog)
	normal.start({"isAbyss":true, "floor":1, "enemies":["wolf"], "seed":241101}, [{"id":"ayla"}])
	var target: Dictionary = normal.state.enemies[0]
	for n in 10: normal.apply_status(target, "poison", 2)
	var hp := int(target.currentHp)
	normal._end_round()
	ck(hp - target.currentHp == int(target.maxHp * 0.05) * 10, "ten poison stacks retain normal enemy five-percent coefficient")
