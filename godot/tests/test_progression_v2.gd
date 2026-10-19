extends SceneTree

const Game = preload("res://scripts/game_model.gd")
const Battle = preload("res://scripts/battle_model.gd")
var passed := 0
var failed := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if condition:
		passed += 1
		print("PASS: " + message)
	else:
		failed += 1
		push_error("FAIL: " + message)

func fresh():
	var model = Game.new("")
	model.rng.seed = 73
	model.prepare_abyss()
	model._issued_config.clear()
	model.state.abyss.rogue.activeEncounter = {}
	model.state.abyss.savedPartyState = [{"id": "ember", "currentHp": 400, "maxHp": 1000, "energy": 10, "cooldowns": {"flame_strike": 3}}, {"id": "zeph", "currentHp": 0, "maxHp": 800, "energy": 0, "cooldowns": {}}]
	return model

func event_node(model, event_id: String) -> void:
	model.state.abyss.rogue.nextStep = {"type": "event", "floor": 2}
	model.state.abyss.rogue.pendingNode = {"id": "event_2", "type": "event", "eventId": event_id}

func test_events() -> void:
	var model = fresh()
	check(model.rogue_data.events.size() == 5, "five distinct random events are shipped")
	for event in model.rogue_data.events:
		check(event.options.size() == 3, "three explicit choices in " + event.id)
		for choice in event.options:
			check(choice.has("cost") and choice.has("risk") and choice.has("reward") and not str(choice.description).is_empty(), "visible cost, risk, outcome: " + event.id + "/" + choice.id)
	event_node(model, "blood_altar")
	var choices: Array = model.node_options().options
	check(not choices[0].enabled and not str(choices[0].disabledReason).is_empty(), "HP sacrifice disabled while any hero is down")
	var before := JSON.stringify(model.state)
	check(not model.choose_abyss_node("sacrifice").success and before == JSON.stringify(model.state), "unpayable event leaves every state field intact")
	model.state.abyss.savedPartyState[1].currentHp = 500
	model.state.abyss.rogue.temporaryCurrency = 100
	check(model.choose_abyss_node("sacrifice").success, "payable sacrifice gives blessing")
	check(model.state.abyss.savedPartyState[0].currentHp == 200 and model.state.abyss.savedPartyState[1].currentHp == 340, "sacrifice charges exact 20% maximum HP per hero")
	check(model.state.abyss.rogue.selectedRewards.size() == 1 and model.state.abyss.rogue.selectedRewards[0].rarity == "blue", "sacrifice grants promised rarity")
	check(model.state.abyss.rogue.nextStep.type == "none" and model.state.abyss.rogue.pendingNode.is_empty(), "resolved event opens next combat")
	before = JSON.stringify(model.state)
	check(not model.choose_abyss_node("sacrifice").success and JSON.stringify(model.state) == before, "event cannot pay twice")
	model = fresh()
	model.state.abyss.rogue.temporaryCurrency = 100
	event_node(model, "rift_well")
	model.random_source = func(): return 0.1
	check(model.choose_abyss_node("gamble").success and model.state.abyss.rogue.temporaryCurrency == 160, "advertised winning gamble spends35 and returns95")
	model = fresh()
	model.state.abyss.rogue.temporaryCurrency = 100
	event_node(model, "rift_well")
	model.random_source = func(): return 0.9
	check(model.choose_abyss_node("gamble").success and model.state.abyss.rogue.temporaryCurrency == 75, "advertised losing gamble spends35 and returns10")
	model = fresh()
	event_node(model, "abandoned_cache")
	check(model.choose_abyss_node("research").success and model.state.abyss.meta.currency == 5, "event permanent reward banks immediately")
	check(model.reset_abyss().success and model.state.abyss.meta.currency == 5 and model.state.abyss.rogue.temporaryCurrency == 0, "retreat retains event meta while clearing temporary money")

