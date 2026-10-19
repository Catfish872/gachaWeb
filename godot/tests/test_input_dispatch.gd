extends SceneTree

var app
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("INPUT DISPATCH: " + description)

func frames() -> void:
	for i in 8:
		await process_frame

func pointer(at: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = at
	event.global_position = at
	event.pressed = pressed
	root.push_input(event, true)

func run() -> void:
	root.size = Vector2i(1080, 1920)
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await frames()
	app.set_process(false)
	app._show_navigation()
	await frames()
	var menu_item: Button = app.overlay.find_child("MenuNav_story", true, false)
	check(menu_item != null, "Actual menu item exists")
	var at := menu_item.get_global_rect().get_center()
	pointer(at, true)
	pointer(at, false)
	check(app.current_screen == "home", "Navigation waits until input propagation completes")
	check(menu_item.is_inside_tree(), "Input target remains in tree throughout release dispatch")
	check(menu_item.get_meta("ui_action_pending", false), "Native-dispatch action is queued")
	await frames()
	check(app.current_screen == "story", "Deferred navigation executes")
	check(app.overlay.get_child_count() == 0, "Navigation closes modal after dispatch")

	var state := {"calls": 0}
	var target: Button = app._button(app.main_body, "Dispatch probe", func(): state.calls += 1)
	pointer(Vector2.ZERO, true)
	target.pressed.emit()
	target.pressed.emit()
	check(state.calls == 0, "Actions defer while input is active")
	await frames()
	check(state.calls == 1, "Duplicate pending releases execute once")
	target.pressed.emit()
	check(state.calls == 2, "Programmatic calls outside input retain synchronous behavior")

	pointer(Vector2.ZERO, false)
	target.pressed.emit()
	app.main_body.remove_child(target)
	target.queue_free()
	await frames()
	check(state.calls == 2, "Obsolete queued controls cannot execute their action")
	print("INPUT DISPATCH: %d checks; %d failures" % [checks, failures])
	quit(1 if failures else 0)
