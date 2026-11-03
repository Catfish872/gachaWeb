extends "res://tests/test_lantern_journey_ui_v270.gd"
const Avatars = preload("res://scripts/ui/character_avatar.gd")
const Bust = preload("res://scripts/ui/character_bust.gd")
const OUT281 = "res://validation/v281-portraits/"

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT281 + label + ".png")

func descendants(node: Node) -> Array:
	var result: Array = []
	for child in node.get_children():
		result.append(child)
		result.append_array(descendants(child))
	return result

func check_bust(portrait, id: String, label: String) -> void:
	ck(portrait != null and portrait is Bust, label + " uses the shared bust renderer")
	if portrait == null or not portrait is Bust:return
	ck(portrait.texture != null and not portrait.texture is AtlasTexture, label + " keeps the complete transparent illustration")
	if portrait.texture == null:return
	ck(portrait.texture.resource_path == Avatars.source_path(id), label + " uses the correct character source")
	var rects = Bust.composition_rects(Rect2(Vector2.ZERO, portrait.size), portrait.texture.get_size(), portrait.composition_region)
	ck(rects.size() == 2, label + " has a valid visible composition")
	if rects.size() == 2:
		ck(absf(rects[0].end.y - portrait.size.y) < .1, label + " continues naturally to the frame bottom")
		ck(rects[1].position.x < portrait.composition_region.position.x or rects[1].end.x > portrait.composition_region.end.x or rects[1].end.y > portrait.composition_region.end.y, label + " does not crop at the internal composition anchor")

func shared_paths() -> void:
	var holder := Control.new()
	app.add_child(holder)
	for id in app.model.catalog.CharacterData:
		ck(Avatars.get_texture(str(id), "face") != null, "every released character has a readable face: " + str(id))
		ck(Avatars.get_texture(str(id), "bust") != null, "every released character has a bust source: " + str(id))
	for id in ["tiya", "lumi"]:
		var face: Texture2D = Avatars.get_texture(id, "face")
		ck(face is AtlasTexture and face.atlas.resource_path == "res://assets/content_v280/portraits/%s.png" % id, id + " uses its dedicated face asset")
		ck(face is AtlasTexture and face.region == Avatars.region_for(id, "face") and face.region.size.x < 512, id + " has a curated head crop matching the older small-avatar scale")
		ck(Avatars.source_path(id) == "res://assets/content_v280/characters/%s.png" % id, id + " reveal source resolves outside the old asset folder")
		# All shared small-avatar callers: turn queue, settlement, growth, relics,
		# expedition party, home team, recommendations, party seats and departure.
		for height in [24, 36, 38, 44, 45, 58, 66, 73, 74]:
			var portrait = app._portrait(holder, id, height)
			ck(portrait.get_meta("portrait_mode", "") == "face", id + " small portrait mode " + str(height))
			ck(portrait.get_node("CharacterPortraitTexture").texture == face, id + " small portrait uses close-up " + str(height))
			portrait.free()
		for height in [138, 180, 210, 270]:
			var portrait = app._portrait(holder, id, height)
			ck(portrait.get_meta("portrait_mode", "") == "full", id + " battle/dialogue/settlement full-body mode remains " + str(height))
			ck(portrait.get_node("CharacterPortraitTexture").texture.resource_path == Avatars.source_path(id), id + " full-body source remains unchanged")
			portrait.free()
		for height in [110, 130, 150, 270]:
			var portrait = app._portrait(holder, id, height, false, false, "bust")
			portrait.size = Vector2(240, height)
			await frames(2)
			check_bust(portrait.get_node("CharacterPortraitTexture"), id, id + " shared bust " + str(height))
			portrait.free()
	ck(Avatars.source_path("selin") == "res://assets/content_v270/characters/selin.png", "legacy Selin source remains unchanged")
	ck(Avatars.get_texture("selin", "face").resource_path == "res://assets/content_v270/portraits/selin_face.png", "legacy Selin dedicated face remains unchanged")
	holder.free()