func test_rest_shop_routes() -> void:
	var model = fresh()
	model._set_after_floor(8)
	check(model.node_options().options.size() == 3, "camp exposes three distinct decisions")
	check(not model.prepare_abyss().success, "camp decision gates combat")
	check(model.choose_abyss_node("recover").success, "rest recovery resolves")
	check(model.state.abyss.savedPartyState[0].currentHp == 750 and model.state.abyss.savedPartyState[1].currentHp == 280, "camp heals survivors and revives fallen allies at35%")
	model._set_after_floor(18)
	check(model.choose_abyss_node("meditate").success, "meditation resolves")
	check(model.state.abyss.savedPartyState[0].energy == 50 and model.state.abyss.savedPartyState[0].cooldowns.flame_strike == 0, "meditation adds40 energy and clears cooldown")
	model._set_after_floor(5)
	model.state.abyss.rogue.temporaryCurrency = 1000
	var items: Array = model.abyss_shop_items()
	check(items.size() == 4, "shop holds exactly four limited-stock items")
	check(not model.prepare_abyss().success, "shop remains a mandatory leave decision")
	check(model.purchase_abyss_item("heal").success and model.state.abyss.rogue.temporaryCurrency == 965, "healing purchase costs35 run coins")
	var before := JSON.stringify(model.state)
	check(not model.purchase_abyss_item("heal").success and before == JSON.stringify(model.state), "sold item cannot be purchased twice")
	var blessing: Dictionary = items[2]
	var selected_before: int = model.state.abyss.rogue.selectedRewards.size()
	check(model.purchase_abyss_item(blessing.id).success, "shop blessing purchase succeeds")
	check(model.state.abyss.rogue.selectedRewards.size() == selected_before + 1, "shop blessing is attached to current build")
	check(model.leave_abyss_shop().success and model.state.abyss.rogue.shopStock.is_empty(), "leaving clears the shop inventory")
	check(not model.leave_abyss_shop().success, "shop exit cannot replay")
	model._set_after_floor(2)
	check(model.node_options().options.size() == 2 and not model.prepare_abyss().success, "branch gives two choices and blocks skipping")
	check(model.choose_abyss_node("rest").success and model.state.abyss.rogue.nextStep.type == "rest", "branch can choose a safe camp instead of the rolled event")
	model.choose_abyss_node("scavenge")
	model._set_after_floor(4)
	check(model.choose_abyss_node("event").success and model.node_options().options.size() == 3, "event route reveals three canonical options")
	model.state.abyss.currentFloor = 5
	model.state.abyss.rogue.floorsCleared = 4
	check(model.valid_save(model.state), "live event state round-trips through save validation")

func test_caps_meta_and_rollback() -> void:
	var model = fresh()
	var reward: Dictionary = model.catalog.AbyssData.rogue.rewards[0]
	for _i in range(3):
		model.state.abyss.rogue.selectedRewards.append(reward.duplicate(true))
	var contains := false
	for available in model._available_abyss_rewards():
		contains = contains or available.id == reward.id
	check(not contains, "three copies cap removes blessing from future draws")
	model.reset_abyss()
	var original_stats: Dictionary = model.computed_stats("ember")
	model.state.abyss.meta.currency = 10000
	for upgrade in model.meta_upgrade_list():
		for _rank in range(int(upgrade.maxLevel)):
			check(model.purchase_meta_upgrade(upgrade.id).success, "bounded meta rank purchased " + upgrade.id)
		check(not model.purchase_meta_upgrade(upgrade.id).success, "meta cap enforced " + upgrade.id)
	check(original_stats == model.computed_stats("ember"), "meta never changes base or story computed stats")
	check(model.prepare_abyss().success and model.state.abyss.rogue.temporaryCurrency == 75, "fully upgraded supply starts run with75 coins")
	var atk := 0.0
	var hp := 0.0
	var regen := 0.0
	for effect in model.rogue_effects():
		if effect.get("stat", "") == "atkMult": atk += float(effect.value)
		if effect.get("stat", "") == "maxHpMult": hp += float(effect.value)
		if effect.type == "victoryHealPct": regen += float(effect.value)
	check(is_equal_approx(atk, 0.15) and is_equal_approx(hp, 0.2) and is_equal_approx(regen, 0.06), "full permanent stats remain capped15% attack20% HP6% recovery")
	model = fresh()
	model._set_after_floor(8)
	var before := JSON.stringify(model.state)
	model.save_blocked = true
	check(not model.choose_abyss_node("recover").success and before == JSON.stringify(model.state), "camp save failure rolls back HP and node state")
	model.save_blocked = false
	model._set_after_floor(5)
	model.state.abyss.rogue.temporaryCurrency = 1000
	before = JSON.stringify(model.state)
	model.save_blocked = true
	check(not model.purchase_abyss_item("heal").success and before == JSON.stringify(model.state), "shop save failure rolls back money, stock and healing")
	model = Game.new("")
	model.state.abyss.meta.currency = 100
	before = JSON.stringify(model.state)
	model.save_blocked = true
	check(not model.purchase_meta_upgrade("offense").success and before == JSON.stringify(model.state), "meta save failure rolls back cost and rank")

