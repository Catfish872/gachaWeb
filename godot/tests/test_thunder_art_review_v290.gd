extends "res://tests/test_redesign_layout.gd"
const Avatars = preload("res://scripts/ui/character_avatar.gd")
const OUT = "res://validation/v290-revised-art/"

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
	for resolution in [Vector2i(1440,810), Vector2i(960,540)]:
		root.size = resolution
		for id in ["raisa", "vika", "eve"]:
			var face = Avatars.get_texture(id, "face")
			check(face is AtlasTexture, "curated face atlas " + id)
			check(face.region == Avatars.region_for(id), "curated face coordinates " + id)
			check(face.atlas.resource_path == Avatars.source_path(id), "face matches revised full body " + id)
			check(Avatars.get_texture(id, "bust").resource_path == Avatars.source_path(id), "full body source retained " + id)
			app.model.state.ownedCharacters[id] = app.model.default_character()
			app.selected_character = id
			app.navigate("growth")
			await frames(5)
			await capture("growth-" + id + "-" + str(resolution.x))
		for index in range(1,4):
			var key: String = "ch5_interlude_" + str(index)
			app._play_dialogue(key, Callable())
			app._next_dialogue()
			await frames(5)
			var art = app.find_child("DialogueBackdrop", true, false)
			check(art.texture.resource_path == app.model.catalog.DialogueMeta[key].illustration, "revised story CG " + key)
			check(art.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED, "full story composition " + key)
			var panel = app.find_child("DialogueTextFrame", true, false)
			check(art.get_global_rect().end.y <= panel.get_global_rect().position.y, "story interaction above dialogue " + key)
			await capture("story-" + str(index) + "-" + str(resolution.x))
			app._clear_overlay()
	app.queue_free()
	await frames(3)
	await create_timer(.5).timeout
	print("THUNDER ART REVIEW V290: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
