extends SceneTree

const GameModel = preload("res://scripts/game_model.gd")
const BattleModel = preload("res://scripts/battle_model.gd")
var passed = 0
var failed = 0

func _initialize():
	call_deferred("run")

func check(value, name):
	if value:
		passed += 1
		print("PASS: " + name)
	else:
		failed += 1
		push_error("FAIL: " + name)

func simulate(m, config, abyss = false):
	var b = BattleModel.new(m.catalog)
	if not config.has("seed"):
		config.seed = 20261016
	b.start(config, m.battle_party(abyss), m.rogue_effects())
	var steps = 0
	while b.state.phase not in ["victory", "defeat"] and steps < 2000:
		var result = b.auto_step()
		if not result.get("success", false):
			push_error("AUTO FAILURE: " + str(result))
			break
		steps += 1
	check(b.state.phase in ["victory", "defeat"], "battle terminates: " + str(config.get("id")) + " steps=" + str(steps))
	return b

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

func run():
	var m = GameModel.new("")
	var cases = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/original-stats.json"))
	var mismatches = []
	for sample in cases:
		var c = m.default_character()
		c.level = int(sample.level)
		c.constellation = int(sample.constellation)
		m.state.ownedCharacters[sample.id] = c
		var actual = m.computed_stats(sample.id)
		for key in sample.stats:
			if not is_equal_approx(float(actual.get(key, -99999)), float(sample.stats[key])):
				mismatches.append("%s lv%s C%s %s expected%s actual%s" % [sample.id, sample.level, sample.constellation, key, sample.stats[key], actual.get(key)])
	check(mismatches.is_empty(), "60 original-JS character stat cases match; differences=" + str(mismatches))
	var imported = GameModel.new("")
	check(imported.import_save("res://tests/fixtures/web-save-v3.json").get("success", false), "raw web v3 save imports")
	check(imported.state.resources.diamonds == 4321 and imported.state.ownedCharacters.kaldi.level == 7 and imported.state.ownedCharacters.kaldi.constellation == 3, "import retains resources and progression")
	check(imported.state.relics.size() == 1 and imported.state.relics[0].level == 1 and imported.state.relics[0].equippedBy == "kaldi", "import retains upgraded equipped relic")
	check(imported.import_save("res://tests/fixtures/web-save-export.json").get("success", false), "original browser export envelope imports")
	check(imported.state.dialogueSeen.get("ch1_1_pre", false) and imported.state.chapterGiftClaimed.ch1.claimed, "import retains dialogue and chapter gift")
	var starter = GameModel.new("")
	var start = starter.prepare_stage("ch1_1")
	check(start.get("success", false), "new player can launch first stage")
	if start.get("success", false):
		var b = simulate(starter, start.config)
		check(b.state.phase == "victory", "starter party can win first stage at default stats")
		check(starter.finish_battle(start.config, b.state).get("success", false), "starter battle settles")
	# A mature save exercises all content without requiring hundreds of grind battles.
	for id in m.catalog.CharacterData:
		var c = m.default_character()
		c.level = 10
		c.constellation = 6
		m.state.ownedCharacters[id] = c
	m.state.resources.stamina = 300
	m.state.resources.gold = 1000000
	m.set_team(["kaldi", "ayla", "gus"])
	for chapter in m.catalog.StageData.chapters:
		for stage in chapter.stages:
			var prep = m.prepare_stage(stage.id)
			check(prep.get("success", false), "stage is reachable: " + stage.id)
			if not prep.get("success", false):
				continue
			var b = simulate(m, prep.config)
			check(b.state.phase == "victory", "mature party clears " + stage.id)
			var before = int(m.state.resources.diamonds)
			check(m.finish_battle(prep.config, b.state).get("success", false), "stage settlement " + stage.id)
			check(int(m.state.resources.diamonds) >= before + int(stage.firstClearRewards.get("diamonds", 0)), "first-clear gems granted " + stage.id)
			var settled = JSON.stringify(m.state)
			check(not m.finish_battle(prep.config, b.state).get("success", true) and JSON.stringify(m.state) == settled, "duplicate settlement blocked " + stage.id)
	check(m.state.chapterGiftClaimed.has("ch1") and m.state.chapterGiftClaimed.has("ch2"), "both chapter gifts resolve")
	check(m.state.relics.size() == 10, "all ten stage wins deliver relics")
	for floor_number in range(1, 21):
		_resolve_v2_nodes(m)
		var prep = m.prepare_abyss()
		check(prep.get("success", false), "expedition floor launch " + str(floor_number))
		if not prep.get("success", false):
			break
		var b = simulate(m, prep.config, true)
		check(b.state.phase == "victory", "mature party clears expedition " + str(floor_number))
		var settlement = m.finish_battle(prep.config, b.state)
		check(settlement.get("success", false), "expedition settlement " + str(floor_number))
		if floor_number in [1, 3, 6, 9, 10, 13, 16, 19]:
			check(m.state.abyss.rogue.pendingChoices.size() == 3, "three blessing options after floor " + str(floor_number))
			check(not m.prepare_abyss().get("success", true), "choice gates next encounter " + str(floor_number))
		if b.state.phase != "victory":
			break
	check(m.state.abyss.maxFloor >= 20, "real battle engine clears full twenty-floor expedition")
	check(m.state.abyss.currentFloor == 1 and m.state.abyss.lastRun.get("outcome") == "victory", "completed expedition resets into victory summary")
	check(m.state.abyss.meta.currency > 0 and m.state.abyss.meta.runsCompleted == 1, "complete run banks permanent progression")
	print("INTEGRATION TESTS: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)
