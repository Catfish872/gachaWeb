extends SceneTree
const Game = preload("res://scripts/game_model.gd")
const Events = preload("res://scripts/expedition_events.gd")
var checks := 0
var failures := 0
func ck(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
func _initialize() -> void: call_deferred("run_tests")
func first_difference(a: Variant, b: Variant, path: String = "root") -> String:
	if a is Dictionary and b is Dictionary:
		for key in a:
			if not b.has(key): return path+"."+str(key)+" missing"
			var difference := first_difference(a[key],b[key],path+"."+str(key))
			if not difference.is_empty(): return difference
		return "" if a.size()==b.size() else path+" key count differs"
	if a is Array and b is Array:
		if a.size()!=b.size():return path+" array size differs"
		for index in range(a.size()):
			var difference := first_difference(a[index],b[index],path+"["+str(index)+"]")
			if not difference.is_empty():return difference
		return ""
	if a!=b or typeof(a)!=typeof(b):return "%s: %s (%s) -> %s (%s)"%[path,JSON.stringify(a,"",true,true),typeof(a),JSON.stringify(b,"",true,true),typeof(b)]
	return ""
func fresh():
	var g = Game.new("")
	g.rng.seed = 280
	g.extraction.start_run()
	g.extraction.run().environmentOrder = ["windpass","ruins","forest"]
	g.extraction._generate_map()
	g.extraction.run().phase = "room"
	return g
func run_tests() -> void:
	var g = fresh()
	var ex = g.extraction
	ck(ex.data.environmentThemes.size() == 5, "five theme candidates")
	ck(ex.max_acts() == 3 and ex.run().environmentOrder.size() == 3, "three acts retained")
	for seed_value in range(12):
		var sampled = Game.new(""); sampled.rng.seed = seed_value; sampled.extraction.start_run()
		var order: Array = sampled.extraction.run().environmentOrder
		var unique: Dictionary = {}
		for theme in order: unique[theme] = true
		ck(order.size() == 3 and unique.size() == 3, "draw three unique themes " + str(seed_value))
	ck(ex.run().map.districts.size() == 3 and ex.run().map.rooms.size() == 19, "one act has three maps and unchanged room quota")
	for depth in range(3):
		ex.run().room = ex.run().map.rooms[depth*6].duplicate(true)
		ck(ex.run().map.districts[depth].name == ["谷口外驿","悬枝风廊","云巢风庭"][depth], "district name " + str(depth))
		ck(ex.environment_music_track() == ["windpass_road","windpass_gallery","windpass_core"][depth], "district music " + str(depth))
		ck(ex.battle_background_path() == ex.run().room.background, "frozen room scenery " + str(depth))
	var variants: Array = []
	var counts: Dictionary = {}
	for id in ex.data.items:
		var d: Dictionary = ex.item_def(id)
		if d.get("environmentTheme", "") != "windpass" or d.kind != "loot": continue
		variants.append(id)
		counts[int(d.rarity)] = int(counts.get(int(d.rarity), 0)) + 1
		var base: Dictionary = ex.item_def(d.variantOf)
		for key in ["rarity","width","height","value","effects","category","dropWeight"]:
			ck(d.get(key) == base.get(key), "variant preserves " + key + " " + id)
		ck(ex._environment_loot_id(d.variantOf) == id, "base selection maps once " + id)
	ck(variants.size() == 24 and counts.size() == 6, "24 loot variants over six tiers")
	for rarity in counts: ck(counts[rarity] == 4, "four variants per tier " + str(rarity))
	ck(ex.item_def("key_windpass").buyPrice == 500, "wind key costs 500 gold")
	ck(ex.keyring().size() == 5 and ex.keyring().back().itemId == "key_windpass", "keyring exposes new theme")
	ck(ex.data.environmentThemes.windpass.containers.size() == 6, "six separate clickable containers")
	for id in ["repair_patch","repair_kit","repair_core"]:
		ck(ex._matches_loot_categories(ex.item_def(id),ex._container_categories("cache","windpass_herb_basket",{})), "medical supply routing " + id)
	ck(ex._container_categories("cache","windpass_tool_cabinet",{}).has("整备"), "tool cabinet routes repair categories")
	for id in variants:
		var item_game = fresh(); var item_ex = item_game.extraction
		var variant: Dictionary = item_ex.item_def(id).duplicate(true)
		var base_id: String = variant.variantOf
		var base: Dictionary = item_ex.item_def(base_id).duplicate(true)
		item_ex.data.items = {base_id:base, id:variant}
		item_ex.data.rarityWeightsByAct[0] = [0,0,0,0,0,0]
		item_ex.data.rarityWeightsByAct[0][int(variant.rarity)] = 1
		item_ex._container("主题物资",1,0)
		var box: Dictionary = item_ex.run().containers.back()
		ck(box.items.size() == 1 and box.items[0].itemId == id, "actual generation and packing " + id)
		var uid: String = box.items[0].uid
		ck(item_ex.reveal_next(box.id).success and item_ex.take_item(box.id,uid).success, "reveal and collect " + id)
		item_ex.run().phase = "boss_exit"
		ck(item_ex.extract().success and item_ex.state().stash.any(func(item):return item.uid == uid and item.itemId == id), "extract exact themed item " + id)
	g = fresh(); ex = g.extraction
	for act in range(1,4):
		ex.run().environmentOrder = ["windpass","ruins","forest"] if act == 1 else ["ruins","windpass","forest"] if act == 2 else ["ruins","forest","windpass"]
		ex.run().act = act
		ex._generate_map(); ex.run().node = 4
		for rank in range(6):
			ex.run().difficulty = rank
			ex._generate_encounter("boss")
			var issued: Dictionary = ex.run().activeEncounter.duplicate(true)
			ck(issued.enemies == ["boss_highland_roc","windfield_updraft","windfield_crosswind"], "explicit boss formation " + str([act,rank]))
			ck(is_equal_approx(float(issued.finalBossStatMultiplier),1.15 if act == 3 else 1.0), "final multiplier " + str([act,rank]))
			var budget: Dictionary = ex._theme_encounter_budget("boss",issued.enemies,act,rank)
			var escort_hp := 1620.0 if rank == 5 else 1200.0 if rank == 4 else 0.0
			var escort_atk := 170.0 if rank == 5 else 90.0 if rank == 4 else 0.0
			ck(is_equal_approx(27000.0 * float(budget.hpMod),5500.0+escort_hp), "complete boss HP budget " + str([act,rank]))
			ck(is_equal_approx(292.0 * float(budget.atkMod),140.0+escort_atk*0.0), "bounded escort attack conversion " + str([act,rank]))
			var raw_attack_scale: float = float(issued.scaleMult.atkMod)/float(budget.atkMod)
			var shares: Array = [90,80] if rank == 5 else [90,15] if rank == 4 else [15,15]
			ck(int(issued.enemyAttackOverrides.windfield_updraft)==maxi(1,int(shares[0]*raw_attack_scale)) and int(issued.enemyAttackOverrides.windfield_crosswind)==maxi(1,int(shares[1]*raw_attack_scale)), "field single-target attack shares " + str([act,rank]))
			ck(not issued.enemyAttackOverrides.has("boss_highland_roc"), "field budget stays off boss area attacks")
			var state_before: String = JSON.stringify(ex.run())
			ck(ex.prepare_battle().config == issued and ex.prepare_battle().config == issued and JSON.stringify(ex.run()) == state_before, "issued encounter and RNG remain frozen " + str([act,rank]))
	for theme in ["ruins","forest","sanctum","lantern"]:
		ex.run().environmentOrder = [theme,"windpass","forest"] if theme != "forest" else ["forest","windpass","ruins"]
		ex.run().act = 1; ex.run().difficulty = 5; ex._generate_map(); ex._generate_encounter("boss")
		var ids: Array = ex.run().activeEncounter.enemies
		ck(ids == ["boss_hedor","furnace_lamp","furnace_lamp"] if theme == "lantern" else ids[0] in ["boss_flame_lord","boss_storm_witch"] and ids.slice(1) == ["dark_knight","thunder_hawk"], "old theme formation preserved " + theme)
		ck(Events.event_ids(theme) == [0,1,2,3,4,5,6,7,8], "old theme event candidates preserved " + theme)
		ck(not ex.run().activeEncounter.has("enemyAttackOverrides"), "old theme attack scaling retained " + theme)
	# Reload contracts compare the decoded save payload, exactly as the loader receives it.
	# JSON storage converts integer tags and finite decimal precision before normalization.
	var saved_payload: Dictionary = JSON.parse_string(JSON.stringify(g.state))
	print("JSON_SAVE_BOUNDARY map: "+first_difference(ex.run().map,saved_payload.extraction.run.map))
	var old_map: Dictionary = saved_payload.extraction.run.map.duplicate(true)
	var old_issued: Dictionary = saved_payload.extraction.run.activeEncounter.duplicate(true)
	var old_rng: String = ex.run().rngState
	g.state = g._normalize(saved_payload)
	if ex.run().map != old_map: print("NORMALIZE_MAP_DIFF "+first_difference(old_map,ex.run().map))
	if ex.run().activeEncounter != old_issued: print("NORMALIZE_ENCOUNTER_DIFF "+first_difference(old_issued,ex.run().activeEncounter))
	ck(ex.run().map == old_map and ex.run().activeEncounter == old_issued and ex.run().rngState == old_rng, "reload preserves old map encounter and RNG")
	g = fresh(); ex = g.extraction
	ex.run().room.type = "workshop"
	var gold: int = g.state.resources.gold
	ck(ex.buy_keys("key_windpass").success and g.state.resources.gold == gold-500, "real key purchase charges gold")
	ex.run().room.type = "key_vault"; ex._prepare_room_actions("key_vault")
	ck(ex.choose_room_action("unlock").success and ex.state().keyring.is_empty() and ex.run().room.unlocked, "real key unlock consumes exactly one key")
	g = fresh(); ex = g.extraction
	for event_id in [9,10,11]:
		ex.run().containers = []; ex.run().pendingChoices = []
		ex._prepare_room_actions("event",event_id)
		var event_payload: Dictionary = JSON.parse_string(JSON.stringify(g.state))
		print("JSON_SAVE_BOUNDARY event "+str(event_id)+": "+first_difference(ex.run().roomActions,event_payload.extraction.run.roomActions))
		var actions: String = JSON.stringify(event_payload.extraction.run.roomActions)
		var rng_before: String = ex.run().rngState
		ck(ex.room_actions().size() == 3, "three sampled themed options " + str(event_id))
		g.state = g._normalize(event_payload)
		ck(JSON.stringify(ex.run().roomActions) == actions and ex.run().rngState == rng_before, "themed event read/reload is stable " + str(event_id))
		ck(not ex.choose_room_action("unissued_choice").success, "unissued event option rejected " + str(event_id))
	for floor_number in [1,4,5,10,20,100]:
		var pool: Array = g.abyss_enemy_pool(floor_number)
		ck(not pool.has("windfield_updraft") and not pool.has("windfield_crosswind"), "fields excluded from abyss pool " + str(floor_number))
	ck(not g.abyss_enemy_pool(4).has("wind_falcon") and not g.abyss_enemy_pool(10).has("boss_highland_roc"), "first ten layers retain default enemies")
	g.state.abyss.rogue.sceneBlocks = {"11": {"startFloor":11,"theme":"windpass","depth":0,"background":ex.data.environmentThemes.windpass.backgrounds[0][0]}}
	ck(g.abyss_enemy_pool(11).has("wind_falcon") and g.abyss_enemy_pool(15).has("windwheel_sentinel") and g.abyss_enemy_pool(20)==["boss_highland_roc"], "wind enemies belong to selected abyss block")
	var rng_snapshot: int = g.rng.state
	for id in ex.data.environmentThemes.windpass.enemies.battle + ex.data.environmentThemes.windpass.enemies.elite + ["boss_highland_roc"]:
		var first: String = g.abyss_encounter_background([id],280)
		ck(first.begins_with("res://assets/content_v280/backgrounds/") and first == g.abyss_encounter_background([id],280), "stable compatible abyss habitat " + id)
	ck(g.rng.state == rng_snapshot, "habitat lookup preserves RNG")
	print("WIND WORLD V280: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
