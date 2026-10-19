extends SceneTree
## Adversarial v2 checks use isolated saves and exercise public model entrypoints.

const Game = preload("res://scripts/game_model.gd")
const Battle = preload("res://scripts/battle_model.gd")
var passed := 0
var failed := 0
var work := "/tmp/voidrift-v2-regression-%d" % Time.get_ticks_usec()

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, name: String) -> void:
	if condition:
		passed += 1
		print("PASS: " + name)
	else:
		failed += 1
		push_error("FAIL: " + name)

func snapshot(model) -> String:
	return JSON.stringify(model.state)

func mature(directory: String = ""):
	var model = Game.new(directory)
	model.rng.seed = 20261017
	for id in model.catalog.CharacterData:
		model.state.ownedCharacters[id] = model.default_character()
		model.state.ownedCharacters[id].level = 10
		model.state.ownedCharacters[id].constellation = 6
	model.set_team(["kaldi", "ayla", "gus"])
	model.save_game()
	return model

func battle_result(model, config: Dictionary) -> Dictionary:
	var battle = Battle.new(model.catalog)
	battle.start(config, model.battle_party(bool(config.get("isAbyss", false))), model.rogue_effects())
	var steps := 0
	while battle.state.phase not in ["victory", "defeat"] and steps < 3000:
		var action: Dictionary = battle.auto_step()
		if not action.get("success", false):
			break
		steps += 1
	check(battle.state.phase in ["victory", "defeat"], "battle terminates within action budget")
	return battle.state.duplicate(true)

func test_encounter_persistence() -> void:
	var directory := work.path_join("encounter")
	var model = mature(directory)
	var prepared: Dictionary = model.prepare_abyss()
	check(prepared.get("success", false), "abyss encounter starts")
	if not prepared.get("success", false):
		return
	var config: Dictionary = prepared.config
	check(config.has("seed"), "encounter includes deterministic battle seed")
	var again: Dictionary = model.prepare_abyss()
	check(again.get("success", false) and again.get("config", {}) == config, "repeated prepare preserves encounter, rewards, token and seed")
	var restored = Game.new(directory)
	check(not restored.save_blocked, "active encounter save reloads cleanly")
	var resumed: Dictionary = restored.prepare_abyss()
	check(resumed.get("success", false) and resumed.get("config", {}) == config, "reload resumes identical issued encounter")
	if not resumed.get("success", false):
		return
	var result := battle_result(model, config)
	var replay := battle_result(restored, resumed.config)
	check(result == replay, "identical encounter replays identical combat after reload")
	var before := snapshot(restored)
	check(not restored.prepare_stage("ch1_1").get("success", true) and snapshot(restored) == before, "story cannot overwrite pending abyss encounter")
	var stale := result.duplicate(true)
	stale.config.token = "expired-encounter-token"
	check(not restored.finish_battle(config, stale).get("success", true) and snapshot(restored) == before, "stale battle-state token cannot settle active encounter")
	var altered := config.duplicate(true)
	altered.rewards = {"gold": 999999999, "diamonds": 999999999, "exp": 999999999}
	var gold_before := int(restored.state.resources.gold)
	var settled: Dictionary = restored.finish_battle(altered, replay)
	check(settled.get("success", false), "matching replay settles after reload")
	check(int(restored.state.resources.gold) - gold_before < 999999999, "settlement uses issued rewards rather than caller changes")
	before = snapshot(restored)
	check(not restored.finish_battle(config, replay).get("success", true) and snapshot(restored) == before, "duplicate settlement cannot pay twice")
	var final_reload = Game.new(directory)
	check(not final_reload.finish_battle(config, replay).get("success", true), "settled token remains invalid after reload")

