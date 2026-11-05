extends SceneTree
const GameModel = preload("res://scripts/game_model.gd")
const BattleModel = preload("res://scripts/battle_model.gd")
var failed := 0
var passed := 0
func check(value: bool, label: String) -> void:
	if value: passed += 1; print("PASS: "+label)
	else: failed += 1; push_error("FAIL: "+label)
func _initialize() -> void:
	call_deferred("run_tests")
func new_encounter(kind: String):
	var model = GameModel.new("")
	check(model.extraction.start_run().success, "start extraction")
	var ex = model.extraction
	var target_id: String = ""
	for option in ex.route_options():
		if option.type != "entry" and option.type != "boss": target_id = option.id; break
	for room in ex.run().map.rooms:
		if room.id == target_id: room.type = kind
	if kind == "rest": ex.data.serviceGuards.rest = 1.0
	ex.run().growthBattles = 4
	check(ex.enter_room(target_id).success, "enter "+kind)
	return model
func finish(model, phase: String = "victory") -> Dictionary:
	var engine = BattleModel.new(model.catalog)
	var started: Dictionary = model.extraction.start_battle(engine)
	check(started.success, "start battle")
	# Verify the settlement boundary, not combat damage: intermediate phases
	# cannot award; the final encounter state can award exactly once.
	check(not model.finish_battle(started.config, engine.state).success, "unfinished encounter gives no blessing")
	engine.state.phase = phase
	var result: Dictionary = model.finish_battle(started.config, engine.state)
	check(result.success, "settle "+phase)
	check(not model.finish_battle(started.config, engine.state).success, "repeat settlement rejected")
	return result
func run_tests() -> void:
	for kind in ["battle", "elite", "rest"]:
		var model = new_encounter(kind)
		finish(model)
		var ex = model.extraction
		check(ex.growth_choices().size() == 3, "later "+kind+" win offers three")
		check(ex.run().growthBattles == 5, "one growth count per encounter")
		var choice_id: String = ex.growth_choices()[0].choiceId
		var saved: Dictionary = model.state.duplicate(true)
		var reload = GameModel.new("")
		reload.state = saved
		check(reload.valid_save(reload.state), "pending choice is save-valid")
		check(reload.extraction.growth_choices()[0].choiceId == choice_id, "reload preserves same offer")
		check(reload.extraction.choose_growth(choice_id).success, "choose after reload")
		check(not reload.extraction.choose_growth(choice_id).success, "repeat choice rejected")
		check(reload.extraction.run().blessings.size() == 1, "exactly one blessing applied")
		if kind == "rest":
			check(not reload.extraction.run().room.guardPending, "guard cleared")
			check(not reload.extraction.room_actions().is_empty(), "rest actions retained after blessing")
			check(not reload.extraction.room_interaction_status().canAutoReturn, "service interaction keeps room open")
	var boss_model = GameModel.new("")
	check(boss_model.extraction.start_run().success, "start boss fixture")
	var boss_ex = boss_model.extraction
	boss_ex.run().map.explored = 0
	for room in boss_ex.run().map.rooms:
		if room.type not in ["entry", "boss"]:
			room.visited = true; room.cleared = true
			boss_ex.run().map.explored += 1
	boss_ex.run().map.bossUnlocked = true
	check(boss_ex.enter_room(boss_ex.run().map.bossRoomId).success, "enter unlocked boss")
	finish(boss_model)
	check(boss_ex.run().phase == "boss_exit", "boss exit preserved")
	check(boss_ex.parcel_dimensions() == Vector2i(6,6), "boss parcel preserved")
	check(boss_ex.growth_choices().size() == 3 and boss_ex.growth_choices().all(func(r): return r.rarity == "gold"), "boss offers three gold")
	check(not boss_ex.continue_act().success, "blessing precedes next act")
	check(boss_ex.choose_growth(boss_ex.growth_choices()[0].choiceId).success, "boss blessing selectable")
	check(boss_ex.continue_act().success and boss_ex.run().act == 2, "continue act preserved")
	var defeated = new_encounter("battle")
	finish(defeated, "defeat")
	check(not defeated.extraction.active(), "defeat ends run without reward")
	var model = new_encounter("battle")
	var ex = model.extraction
	check(ex._growth_rarity_weights() == {"white":6.0,"blue":3.0,"gold":1.0}, "ordinary/event per-entry weights retained")
	check(ex._growth_rarity_weights(true) == {"white":6.0,"blue":3.6,"gold":1.4}, "elite per-entry weights improved")
	ex.run().pendingChoices = []
	ex._offer_growth("gold")
	check(ex.growth_choices().all(func(r): return r.rarity == "gold"), "boss gold pool retained")
	for item_id in ["repair_patch", "repair_kit", "repair_core"]:
		check(ex._matches_loot_categories(ex.item_def(item_id), ["疗愈用品"]), item_id+" in healing pool")
		check(ex._matches_loot_categories(ex.item_def(item_id), ["补给"]), item_id+" in supply pool")
		check(not ex._matches_loot_categories(ex.item_def(item_id), ["王室遗物"]), item_id+" outside treasure pool")
	for container_id in ["herb_basket", "alchemy_cabinet"]:
		check(ex._container_categories("cache", container_id, {}).has("补给"), container_id+" uses medical pool")
		check(ex._container_categories("vault", container_id, {"vault":["王室遗物"]}) == ["王室遗物"], "vault priority retained")
	# Use production smart-loot on the same full-bag regression geometry.
	ex.run().phase = "room"; ex.run().activeEncounter = {}; ex.run().pendingChoices = []
	ex.state().utility.backpack = {"itemId":"pack_5"}
	ex.run().bag = []
	for i in range(15):
		var item: Dictionary = ex._make_item("barrier_module")
		item.revealed = true; item.appraisalRisk = 5
		ex.run().bag.append(item)
	ex.run().bag = ex._packed_copy(ex.run().bag, ex.dimensions("bag"))
	var incoming: Dictionary = ex._make_item("reactor")
	incoming.revealed = true; incoming.appraisalRisk = 5
	ex.run().containers = [{"id":"loot_fixture","items":[incoming],"revealed":1}]
	var worn_before: String = JSON.stringify(ex.run().equipped)
	var plan: Dictionary = ex.plan_smart_loot("loot_fixture")
	var expected_gain: int = ex.item_value(incoming)
	for removed_item in plan.get("removed", []): expected_gain -= ex.item_value(removed_item)
	check(plan.success and plan.gain == expected_gain and expected_gain > 0 and not plan.removed.is_empty(), "production smart loot replaces surplus gear")
	check(JSON.stringify(ex.run().equipped) == worn_before, "worn gear untouched")
	print("V268 EXTRACTION: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)
