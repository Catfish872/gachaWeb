extends SceneTree
const GameModel = preload("res://scripts/game_model.gd")
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
func run():
	var folder = "/tmp/voidrift-storage-%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(folder)
	var m = GameModel.new(folder)
	check(m.active_slot == 1 and m.state.resources.diamonds == 1600, "disk default slot is fresh")
	check(m.pull("standard", 1).get("success", false), "disk-backed pull commits")
	check(m.load_slot(2).get("success", false) and m.state.resources.diamonds == 1600, "second slot isolated")
	check(m.purchase("recharge", "recharge_hero").get("success", false), "simulated recharge commits in slot2")
	var second_balance = m.state.resources.diamonds
	var reload = GameModel.new(folder)
	check(reload.active_slot == 2 and reload.state.resources.diamonds == second_balance, "restart restores active slot2 and resources")
	check(not reload.export_save(folder + "/empty.json", 3).get("success", true), "empty inactive slot cannot export current state")
	check(reload.export_save(folder + "/slot1-export.json", 1).get("success", false), "inactive slot1 exports")
	check(reload.active_slot == 2 and reload.state.resources.diamonds == second_balance, "inactive export leaves active slot unchanged")
	var exported = JSON.parse_string(FileAccess.get_file_as_string(folder + "/slot1-export.json"))
	check(exported.data.resources.diamonds == 1440 and exported.data.stats.totalPulls == 1, "export contains correct slot1 history")
	check(reload.import_save("res://tests/fixtures/web-save-export.json", 3).get("success", false), "web export imports into inactive slot3")
	check(reload.active_slot == 2 and reload.state.resources.diamonds == second_balance, "inactive import leaves current slot unchanged")
	check(reload.load_slot(3).get("success", false) and reload.state.resources.diamonds == 4321, "imported slot3 activates correctly")
	var third = GameModel.new(folder)
	check(third.active_slot == 3 and third.state.ownedCharacters.kaldi.level == 7, "restarting imported slot retains progression")
	var bad = FileAccess.open(folder + "/bad.json", FileAccess.WRITE)
	bad.store_string('{"version":3,"resources":{"diamonds":-10}}')
	bad.close()
	var before = JSON.stringify(third.state)
	check(not third.import_save(folder + "/bad.json").get("success", true), "malformed import rejected")
	check(JSON.stringify(third.state) == before, "rejected import preserves entire in-memory state")
	var after = GameModel.new(folder)
	check(after.state.resources.diamonds == 4321 and after.state.ownedCharacters.kaldi.level == 7, "rejected import preserves disk save")
	print("STORAGE TESTS: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)