func character_screens(label: String) -> void:
	app.model.state.team = ["tiya", "lumi", "selin"]
	app.draft_team = app.model.state.team.duplicate()
	app.character_filter = "全部"
	app.navigate("party");await frames(8)
	for id in ["tiya", "lumi"]:
		var stage = app.find_child("PortraitEnvironment_" + id, true, false)
		check_bust(stage.find_child("CharacterPortraitTexture", true, false) if stage != null else null, id, label + " party " + id)
	await capture(label + "-party")
	for id in ["tiya", "lumi"]:
		app.selected_character = id;app.growth_panel = "stats";app.navigate("growth");await frames(8)
		var stage = app.find_child("PortraitEnvironment_" + id, true, false)
		check_bust(stage.find_child("CharacterPortraitTexture", true, false) if stage != null else null, id, label + " growth " + id)
		var roster = app.find_child("GrowthSelect_" + id, true, false)
		var face = roster.find_child("CharacterPortraitTexture", true, false)
		ck(face.texture == Avatars.get_texture(id, "face"), "actual growth roster uses close-up " + id)
		await capture(label + "-growth-" + id)
		app.selected_pool = "limited_" + id;app.navigate("summon");await frames(8)
		stage = app.find_child("SummonStage", true, false)
		var expected_banner: String = "res://assets/content_v280/banner/%s_layered_banner.png" % id
		ck(app.model.catalog.GachaPoolData.pools["limited_" + id].bannerPath == expected_banner, "pool config selects the new large-portrait background " + id)
		ck(stage.get_meta("portrait_background", "") == expected_banner and ResourceLoader.exists(expected_banner), "pool uses the large background portrait and environment " + id)
		ck(stage.get_meta("embedded_banner_character", false), "pool combines a background portrait with the separate full-body foreground " + id)
		var pool_portrait = stage.find_child("CharacterPortraitTexture", true, false)
		ck(pool_portrait is TextureRect and pool_portrait.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED, "pool retains the legacy full-body fit " + id)
		ck(pool_portrait.texture.resource_path == Avatars.source_path(id), "pool uses the original transparent full-body illustration " + id)
		ck(pool_portrait.texture.get_size() == Vector2(1024,1536), "pool art matches legacy source dimensions " + id)
		fits(app.find_child("SummonPreview", true, false), "pool preview")
		await capture(label + "-pool-" + id)
		app._summon_character_preview(id);await frames(8)
		stage = app.find_child("PortraitEnvironment_" + id, true, false)
		check_bust(stage.find_child("CharacterPortraitTexture", true, false) if stage != null else null, id, "pool character preview " + id)
		app._clear_overlay();await frames(2)
	app.selected_pool = "limited_selin";app.navigate("summon");await frames(6)
	var legacy = app.find_child("SummonStage", true, false)
	ck(legacy.get_meta("portrait_background", "") == "res://assets/content_v270/banner/selin_banner.png", "old pool background retained")
	ck(legacy.find_child("CharacterPortraitTexture", true, false).texture.resource_path == Avatars.source_path("selin"), "old pool foreground retained")
	await capture(label + "-pool-selin-reference")

func prepared_reveals(label: String, animate: bool) -> void:
	for id in ["tiya", "lumi"]:
		app.selected_pool = "limited_" + id;app.navigate("summon");await frames(4)
		var before: Dictionary = app.model.state.duplicate(true)
		app.summon_results = [{"charId":id,"rarity":5,"isNew":true,"shards":0}]
		app._reveal_summon();await frames(6)
		var sequence = app.summon_sequence
		ck(sequence._background.resource_path == "res://assets/content_v280/banner/%s_layered_banner.png" % id, "reveal keeps the same large-portrait environment as the pool " + id)
		ck(sequence._art[0] != null and sequence._art[0].resource_path == Avatars.source_path(id), "real reveal loads the new source " + id)
		if animate:
			var deadline := Time.get_ticks_msec() + 7000
			while sequence.stage != "result" and Time.get_ticks_msec() < deadline:await process_frame
			ck(sequence.stage == "result" and sequence.stage_history.size() >= 6, "new character animation reaches result " + id)
		else:
			sequence._enter("result");await frames(4)
		check_bust(sequence._portrait, id, label + " reveal " + id)
		ck(sequence._portrait.material is ShaderMaterial, "reveal keeps its soft bottom fade " + id)
		await capture(label + "-reveal-" + id)
		ck(app.model.state == before, "portrait presentation does not change pulls or rewards " + id)
		app._clear_overlay();await frames(3)
	app.summon_results = []
	for i in 10:
		app.summon_results.append({"charId":"tiya" if i % 2 == 0 else "lumi","rarity":5,"isNew":false,"shards":10})
	app._reveal_summon();await frames(6)
	app.summon_sequence.show_summary();await create_timer(1.2).timeout
	var count := 0
	for node in descendants(app.summon_sequence._summary):
		if node is Bust:
			check_bust(node, node.character_id, label + " ten-pull card " + str(count))
			count += 1
	ck(count == 10, "all ten result portraits are rendered")
	await capture(label + "-ten-pull")
	app._clear_overlay();await frames(3)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT281)
	app = load("res://main.tscn").instantiate();root.add_child(app);await frames(12);app.set_process(false);fresh()
	for id in app.model.catalog.CharacterData:app.model.state.ownedCharacters[id] = app.model.default_character()
	await shared_paths()
	for resolution in [Vector2i(2048,945), Vector2i(960,540)]:
		root.size = resolution;await frames(8)
		await character_screens(str(resolution.x))
		await prepared_reveals(str(resolution.x), resolution.x == 960)
	app.queue_free();await frames(6)
	print("WIND PORTRAITS V281: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
