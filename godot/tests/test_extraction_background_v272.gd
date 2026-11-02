extends SceneTree

const GameModel = preload("res://scripts/game_model.gd")
const Main = preload("res://scripts/main.gd")
var failures := 0

func check(value: bool, label: String) -> void:
	if value: print("PASS: " + label)
	else: failures += 1; push_error("FAIL: " + label)

func _initialize() -> void:
	call_deferred("run_tests")

func run_tests() -> void:
	var model = GameModel.new("")
	var ex = model.extraction
	var app = Main.new()
	app.model = model
	app.current_screen = "battle"
	check(ex.start_run().success, "run starts")
	for theme in ["ruins", "forest", "sanctum", "lantern"]:
		ex.run().environmentOrder = [theme, "ruins", "forest"]
		ex.run().act = 1
		ex._generate_map()
		for district in range(3):
			var room: Dictionary = ex.run().map.rooms[district * 6 + 1].duplicate(true)
			var expected: String = str(room.background)
			ex.run().room = room
			ex.run().map.currentRoomId = room.id
			var music: String = ex.environment_music_track()
			for kind in ["battle", "elite", "boss"]:
				ex._generate_encounter(kind)
				var prepared: Dictionary = ex.prepare_battle()
				app.battle_config = prepared.config
				check(prepared.config.background == expected and app._background_path() == expected, "%s district %d %s uses chosen room" % [theme, district, kind])
				check(ResourceLoader.exists(prepared.config.background), "background resource exists")
				var snapshot: Dictionary = model.state.duplicate(true)
				check(ex.prepare_battle() == prepared and model.state == snapshot, "repeat entry preserves encounter and RNG")
				model.state = JSON.parse_string(JSON.stringify(snapshot))
				app.battle_config = ex.prepare_battle().config
				check(app._background_path() == expected, "saved encounter restores same scenery")
				check(ex.environment_music_track() == music, "theme/district music retained")
			# Old issued configs stay byte-for-byte equivalent while rendering their room.
			ex.run().activeEncounter.erase("background")
			app.battle_config = ex.prepare_battle().config
			var legacy: Dictionary = model.state.duplicate(true)
			check(app._background_path() == expected, "legacy encounter uses current room")
			check(ex.prepare_battle().config == legacy.extraction.run.activeEncounter and model.state == legacy, "legacy issued config and RNG unchanged")
			ex.run().room.erase("background")
			check(ex.battle_background_path() == expected, "legacy room uses saved map node")
			for node in ex.run().map.rooms:
				if node.id == room.id: node.erase("background")
			check(ex.battle_background_path() == ex.run().map.districts[district].background, "legacy map uses saved district")
	app.battle_config = {"isAbyss": true}
	check(app._background_path() == "res://assets/backgrounds/abyss.png", "abyss default unchanged")
	app.battle_config = {"background": "res://assets/content_v270/backgrounds/snow_inn.png"}
	check(app._background_path() == app.battle_config.background, "explicit story background unchanged")
	ex.run().erase("map")
	ex.run().room = {}
	check(ResourceLoader.exists(ex.battle_background_path()), "pre-map legacy fallback exists")
	app.free()
	print("EXTRACTION BACKGROUND FAILURES: ", failures)
	quit(1 if failures else 0)
