extends SceneTree

const Model = preload("res://scripts/game_model.gd")
var passed := 0
var failed := 0
var work := "/tmp/full-godot-model-test-%d" % Time.get_ticks_usec()

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(work)
	_test_defaults_and_progression()
	_test_gacha()
	_test_original_gacha_parity()
	_test_relics()
	_test_stamina_and_shop()
	_test_stages()
	_test_abyss()
	_test_persistence()
	_test_save_regressions()
	print("MODEL TEST RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func check(condition: bool, name: String) -> void:
	if condition:
		passed += 1
		print("PASS ", name)
	else:
		failed += 1
		printerr("FAIL ", name)

func write_json(path: String, value: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()

func _test_defaults_and_progression() -> void:
	var m = Model.new("")
	check(m.valid_save(m.state), "default save validates")
	check(m.catalog.CharacterData.size() == 10 and m.stage_list().size() == 10, "all ten characters and stages loaded")
	check(m.state.resources.diamonds == 1600 and m.state.resources.gold == 50000 and m.state.resources.stamina == 100, "original starter resources")
	check(m.battle_party().size() == 2 and m.state.ownedCharacters.ember.shards == 3, "starter team and shards")
	check(m.exp_to_next_level(1) == 50 and m.exp_to_next_level(2) == 200 and m.exp_to_next_level(9) == 5000 and m.exp_to_next_level(10) == 0, "original exponential EXP curve capped")
	var before: Dictionary = m.state.duplicate(true)
	check(not m.set_team([]).success and m.state == before, "empty party rejected atomically")
	check(not m.set_team(["ember", "ember"]).success and m.state == before, "duplicate party rejected atomically")
	check(not m.set_team(["kaldi"]).success and m.state == before, "unowned party rejected atomically")
	check(m.set_team(["zeph"]).success and m.state.team.size() == 3, "one-character party padded to three slots")
	check(m.set_team(["ember", "zeph"]).success, "starter party restored")
	var trained: Dictionary = m.train_character("ember")
	check(trained.success and trained.newLevel == 2 and m.state.ownedCharacters.ember.exp == 50 and m.state.resources.gold == 49500, "training spends 500 for100 EXP")
	m.state.ownedCharacters.ember.exp = 1000000
	m._normalize_progress(m.state.ownedCharacters.ember)
	check(m.state.ownedCharacters.ember.level == 10 and m.state.ownedCharacters.ember.exp == 0, "large EXP settles to capped level10")
	before = m.state.duplicate(true)
	check(not m.train_character("ember").success and m.state == before, "max-level training rejected without charging")
	m.state.ownedCharacters.ember.shards = 30
	for level in range(1, 7):
		check(m.unlock_constellation("ember").success and m.state.ownedCharacters.ember.constellation == level, "constellation C%d unlock" % level)
	check(not m.unlock_constellation("ember").success and m.state.ownedCharacters.ember.shards == 0, "C6 cap enforced")
	var info: Array = m.constellation_info("ember")
	check(info.size() == 6 and info[5].unlocked and info[5].buff.c6_type == "burn_chance_up", "constellation descriptions and exclusiveC6")
	var stats: Dictionary = m.computed_stats("ember")
	check(stats.maxHp > 850 and is_equal_approx(stats.normalDmgBonus, 0.15) and stats.skillCdReduce == 1, "level and constellation calculated stats")
	m.mark_dialogue_seen("ch1_1_pre")
	m.mark_dialogue_seen("unknown")
	check(m.state.dialogueSeen == {"ch1_1_pre": true}, "dialogue seen persists valid keys")

func _test_gacha() -> void:
	var m = Model.new("")
	var before: Dictionary = m.state.duplicate(true)
	check(not m.pull("missing", 1).success and m.state == before, "unknown pool rejected")
	check(not m.pull("standard", -1).success and m.state == before, "negative pulls rejected")
	check(not m.pull("standard", 1001).success and m.state == before, "oversized pull request rejected")
	m.random_source = func(): return 0.99
	var result: Dictionary = m.pull("standard", 10)
	check(result.success and result.cost == 1600 and result.results.size() == 10, "ten-pull cost and result count")
	check(int(result.results.back().rarity) == 4 and m.state.pityCounters.standard.count4 == 0, "tenth pull guarantees four-star")
	check(m.state.resources.diamonds == 0 and m.state.stats.totalPulls == 10, "pull currency and statistics")
	before = m.state.duplicate(true)
	check(not m.pull("standard", 1).success and m.state == before, "insufficient pull is atomic")
	m.state.resources.diamonds = 160000
	m.state.pityCounters.limited_kaldi.count = 89
	result = m.pull("limited_kaldi", 1)
	check(result.success and result.results[0].rarity == 5 and result.results[0].charId == "ayla" and m.state.pityCounters.limited_kaldi.guaranteedFeatured, "hard pity and lost featured flag")
	m.state.pityCounters.limited_kaldi.count = 89
	result = m.pull("limited_kaldi", 1)
	check(result.results[0].charId == "kaldi" and not m.state.pityCounters.limited_kaldi.guaranteedFeatured, "next hard pity guarantees featured")
	m.state.pityCounters.standard.count = 73
	check(is_equal_approx(m.pity_info("standard").rate5, 0.076), "soft pity starts at count73")
	m.state.pityCounters.standard.count = 89
	result = m.pull("standard", 1)
	check(result.results[0].shards == 25 and not result.results[0].isNew, "five-star duplicate gives25shards")
	m.state.pityCounters.limited_kaldi.count = 89
	var draws: Array = [0.6, 0.0]
	m.random_source = func(): return draws.pop_front()
	result = m.pull("limited_kaldi", 1)
	check(result.results[0].charId == "kaldi" and not result.results[0].isFeatured and m.state.pityCounters.limited_kaldi.guaranteedFeatured, "source nonfeatured Kaldi branch preserved")

func _test_relics() -> void:
	var m = Model.new("")
	m.rng.seed = 192837
	for rarity in [3, 4, 5]:
		for slot in m.catalog.RelicSlots:
			var relic: Dictionary = m.generate_relic(rarity, slot.id)
			check(relic.subStats.size() == rarity - 1 and m.add_relic(relic).success, "generate valid %d-star %s" % [rarity, slot.id])
	check(m.state.relics.size() == 15, "complete relic slot and rarity inventory")
	var uid: String = m.state.relics[0].uid
	check(m.relic_upgrade_cost_to_max(uid) == 8000 and m.relic_max_cost(uid) == 8000, "original0to25 upgrade cost exactly8000")
	var before: Dictionary = m.state.duplicate(true)
	check(not m.equip_relic(uid, "unknown").success and m.state == before, "invalid equip leaves ownership intact")
	check(m.equip_relic(uid, "ember").success and m.get_relic(uid).equippedBy == "ember", "equip links both inventory and owner")
	check(m.computed_stats("ember").maxHp > 850, "equipped relic stats contribute")
	check(m.equip_relic(uid, "zeph").success and not m.state.ownedCharacters.ember.equippedRelics.has("helmet"), "relic transfers between owners")
	var upgraded: Dictionary = m.upgrade_relic_to_max(uid)
	check(upgraded.success and upgraded.totalCost == 8000 and upgraded.boostedStats.size() == 6 and m.get_relic(uid).level == 25, "max upgrade six substat rolls")
	before = m.state.duplicate(true)
	check(not m.upgrade_relic(uid).success and m.state == before, "relic max25 prevents spending")
	var sold: Dictionary = m.batch_sell_relic_options({"all3Star": true, "all4Star": true, "allUnupgraded": true})
	check(sold.success and sold.count == 14 and m.state.relics.size() == 1 and m.get_relic(uid).equippedBy == "zeph", "combined bulk salvage protects equipped relic")
	check(m.unequip_relic("zeph", "helmet").success and m.get_relic(uid).equippedBy == null, "unequip maintains both links")
	sold = m.sell_relic(uid)
	check(sold.success and sold.gold == 550 and m.state.relics.is_empty(), "single salvage returns rarity plus upgrade value")
	check(not m.batch_sell_relics(3).success, "empty salvage reports failure")
	var a: Dictionary = m.generate_relic(5, "helmet")
	var b: Dictionary = m.generate_relic(4, "helmet")
	m.add_relic(a)
	m.add_relic(b)
	m.equip_relic(a.uid, "ember")
	m.equip_relic(b.uid, "ember")
	check(m.get_relic(a.uid).equippedBy == null and m.state.ownedCharacters.ember.equippedRelics.helmet == b.uid, "same-slot replacement unequips prior relic")
	check(m.sell_relic(b.uid).success and not m.state.ownedCharacters.ember.equippedRelics.has("helmet"), "single equipped salvage cleans owner map")

func _test_stamina_and_shop() -> void:
	var m = Model.new("")
	m.state.resources.stamina = 0
	m.state.resources.staminaLastUpdate = 1000
	check(m.recover_stamina(361500).recovered == 1 and m.state.resources.staminaLastUpdate == 361000, "stamina recovers six-minute ticks with remainder")
	check(m.stamina_time_remaining(361500) == 359500, "stamina countdown preserves remainder")
	check(m.recover_stamina(1000 + 200 * 360000).success and m.state.resources.stamina == 100, "offline stamina caps at100")
	m.state.resources.stamina = 300
	m.recover_stamina(1000 + 201 * 360000)
	check(m.state.resources.stamina == 300, "overflow stamina preserved during recovery")
	m.state.resources.stamina = 50
	m.state.resources.staminaLastUpdate = 5000
	check(m.recover_stamina(4000).success and m.state.resources.stamina == 50 and m.state.resources.staminaLastUpdate == 4000, "clock rollback resets baseline without granting stamina")
	var gold := int(m.state.resources.gold)
	check(m.purchase("item", "buy_diamonds_500").success and m.state.resources.gold == gold - 5000 and m.state.resources.diamonds == 2100, "gold item purchase")
	check(m.purchase("recharge", "recharge_supreme").success and m.state.resources.stamina == 300 and m.state.resources.diamonds == 5380, "simulated recharge rewards cap stamina300")
	m.purchase("item", "buy_stamina_60")
	check(m.state.resources.stamina == 300, "item stamina uses same overflow cap")
	m.state.resources.stamina = 500
	m.purchase("item", "buy_stamina_60")
	check(m.state.resources.stamina == 500, "legacy overflow above300 preserved without further growth")
	var before: Dictionary = m.state.duplicate(true)
	check(not m.purchase("fragment", "test").success and m.state == before, "reserved fragment shop has no mutations")
	check(not m.purchase("item", "wrong").success and m.state == before, "unknown shop item rejected")
	m.state.resources.gold = 0
	before = m.state.duplicate(true)
	check(not m.purchase("item", "buy_diamonds_500").success and m.state == before, "insufficient item currency atomic")

func _win(m, stage: String) -> Dictionary:
	var preparation: Dictionary = m.prepare_stage(stage)
	if not preparation.success:
		return preparation
	return m.finish_battle(preparation.config, {"config": preparation.config, "phase": "victory", "turn": 7, "allies": m.battle_party()})

func _test_stages() -> void:
	var m = Model.new("")
	var before: Dictionary = m.state.duplicate(true)
	check(not m.prepare_stage("ch2_1").success and m.state == before, "locked chapter rejected before stamina charge")
	check(not m.prepare_stage("unknown").success and m.state == before, "unknown stage rejected before stamina charge")
	m.state.team = []
	before = m.state.duplicate(true)
	check(not m.prepare_stage("ch1_1").success and m.state == before, "empty team rejected before stamina charge")
	m.set_team(["ember", "zeph"])
	var prep: Dictionary = m.prepare_stage("ch1_1")
	check(prep.success and m.state.resources.stamina == 94, "valid stage deducts original stamina")
	check(not m.finish_battle(prep.config, {"config": prep.config, "phase": "player_turn"}).success, "unfinished battle cannot settle")
	var malicious: Dictionary = prep.config.duplicate(true)
	malicious.rewards = {"diamonds": 999999}
	var result: Dictionary = m.finish_battle(malicious, {"config": prep.config, "phase": "victory", "turn": 7, "allies": m.battle_party()})
	check(result.success and result.rewards.diamonds == 15 and m.state.resources.diamonds == 1615, "first-clear gems awarded from authoritative config")
	before = m.state.duplicate(true)
	check(not m.finish_battle(prep.config, {"config": prep.config, "phase": "victory"}).success and m.state == before, "replayed victory cannot duplicate rewards")
	result = _win(m, "ch1_1")
	check(result.success and not result.firstClear and result.rewards.diamonds == 0 and m.state.resources.diamonds == 1615, "repeat stage excludes first-clear gems")
	check(not m.get_stage("ch1_4").unlocked, "cannot skip uncleared story stages")
	_win(m, "ch1_2")
	_win(m, "ch1_3")
	result = _win(m, "ch1_4")
	check(result.success and result.gift.isNew and m.state.ownedCharacters.has("kaldi"), "chapterone penultimate gift grants Kaldi")
	result = _win(m, "ch1_4")
	check(result.success and result.gift.is_empty() and m.state.ownedCharacters.kaldi.shards == 0, "chapter gift is one-time")
	result = _win(m, "ch1_5")
	check(result.success and m.get_stage("ch2_1").unlocked, "boss clear unlocks next chapter")
	m.state.resources.stamina = 100
	for stage_id in ["ch2_1", "ch2_2", "ch2_3"]:
		_win(m, stage_id)
	result = _win(m, "ch2_4")
	check(result.success and result.gift.charId == "ayla" and m.state.chapterGiftClaimed.ch2.claimed, "chaptertwo penultimate gift grants Ayla")
	prep = m.prepare_stage("ch2_1")
	var gold := int(m.state.resources.gold)
	result = m.abandon_battle(prep.config)
	check(result.success and not result.victory and m.state.resources.gold == gold, "retreat records defeat without rewards")
	check(m.state.stats.totalBattles == 12 and m.state.stats.totalVictories == 11, "victory and defeat statistics count once")
	m = Model.new("")
	m.state.ownedCharacters.kaldi = m.default_character()
	for stage_id in ["ch1_1", "ch1_2", "ch1_3"]:
		_win(m, stage_id)
	result = _win(m, "ch1_4")
	check(result.success and not result.gift.isNew and result.gift.shardsGained == 25 and m.state.ownedCharacters.kaldi.shards == 25, "gift duplicate converts25shards")
	var old: Dictionary = m.prepare_stage("ch1_1")
	prep = m.prepare_stage("ch1_2")
	check(not prep.success, "cannot overwrite a pending story encounter")
	check(m.finish_battle(old.config, {"config": old.config, "phase": "defeat"}).success, "original encounter still settles")

func _resolve_v2_nodes(m) -> void:
	for _guard in range(8):
		var kind: String = m.state.abyss.rogue.nextStep.get("type", "none")
		if kind == "none":
			return
		check(not m.prepare_abyss().success, "pending %s gates combat" % kind)
		if kind == "reward":
			var choices: Array = m.state.abyss.rogue.pendingChoices
			check(choices.size() == 3, "three distinct blessing choices")
			var id: String = choices[0].choiceId
			check(m.choose_abyss_reward(id).success, "blessing selected")
			check(not m.choose_abyss_reward(id).success, "blessing cannot replay")
		elif kind == "shop":
			check(m.leave_abyss_shop().success, "shop can leave without purchase")
		else:
			var options: Array = m.node_options().get("options", [])
			var selected := ""
			for option in options:
				if option.get("enabled", false) and int(option.get("cost", 0)) == 0:
					selected = str(option.id)
			check(not selected.is_empty(), "node has safe free option")
			if selected.is_empty():
				return
			check(m.choose_abyss_node(selected).success, "node resolves")
	check(false, "node resolution must terminate")

func _test_abyss() -> void:
	var m = Model.new("")
	m.state.ownedCharacters.kaldi = m.default_character()
	m.state.ownedCharacters.ayla = m.default_character()
	m.set_team(["kaldi", "ayla", "ember"])
	m.rng.seed = 665544
	var stamina := int(m.state.resources.stamina)
	for floor_number in range(1, 11):
		_resolve_v2_nodes(m)
		var prep: Dictionary = m.prepare_abyss()
		check(prep.success and prep.config.floor == floor_number and m.state.resources.stamina == stamina, "abyss floor%d prepares free" % floor_number)
		if not prep.success:
			return
		var units: Array = m.battle_party(true)
		for unit in units:
			unit.currentHp = 400
			unit.maxHp = 1000
			unit.energy = 37
			unit.cooldowns = {"kaldi_skill": 3}
		var result: Dictionary = m.finish_battle(prep.config, {"config": prep.config, "phase": "victory", "allies": units, "turn": 4})
		check(result.success and m.state.abyss.currentFloor == floor_number + 1 and m.state.abyss.maxFloor == floor_number, "abyss floor%d advances and records" % floor_number)
		check(result.success and result.rewards.runCoins > 0 and result.rewards.meta > 0, "floor win grants separate run and permanent currency")
		if floor_number in [1, 3, 6, 9, 10]:
			check(m.state.abyss.rogue.pendingChoices.size() == 3, "reward floor three choices")
		if floor_number == 10:
			check(m.state.abyss.rogue.pendingChoices.all(func(x): return x.rarity == "gold"), "boss offers gold blessings")
		var party: Array = m.battle_party(true)
		check(party[0].energy == 37 and party[0].cooldowns.kaldi_skill == 3 and party[0]._abyssSavedMaxHp == 1000, "HP-energy-cooldown state carried")
	_resolve_v2_nodes(m)
	check(m.state.abyss.rogue.selectedRewards.size() >= 5 and not m.rogue_effects().is_empty(), "selected blessings feed combat effects")
	check(m.state.abyss.rogue.eligibleCharacters == ["kaldi", "ayla"], "five-star eligibility captured")
	var heal_reward: Dictionary = {}
	for reward in m.catalog.AbyssData.rogue.rewards:
		if reward.id == "common_victory_heal_blue":
			heal_reward = reward.duplicate(true)
	m.state.abyss.rogue.selectedRewards = [heal_reward]
	var prep: Dictionary = m.prepare_abyss()
	m.finish_battle(prep.config, {"config": prep.config, "phase": "victory", "allies": [{"id": "kaldi", "currentHp": 400, "maxHp": 1000}, {"id": "ayla", "currentHp": 0, "maxHp": 1000}, {"id": "ember", "currentHp": 400, "maxHp": 1000}]})
	check(m.state.abyss.savedPartyState[0].currentHp == 580 and m.state.abyss.savedPartyState[1].currentHp == 0, "victory recovery heals living18percent and preserves fallen")
	_resolve_v2_nodes(m)
	prep = m.prepare_abyss()
	var earned := int(m.state.abyss.meta.currency)
	m.finish_battle(prep.config, {"config": prep.config, "phase": "defeat"})
	check(m.state.abyss.currentFloor == 1 and m.state.abyss.maxFloor == 11 and m.state.abyss.savedPartyState == null and m.state.abyss.rogue.selectedRewards.is_empty(), "defeat resets floor and run but preserves best")
	check(m.state.abyss.meta.currency == earned and earned > 0, "earned permanent fragments survive defeat")
	var diamonds := int(m.state.resources.diamonds)
	check(m.reset_abyss(false, 1800000000000).success, "free restart")
	check(m.reset_abyss(false, 1800000000010).success, "repeat restart is free without daily wall")
	check(m.reset_abyss(true, 1800000000010).success and m.state.resources.diamonds == diamonds, "legacy paid flag no longer charges gems")
	check(m.can_free_abyss_reset(), "restarts always available")

func _test_persistence() -> void:
	var directory := work.path_join("saves")
	var m = Model.new(directory)
	check(FileAccess.file_exists(directory.path_join("slot1.json")), "new slot file persisted")
	m.purchase("item", "buy_diamonds_500")
	check(m.load_slot(2).success and m.state.resources.diamonds == 1600, "slot2 independent default")
	m.purchase("recharge", "recharge_traveler")
	var restarted = Model.new(directory)
	check(restarted.active_slot == 2 and restarted.state.resources.diamonds == 1660, "restart restores active slot and resources")
	check(m.load_slot(1).success and m.state.resources.diamonds == 2100, "switch restores slot1 resources")
	check(m.slot_summaries().size() == 3 and not m.slot_summaries()[2].hasData, "three summaries include empty slot")
	var exported := work.path_join("export.json")
	check(m.export_save(exported).success, "native export file created")
	var raw = JSON.parse_string(FileAccess.get_file_as_string(exported))
	check(raw.game == "void-rift-gacha" and raw.schema == 4 and raw.data.resources.diamonds == 2100, "export uses v4 envelope with original game identity")
	check(m.import_save("res://tests/fixtures/web-save-export.json", 3).success and m.active_slot == 1 and m.state.resources.diamonds == 2100, "inactive slot import preserves active state")
	var inactive_export := work.path_join("slot3-export.json")
	check(m.export_save(inactive_export, 3).success and m.active_slot == 1, "inactive slot export preserves active state")
	check(m.load_slot(3).success and m.state.resources.diamonds == 4321 and m.state.ownedCharacters.kaldi.level == 7, "original web export imports resources and progression")
	check(m.state.relics.size() == 1 and m.state.relics[0].equippedBy == "kaldi" and m.state.ownedCharacters.kaldi.equippedRelics.helmet == m.state.relics[0].uid, "web imported relic equipment links retained")
	check(m.state.stageProgress.ch1_1.cleared and m.state.chapterGiftClaimed.ch1.claimed and m.state.dialogueSeen.ch1_1_pre, "web imported progression and gift flags retained")
	check(m.import_save("res://tests/fixtures/web-save-v3.json").success, "raw webv3 save import")
	var before: Dictionary = m.state.duplicate(true)
	var persisted := FileAccess.get_file_as_string(directory.path_join("slot3.json"))
	var invalid := work.path_join("invalid.json")
	for value in [null, [], {}, {"data": null}, {"resources": {"gold": -1}, "ownedCharacters": {}}]:
		write_json(invalid, value)
		check(not m.import_save(invalid).success and m.state == before and FileAccess.get_file_as_string(directory.path_join("slot3.json")) == persisted, "malformed import preserves memory and disk")
	var malformed: Dictionary = before.duplicate(true)
	malformed.resources.staminaLastUpdate = []
	write_json(invalid, malformed)
	check(not m.import_save(invalid).success and m.state == before, "malformed nested timestamp rejected")
	malformed = before.duplicate(true)
	malformed.relics[0].subStats = [null]
	write_json(invalid, malformed)
	check(not m.import_save(invalid).success and m.state == before, "malformed relic rejected")
	var legacy: Dictionary = before.duplicate(true)
	legacy.version = 2
	legacy.erase("abyss")
	legacy.erase("dialogueSeen")
	legacy.erase("chapterGiftClaimed")
	legacy.customExtension = {"note": "preserved"}
	write_json(invalid, legacy)
	check(m.import_save(invalid).success and m.state.version == 4 and m.state.abyss.currentFloor == 1 and m.state.customExtension.note == "preserved", "v2 migration fills additions and preserves extension fields")
	check(m.reset_slot(2).success and m.active_slot == 3, "inactive slot reset leaves active selection")
	var corrupted_path := directory.path_join("slot3.json")
	var corrupt_file := FileAccess.open(corrupted_path, FileAccess.WRITE)
	corrupt_file.store_string("{broken save")
	corrupt_file.close()
	restarted = Model.new(directory)
	check(restarted.save_blocked and FileAccess.get_file_as_string(corrupted_path) == "{broken save", "corrupt startup preserves original bytes")
	before = restarted.state.duplicate(true)
	check(not restarted.purchase("recharge", "recharge_traveler").success and restarted.state == before and FileAccess.get_file_as_string(corrupted_path) == "{broken save", "corrupt slot blocks implicit overwrite")
	check(restarted.load_slot(1).success and not restarted.save_blocked, "valid slot accessible after corrupt slot")
	check(restarted.reset_slot(3).success, "explicit reset repairs corrupt slot")
	var blocker := work.path_join("blocker")
	write_json(blocker, {})
	m = Model.new("")
	m.save_dir = blocker.path_join("unwritable")
	before = m.state.duplicate(true)
	check(not m.pull("standard", 1).success and m.state == before, "failed gacha persistence rolls back currency-pity-collection")
	check(not m.train_character("ember").success and m.state == before, "failed training persistence rolls back character and gold")
	check(not m.purchase("recharge", "recharge_supreme").success and m.state == before, "failed shop persistence rolls back all resources")

func _test_save_regressions() -> void:
	var m = Model.new("")
	var before: Dictionary = m.state.duplicate(true)
	var malformed: Dictionary = before.duplicate(true)
	malformed.abyss.rogue.selectedRewards = [{"id": "bad", "effects": [{"type": "enemyBattleStartStatus"}]}]
	var path := work.path_join("malformed-rogue.json")
	write_json(path, malformed)
	check(not m.import_save(path).success and m.state == before, "unknown malformed rogue reward rejected atomically")
	var reward: Dictionary = m.catalog.AbyssData.rogue.rewards.back().duplicate(true)
	reward.effects[0].erase("statusId")
	malformed.abyss.rogue.selectedRewards = [reward]
	write_json(path, malformed)
	check(not m.import_save(path).success and m.state == before, "known rogue reward missing statusId rejected")
	reward = m.catalog.AbyssData.rogue.rewards[0].duplicate(true)
	reward.effects[0].value = []
	malformed.abyss.rogue.selectedRewards = [reward]
	write_json(path, malformed)
	check(not m.import_save(path).success and m.state == before, "known rogue reward nonnumeric value rejected")
	var directory := work.path_join("metadata-failure")
	m = Model.new(directory)
	DirAccess.make_dir_recursive_absolute(directory.path_join("active_slot.json"))
	before = m.state.duplicate(true)
	check(not m.load_slot(2).success and m.active_slot == 1 and m.state.resources == before.resources, "failed active-slot metadata keeps original active state")

func _test_original_gacha_parity() -> void:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/gacha-parity.json"))
	var values: Array = fixture.randoms.duplicate()
	var m = Model.new("")
	m.state.resources.diamonds = int(fixture.initial_diamonds)
	m.random_source = func(): return values.pop_front() if not values.is_empty() else -1.0
	var matches := true
	for action in fixture.actions:
		var outcome: Dictionary = m.pull(action.pool, int(action.count))
		matches = matches and outcome.success and outcome.results.size() == action.results.size()
		for index in range(outcome.results.size()):
			var actual: Dictionary = outcome.results[index]
			var expected: Dictionary = action.results[index]
			matches = matches and actual.charId == expected.charId and actual.rarity == expected.rarity and actual.isFeatured == expected.isFeatured
		for id in action.pity:
			var actual: Dictionary = m.state.pityCounters[id]
			var expected: Dictionary = action.pity[id]
			matches = matches and actual.count == expected.count and actual.count4 == expected.count4 and actual.guaranteedFeatured == expected.guaranteedFeatured
		matches = matches and m.state.resources.diamonds == action.diamonds and m.state.stats.totalPulls == action.total_pulls
	for id in fixture.owned:
		matches = matches and m.state.ownedCharacters.has(id) and m.state.ownedCharacters[id].shards == fixture.owned[id].shards
	matches = matches and values.is_empty() and m.state.ownedCharacters.size() == fixture.owned.size()
	check(matches, "original JavaScript parity: %d pulls, %d RNG draws, all outcomes-pity-balances-shards" % [m.state.stats.totalPulls, fixture.randoms.size()])
