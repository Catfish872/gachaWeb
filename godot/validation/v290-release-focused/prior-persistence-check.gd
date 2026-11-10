extends SceneTree
const Game = preload("res://scripts/game_model.gd")
const SAVE = "/tmp/ch5-persistence-v290/saves-clean"
var failures := 0
var checks := 0
func ck(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func _init() -> void:
	var game = Game.new(SAVE)
	var chapter: Dictionary = game.catalog.StageData.chapters.back()
	ck(chapter.id == "ch5", "chapter five selected")
	if OS.get_cmdline_user_args().has("write"):
		for stage in game.stage_list():
			if not str(stage.id).begins_with("ch5_"):
				game.state.stageProgress[stage.id] = {"cleared":true,"stars":3,"bestTurns":5}
		game.mark_dialogue_seen("ch4_12_post")
		for stage in chapter.stages:
			game.state.resources.stamina = 120
			var prepared: Dictionary = game.prepare_stage(stage.id)
			ck(prepared.success, "prepare " + stage.id)
			if not prepared.success: continue
			var result: Dictionary = game.finish_battle(prepared.config, {"phase":"victory","turn":5,"allies":[{"currentHp":1}]})
			ck(result.success and result.firstClear, "settle " + stage.id)
			game.mark_dialogue_seen(str(stage.id) + "_pre")
			for key in stage.get("postDialogueKeys", [str(stage.id) + "_post"]):
				game.mark_dialogue_seen(key)
		ck(game.save_game(), "explicit disk save")
		ck(FileAccess.file_exists(SAVE + "/slot1.json"), "real save file exists")
		var disk = JSON.parse_string(FileAccess.get_file_as_string(SAVE + "/slot1.json"))
		ck(disk.stageProgress.size() == game.state.stageProgress.size(), "disk stage count")
		var file = FileAccess.open("/tmp/ch5-persistence-v290/expected.json", FileAccess.WRITE)
		file.store_string(JSON.stringify(game.state));file.close()
	else:
		ck(not game.save_blocked, "fresh process load valid")
		var expected = JSON.parse_string(FileAccess.get_file_as_string("/tmp/ch5-persistence-v290/expected.json"))
		for key in ["stageProgress","dialogueSeen","ownedCharacters","relics","chapterGiftClaimed","stats"]:
			ck(JSON.parse_string(JSON.stringify(game.state[key])) == expected[key], "persisted " + key)
		ck(game.state.resources.diamonds == expected.resources.diamonds and game.state.resources.gold == expected.resources.gold, "persisted rewards")
		for stage in chapter.stages:
			ck(game.get_stage(stage.id).unlocked and game.state.stageProgress[stage.id].cleared, "completed and unlocked " + stage.id)
		for key in chapter.stages.back().postDialogueKeys:
			ck(game.state.dialogueSeen.get(key, false), "ending persisted " + key)
		game.state.resources.stamina = 120
		var replay: Dictionary = game.prepare_stage(chapter.stages.back().id)
		ck(replay.success, "final stage replay after restart")
		var result: Dictionary = game.finish_battle(replay.config, {"phase":"victory","turn":9})
		ck(result.success and not result.firstClear and result.rewards.diamonds == 0, "restart replay excludes first reward")
	print("CHAPTER5_DISK_RESTART mode=", OS.get_cmdline_user_args(), " pid=", OS.get_process_id(), " checks=",checks," failures=",failures)
	quit(1 if failures else 0)