func test_full_expedition() -> void:
	var model = Game.new("")
	model.rng.seed = 44
	for id in ["kaldi", "ayla", "gus"]:
		model.state.ownedCharacters[id] = model.default_character()
		model.state.ownedCharacters[id].level = 10
		model.state.ownedCharacters[id].constellation = 6
	model.set_team(["kaldi", "ayla", "gus"])
	var ended := false
	var history_count := 0
	for floor_number in range(1, 21):
		var prepared: Dictionary = model.prepare_abyss()
		check(prepared.success, "20-floor run starts encounter %d" % floor_number)
		if not prepared.success: break
		var battle = Battle.new(model.catalog)
		battle.start(prepared.config, model.battle_party(true), model.rogue_effects())
		for _step in range(3000):
			if battle.state.phase in ["victory", "defeat"]: break
			battle.auto_step()
		check(battle.state.phase == "victory", "mature test squad clears encounter %d" % floor_number)
		var result: Dictionary = model.finish_battle(prepared.config, battle.state)
		check(result.success, "20-floor run settles encounter %d" % floor_number)
		check(model.valid_save(model.state), "run save validates after floor %d" % floor_number)
		if result.get("ended", false):
			ended = floor_number == 20
			break
		for _node in range(4):
			var kind: String = model.state.abyss.rogue.nextStep.type
			if kind == "none": break
			check(not model.prepare_abyss().success, "pending %s blocks floor skip" % kind)
			if kind == "reward":
				model.choose_abyss_reward(model.state.abyss.rogue.pendingChoices[0].choiceId)
			elif kind == "shop":
				for item in model.abyss_shop_items():
					if item.enabled: model.purchase_abyss_item(item.id)
				model.leave_abyss_shop()
			else:
				var options: Array = model.node_options().options
				for option in options:
					if option.enabled:
						model.choose_abyss_node(option.id)
						break
			check(model.valid_save(model.state), "resolved %s state remains valid" % kind)
		history_count = maxi(history_count, model.state.abyss.rogue.eventHistory.size())
	check(ended and not model.abyss_run_active() and model.state.abyss.currentFloor == 1, "floor20 completes expedition and returns to fresh floor1")
	check(model.state.abyss.maxFloor == 20 and model.state.abyss.meta.runsCompleted == 1, "completion preserves20-floor record and increments wins")
	check(model.state.abyss.meta.currency >= 140 and model.state.abyss.lastRun.metaEarned == model.state.abyss.meta.currency, "run payouts and completion bonus are permanently banked")
	check(history_count >= 8, "full expedition includes numerous resolved route encounters")
	check(model.state.abyss.rogue.selectedRewards.is_empty() and model.state.abyss.rogue.temporaryCurrency == 0, "completion clears temporary blessings and coins")
	check(model.state.abyss.meta.unlockedDifficulty == 1 and model.state.abyss.meta.selectedDifficulty == 0, "normal clear unlocks rank1 while retaining selected rank")
	check(not model.set_abyss_difficulty(2).success, "rank2 requires rank1 completion")
	check(model.set_abyss_difficulty(1).success, "unlocked rank1 can be selected between runs")
	var ranked: Dictionary = model.prepare_abyss()
	check(ranked.success and ranked.config.difficulty == 1 and model.state.abyss.rogue.difficulty == 1, "rank snapshots into persisted encounter and expedition")
	check(not model.set_abyss_difficulty(0).success, "difficulty cannot change during an active expedition")
	var saved_meta: int = model.state.abyss.meta.currency
	check(model._bank_meta(20) == 25 and model.state.abyss.meta.currency == saved_meta + 25, "rank1 gives advertised25% permanent reward bonus")
	check(model.valid_save(model.state), "ranked expedition save validates")
	var malformed: Dictionary = model.state.duplicate(true)
	malformed.abyss.meta.selectedDifficulty = 4
	check(not model.valid_save(malformed), "rank above3 is rejected by import validation")
	malformed = model.state.duplicate(true)
	malformed.abyss.meta.selectedDifficulty = 2
	check(not model.valid_save(malformed), "locked chosen rank is rejected by import validation")
	model.state.abyss.rogue.floorsCleared = 20
	model._end_abyss_run("victory")
	check(model.state.abyss.meta.unlockedDifficulty == 2 and model.state.abyss.lastRun.difficulty == 1, "clearing rank1 unlocks rank2 and records rank")
	model.set_abyss_difficulty(2)
	model._init_rogue_run()
	model._end_abyss_run("victory")
	model.set_abyss_difficulty(3)
	model._init_rogue_run()
	model._end_abyss_run("victory")
	check(model.state.abyss.meta.unlockedDifficulty == 3, "difficulty unlocks remain bounded at rank3")

func run() -> void:
	test_events()
	test_rest_shop_routes()
	test_caps_meta_and_rollback()
	test_full_expedition()
	print("V2 PROGRESSION TESTS: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)
