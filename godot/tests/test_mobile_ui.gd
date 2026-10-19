extends SceneTree
## Mobile regression tests use physical window sizes, logical layout, and synthetic
## viewport input. They do not certify Android OS dispatch or real-device usability.
var app
var checks := 0
var failures: Array[String] = []
const PHONE_SIZES := [Vector2i(1080, 2400), Vector2i(1080, 1920), Vector2i(720, 1600), Vector2i(2400, 1080), Vector2i(1920, 1080)]
const PAGES := ["home", "story", "summon", "party", "growth", "relics", "abyss", "shop", "save"]

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		push_error("MOBILE UI CHECK: " + description)

func frames(count: int = 8) -> void:
	for i in count:
		await process_frame

func descendants(node: Node) -> Array[Node]:
	var result: Array[Node] = []
	for child in node.get_children():
		result.append(child)
		result.append_array(descendants(child))
	return result

func touch(at: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.position = at
	event.pressed = pressed
	root.push_input(event, true)

func drag(at: Vector2, offset: Vector2) -> void:
	touch(at, true)
	await frames(2)
	for step in range(1, 11):
		var event := InputEventScreenDrag.new()
		event.index = 0
		event.position = at + offset * (float(step) / 10.0)
		event.relative = offset / 10.0
		event.velocity = offset * 3.0
		root.push_input(event, true)
		await frames(1)
	touch(at + offset, false)
	await frames(3)

func first_texture(parent: Node) -> TextureRect:
	for node in descendants(parent):
		if node is TextureRect and node.texture != null:
			return node
	return null

func assert_page_fits(label: String) -> void:
	var scroll: ScrollContainer = app.main_body.get_parent()
	var viewport := Rect2(Vector2.ZERO, app.size)
	check(viewport.encloses(app.shell.get_global_rect()), label + " shell stays within logical viewport")
	check(viewport.encloses(scroll.get_global_rect()), label + " scroll viewport stays on screen")
	check(scroll.size.y >= 160, label + " leaves useful page height")
	check(app.main_body.get_combined_minimum_size().x <= scroll.size.x + 2, label + " content fits available width")
	for node in descendants(app.main_body):
		if node is TextureRect and node.texture != null and "/characters/" in node.texture.resource_path:
			check(node.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED or node.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT, label + " character artwork preserves complete aspect ratio")

func test_scroll_over_art() -> void:
	app.navigate("home")
	await frames()
	var scroll: ScrollContainer = app.main_body.get_parent()
	var art := first_texture(app.main_body)
	check(art != null, "Home has actual scene artwork")
	if art == null:
		return
	var visible_art := art.get_global_rect().intersection(scroll.get_global_rect())
	check(visible_art.size.y > 100, "Scene artwork is visible before drag")
	var start := Vector2(visible_art.end.x - 35, visible_art.position.y + minf(visible_art.size.y - 25, 220))
	var before := scroll.scroll_vertical
	await drag(start, Vector2(0, -130))
	check(scroll.scroll_vertical > before + 30, "Synthetic touch drag starting on scene artwork scrolls page")
	check(app.current_screen == "home", "Dragging artwork preserves current screen")

func pointer_click(at: Vector2) -> void:
	# Mouse events represent Godot's Android touch-to-mouse adapter. They are
	# dispatched through Viewport hit testing rather than emitting button signals.
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = at
		event.global_position = at
		event.pressed = pressed
		root.push_input(event, true)
		await frames(2)

func pointer_drag(at: Vector2, offset: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.position = at
	down.global_position = at
	down.pressed = true
	root.push_input(down, true)
	for step in range(1, 6):
		var motion := InputEventMouseMotion.new()
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		motion.position = at + offset * (float(step) / 5.0)
		motion.global_position = motion.position
		motion.relative = offset / 5.0
		root.push_input(motion, true)
		await frames(1)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.position = at + offset
	up.global_position = up.position
	up.pressed = false
	root.push_input(up, true)
	await frames()

func test_card_drag_and_tap() -> void:
	app.navigate("party")
	await frames()
	var scroll: ScrollContainer = app.main_body.get_parent()
	var art := first_texture(app.main_body)
	check(art != null, "Party contains a portrait touch target")
	if art == null:
		return
	scroll.scroll_vertical = maxi(0, int(art.global_position.y - scroll.global_position.y - 20))
	await frames()
	var visible := art.get_global_rect().intersection(scroll.get_global_rect())
	var start := visible.get_center()
	var team_before: Array = app.draft_team.duplicate()
	var before := scroll.scroll_vertical
	await drag(start, Vector2(0, -100))
	check(scroll.scroll_vertical > before + 25, "Touch drag over clickable portrait scrolls party")
	check(app.draft_team == team_before, "Portrait drag does not toggle team membership")
	# Reset scroll and reacquire the target after dragging.
	scroll.scroll_vertical = maxi(0, int(art.global_position.y + scroll.scroll_vertical - scroll.global_position.y - 20))
	await frames()
	visible = art.get_global_rect().intersection(scroll.get_global_rect())
	await pointer_drag(visible.get_center(), Vector2(0, -35))
	check(app.draft_team == team_before, "Pointer drag across portrait does not activate card")
	await pointer_click(visible.get_center())
	check(app.draft_team != team_before, "Portrait pointer tap toggles team membership exactly once")

func test_menu_navigation() -> void:
	app.navigate("home")
	await frames()
	var menu := app.find_child("MenuButton", true, false) as Button
	var back := app.find_child("BackButton", true, false) as Button
	check(menu != null and back != null, "Phone exposes fixed menu and back controls")
	if menu == null or back == null:
		return
	check(menu.size.y >= 48 and back.size.y >= 48, "Phone menu and back provide 48 logical pixel touch targets")
	await pointer_click(menu.get_global_rect().get_center())
	check(app.overlay.get_child_count() > 0, "Pointer tap opens phone navigation")
	var target: Button
	for node in descendants(app.overlay):
		if node is Button and "旅程档案" in node.text:
			target = node
	check(target != null, "Phone navigation exposes last destination")
	if target != null:
		var viewport := Rect2(Vector2.ZERO, app.size)
		var menu_scroll: ScrollContainer
		for node in descendants(app.overlay):
			if node is ScrollContainer:
				menu_scroll = node
		if menu_scroll != null:
			for attempt in 5:
				if menu_scroll.get_global_rect().encloses(target.get_global_rect()):
					break
				var bounds := menu_scroll.get_global_rect()
				await drag(bounds.get_center(), Vector2(0, -minf(110, bounds.size.y * 0.4)))
		check(viewport.encloses(target.get_global_rect()), "Last navigation destination is reachable on screen")
		await pointer_click(target.get_global_rect().get_center())
		check(app.current_screen == "save" and app.overlay.get_child_count() == 0, "Pointer selects destination and closes menu")
	app._clear_overlay()

func test_back_dispatch() -> void:
	app.navigate("home")
	app.navigation_history.clear()
	app.navigate("shop")
	await frames()
	app.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await frames()
	check(app.current_screen == "home", "Android back notification returns secondary page to home")
	app._confirm("Mobile dismissal test", "Dismiss using Android back.", func(): check(false, "Back must not accept confirmation"))
	await frames()
	app.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await frames()
	check(app.overlay.get_child_count() == 0, "Android back notification dismisses confirmation")
	check(app.current_screen == "home", "Modal dismissal preserves underlying screen")
	app.navigate("party")
	await frames()
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	root.push_input(escape, true)
	await frames()
	check(app.current_screen == "home", "Escape uses same page back route")

func test_open_modal_rotation() -> void:
	app.navigate("home")
	app._show_navigation()
	for physical_size in [Vector2i(1080, 2400), Vector2i(2400, 1080), Vector2i(1080, 1920)]:
		root.size = physical_size
		await frames(16)
		check(app.overlay.get_child_count() > 0, "Rotation preserves open navigation modal")
		for node in descendants(app.overlay):
			if node is PanelContainer:
				check(Rect2(Vector2.ZERO, app.size).encloses(node.get_global_rect()), "Open modal fits after rotation " + str(physical_size))
	app.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await frames()
	check(app.overlay.get_child_count() == 0, "Rotated modal remains dismissible")

func test_battle_back_safety() -> void:
	app.navigate("story")
	app._begin_stage("ch1_1")
	await frames()
	check(app.dialogue_key != "", "Stage preparation opens story dialogue")
	app.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await frames()
	check(app.current_screen == "story" and app.dialogue_key == "", "Back cancels prebattle dialogue at stage picker")
	var prepared: Dictionary = app.model.prepare_stage("ch1_1")
	check(prepared.get("success", false), "Mobile fixture prepares real battle")
	if not prepared.get("success", false):
		return
	app._start_battle(prepared.config)
	await frames()
	app.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await frames()
	check(app.current_screen == "battle" and app.overlay.get_child_count() > 0, "Back requests confirmation before abandoning battle")
	app.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await frames()
	check(app.current_screen == "battle" and app.overlay.get_child_count() == 0, "Back dismisses retreat confirmation and preserves battle")

func run() -> void:
	root.size = PHONE_SIZES[0]
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await frames()
	app.set_process(false)
	app.model = load("res://scripts/game_model.gd").new("")
	app.battle = load("res://scripts/battle_model.gd").new(app.model.catalog)
	for physical_size in PHONE_SIZES:
		root.size = physical_size
		await frames(16)
		print("MOBILE VIEWPORT physical=", root.size, " logical=", root.content_scale_size, " app=", app.size)
		check(minf(app.size.x, app.size.y) <= 360.5, "Phone short edge preserves touch density " + str(physical_size))
		check(root.size == physical_size, "Window accepts physical phone resolution " + str(physical_size))
		check(absf(app.size.x / app.size.y - float(physical_size.x) / physical_size.y) < 0.02, "Logical viewport matches phone aspect " + str(physical_size))
		for page in PAGES:
			app.navigate(page)
			await frames()
			assert_page_fits(str(physical_size) + " " + page)
		await test_scroll_over_art()
		await test_card_drag_and_tap()
		await test_menu_navigation()
		await test_back_dispatch()
	await test_open_modal_rotation()
	await test_battle_back_safety()
	app.queue_free()
	await frames()
	print("MOBILE UI: ", checks, " checks; ", failures.size(), " failures. Input source: synthetic Linux Viewport events.")
	quit(0 if failures.is_empty() else 1)
