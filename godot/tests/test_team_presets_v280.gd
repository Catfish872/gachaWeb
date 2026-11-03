extends SceneTree
const Game = preload("res://scripts/game_model.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func ck(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("TEAM PRESETS: " + label)
func snapshot(game) -> String: return JSON.stringify(game.state)
func run() -> void:
	var game = Game.new("")
	ck(game.state.teamPresets.size() == 5, "five independent presets")
	ck(game.state.teamPresets[0].team == game.state.team and game.state.activeTeamPreset == 0, "first preset starts with current team")
	ck(game.state.teamPresets[4].team.is_empty(), "remaining slots begin empty")
	var initial := snapshot(game)
	for index in [-1, 5, 99]:
		ck(not game.save_team_preset(index, ["ember"]).success, "invalid save slot rejected")
		ck(not game.switch_team_preset(index).success, "invalid switch slot rejected")
		ck(not game.rename_team_preset(index, "新名称").success, "invalid rename slot rejected")
	for invalid in [[], ["ember", "ember"], ["kaldi"], ["missing"], [42], ["ember", "zeph", null, null]]:
		ck(not game.save_team_preset(1, invalid).success, "invalid formation rejected")
	ck(not game.switch_team_preset(4).success, "empty slot cannot replace live team")
	ck(snapshot(game) == initial, "all rejected operations preserve state")
	ck(game.save_team_preset(1, ["zeph", "ember"]).success, "second preset saves and activates")
	ck(game.state.team == ["zeph", "ember", null] and game.state.activeTeamPreset == 1, "character order retained")
	ck(game.state.teamPresets[0].team == ["ember", "zeph", null], "saving another slot retains first team")
	ck(game.rename_team_preset(1, "  风火同行  ").success and game.state.teamPresets[1].name == "风火同行", "rename trims edges")
	ck(not game.rename_team_preset(1, " \t\n ").success, "empty name rejected")
	ck(game.rename_team_preset(4, "甲".repeat(30)).success and game.state.teamPresets[4].name.length() == 16, "name length bounded")
	ck(game.switch_team_preset(0).success and game.state.team == ["ember", "zeph", null], "quick switch restores first order")
	ck(game.switch_team_preset(1).success and game.state.team == ["zeph", "ember", null], "repeated quick switch restores second order")
	game.state.team[0] = "ember"
	ck(game.state.teamPresets[1].team[0] == "zeph", "live team and saved preset do not alias")
	game.switch_team_preset(1)
	ck(game.set_team(["zeph"]).success and game.state.activeTeamPreset == -1, "legacy formation API leaves saved presets intact")
	ck(game.state.teamPresets[1].team == ["zeph", "ember", null], "manual formation preserves saved composition")
	game.switch_team_preset(1)
	var before_fail := snapshot(game)
	game.save_blocked = true
	ck(not game.save_team_preset(2, ["ember"]).success and snapshot(game) == before_fail, "save failure rolls back team and preset")
	ck(not game.switch_team_preset(0).success and snapshot(game) == before_fail, "switch failure rolls back active slot and team")
	ck(not game.rename_team_preset(1, "失败名称").success and snapshot(game) == before_fail, "rename failure rolls back name")
	game.save_blocked = false
	for lock_kind in ["abyss", "extraction", "battle"]:
		var locked = Game.new("")
		if lock_kind == "abyss": locked.state.abyss.rogue.runId = "locked-test"
		elif lock_kind == "extraction": locked.state.extraction.run = {"id": "locked-test"}
		else: locked._issued_config = {"token": "locked-test"}
		var before := snapshot(locked)
		ck(locked.team_is_locked(), lock_kind + " exposes formation lock")
		ck(not locked.set_team(["zeph"]).success, lock_kind + " blocks ordinary team edits")
		ck(not locked.save_team_preset(1, ["zeph"]).success, lock_kind + " blocks preset saving")
		ck(not locked.switch_team_preset(0).success, lock_kind + " blocks preset switching")
		ck(snapshot(locked) == before, lock_kind + " preserves current run and state")
	for version in range(2, 10):
		var old: Dictionary = game.default_state()
		old.version = version
		old.team = ["zeph", "ember", null]
		old.erase("teamPresets")
		old.erase("activeTeamPreset")
		ck(game.valid_save(old), "old version %d accepted" % version)
		var migrated: Dictionary = game._normalize(old)
		ck(migrated.team == old.team and migrated.teamPresets[0].team == old.team, "old version %d keeps order and current team" % version)
		ck(migrated.teamPresets.size() == 5 and migrated.activeTeamPreset == 0, "old version %d gains five slots" % version)
		ck(migrated.resources == old.resources and migrated.ownedCharacters.keys() == old.ownedCharacters.keys(), "old version %d preserves ownership and resources" % version)
	var corrupt: Dictionary = game.state.duplicate(true)
	corrupt.teamPresets[2].team = ["ember", "ember"]
	ck(not game.valid_save(corrupt), "import rejects duplicate preset members")
	corrupt = game.state.duplicate(true)
	corrupt.activeTeamPreset = 4.5
	ck(not game.valid_save(corrupt), "import rejects fractional active index")
	corrupt = game.state.duplicate(true)
	corrupt.teamPresets = ["bad"]
	ck(not game.valid_save(corrupt), "import rejects malformed presets")
	var dir := "/tmp/voidrift-team-presets-%d" % Time.get_ticks_usec()
	var disk = Game.new(dir)
	ck(disk.save_team_preset(4, ["zeph", "ember"]).success and disk.rename_team_preset(4, "第五队").success, "disk stores fifth team")
	var reload = Game.new(dir)
	ck(reload.state.activeTeamPreset == 4 and reload.state.team == ["zeph", "ember", null] and reload.state.teamPresets[4].name == "第五队", "restart restores active fifth team and name")
	ck(reload.export_save(dir + "/export.json").success, "presets export through current format")
	ck(reload.load_slot(2).success and reload.state.teamPresets[4].team.is_empty(), "save slots keep presets isolated")
	ck(reload.import_save(dir + "/export.json").success and reload.state.activeTeamPreset == 4, "import restores preset identity")
	ck(reload.state.teamPresets[4].team == ["zeph", "ember", null], "import restores saved order")
	ck(reload.load_slot(1).success and reload.state.teamPresets[4].name == "第五队", "original save slot remains intact")
	print("TEAM PRESETS V280: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