func test_run_lock_and_defeat() -> void:
	var model = mature()
	var prepared: Dictionary = model.prepare_abyss()
	if not prepared.get("success", false):
		check(false, "run lock test starts encounter")
		return
	var before := snapshot(model)
	check(not model.set_team(["ember", "zeph", "tide"]).get("success", true) and snapshot(model) == before, "active run prevents swapping wounded roster for fresh units")
	var outcome := battle_result(model, prepared.config)
	check(model.finish_battle(prepared.config, outcome).get("success", false), "run advances through first settlement")
	before = snapshot(model)
	check(not model.set_team(["ember", "zeph", "tide"]).get("success", true) and snapshot(model) == before, "party lock persists between encounters")
	if not model.state.abyss.rogue.pendingChoices.is_empty():
		var reward: Dictionary = model.state.abyss.rogue.pendingChoices[0]
		check(model.choose_abyss_reward(str(reward.get("choiceId", reward.id))).get("success", false), "mandatory opening blessing resolves")
	var next: Dictionary = model.prepare_abyss()
	if not next.get("success", false):
		check(false, "second encounter ready before defeat")
		return
	var abandoned: Dictionary = model.abandon_battle(next.config)
	check(abandoned.get("success", false), "abandon resolves current expedition")
	check(int(model.state.abyss.currentFloor) == 1, "defeat returns next expedition to floor one")
	check(model.state.abyss.savedPartyState == null, "defeat clears carried party health")
	check(model.state.abyss.rogue.selectedRewards.is_empty() and model.state.abyss.rogue.pendingChoices.is_empty(), "defeat clears temporary build and pending choices")
	check(model.set_team(["ember", "zeph", "tide"]).get("success", false), "roster can change after expedition ends")
	before = snapshot(model)
	check(not model.finish_battle(next.config, {"phase": "victory"}).get("success", true) and snapshot(model) == before, "abandoned encounter cannot pay later victory")

func test_transaction_rollback() -> void:
	var model = mature()
	var before := snapshot(model)
	model.save_blocked = true
	check(not model.prepare_abyss().get("success", true) and snapshot(model) == before, "failed encounter save rolls back run creation")
	model.save_blocked = false
	var prepared: Dictionary = model.prepare_abyss()
	if not prepared.get("success", false):
		check(false, "rollback settlement test starts encounter")
		return
	var outcome := battle_result(model, prepared.config)
	before = snapshot(model)
	model.save_blocked = true
	check(not model.finish_battle(prepared.config, outcome).get("success", true) and snapshot(model) == before, "failed settlement save rolls back resources, floor, and meta")
	model.save_blocked = false
	check(model.finish_battle(prepared.config, outcome).get("success", false), "failed settlement keeps token available for retry")
	before = snapshot(model)
	check(not model.finish_battle(prepared.config, outcome).get("success", true) and snapshot(model) == before, "successful retry consumes settlement token exactly once")

func test_meta_economy() -> void:
	var model = mature()
	var before: Dictionary = model.state.abyss.meta.duplicate(true)
	for item in model.catalog.ShopData.rechargeItems:
		check(model.purchase("recharge", str(item.id)).get("success", false), "sandbox recharge remains available")
	check(model.state.abyss.meta == before and int(model.state.abyss.rogue.temporaryCurrency) == 0, "sandbox recharge cannot mint earned expedition currencies")
	var upgrades: Array = model.meta_upgrade_list()
	check(upgrades.size() == 4, "four bounded persistent upgrade tracks are exposed")
	if upgrades.is_empty():
		return
	var id := str(upgrades[0].id)
	var original := snapshot(model)
	check(not model.purchase_meta_upgrade(id).get("success", true) and snapshot(model) == original, "unfunded meta purchase is atomic")
	model.state.abyss.meta.currency = 100000
	model.state.abyss.meta.totalEarned = 100000
	model.save_game()
	for upgrade in upgrades:
		var key := str(upgrade.id)
		var bought := 0
		for attempt in range(10):
			var old_currency := int(model.state.abyss.meta.currency)
			var old_level := int(model.state.abyss.meta.upgrades[key])
			var result: Dictionary = model.purchase_meta_upgrade(key)
			if not result.get("success", false):
				break
			bought += 1
			check(int(model.state.abyss.meta.currency) < old_currency and int(model.state.abyss.meta.upgrades[key]) == old_level + 1, "meta purchase spends currency and advances exactly one rank")
		check(bought > 0 and bought < 10, "meta track has a finite purchase cap: " + key)
		original = snapshot(model)
		check(not model.purchase_meta_upgrade(key).get("success", true) and snapshot(model) == original, "maxed meta track rejects further spending: " + key)
	var another = mature()
	another.state.abyss.meta.currency = 1000
	another.state.abyss.meta.totalEarned = 1000
	another.prepare_abyss()
	original = snapshot(another)
	check(not another.purchase_meta_upgrade(id).get("success", true) and snapshot(another) == original, "meta upgrades are locked for active expedition")

