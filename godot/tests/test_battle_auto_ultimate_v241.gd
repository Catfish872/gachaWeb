extends SceneTree
const Game = preload("res://scripts/game_model.gd")
const Battle = preload("res://scripts/battle_model.gd")
var checks := 0
var failures: Array = []
var catalog: Dictionary

func _init() -> void:
	catalog = JSON.parse_string(FileAccess.get_file_as_string("res://data/catalog.json"))
	test_ayla_healing_value()
	test_support_value()
	test_eligibility_and_other_characters()
	test_actual_battles()
	print("AUTO ULTIMATE V241: %d checks, %d failures" % [checks, failures.size()])
	for label in failures: printerr("FAIL: ", label)
	quit(0 if failures.is_empty() else 1)

func ck(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func arena(id: String = "ayla", c: int = 0, effects: Array = []) -> Variant:
	var g = Game.new("")
	var ids: Array = [id]
	for candidate in ["ember", "zeph", "tide"]:
		if candidate != id and ids.size() < 3: ids.append(candidate)
	for cid in ids: g.state.ownedCharacters[cid] = g.default_character()
	g.state.ownedCharacters[id].constellation = c
	g.set_team(ids)
	var party: Array = g.battle_party()
	party[0].energy = 100
	party[0].stats.spd = 1000
	var b = Battle.new(catalog)
	b.start({"enemies": ["boss_storm_witch"], "seed": 241005, "isAbyss": not effects.is_empty(), "floor": 1}, party, effects)
	return b

func cast(b) -> String:
	var actor: String = b.current_actor().uid
	var result: Dictionary = b.auto_step()
	ck(result.success, "automatic step accepted")
	for event in result.events:
		if event.type == "skill" and event.actor == actor: return event.skill_id
	return ""

func test_ayla_healing_value() -> void:
	for ratio in [1.0, 0.999, 0.95, 0.85, 0.80, 0.79, 0.01]:
		var b = arena()
		b.state.allies[1].currentHp = maxi(1, int(b.state.allies[1].maxHp * ratio))
		ck(cast(b) == "ayla_ult", "ready Ayla ultimate fires at HP ratio %s" % ratio)
		ck(b.state.allies[0].energy == 0, "Ayla ultimate consumes energy at HP ratio %s" % ratio)
		ck(b.state.allies.all(func(u): return b.has_status(u, "regen")), "Ayla ultimate supplies actual team regeneration")
	var b = arena()
	for friend in b.state.allies: b.apply_status(friend, "regen", 3)
	ck(cast(b) == "ayla_ult", "existing regeneration also allows ready ultimate")
	ck(b.state.allies.all(func(u): return u.statuses.filter(func(s): return s.id == "regen")[0].duration == 6), "ready ultimate extends existing regeneration")
	b = arena()
	b.state.allies[1].currentHp = 0
	ck(cast(b) == "ayla_ult" and b.state.allies[1].currentHp == 0, "ready ultimate heals survivors while fallen ally stays fallen")

func test_support_value() -> void:
	var b = arena("shana")
	ck(cast(b) == "shana_ult", "Shana full-health ultimate also fires")
	ck(b.state.allies.all(func(u): return u.shield == int(u.maxHp * 0.3)), "Shana full-health ultimate supplies catalog shield amounts")
	b = arena("shana")
	for friend in b.state.allies: b.apply_status(friend, "shield", 3, 0.5)
	ck(cast(b) == "shana_ult", "existing shields also allow ready healing ultimate")
	b = arena("shana", 6)
	b.state.allies[0].energy = 0
	ck(cast(b) == "shana_normal", "ordinary full-health healing skill retains existing hold policy")
	b = arena("ayla", 0, [{"type":"statusAfterHeal", "statusId":"regen", "duration":2}])
	ck(cast(b) == "ayla_ult", "full-health Ayla fires with actual on-heal blessing")
	ck(b.state.allies.all(func(u): return u.statuses.filter(func(s): return s.id == "regen")[0].duration == 5), "full-health heal triggers blessing regeneration plus skill regeneration")
	b = arena("ayla", 6, [{"type":"statusAfterHeal", "statusId":"regen", "duration":2}])
	ck(cast(b) == "ayla_ult", "C6 Ayla full-health ultimate also fires")
	ck(b.state.allies.all(func(u): return u.statuses.filter(func(s): return s.id == "regen")[0].duration == 6), "C6 and on-heal blessing both execute at full HP")
	b = arena("ayla", 0, [{"type":"statusAfterHeal", "statusId":"shield", "duration":2, "value":0.2}])
	ck(cast(b) == "ayla_ult", "full-health ultimate executes supported heal-trigger shield")
	ck(b.state.allies.all(func(u): return u.shield == int(u.maxHp * 0.2)), "heal-trigger shield applies through real healing pipeline")

func test_eligibility_and_other_characters() -> void:
	var b = arena()
	b.state.allies[1].currentHp = 1
	b.state.allies[0].energy = 99
	ck(cast(b) == "ayla_skill", "insufficient energy remains enforced")
	b = arena()
	b.state.allies[1].currentHp = 1
	b.state.allies[0].cooldowns.ayla_ult = 2
	ck(cast(b) == "ayla_skill", "ultimate cooldown remains enforced")
	b = arena()
	b.apply_status(b.state.allies[0], "freeze", 1)
	b._seek_actor()
	ck(b.current_actor().id != "ayla" and b.state.allies[0].energy == 100, "controlled Ayla skips through normal turn resolution without spending energy")
	b = arena()
	ck(b.act("ayla_ult").success and b.state.allies[0].energy == 0, "manual full-health ultimate remains available")
	b = arena()
	b.state.allies[0].skills = ["ayla_ult", "ayla_skill", "ayla_normal"]
	b.state.allies[1].currentHp = 1
	ck(cast(b) == "ayla_ult", "useful ultimate priority survives reordered catalog skills")
	b = arena("shana")
	b.state.allies[0].energy = 0
	b.state.allies[1].currentHp = int(b.state.allies[1].maxHp * 0.89)
	ck(cast(b) == "shana_skill", "ordinary heal skill retains ninety-percent injury trigger")
	for id in ["kaldi", "gus", "lorin", "ember", "zeph", "bolt", "tide", "cinder"]:
		b = arena(id)
		ck(cast(b) == id + "_ult", id + " useful damaging or shielding ultimate priority unchanged")

func fixture(late: bool):
	var g = Game.new("")
	g.rng.seed = 241031
	var ids: Array = ["kaldi", "ayla", "gus"] if late else ["ember", "ayla", "zeph"]
	for id in ids:
		g.state.ownedCharacters[id] = g.default_character()
		g.state.ownedCharacters[id].level = 10 if late else 1
		g.state.ownedCharacters[id].constellation = 6 if late else 0
	g.set_team(ids)
	if late:
		g.state.resources.gold = 10000000
		for id in ids:
			for slot in g.catalog.RelicSlots:
				var relic: Dictionary = g.generate_relic(5, slot.id)
				g.add_relic(relic); g.upgrade_relic_to_max(relic.uid); g.equip_relic(relic.uid, id)
	return g

func actual_battle(late: bool, seed_value: int) -> Dictionary:
	var g = fixture(late)
	var b = Battle.new(g.catalog)
	b.start({"isAbyss":true, "floor":50 if late else 1, "difficulty":3 if late else 0, "enemies":["boss_storm_witch"], "seed":seed_value, "maxSteps":1000}, g.battle_party())
	var actions: Array = []
	var guard := 0
	while b.state.phase not in ["victory", "defeat"] and guard < 1001:
		var result: Dictionary = b.auto_step()
		for event in result.events:
			if event.type == "skill": actions.append(str(event.skill_id))
		guard += 1
	return {"actions":actions, "phase":b.state.phase, "steps":guard, "turn":b.state.turn}

func test_actual_battles() -> void:
	for late in [false, true]:
		var seed_value := 241005 if late else 241003
		var result := actual_battle(late, seed_value)
		ck(result.actions.has("ayla_ult"), "actual %s fixture uses previously starved Ayla ultimate" % ("C6 gear25" if late else "initial"))
		ck(result.phase in ["victory", "defeat"] and result.steps < 1000, "actual battle reaches bounded terminal outcome")
		ck(actual_battle(late, seed_value) == result, "actual battle exact deterministic replay")
		print("AUTO ACTUAL ", "C6 gear25" if late else "initial", " ", result.phase, " steps=", result.steps, " ultimates=", result.actions.count("ayla_ult"))
