extends "res://tests/test_lantern_journey_ui_v270.gd"

func start_story() -> void:
	var prepared: Dictionary = app.model.prepare_stage("ch1_1")
	ck(prepared.get("success", false), "story encounter prepares")
	if prepared.get("success", false): app._start_battle(prepared.config)

func leave_battle() -> void:
	ck(app.model.abandon_battle(app.battle_config, app.battle.state).get("success", false), "encounter retreat succeeds")
	app.battle_settled = true
	app.navigate("story")

func press_battle_control(control_name: String) -> void:
	var control: Button = app.find_child(control_name, true, false)
	ck(control != null, "battle control exists: " + control_name)
	if control != null: control.pressed.emit()

func run() -> void:
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await frames(8)
	app.set_process(false)
	ck(app.battle_auto and app.preferred_battle_auto, "fresh settings default to automatic combat")
	var preference_file := "/tmp/voidrift-battle-preferences-%d.cfg" % Time.get_ticks_usec()
	var legacy := ConfigFile.new()
	legacy.set_value("audio", "music", false)
	ck(legacy.save(preference_file) == OK, "legacy settings fixture saves")
	app.battle_auto = false
	app.preferred_battle_auto = false
	app._load_preferences(preference_file)
	ck(app.battle_auto and app.preferred_battle_auto, "old settings without battle choice default to automatic")
	fresh()
	start_story()
	ck(app.battle_auto, "first encounter applies automatic preference")
	press_battle_control("BattleAutoToggle")
	ck(not app.battle_auto and not app.preferred_battle_auto, "manual choice updates runtime and stored preference")
	leave_battle()
	app.battle_auto = true
	start_story()
	ck(not app.battle_auto, "next encounter restores explicit manual choice")
	press_battle_control("BattleAutoToggle")
	press_battle_control("BattleSpeedToggle")
	press_battle_control("BattleSpeedToggle")
	ck(app.battle_auto and app.battle_speed == 4.0, "actual controls choose automatic and four times speed")
	app._do_battle_action("invalid_test_skill", "", false)
	ck(not app.battle_auto and app.preferred_battle_auto, "action safeguard changes only current combat state")
	leave_battle()
	start_story()
	ck(app.battle_auto and app.battle_speed == 4.0, "next encounter restores automatic choice and keeps speed")
	leave_battle()
	app.model.state.extraction.unlockedDifficulty = 5
	app._set_extraction_difficulty(4)
	app._save_preferences(preference_file)
	var restarted = load("res://main.tscn").instantiate()
	root.add_child(restarted)
	await frames(8)
	restarted.set_process(false)
	restarted.model.state.extraction.unlockedDifficulty = 5
	restarted._load_preferences(preference_file)
	ck(restarted.battle_auto and restarted.preferred_battle_auto and restarted.battle_speed == 4.0 and restarted.extraction_difficulty == 4, "new app instance restores all three saved choices")
	restarted._set_battle_auto(false)
	restarted._cycle_battle_speed()
	restarted._save_preferences(preference_file)
	app._load_preferences(preference_file)
	ck(not app.battle_auto and not app.preferred_battle_auto and app.battle_speed == 1.0 and app.extraction_difficulty == 4, "explicit manual and new speed survive disk reload")
	ck(app.model.extraction.start_run(app.extraction_difficulty).success, "saved extraction difficulty starts run")
	app.model.extraction._generate_encounter("patrol")
	app._begin_extraction_battle()
	ck(app.current_screen == "battle" and not app.battle_auto and app.battle_speed == 1.0 and int(app.battle_config.difficulty) == 4, "extraction encounter follows saved manual speed and difficulty")
	fresh()
	app.preferred_battle_auto = false
	app.abyss_auto_continue = true
	app._start_battle({"isAbyss":true,"floor":1,"difficulty":0,"enemies":["wolf"],"seed":28001})
	ck(app.battle_auto and not app.preferred_battle_auto, "continuous abyss explicitly enables auto without replacing saved choice")
	press_battle_control("BattleAutoToggle")
	ck(not app.battle_auto and not app.abyss_auto_continue, "manual toggle cancels continuous abyss")
	restarted.queue_free()
	app.queue_free()
	await frames()
	DirAccess.remove_absolute(preference_file)
	print("BATTLE PREFERENCES V280: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
