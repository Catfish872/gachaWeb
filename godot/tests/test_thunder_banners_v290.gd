extends "res://tests/test_redesign_layout.gd"
const OUT = "res://validation/v290-revised-art/"
const Sequence = preload("res://scripts/ui/summon_sequence.gd")

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + label + ".png")

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await frames()
	app.set_process(false)
	app.model = load("res://scripts/game_model.gd").new("")
	var original: Dictionary = app.model.state.duplicate(true)
	var patch: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/thunder_acquisition_patch.json"))
	for resolution in [Vector2i(1440, 810), Vector2i(960, 540)]:
		root.size = resolution
		for id in ["raisa", "vika", "eve"]:
			var pool_id: String = "limited_" + id
			var path: String = "res://assets/content_v290/banner/%s_layered_banner.png" % id
			check(app.model.catalog.GachaPoolData.pools[pool_id].bannerPath == path, "catalog layered banner " + id)
			check(patch[pool_id].bannerPath == path, "patch layered banner " + id)
			check(ResourceLoader.exists(path), "layered banner imported " + id)
			if not ResourceLoader.exists(path): continue
			var texture: Texture2D = load(path)
			check(texture.get_width() > texture.get_height(), "landscape banner " + id)
			app.selected_pool = pool_id
			app.navigate("summon")
			await frames(4)
			var stage = app.main_body.find_child("SummonStage", true, false)
			check(stage != null and stage.get_meta("embedded_banner_character", false), "embedded half-body composition " + id)
			fits(stage, "thunder summon stage " + id)
			fits(app.main_body.find_child("SummonPull_1", true, false), "single pull " + id)
			fits(app.main_body.find_child("SummonPull_10", true, false), "ten pull " + id)
			await capture("banner-" + id + "-" + str(resolution.x))
			var sequence = Sequence.new()
			sequence.setup(app, [{"charId": id}], pool_id, true)
			check(sequence._background.resource_path == path, "summon sequence shares banner " + id)
			sequence.free()
	check(app.model.state == original, "banner navigation and presentation preserve save state")
	app.queue_free()
	await frames(3)
	await create_timer(.5).timeout
	print("THUNDER BANNERS V290: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
