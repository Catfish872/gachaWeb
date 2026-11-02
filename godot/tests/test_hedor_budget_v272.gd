extends SceneTree
const Game = preload("res://scripts/game_model.gd")
const Battle = preload("res://scripts/battle_model.gd")
var failures := 0

func check(value: bool, label: String) -> void:
	if value: print("PASS: " + label)
	else: failures += 1; push_error("FAIL: " + label)

func _initialize() -> void:
	call_deferred("run_tests")

func run_tests() -> void:
	var game = Game.new("")
	var ex = game.extraction
	check(ex.start_run().success, "run starts")
	ex.run().environmentOrder = ["ruins", "forest", "lantern"]
	ex.run().act = 3
	ex.run().node = 4
	var enemies := ["boss_hedor", "furnace_lamp", "furnace_lamp"]
	for rank in range(6):
		ex.run().difficulty = rank
		var escort_hp := 1620.0 if rank == 5 else 1200.0 if rank == 4 else 0.0
		var escort_atk := 170.0 if rank == 5 else 90.0 if rank == 4 else 0.0
		var budget: Dictionary = ex._theme_encounter_budget("boss", enemies, 3, rank)
		check(is_equal_approx(float(budget.hpMod) * 21600.0, (4750.0 + escort_hp) * 1.08), "full HP budget rank %d" % rank)
		check(is_equal_approx(float(budget.atkMod) * 295.0, (130.0 + escort_atk * 0.25) * 1.05), "attack conversion rank %d" % rank)
		ex._generate_encounter("boss")
		var config: Dictionary = ex.run().activeEncounter.duplicate(true)
		check(config.enemies == enemies, "themed boss and lamps rank %d" % rank)
		var common := 1.07 * float(ex.data.balance.rankAtk[rank]) * 1.65 * 0.85
		var expected_atk := int(235.0 * ((130.0 + escort_atk * 0.25) * 1.05 / 295.0) * common * 1.15)
		var battle = Battle.new(game.catalog)
		battle.start(config, [{"id":"kaldi", "stats":{"maxHp":1000000, "atk":100, "def":100, "spd":1000, "cri":0.0, "criDmg":1.5}}])
		check(int(battle.state.enemies[0].stats.atk) == expected_atk, "generated ATK with one final multiplier rank %d" % rank)
		if rank == 4: check(expected_atk == 11006, "rank4 calibrated attack")
		if rank == 5: check(expected_atk == 22410, "rank5 calibrated attack")
		var rng_before := str(ex.run().rngState)
		check(ex.prepare_battle().config == config and str(ex.run().rngState) == rng_before, "issued encounter preserved rank %d" % rank)
	# A deliberately changed global pool must never leak into legacy themes.
	var abyss_pool: Array = game.catalog.AbyssData.pools.boss.duplicate()
	game.catalog.AbyssData.pools.boss = ["boss_hedor"]
	for theme in ["ruins", "forest", "sanctum"]:
		ex.run().environmentOrder = ["lantern", "ruins", theme]
		ex._generate_encounter("boss")
		check(ex.run().activeEncounter.enemies[0] in ["boss_flame_lord", "boss_storm_witch"], "legacy boss pool " + theme)
		check(ex.run().activeEncounter.enemies.slice(1) == ["dark_knight", "thunder_hawk"], "legacy escorts " + theme)
		for kind in ["battle", "elite"]:
			ex._generate_encounter(kind)
			check(ex.run().activeEncounter.enemies.all(func(id): return not game.catalog.EnemyData[id].has("abyssBaseStats")), "legacy base isolation " + theme + " " + kind)
	check(game.catalog.AbyssData.pools.boss == ["boss_hedor"], "generation leaves abyss pool unchanged")
	game.catalog.AbyssData.pools.boss = abyss_pool
	print("HEDOR_BUDGET_V272 failures: ", failures)
	quit(1 if failures else 0)