func test_save_validation() -> void:
	var model = mature()
	check(model.valid_save(model.state), "v2 default and roster save validates")
	var legacy = Game.new("")
	check(legacy.import_save("res://tests/fixtures/web-save-v3.json").get("success", false), "legacy v3 save migrates")
	check(legacy.valid_save(legacy.state) and legacy.state.abyss.has("meta"), "migrated save gains valid persistent progression defaults")
	var partial: Dictionary = model.state.duplicate(true)
	partial.abyss.meta = {"currency": 0}
	partial.abyss.rogue = {"runId": null}
	check(model.valid_save(partial), "partial legacy-compatible progression fields can be defaulted")
	var malformed: Array = []
	var invalid: Dictionary = model.state.duplicate(true)
	invalid.abyss.meta.currency = -1
	malformed.append([invalid, "negative permanent currency"])
	invalid = model.state.duplicate(true)
	invalid.abyss.meta.upgrades.vitality = 999
	malformed.append([invalid, "out-of-range meta level"])
	invalid = model.state.duplicate(true)
	invalid.abyss.meta.upgrades = []
	malformed.append([invalid, "wrong meta upgrades type"])
	invalid = model.state.duplicate(true)
	invalid.abyss.rogue.temporaryCurrency = -1
	malformed.append([invalid, "negative run currency"])
	invalid = model.state.duplicate(true)
	invalid.abyss.rogue.runTeam = ["unknown-character"]
	malformed.append([invalid, "unknown locked roster member"])
	invalid = model.state.duplicate(true)
	invalid.abyss.rogue.pendingNode = []
	malformed.append([invalid, "wrong pending node type"])
	invalid = model.state.duplicate(true)
	invalid.abyss.rogue.activeEncounter = {"unexpected": true}
	malformed.append([invalid, "incomplete persisted encounter"])
	invalid = model.state.duplicate(true)
	invalid.abyss.rogue.nextStep.type = "unsupported-node"
	malformed.append([invalid, "unknown node state"])
	invalid = model.state.duplicate(true)
	invalid.abyss.rogue.floorsCleared = -1
	malformed.append([invalid, "negative cleared floors"])
	for sample in malformed:
		check(not model.valid_save(sample[0]), "save validation rejects " + str(sample[1]))
	var active = mature()
	active.prepare_abyss()
	var active_base: Dictionary = active.state.duplicate(true)
	invalid = active_base.duplicate(true)
	invalid.abyss.rogue.activeEncounter = {}
	invalid.abyss.rogue.nextStep = {"type": "reward", "floor": 1}
	check(not active.valid_save(invalid), "empty mandatory blessing gate cannot strand imported run")
	invalid = active_base.duplicate(true)
	invalid.abyss.rogue.activeEncounter = {}
	invalid.abyss.currentFloor = 2
	invalid.abyss.rogue.floorsCleared = 1
	check(not active.valid_save(invalid), "advanced run requires persisted roster health")
	invalid = active_base.duplicate(true)
	invalid.abyss.savedPartyState = [{"id": "kaldi"}]
	check(not active.valid_save(invalid), "incomplete carried unit rejects cleanly without exception")
	invalid = active_base.duplicate(true)
	for index in range(15):
		invalid.abyss.rogue.selectedRewards.append(active.catalog.AbyssData.rogue.rewards[0].duplicate(true))
	check(not active.valid_save(invalid), "import cannot exceed a blessing stack limit")

