extends SceneTree
const Game = preload("res://scripts/game_model.gd")
const Audio = preload("res://scripts/thunder_audio.gd")
var checks := 0
var failures := 0
func ck(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
func _initialize() -> void: call_deferred("run_tests")
func fresh():
	var g = Game.new(""); g.rng.seed = 290
	g.extraction.start_run()
	g.extraction.run().environmentOrder = ["thunder_city", "ruins", "forest"]
	g.extraction._generate_map(); g.extraction.run().phase = "room"
	return g
func run_tests() -> void:
	var g = fresh(); var ex = g.extraction
	ck(ex.data.environmentThemes.size() == 6, "six themes")
	ck(ex.max_acts() == 3 and ex.run().environmentOrder.size() == 3, "existing three-act length")
	for seed_value in range(24):
		var sampled = Game.new(""); sampled.rng.seed = seed_value; sampled.extraction.start_run()
		var unique := {}; var order: Array = sampled.extraction.run().environmentOrder
		for theme in order: unique[theme] = true
		ck(order.size() == 3 and unique.size() == 3, "without-replacement theme draw %d"%seed_value)
	ck(ex.run().map.districts.size() == 3 and ex.run().map.rooms.size() == 19, "three maps and original room quota")
	ck(ex.run().map.rooms.back().background=="res://assets/content_v290/backgrounds/rift_core.png", "boss room uses the underground rift core")
	for depth in range(3):
		ex.run().room = ex.run().map.rooms[depth*6].duplicate(true)
		ck(ex.run().map.districts[depth].name == ["雷雨城郊","鸣雷旧城","雷塔禁区"][depth], "district name")
		ck(ex.environment_music_track() == ["thunder_city_gate","thunder_city_street","thunder_city_core"][depth], "district score")
		ck(ex.battle_background_path() == ex.run().room.background, "room background frozen")
	var variants := []; var counts := {}
	for id in ex.data.items:
		var d: Dictionary = ex.item_def(id)
		if d.get("environmentTheme", "") != "thunder_city" or d.kind != "loot": continue
		variants.append(id); counts[int(d.rarity)] = int(counts.get(int(d.rarity),0))+1
		var base: Dictionary = ex.item_def(d.variantOf)
		for key in ["rarity","width","height","value","effects"]:
			ck(d.get(key) == base.get(key), "base economy unchanged %s/%s"%[id,key])
		var selected: String = ex._environment_loot_id(d.variantOf)
		var selected_def: Dictionary = ex.item_def(selected)
		ck(selected == id or (selected_def.get("lootTheme", "") == "thunder_city" and selected_def.get("economyAnchor", "") == d.variantOf), "theme family mapping "+id)
		ck(ResourceLoader.exists(d.icon), "loot icon "+id)
	ck(variants.size() == 24 and counts.size() == 6, "24 loot over six qualities")
	for rarity in counts: ck(counts[rarity] == 4, "four per quality")
	for id in variants:
		var item_game = fresh(); var item_ex = item_game.extraction
		var variant: Dictionary = item_ex.item_def(id).duplicate(true)
		var base_id: String = variant.variantOf
		item_ex.data.items = {base_id:item_ex.item_def(base_id).duplicate(true), id:variant}
		item_ex.data.rarityWeightsByAct[0] = [0,0,0,0,0,0]; item_ex.data.rarityWeightsByAct[0][int(variant.rarity)] = 1
		item_ex._container("主题物资",1,0)
		var box: Dictionary = item_ex.run().containers.back()
		ck(box.items.size() == 1 and box.items[0].itemId == id, "actual loot generation "+id)
		var uid: String = box.items[0].uid
		ck(item_ex.reveal_next(box.id).success and item_ex.take_item(box.id,uid).success, "search and pack "+id)
		item_ex.run().phase = "boss_exit"
		ck(item_ex.extract().success and item_ex.state().stash.any(func(item):return item.uid == uid and item.itemId == id), "extracted exact item "+id)
	g = fresh(); ex = g.extraction
	ck(ex.keyring().size()==6 and ex.keyring().back().itemId=="key_thunder_city", "keyring new theme")
	ex.run().room.type="workshop"; var gold: int=g.state.resources.gold
	ck(ex.buy_keys("key_thunder_city").success and g.state.resources.gold == gold-500, "key purchase 500")
	ex.run().room.type="key_vault"; ex._prepare_room_actions("key_vault")
	ck(ex.choose_room_action("unlock").success and ex.state().keyring.is_empty() and ex.run().room.unlocked, "correct key consumed once")
	for id in ex.data.environmentThemes.thunder_city.containers:
		ck(ResourceLoader.exists(ex.data.environmentContainers[id].sprite), "independent container "+id)
	ck(ex._container_categories("cache","thunder_city_medicine",{}).has("疗愈用品"), "clinic container medical identity")
	ck(ex._container_categories("cache","thunder_city_tools",{}).has("整备"), "workshop container repair identity")
	for act in range(1,4):
		ex.run().environmentOrder = ["thunder_city","ruins","forest"] if act==1 else ["ruins","thunder_city","forest"] if act==2 else ["ruins","forest","thunder_city"]
		ex.run().act=act; ex._generate_map(); ex.run().node=4
		for rank in range(6):
			ex.run().difficulty=rank; ex._generate_encounter("boss")
			var issued: Dictionary=ex.run().activeEncounter.duplicate(true)
			ck(issued.enemies==["boss_city_sealer","sealer_core","sealer_ward"], "three selectable boss targets")
			var budget: Dictionary=ex._theme_encounter_budget("boss",issued.enemies,act,rank)
			var escort_hp: float=1620.0 if rank==5 else 1200.0 if rank==4 else 0.0
			ck(is_equal_approx(39200.0*float(budget.hpMod),5500.0+escort_hp), "complete boss durability budget")
			ck(is_equal_approx(342.0*float(budget.atkMod),140.0), "escort attack remains separate from boss area attacks")
			ck(not issued.enemyAttackOverrides.has("boss_city_sealer"), "boss receives no support attack allocation")
			var before: String=JSON.stringify(ex.run())
			ck(ex.prepare_battle().config==issued and ex.prepare_battle().config==issued and JSON.stringify(ex.run())==before, "issued encounter and RNG frozen")
	for theme in ["ruins","forest","sanctum","lantern","windpass"]:
		ex.run().environmentOrder=[theme,"thunder_city","forest"] if theme!="forest" else ["forest","thunder_city","ruins"]
		ex.run().act=1; ex.run().difficulty=5; ex._generate_map(); ex._generate_encounter("boss")
		var ids: Array=ex.run().activeEncounter.enemies
		ck(not ids.has("boss_city_sealer") and not ids.has("sealer_core"), "old theme excludes new boss "+theme)
		if theme in ["ruins","forest","sanctum"]: ck(ids[0] in ["boss_flame_lord","boss_storm_witch"] and ids.slice(1)==["dark_knight","thunder_hawk"], "legacy formation "+theme)
	var payload: Dictionary=JSON.parse_string(JSON.stringify(g.state))
	var saved_map: Dictionary=payload.extraction.run.map.duplicate(true); var saved_encounter: Dictionary=payload.extraction.run.activeEncounter.duplicate(true)
	var saved_rng: String=ex.run().rngState
	g.state=g._normalize(payload)
	ck(ex.run().map==saved_map and ex.run().activeEncounter==saved_encounter and ex.run().rngState==saved_rng, "save preserves issued content")
	g=fresh();ex=g.extraction
	var options: Array=g.abyss_scene_options(); ck(options.size()==18, "18 uniform nondefault map slots")
	for index in range(options.size()):
		var scene: Dictionary=g.abyss_scene_from_roll(11,.25+.75*(index+.5)/options.size())
		ck(scene.theme==options[index].theme and scene.depth==options[index].depth, "uniform nondefault scene bin")
		if scene.theme=="thunder_city":
			ck(ResourceLoader.exists(scene.background), "new abyss scene resource")
			ck(g.abyss_scene_enemy_pool(20,scene)==["boss_city_sealer"], "new abyss boss pool")
			ck(g.abyss_boss_music_track(scene)=="thunder_boss", "new abyss boss score")
			ck(g.abyss_music_track(scene)==["thunder_city_gate","thunder_city_street","thunder_city_core"][int(scene.depth)], "new abyss exploration score")
	for floor_number in [1,10]:ck(g.abyss_scene_from_roll(floor_number,.9999).theme=="", "first ten floors remain default")
	ck(g.abyss_scene_from_roll(11,.24999).theme=="", "default probability remains 25 percent")
	var scene: Dictionary={"startFloor":11,"theme":"thunder_city","depth":0,"background":ex.data.environmentThemes.thunder_city.backgrounds[0][0]}
	g.state.abyss.rogue.sceneBlocks={"11":scene}
	for floor_number in [11,15,20]:
		ck(g.abyss_scene_enemy_pool(floor_number).all(func(id):return g.catalog.EnemyData[id].environmentTheme=="thunder_city" and not g.catalog.EnemyData[id].get("encounterAttachment",false)), "scene-pool isolation")
	for track in Audio.MUSIC:
		ck(ResourceLoader.exists(Audio.music_path(track)) and Audio.music_loop_offset(track)==0.0,"new licensed score "+track)
	var notice := FileAccess.get_file_as_string("res://assets/audio/content_v290/LICENSES.txt") + FileAccess.get_file_as_string("res://assets/audio/content_v293/LICENSES.txt")
	for credit in Audio.music_credits():
		ck(notice.contains(str(credit.title).split(" · ")[0]) and notice.contains(str(credit.source_url)), "music notice retains title and source " + str(credit.id))
		ck(notice.contains(str(credit.creator).replace("Music by ", "").split(" (")[0]) and notice.contains(str(credit.license_url)), "music attribution and license " + str(credit.id))
	var presets := ConfigFile.new()
	ck(presets.load("res://export_presets.cfg") == OK, "export presets readable")
	for section in presets.get_sections():
		if not section.begins_with("preset.") or section.ends_with(".options"): continue
		var includes_notice := false
		for pattern in str(presets.get_value(section, "include_filter", "")).split(","):
			if "assets/audio/content_v290/LICENSES.txt".match(pattern.strip_edges()): includes_notice = true
		ck(includes_notice, "export retains thunder music license " + section)
	print("THUNDER WORLD V290: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
