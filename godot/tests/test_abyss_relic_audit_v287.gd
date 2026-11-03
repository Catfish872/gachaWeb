extends SceneTree
const Game = preload("res://scripts/game_model.gd")
const TARGET := "aurora_prayer"
var checks := 0
var failures := 0

func ck(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func _init() -> void:
	if "--delta-only" in OS.get_cmdline_user_args():
		post_fifty_delta()
		print("ABYSS RELIC POST50 V287: %d checks, %d failures" % [checks, failures])
		quit(0 if failures == 0 else 1)
		return
	expectations_and_rolls()
	issued_settlements()
	reload_and_retry()
	legacy_run()
	post_fifty_delta()
	print("ABYSS RELIC AUDIT V287: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func fixture(floor_number: int, rank: int):
	var g = Game.new("")
	g.rng.seed = 287000 + rank * 1000 + floor_number
	g.state.abyss.meta.unlockedDifficulty = 3
	g.set_abyss_difficulty(rank)
	g.set_abyss_relic_set(TARGET)
	g._init_rogue_run()
	# Isolate the reward boundary without replaying unrelated combat or events.
	g.state.abyss.currentFloor = floor_number
	g.state.abyss.rogue.floorsCleared = floor_number - 1
	if floor_number > 1:
		g.state.abyss.savedPartyState = []
		for unit in g.battle_party(false):
			g.state.abyss.savedPartyState.append({"id":unit.id,"currentHp":unit.maxHp,"maxHp":unit.maxHp,"energy":0,"cooldowns":{}})
	return g

func victory(config: Dictionary) -> Dictionary:
	return {"phase":"victory","config":config,"allies":config.partySnapshot.duplicate(true),"turn":1}

func expectations_and_rolls() -> void:
	var g = Game.new("")
	for rank in range(4):
		var info: Dictionary = g.abyss_relic_drop_info(rank)
		ck(is_equal_approx(info.expectedPer50, 10.0 + 4.0 * rank), "per-50 total expectation rank %d" % rank)
		ck(is_equal_approx(info.expectedFourStarPer50, 5.0 + 3.2 * rank), "per-50 four-star expectation rank %d" % rank)
		ck(is_equal_approx(info.expectedFiveStarPer50, 5.0 + 0.8 * rank), "per-50 five-star expectation rank %d" % rank)
		ck(is_equal_approx(info.expectedPer50, info.expectedFourStarPer50 + info.expectedFiveStarPer50), "display total includes both rarities")
	# Select one independent reward seed from each chance interval and rarity side.
	var chosen: Dictionary = {}
	for seed_value in range(1000):
		var r := RandomNumberGenerator.new()
		r.seed = seed_value ^ 0x51E7C0DE
		var roll := r.randf()
		var quality := r.randf()
		var interval := 0 if roll < 0.1 else (1 if roll < 0.2 else (2 if roll < 0.3 else 3))
		var key := "%d_%d" % [interval, int(quality >= 0.8)]
		if not chosen.has(key): chosen[key] = {"seed":seed_value,"roll":roll,"rarity":4 if quality < 0.8 else 5}
		if chosen.size() == 8: break
	ck(chosen.size() == 8, "bounded seeds cover all probability intervals and both rarity branches")
	var host_rng: int = g.rng.state
	for sample in chosen.values():
		for rank in range(4):
			var drop: Dictionary = g._abyss_relic_drop(49, rank, TARGET, int(sample.seed), "audit")
			var expected: bool = float(sample.roll) < float(g.rogue_data.relicDrops.normalChanceByDifficulty[rank])
			ck((not drop.is_empty()) == expected, "normal chance uses selected difficulty")
			if expected:
				ck(drop.rarity == sample.rarity and drop.item.setId == TARGET, "extra rarity and target set match signed item")
				ck(drop == g._abyss_relic_drop(49, rank, TARGET, int(sample.seed), "audit"), "same signed reward seed reproduces complete item")
		for floor_number in [5, 10, 50, 100, 250]:
			var drop: Dictionary = g._abyss_relic_drop(floor_number, 3, TARGET, int(sample.seed), "milestone")
			ck(drop.rarity == (5 if floor_number % 10 == 0 else 4) and drop.item.setId == TARGET, "milestones give one guaranteed target item")
	ck(g.rng.state == host_rng, "reward generation leaves host random stream untouched")

func issued_settlements() -> void:
	for rank in range(4):
		var floors: Array = [1, 5, 10, 50, 51, 100, 250] if rank == 3 else [1, 5, 10, 50]
		for floor_number in floors:
			var g = fixture(int(floor_number), rank)
			var prepared: Dictionary = g.prepare_abyss()
			ck(prepared.success and g.valid_save(g.state), "prepared floor %d rank %d validates" % [floor_number, rank])
			if not prepared.success: continue
			var config: Dictionary = prepared.config
			var expected: Dictionary = config.rewards.get("relicDrop", {}).get("item", {})
			var result: Dictionary = g.finish_battle(config, victory(config))
			ck(result.success and g.valid_save(g.state), "real settlement validates")
			if not result.success: continue
			ck(result.relic == expected and g.state.relics.size() == (0 if expected.is_empty() else 1), "inventory receives exactly the signed item")
			if not expected.is_empty(): ck(result.relic.setId == TARGET, "actual payout always belongs to target set")
			ck(not result.firstClear and int(result.rewards.gold) == 0, "relic settlement independent of first-clear and direct gold")
			if int(floor_number) % 5 == 0: ck(int(result.relic.rarity) == (5 if int(floor_number) % 10 == 0 else 4), "actual milestone rarity guaranteed")
			var retained: Array = g.state.relics.duplicate(true)
			ck(g.reset_abyss().success and g.state.relics == retained, "retreat retains earned inventory")

func reload_and_retry() -> void:
	var g = fixture(100, 3)
	var prepared: Dictionary = g.prepare_abyss()
	var saved: Dictionary = JSON.parse_string(JSON.stringify(g.state))
	ck(g.valid_save(saved), "issued encounter survives JSON save validation")
	var restored = Game.new("")
	restored.state = restored._normalize(saved)
	var resumed: Dictionary = restored.prepare_abyss()
	# Compare both sides in save-file form: normalization restores integer types.
	ck(resumed.resumed and JSON.parse_string(JSON.stringify(resumed.config)) == JSON.parse_string(JSON.stringify(prepared.config)), "resume retains complete signed encounter values")
	ck(resumed.config.seed == prepared.config.seed and resumed.config.token == prepared.config.token and resumed.config.targetRelicSetId == TARGET, "resume preserves reward seed token and target")
	var host_rng: int = restored.rng.state
	ck(restored.prepare_abyss().config == resumed.config and restored.rng.state == host_rng, "repeat prepare uses zero random draws")
	var before: Dictionary = restored.state.duplicate(true)
	ck(not restored.set_abyss_relic_set("flame_oath").success and restored.state == before, "target selection remains locked")
	restored.save_blocked = true
	ck(not restored.finish_battle(resumed.config, victory(resumed.config)).success and restored.state == before, "failed persistence rolls back inventory and floor together")
	restored.save_blocked = false
	var result: Dictionary = restored.finish_battle(resumed.config, victory(resumed.config))
	ck(result.success and result.relic == resumed.config.rewards.relicDrop.item and restored.state.relics.size() == 1, "retry pays signed item once")
	before = restored.state.duplicate(true)
	ck(not restored.finish_battle(resumed.config, victory(resumed.config)).success and restored.state == before, "duplicate settlement rejected atomically")
	ck(restored.reset_abyss().success and restored.state.relics.size() == 1, "return to camp retains payout")
	# A second visit at the same daily milestone still grants a separate relic.
	restored._init_rogue_run()
	restored.state.abyss.currentFloor = 100
	restored.state.abyss.rogue.floorsCleared = 99
	restored.state.abyss.savedPartyState = g.state.abyss.savedPartyState.duplicate(true)
	var repeat: Dictionary = restored.prepare_abyss()
	var repeat_result: Dictionary = restored.finish_battle(repeat.config, victory(repeat.config))
	ck(repeat_result.success and repeat_result.dailyAward.amount == 0 and restored.state.relics.size() == 2, "daily crystal limit leaves repeat relic payout intact")
	ck(restored.state.relics[0].uid != restored.state.relics[1].uid, "same milestone produces separate inventory entries")
	var retained: Array = restored.state.relics.duplicate(true)
	restored.reset_abyss()
	var next: Dictionary = restored.prepare_abyss()
	ck(restored.finish_battle(next.config, {"phase":"defeat"}).success and restored.state.relics == retained, "defeat retains prior items and gives no current reward")

func legacy_run() -> void:
	var g = fixture(10, 3)
	g.prepare_abyss()
	var saved: Dictionary = g.state.duplicate(true)
	saved.version = 8
	saved.abyss.rogue.erase("targetRelicSetId")
	saved.abyss.rogue.erase("relicRewardVersion")
	saved.abyss.rogue.activeEncounter.erase("targetRelicSetId")
	saved.abyss.rogue.activeEncounter.erase("relicRewardVersion")
	saved.abyss.rogue.activeEncounter.rewards.relicDrop = {"slotId":"helmet","rarity":5}
	ck(g.valid_save(saved), "pre-target active save remains valid")
	var old = Game.new("")
	old.state = old._normalize(saved)
	var info: Dictionary = old.abyss_relic_drop_info()
	ck(info.legacy and info.normalChance == 0 and info.expectedPer50 == 10 and info.targetSetId == "", "legacy UI reports ten loose pieces rather than targeted twenty-two")
	var prepared: Dictionary = old.prepare_abyss()
	var result: Dictionary = old.finish_battle(prepared.config, victory(prepared.config))
	ck(result.success and not result.relic.has("setId"), "legacy issued reward remains its original loose piece")
	old.reset_abyss()
	var next: Dictionary = old.prepare_abyss()
	ck(next.success and next.config.relicRewardVersion == 1 and next.config.targetRelicSetId == TARGET and old.state.relics.size() == 1, "next run activates targeted rewards while preserving legacy item")

func post_fifty_delta() -> void:
	var g = Game.new("")
	var branches: Dictionary = {}
	for seed_value in range(1000):
		var old_drop: Dictionary = g._abyss_relic_drop(49, 3, TARGET, seed_value, "boundary")
		var rarity: int = int(old_drop.get("rarity", 0))
		if branches.has(rarity): continue
		branches[rarity] = seed_value
		var new_drop: Dictionary = g._abyss_relic_drop(51, 3, TARGET, seed_value, "boundary")
		ck(old_drop.is_empty() == new_drop.is_empty(), "51st-floor change preserves exact drop occurrence")
		if not old_drop.is_empty():
			ck(new_drop.rarity == 5 and new_drop.item.rarity == 5 and new_drop.item.setId == TARGET, "51st-floor ordinary drop is targeted five-star")
			ck(old_drop.slotId == new_drop.slotId, "rarity upgrade preserves slot roll")
			ck(new_drop == g._abyss_relic_drop(51, 3, TARGET, seed_value, "boundary"), "new five-star item remains reproducible")
		if branches.size() == 3: break
	ck(branches.has(0) and branches.has(4) and branches.has(5), "pre-50 ordinary no-drop four-star and five-star branches retained")
	for floor_number in [5, 45, 50, 55, 60, 100]:
		var run = fixture(floor_number, 3)
		var prepared: Dictionary = run.prepare_abyss()
		var expected: int = 4 if floor_number < 51 and floor_number % 10 != 0 else 5
		ck(prepared.success and int(prepared.config.rewards.relicDrop.rarity) == expected, "prepared boundary rarity at floor %d" % floor_number)
		var result: Dictionary = run.finish_battle(prepared.config, victory(prepared.config))
		ck(result.success and int(result.relic.rarity) == expected and run.state.relics.size() == 1 and result.relic.setId == TARGET, "boundary pays one exact target relic")
	# Ordinary floor 51: find a fixed preparation seed with a real drop.
	var ordinary_seen := false
	for offset in range(20):
		var run = fixture(51, 3)
		run.rng.seed = 2875100 + offset
		var prepared: Dictionary = run.prepare_abyss()
		if not prepared.config.rewards.has("relicDrop"): continue
		var saved: Dictionary = JSON.parse_string(JSON.stringify(run.state))
		var resumed = Game.new("")
		resumed.state = resumed._normalize(saved)
		var restored: Dictionary = resumed.prepare_abyss()
		var result: Dictionary = resumed.finish_battle(restored.config, victory(restored.config))
		ck(result.success and result.relic.rarity == 5 and result.relic == restored.config.rewards.relicDrop.item and resumed.state.relics.size() == 1, "new ordinary five-star reward survives save resume and settlement")
		ordinary_seen = true
		break
	ck(ordinary_seen, "bounded ordinary preparation fixture found")
	# Existing signed four-star gear must survive an update exactly as issued.
	var staged = fixture(55, 3)
	var prepared: Dictionary = staged.prepare_abyss()
	var saved: Dictionary = staged.state.duplicate(true)
	var signed: Dictionary = saved.abyss.rogue.activeEncounter.rewards.relicDrop
	var old_item: Dictionary = staged.generate_relic(4, str(signed.slotId), TARGET)
	old_item.uid = signed.item.uid
	signed.rarity = 4
	signed.item = old_item
	ck(staged.valid_save(saved), "pre-update signed four-star at floor55 remains valid")
	var resumed = Game.new("")
	resumed.state = resumed._normalize(JSON.parse_string(JSON.stringify(saved)))
	var restored: Dictionary = resumed.prepare_abyss()
	ck(restored.resumed and restored.config.rewards.relicDrop.item.rarity == 4 and JSON.parse_string(JSON.stringify(restored.config.rewards.relicDrop.item)) == JSON.parse_string(JSON.stringify(old_item)), "old signed item is preserved rather than rerolled or upgraded")
	var result: Dictionary = resumed.finish_battle(restored.config, victory(restored.config))
	ck(result.success and result.relic.rarity == 4 and resumed.state.relics.size() == 1, "old pending reward settles once at its signed rarity")
	var legacy = fixture(55, 3)
	legacy.state.abyss.rogue.relicRewardVersion = 0
	legacy.state.abyss.rogue.targetRelicSetId = ""
	var legacy_prepared: Dictionary = legacy.prepare_abyss()
	ck(legacy_prepared.success and legacy_prepared.config.rewards.relicDrop.rarity == 5 and not legacy_prepared.config.rewards.relicDrop.has("item"), "legacy run keeps loose-item count while new post50 milestone is five-star")
	var info: Dictionary = g.abyss_relic_drop_info(3)
	ck(info.fiveStarFromFloor == 51 and info.expectedPer50 == 22 and is_equal_approx(info.expectedFiveStarPer50 + info.expectedPer50, 29.4), "100-floor total remains44 with29.4 expected five-star items")
