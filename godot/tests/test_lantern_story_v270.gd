extends SceneTree
const Game = preload("res://scripts/game_model.gd")
var failures := 0
func check(ok: bool, caption: String) -> void:
	if not ok:
		failures += 1
		push_error(caption)
func _initialize() -> void:
	var model = Game.new("")
	var chapter: Dictionary = model.catalog.StageData.chapters[2]
	check(chapter.id == "ch3" and chapter.stages.size() == 8, "third chapter has eight stages")
	var diamonds := 0
	for stage in chapter.stages:
		diamonds += int(stage.firstClearRewards.diamonds)
		check(model.catalog.DialogueData.has(stage.id+"_pre") and model.catalog.DialogueData.has(stage.id+"_post"), "story dialogue " + stage.id)
		for wave in stage.waves:
			for id in wave.enemies:
				check(model.catalog.EnemyData.has(id), "enemy reference " + id)
				for skill in model.catalog.EnemyData[id].skills:check(model.catalog.EnemySkillData.has(skill), "enemy skill " + skill)
	check(diamonds == 800, "chapter total first clear 800")
	check(not model.get_stage("ch3_1").unlocked, "new chapter initially locked")
	for stage in model.stage_list():
		if not str(stage.id).begins_with("ch3_"):model.state.stageProgress[stage.id] = {"cleared":true}
	check(model.get_stage("ch3_1").unlocked and not model.get_stage("ch3_2").unlocked, "chapter follows cleared ch2_5")
	var owned: Dictionary = model.state.ownedCharacters.duplicate(true)
	var team: Array = model.state.team.duplicate(true)
	var relics: Array = model.state.relics.duplicate(true)
	var wallet := int(model.state.resources.diamonds)
	var trial: Dictionary = model.prepare_selin_trial()
	check(trial.success, "trial prepared")
	check(model.battle_party().size() == 3 and model.battle_party()[0].id == "selin", "trial uses separate snapshot")
	check(model.battle_party()[0].trialRelics.size() == 5, "trial fixed relic loadout")
	var result: Dictionary = model.finish_battle(trial.config,{"phase":"victory","turn":5,"allies":[{"currentHp":10}]})
	check(result.success and int(model.state.resources.diamonds)==wallet+160, "trial first clear 160")
	check(model.state.ownedCharacters == owned and model.state.team == team and model.state.relics == relics, "trial does not contaminate ownership equipment or XP")
	check(not model.finish_battle(trial.config,{"phase":"victory"}).success, "trial cannot settle twice")
	trial = model.prepare_selin_trial()
	result = model.finish_battle(trial.config,{"phase":"victory","turn":4,"allies":[{"currentHp":10}]})
	check(result.success and int(result.rewards.diamonds)==0 and result.relic.is_empty(), "trial repeat has no rewards")
	for id in ["ch3_4","ch3_8"]:
		var reward: Dictionary = model._stage_rewards(model.get_stage(id),true)
		check(reward.relicDrop.setId=="ember_lantern" and int(reward.relicDrop.rarity)==5, "fixed five star set reward " + id)
	check(model.relic_set_options().any(func(s):return s.id=="ember_lantern"), "new set can be targeted in abyss")
	model.state.resources.diamonds = 2000
	model.state.pityCounters.limited_kaldi={"count":57,"count4":3,"guaranteedFeatured":true}
	var old_pity: Dictionary = model.state.pityCounters.limited_kaldi.duplicate(true)
	model.state.pityCounters.limited_selin={"count":89,"count4":0,"guaranteedFeatured":false}
	model.random_source=func():return .99
	var pull: Dictionary = model.pull("limited_selin",1)
	check(pull.success and pull.results[0].charId!="selin" and model.state.pityCounters.limited_selin.guaranteedFeatured, "off banner excludes Selin and sets guarantee")
	model.state.pityCounters.limited_selin.count=89
	pull=model.pull("limited_selin",1)
	check(pull.success and pull.results[0].charId=="selin" and not model.state.pityCounters.limited_selin.guaranteedFeatured, "next five star guaranteed Selin")
	check(model.state.pityCounters.limited_kaldi == old_pity, "existing pool pity untouched")
	var ayla_rewards: Array = model.catalog.AbyssData.rogue.rewards.filter(func(r):return str(r.id).begins_with("ayla_"))
	check(ayla_rewards.size()==5, "Ayla old blessing pool unchanged")
	check(not model.abyss_enemy_pool(1).has("ash_moth") and not model.abyss_enemy_pool(10).has("boss_hedor"), "first ten layers keep default enemies")
	model._init_rogue_run()
	model.state.abyss.currentFloor = 11
	model.state.abyss.rogue.floorsCleared = 10
	model.state.abyss.savedPartyState = model.battle_party(true)
	model.state.abyss.rogue.sceneBlocks = {"11": {"startFloor":11,"theme":"lantern","depth":0,"background":model.extraction.data.environmentThemes.lantern.backgrounds[0][0]}}
	check(model.abyss_enemy_pool(11).has("ash_moth"), "lantern block normal enemy pool")
	check(model.abyss_enemy_pool(11).has("furnace_guard") and model.abyss_enemy_pool(11).has("cracked_puppet"), "lantern block ordinary candidates")
	check(model.abyss_enemy_pool(15)==["lamp_overseer"], "lantern block elite pool")
	check(model.abyss_enemy_pool(20)==["boss_hedor"], "lantern block boss pool")
	check(model.abyss_encounter_background(["ash_moth"],123)==model.abyss_encounter_background(["ash_moth"],123), "stable seed-selected background")
	check(model.abyss_encounter_background(["boss_hedor"],123).ends_with("furnace_core.png"), "boss core scene")
	var encounter: Dictionary = model.prepare_abyss()
	check(encounter.success and encounter.config.enemies.all(func(id):return id in model.abyss_enemy_pool(11)) and encounter.config.abyssScene.theme=="lantern", "real prepare selects only lantern block enemies")
	var resumed: Dictionary = model.prepare_abyss()
	check(resumed.success and resumed.config==encounter.config, "resume preserves issued enemies seed background and rewards")
	print("lantern_story_v270: %s" % ("PASS" if failures==0 else str(failures)+" failures"))
	quit(0 if failures==0 else 1)