func resolve_pending(model, visited: Dictionary) -> bool:
	for guard in range(5):
		var kind := str(model.state.abyss.rogue.nextStep.type)
		if kind == "none":
			return true
		visited[kind] = true
		var before := snapshot(model)
		check(not model.prepare_abyss().get("success", true) and snapshot(model) == before, "pending " + kind + " blocks encounter skipping")
		if kind == "reward":
			check(not model.choose_abyss_reward("stale-choice").get("success", true) and snapshot(model) == before, "unknown blessing selection is atomic")
			var choices: Array = model.state.abyss.rogue.pendingChoices
			if choices.is_empty():
				return false
			var choice := str(choices[0].get("choiceId", choices[0].id))
			var result: Dictionary = model.choose_abyss_reward(choice)
			check(result.get("success", false), "valid blessing selection advances")
			before = snapshot(model)
			check(not model.choose_abyss_reward(choice).get("success", true) and snapshot(model) == before, "blessing callback replay cannot duplicate reward")
		elif kind in ["route", "event", "rest"]:
			check(not model.choose_abyss_node("stale-node").get("success", true) and snapshot(model) == before, "unknown " + kind + " option is atomic")
			var node: Dictionary = model.node_options()
			var choices: Array = node.get("options", [])
			var selected := ""
			if kind == "route":
				for option in choices:
					if not visited.has(str(option.id)):
						selected = str(option.id)
						break
			for option in choices:
				if selected.is_empty() and bool(option.get("enabled", false)) and int(option.get("cost", 0)) == 0:
					selected = str(option.id)
					break
			if selected.is_empty():
				return false
			check(model.choose_abyss_node(selected).get("success", false), "valid " + kind + " option resolves")
			before = snapshot(model)
			check(not model.choose_abyss_node(selected).get("success", true) and snapshot(model) == before, "replayed " + kind + " option cannot grant twice")
		elif kind == "shop":
			var stock: Array = model.abyss_shop_items()
			check(stock.size() >= 3, "shop presents supplies and blessing stock")
			var restored = Game.new(model.save_dir)
			check(restored.state.abyss.rogue.shopStock == model.state.abyss.rogue.shopStock, "shop stock persists without reload reroll")
			check(not model.purchase_abyss_item("missing-item").get("success", true) and snapshot(model) == before, "unknown shop item cannot spend currency")
			if int(model.state.abyss.rogue.temporaryCurrency) >= 35:
				model.state.abyss.savedPartyState[0].currentHp = 0
				model.state.abyss.savedPartyState[1].currentHp = int(model.state.abyss.savedPartyState[1].maxHp / 2)
				model.save_game()
				before = snapshot(model)
				model.save_blocked = true
				check(not model.purchase_abyss_item("heal").get("success", true) and snapshot(model) == before, "failed shop commit rolls back spend, healing and sold flag")
				model.save_blocked = false
				var coins := int(model.state.abyss.rogue.temporaryCurrency)
				check(model.purchase_abyss_item("heal").get("success", false), "healing supply purchase succeeds")
				check(int(model.state.abyss.rogue.temporaryCurrency) == coins - 35 and int(model.state.abyss.savedPartyState[0].currentHp) > 0, "healing supply pays exact price and revives fallen ally")
				before = snapshot(model)
				check(not model.purchase_abyss_item("heal").get("success", true) and snapshot(model) == before, "sold shop item cannot be repurchased")
				restored = Game.new(model.save_dir)
				check(not restored.purchase_abyss_item("heal").get("success", true), "sold flag persists across reload")
			check(model.leave_abyss_shop().get("success", false), "leaving shop resumes path")
			before = snapshot(model)
			check(not model.leave_abyss_shop().get("success", true) and snapshot(model) == before, "replayed shop exit is atomic")
		else:
			return false
	return false

func test_complete_node_journey() -> void:
	var model = mature(work.path_join("journey"))
	var visited: Dictionary = {}
	var last_config: Dictionary = {}
	var last_result: Dictionary = {}
	for floor_number in range(1, 21):
		if not resolve_pending(model, visited):
			check(false, "every pending node has a usable continuation")
			return
		var prepared: Dictionary = model.prepare_abyss()
		check(prepared.get("success", false), "complete journey launches floor " + str(floor_number))
		if not prepared.get("success", false):
			return
		var outcome := battle_result(model, prepared.config)
		check(outcome.phase == "victory", "prepared mature party clears journey floor " + str(floor_number))
		if outcome.phase != "victory":
			return
		var earned_before := int(model.state.abyss.meta.currency)
		check(model.finish_battle(prepared.config, outcome).get("success", false), "journey settlement succeeds")
		check(int(model.state.abyss.meta.currency) > earned_before, "successful floor immediately banks permanent progression")
		check(model.valid_save(model.state), "each floor produces a valid reloadable save")
		last_config = prepared.config
		last_result = outcome
	for kind in ["reward", "route", "event", "rest", "shop"]:
		check(visited.has(kind), "full journey exercises " + kind)
	check(not model.abyss_run_active() and int(model.state.abyss.currentFloor) == 1, "final boss closes run and prepares floor one")
	check(int(model.state.abyss.meta.runsCompleted) == 1 and int(model.state.abyss.meta.currency) > 0, "completed expedition records completion and retains earned progression")
	check(int(model.state.abyss.meta.unlockedDifficulty) == 1, "first completion unlocks exactly the next difficulty")
	check(int(model.state.abyss.rogue.temporaryCurrency) == 0 and model.state.abyss.rogue.selectedRewards.is_empty(), "completed expedition clears temporary currencies and blessings")
	var before := snapshot(model)
	check(not model.finish_battle(last_config, last_result).get("success", true) and snapshot(model) == before, "final boss settlement cannot duplicate completion payout")
	var restored = Game.new(model.save_dir)
	var summary_matches: bool = not restored.save_blocked and str(restored.state.abyss.lastRun.get("outcome", "")) == str(model.state.abyss.lastRun.outcome)
	for key in ["floorsCleared", "metaEarned", "blessings", "coinsLost"]:
		summary_matches = summary_matches and int(restored.state.abyss.lastRun.get(key, -1)) == int(model.state.abyss.lastRun[key])
	check(summary_matches, "completed run summary survives disk reload")

