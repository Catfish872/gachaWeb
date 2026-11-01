extends SceneTree
const Game = preload("res://scripts/game_model.gd")
var checks := 0
var failures := 0
func ck(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL ", message)
func _init() -> void:
	var orders: Dictionary = {}
	for seed_value in range(6):
		var g = Game.new("")
		g.rng.seed = 260100 + seed_value
		var x = g.extraction
		ck(x.start_run().success, "new run starts")
		orders[JSON.stringify(x.run().environmentOrder)] = true
		var order: Array = x.run().environmentOrder.duplicate()
		var unique: Dictionary = {}
		for theme in order: unique[theme] = true
		ck(unique.size() == 3, "three themes without replacement")
		for act in range(1,4):
			x.run().act = act
			x.run().node = 0
			x._generate_map()
			x._routes()
			var map: Dictionary = x.run().map
			var config: Dictionary = x.data.environmentThemes[order[act-1]]
			ck(map.theme == order[act-1] and map.name == config.name, "act uses persisted shuffled environment")
			ck(x.environment_music_track() == config.music, "music follows environment")
			for district in map.districts:
				ck(district.theme == map.theme and district.name == config.depthNames[int(district.depth)], "district names describe same-theme depth")
			for room in map.rooms:
				ck(room.environmentTheme == map.theme and room.background in config.backgrounds[int(room.depth)], "room backdrop belongs to its environment depth")
				ck(room.districtName == config.depthNames[int(room.depth)], "room depth label matches scene")
				if room.type == "relay":
					ck(map.rooms.find(room) not in [0,1,2,18], "relay occupies a legal non-entry room")
			ck(map.rooms.back().background == config.backgrounds[2][0], "boss reaches visual core")
			ck(g.valid_save(g.state), "new environment save passes model validation")
			var snapshot := JSON.stringify(JSON.parse_string(JSON.stringify(x.run().map)))
			var random_state: String = x.run().rngState
			var serialized = JSON.parse_string(JSON.stringify(g.state))
			g.state = serialized
			x.migrate_state(g.state,9)
			x._routes()
			ck(JSON.stringify(x.run().map) == snapshot and x.run().rngState == random_state, "loading and map revisit preserve all rooms and RNG")
			ck(x.run().environmentOrder == order, "loading preserves environment order")
		# Same pre-loot RNG state produces equal economic objects; only art/name IDs vary.
		var before: Dictionary = g.state.duplicate(true)
		x.run().containers = []
		x._container("same",12,1)
		var themed_box: Dictionary = x.run().containers.back().duplicate(true)
		var themed_rng: String = x.run().rngState
		g.state = before.duplicate(true)
		x.run().erase("environmentOrder")
		x.run().containers = []
		x._container("same",12,1)
		var original_box: Dictionary = x.run().containers.back()
		ck(x.run().rngState == themed_rng and original_box.items.size() == themed_box.items.size(), "themed loot preserves RNG draws and item count")
		for i in range(original_box.items.size()):
			var old: Dictionary = original_box.items[i]
			var themed: Dictionary = themed_box.items[i]
			var definition: Dictionary = x.item_def(themed.itemId)
			ck(str(definition.get("variantOf",themed.itemId)) == str(old.itemId), "themed item is exact original weighted draw")
			ck(x.item_value(themed) == x.item_value(old) and x._size(themed) == x._size(old), "themed item keeps exact value and shape")
		# A legacy active map keeps its names, scenes, order and old music on load.
		g.state = before.duplicate(true)
		x.run().erase("environmentOrder")
		x._generate_map();x._routes()
		var legacy := JSON.stringify(x.run().map)
		x.migrate_state(g.state,9);x._routes()
		ck(JSON.stringify(x.run().map) == legacy and not x.run().has("environmentOrder"), "legacy run is not rerolled or upgraded in place")
		ck(x.environment_music_track() == "dungeon_mystic", "legacy act music preserved")
	ck(orders.size() > 1, "run order actually varies across seeds")
	var g = Game.new("")
	for district in range(3):
		for conflict in [6,9,12,17]:
			for slot_roll in [0.0,0.5,0.999]:
				var index: int = g.extraction._relay_room_index((district+0.5)/3.0,slot_roll,conflict,16)
				ck(int(index/6) == district and index not in [0,1,2,conflict,16], "equal-third district choice retains legal random slot")
	var count := 0
	for id in g.extraction.data.items:
		var item: Dictionary = g.extraction.item_def(id)
		if not item.has("variantOf"): continue
		count += 1
		var base: Dictionary = g.extraction.item_def(item.variantOf)
		for key in ["rarity","kind","width","height","value","category","effects"]:
			ck(item.get(key) == base.get(key), "variant preserves base field " + key)
		ck(item.get("dropWeight",1.0) == base.get("dropWeight",1.0), "variant preserves weighted share")
	ck(count == 12, "twelve themed collectibles added")
	print("THEMED MAPS V260: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
