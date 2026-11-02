extends SceneTree

const Battle = preload("res://scripts/battle_model.gd")
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label)

func unit(ally: bool = true) -> Dictionary:
	return {"uid":"ally" if ally else "enemy", "id":"test", "name":"Test", "isAlly":ally,
		"currentHp":1000, "maxHp":1000, "stats":{"def":100, "atk":100, "spd":100},
		"statuses":[], "shield":0, "ownerEffects":[], "energy":0, "passiveId":"",
		"cooldowns":{}, "deathReported":false}

func battle(target: Dictionary, config: Dictionary = {}):
	var model = Battle.new()
	model.state = {"allies":[target] if target.isAlly else [], "enemies":[] if target.isAlly else [target], "config":config}
	return model

func shield(hp: int, equipment: bool = false) -> Dictionary:
	return {"id":"shield", "duration":2, "shieldHp":hp, "source":"expedition_equipment" if equipment else "skill", "persistent":equipment}

func _initialize() -> void:
	for config in [{}, {"isAbyss":true}, {"isExtraction":true}]:
		var target := unit()
		var model = battle(target, config)
		model._status_damage(target, 200, "burn", {"sourceUid":"missing"})
		check(target.currentHp == 900, "all modes apply defense " + str(config))
		check(model._events.back().amount == 100 and model._events.back().damageSource == "burn", "UI uses mitigated DOT")
		check(target.energy == 0, "DOT gives no energy")

	var target := unit()
	var model = battle(target)
	target.statuses = [{"id":"def_up", "duration":2, "value":1.0}, {"id":"stun", "duration":2}]
	model._status_damage(target, 240, "poison")
	check(target.currentHp == 900, "effective defense combines defense buff and stun")
	target = unit()
	model = battle(target)
	target.ownerEffects = [{"type":"damageTakenMult", "value":-0.8}, {"type":"damageTakenWhileStatus", "statusId":"burn", "value":-0.8}]
	target.statuses = [{"id":"burn", "duration":2}]
	model._status_damage(target, 200, "burn")
	check(target.currentHp == 990, "existing 90 percent ordinary reduction ceiling")

	target = unit()
	model = battle(target, {"isExtraction":true})
	target.statuses = [shield(80, true), shield(30)]
	model._sync_shield(target)
	model._status_damage(target, 200, "burn")
	check(target.currentHp == 1000 and target.shield == 10, "shield absorbs mitigated DOT")
	check(model.state.equipmentShieldRemaining == 10, "equipment shield ledger updates")
	check(model._events[0].source == "skill" and model._events[0].amount == 30, "skill shield consumed first")
	check(model._events[1].source == "expedition_equipment" and model._events[1].amount == 70, "equipment shield consumed second")
	check(model._events.back().amount == 0, "fully absorbed DOT reports zero HP damage")
	model._status_damage(target, 200, "poison", {"dotSources":[{"uid":"gone_a"}, {"uid":"gone_b"}]})
	check(target.currentHp == 910 and target.shield == 0 and model.state.equipmentShieldRemaining == 0, "shield overflow and ledger zero")
	check(model._events.back().dotSources.size() == 2, "mixed sources retained")

	target = unit(false)
	model = battle(target)
	target.statuses = [shield(300)]
	model._sync_shield(target)
	model._status_damage(target, 200, "burn")
	check(target.currentHp == 800 and target.shield == 300, "enemy DOT bypass unchanged")

	target = unit()
	model = battle(target)
	target.statuses = [{"id":"invincible", "duration":1}, shield(100)]
	model._sync_shield(target)
	model._status_damage(target, 200, "burn")
	check(target.currentHp == 1000 and target.shield == 100 and model._events.back().type == "miss", "invincibility preserves shield")

	target = unit()
	model = battle(target)
	target.currentHp = 10
	model._status_damage(target, 200, "burn")
	model._report_deaths()
	var event_count: int = model._events.size()
	model._status_damage(target, 200, "poison")
	model._report_deaths()
	check(target.currentHp == 0 and model._events.size() == event_count and model._events.back().type == "death", "death reported once, no postmortem DOT")

	# Exercise actual round settlement with a dead source plus a missing source.
	target = unit()
	model = battle(target)
	var dead_source := unit(false)
	dead_source.currentHp = 0
	model.state.enemies = [dead_source]
	target.statuses = [{"id":"burn", "duration":2, "dotAttack":1000, "sourceUid":"enemy"},
		{"id":"poison", "duration":1, "persistent":true, "dotAttack":1000, "sourceUid":"enemy"},
		{"id":"poison", "duration":1, "persistent":true, "dotAttack":1000, "sourceUid":"missing"}]
	model._end_round()
	check(target.currentHp == 888, "round dead-source burn 90 plus mixed-source poison 22")
	check(target.statuses[0].duration == 1 and target.statuses[1].duration == 1 and target.statuses[2].duration == 1, "burn duration and permanent poison unchanged")
	check(model._events.size() == 2 and target.energy == 0, "round adds no proc chain")
	if failures.is_empty(): print("PASS player DOT defense v275")
	else:
		for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
