extends "res://tests/test_lantern_journey_ui_v270.gd"

const STORY_OUT := "res://validation/v284-story-background/"

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	DirAccess.make_dir_recursive_absolute(STORY_OUT)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(STORY_OUT + label + ".png")

func assert_story_scene(expected: String, label: String) -> void:
	var backdrop := app.get_node("SceneBackdrop") as TextureRect
	ck(app._background_path() == expected, label + " resolves selected stage background")
	ck(backdrop.texture != null and backdrop.texture.resource_path == expected, label + " updates outer background")
	var matching_previews := 0
	for image in app.main_body.find_children("*", "TextureRect", true, false):
		if image.texture != null and image.texture.resource_path == expected:
			matching_previews += 1
	ck(matching_previews == 1, label + " preview and outer background share selected map")
	ck(backdrop.modulate == Color(0.28, 0.32, 0.4, 0.20), label + " retains mobile background tint")
	ck(backdrop.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_COVERED, label + " retains full-screen art crop")

func fixture_story() -> void:
	fresh()
	for stage in app.model.stage_list():
		if not str(stage.id).begins_with("ch4_") or int(str(stage.id).trim_prefix("ch4_")) <= 9:
			app.model.state.stageProgress[stage.id] = {"cleared": true}
	app.navigate("story")
	await frames(8)

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await frames(10)
	app.set_process(false)
	await fixture_story()
	# Resolve only the affected chapter mapping, without replaying combat or dialogue.
	for chapter_index in app.model.catalog.StageData.chapters.size():
		app.selected_chapter = chapter_index
		for stage in app.model.catalog.StageData.chapters[chapter_index].stages:
			app.selected_stage_id = str(stage.id)
			var fallback := "res://assets/backgrounds/snowfield.png" if chapter_index == 1 else "res://assets/wilderness.png"
			var expected := str(stage.get("background", fallback))
			ck(app._background_path() == expected, str(stage.id) + " chapter background mapping")
	for resolution in [Vector2i(960, 540), Vector2i(2048, 945)]:
		root.size = resolution
		await frames(8)
		await fixture_story()
		ck(app.selected_chapter == 3 and app.selected_stage_id == "ch4_10", "opens current unfinished fourth-chapter stage")
		assert_story_scene("res://assets/content_v280/backgrounds/rope_bridge.png", "fourth chapter initial selection")
		fits(app.find_child("StoryEnter", true, false), "story action")
		await capture(str(resolution.x) + "-chapter4-bridge")
		var scroll := app.find_child("StoryStageScroll", true, false) as ScrollContainer
		var card := app.find_child("StageCard_ch4_9", true, false) as Control
		scroll.ensure_control_visible(card)
		await frames(4)
		var scroll_before := scroll.scroll_vertical
		await tap(card)
		ck(app.selected_stage_id == "ch4_9", "actual stage card tap selects adjacent map")
		assert_story_scene("res://assets/content_v280/backgrounds/flooded_gallery.png", "fourth chapter changed selection")
		scroll = app.find_child("StoryStageScroll", true, false) as ScrollContainer
		ck(abs(scroll.scroll_vertical - scroll_before) <= 1, "stage selection preserves list scroll")
		app._render_screen()
		await frames(6)
		assert_story_scene("res://assets/content_v280/backgrounds/flooded_gallery.png", "fourth chapter repeated redraw")
		app.find_child("StoryChapter_2", true, false).pressed.emit()
		await frames(6)
		ck(app.selected_chapter == 2 and app.selected_stage_id == "ch3_8", "chapter tab changes selection")
		assert_story_scene("res://assets/content_v270/backgrounds/furnace_core.png", "third chapter preserved mapping")
		await capture(str(resolution.x) + "-chapter3-furnace")
		app.find_child("StoryChapter_0", true, false).pressed.emit()
		await frames(4)
		assert_story_scene("res://assets/wilderness.png", "first chapter legacy fallback")
		app.find_child("StoryChapter_1", true, false).pressed.emit()
		await frames(4)
		assert_story_scene("res://assets/backgrounds/snowfield.png", "second chapter legacy fallback")
		app.find_child("StoryChapter_3", true, false).pressed.emit()
		await frames(6)
		assert_story_scene("res://assets/content_v280/backgrounds/rope_bridge.png", "fourth chapter return")
		app.navigate("home")
		await frames(4)
		ck(app.get_node("SceneBackdrop").texture.resource_path == "res://assets/backgrounds/camp.png", "home keeps camp background")
		app.navigate("story")
		await frames(6)
		assert_story_scene("res://assets/content_v280/backgrounds/rope_bridge.png", "story re-entry")
	app.queue_free()
	await frames(6)
	print("STORY BACKGROUND V284: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