func test_difficulty_progression() -> void:
	var model = mature(work.path_join("difficulty"))
	var options: Array = model.abyss_difficulty_options()
	check(options.size() == 4 and bool(options[0].unlocked) and not bool(options[1].unlocked), "fresh save exposes four progressively locked difficulties")
	var before := snapshot(model)
	for rank in [-1, 1, 4]:
		check(not model.set_abyss_difficulty(rank).get("success", true) and snapshot(model) == before, "locked or invalid difficulty selection is atomic: " + str(rank))
	for key in ["selectedDifficulty", "unlockedDifficulty"]:
		for value in [-1, 4, 1.5, "1", {}]:
			var malformed: Dictionary = model.state.duplicate(true)
			malformed.abyss.meta[key] = value
			check(not model.valid_save(malformed), "save rejects malformed difficulty " + key + ": " + str(value))
	var malformed: Dictionary = model.state.duplicate(true)
	malformed.abyss.meta.selectedDifficulty = 1
	check(not model.valid_save(malformed), "save cannot select difficulty beyond unlocked rank")
	model.state.abyss.meta.unlockedDifficulty = 3
	check(model.set_abyss_difficulty(3).get("success", false), "unlocked highest difficulty can be selected")
	var prepared: Dictionary = model.prepare_abyss()
	check(prepared.get("success", false) and int(prepared.config.get("difficulty", -1)) == 3, "encounter snapshots chosen difficulty")
	before = snapshot(model)
	check(not model.set_abyss_difficulty(0).get("success", true) and snapshot(model) == before, "active expedition difficulty cannot change")
	malformed = model.state.duplicate(true)
	malformed.abyss.rogue.activeEncounter.difficulty = 0
	check(not model.valid_save(malformed), "persisted encounter rank must match active run")
	var restored = Game.new(model.save_dir)
	var resumed: Dictionary = restored.prepare_abyss()
	check(resumed.get("success", false) and int(resumed.config.get("difficulty", -1)) == 3, "difficulty persists on encounter reload")
	var outcome := battle_result(model, prepared.config)
	check(outcome.phase == "victory", "mature party can exercise highest-rank settlement")
	var earned_before := int(model.state.abyss.meta.currency)
	var settlement: Dictionary = model.finish_battle(prepared.config, outcome)
	var actual_gain := int(model.state.abyss.meta.currency) - earned_before
	check(settlement.get("success", false) and actual_gain > 3, "difficulty increases actual permanent reward")
	check(int(settlement.get("rewards", {}).get("meta", -1)) == actual_gain, "settlement reports actual scaled meta reward")
	var visited: Dictionary = {}
	if not resolve_pending(model, visited):
		check(false, "difficulty journey can resolve opening choice")
		return
	prepared = model.prepare_abyss()
	if not prepared.get("success", false):
		check(false, "difficulty event test launches second floor")
		return
	outcome = battle_result(model, prepared.config)
	check(model.finish_battle(prepared.config, outcome).get("success", false), "difficulty event test settles second floor")
	# Select a specific canonical event to verify its scaled reward accounting.
	model.state.abyss.rogue.pendingNode.eventId = "lost_caravan"
	check(model.choose_abyss_node("event").get("success", false), "difficulty event route opens")
	earned_before = int(model.state.abyss.meta.currency)
	var event_result: Dictionary = model.choose_abyss_node("escort")
	actual_gain = int(model.state.abyss.meta.currency) - earned_before
	check(event_result.get("success", false) and actual_gain == 14, "highest-rank event applies promised permanent reward multiplier")
	check(int(event_result.get("outcome", {}).get("meta", -1)) == actual_gain, "event result reports actual scaled meta reward")

func run() -> void:
	DirAccess.make_dir_recursive_absolute(work)
	test_encounter_persistence()
	test_run_lock_and_defeat()
	test_transaction_rollback()
	test_meta_economy()
	test_save_validation()
	test_complete_node_journey()
	test_difficulty_progression()
	print("V2 ADVERSARIAL REGRESSIONS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)
