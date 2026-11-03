extends SceneTree
const Game = preload("res://scripts/game_model.gd")
const Battle = preload("res://scripts/battle_model.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func ck(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error("WIND TRIAL: " + label)
func victory(config: Dictionary) -> Dictionary:
	return {"config":config.duplicate(true),"phase":"victory","turn":5,"allies":[{"currentHp":100}]}
func run() -> void:
	var game = Game.new("")
	var initial: Dictionary = game.state.duplicate(true)
	ck(not game.prepare_wind_trial("invalid").success and game.state == initial, "invalid trial is atomic")
	for kind in ["tiya", "lumi", "duo"]:
		var before: Dictionary = game.state.duplicate(true)
		var prepared: Dictionary = game.prepare_wind_trial(kind)
		ck(prepared.success, kind + " prepares")
		if not prepared.success: continue
		ck(game.state == before, kind + " preparation preserves all permanent state")
		ck(prepared.config._team.is_empty(), kind + " excludes owned character progression")
		ck(game.battle_party().size() == 3, kind + " has full temporary party")
		ck(game.battle_party()[0].id == ("lumi" if kind == "duo" else kind), kind + " featured opening member")
		for ally in game.battle_party():
			ck(ally.level == 5 and ally.constellation == 0 and ally.energy == 100 and ally.trialRelics.size() == 5, kind + " fixed trial build")
		ck(not game.prepare_wind_trial(kind).success, kind + " repeated start cannot replace current token")
		ck(not game.switch_team_preset(0).success, kind + " temporarily locks saved formations")
		var config: Dictionary = prepared.config.duplicate(true)
		config.firstClearRewards.diamonds = 99999
		var result: Dictionary = game.finish_battle(config, victory(prepared.config))
		var expected := 0 if kind == "duo" else 160
		ck(result.success and int(result.rewards.diamonds) == expected, kind + " issued reward resists caller edits")
		ck(int(game.state.resources.diamonds) == int(before.resources.diamonds) + expected, kind + " reward amount exact")
		for field in ["ownedCharacters", "team", "teamPresets", "activeTeamPreset", "relics", "pityCounters", "abyss", "extraction", "stats"]:
			ck(game.state[field] == before[field], kind + " isolates " + field)
		for resource in ["gold", "stamina"]: ck(game.state.resources[resource] == before.resources[resource], kind + " preserves " + resource)
		if kind == "duo": ck(game.state == before, "joint demonstration changes no permanent state")
		ck(not game.finish_battle(prepared.config, victory(prepared.config)).success, kind + " settlement cannot replay")
		prepared = game.prepare_wind_trial(kind)
		var repeat_before: Dictionary = game.state.duplicate(true)
		result = game.finish_battle(prepared.config, victory(prepared.config))
		ck(result.success and result.rewards.diamonds == 0 and game.state == repeat_before, kind + " repeat is reward-free and isolated")
	var retry = Game.new("")
	var pending: Dictionary = retry.prepare_wind_trial("tiya")
	var old: Dictionary = retry.state.duplicate(true)
	retry.save_blocked = true
	ck(not retry.finish_battle(pending.config, victory(pending.config)).success and retry.state == old, "failed award rolls back claim and crystals")
	ck(not retry._issued_config.is_empty(), "failed award retains retry token")
	retry.save_blocked = false
	ck(retry.finish_battle(pending.config, victory(pending.config)).success and retry.state.resources.diamonds == old.resources.diamonds + 160, "award retry succeeds exactly once")
	pending = retry.prepare_wind_trial("lumi")
	var retreat_before: Dictionary = retry.state.duplicate(true)
	ck(retry.abandon_battle(pending.config).success and retry.state == retreat_before and retry._issued_config.is_empty(), "retreat leaves all permanent state intact")
	var legacy: Dictionary = game.default_state()
	legacy.stageProgress.trial_selin = {"cleared":true,"stars":3,"bestTurns":4}
	legacy.erase("teamPresets"); legacy.erase("activeTeamPreset")
	var migrated: Dictionary = game._normalize(legacy)
	ck(migrated.stageProgress.trial_selin.cleared and not migrated.stageProgress.has("trial_tiya") and not migrated.stageProgress.has("trial_lumi"), "legacy Selin claim and new independent claims coexist")
	# Actual BattleModel runs establish playable victories, not fabricated results.
	for kind in ["tiya", "lumi", "duo"]:
		var actual = Game.new("")
		var prepared: Dictionary = actual.prepare_wind_trial(kind)
		var battle = Battle.new(actual.catalog)
		battle.start(prepared.config, actual.battle_party())
		var armor_seen := false
		var piercing_seen := false
		var actions := 0
		while battle.state.phase not in ["victory", "defeat"] and actions < 600:
			var step: Dictionary = battle.auto_step()
			for event in step.get("events", []):
				if event.get("statusId", "") == "wind_armor": armor_seen = true
				if event.get("followUpTag", "") == "innate_piercing": piercing_seen = true
			actions += 1
		ck(battle.state.phase == "victory", kind + " actual combat reaches victory")
		ck(armor_seen, kind + " actual combat demonstrates armor break")
		if kind != "lumi": ck(piercing_seen, kind + " actual combat demonstrates innate piercing")
		ck(actual.finish_battle(prepared.config, battle.state).success, kind + " actual victory settles")
		print("WIND TRIAL COMBAT ", kind, ": ", actions, " actions, ", battle.state.turn, " turns, ", battle.state.phase)
	print("WIND TRIALS V280: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
