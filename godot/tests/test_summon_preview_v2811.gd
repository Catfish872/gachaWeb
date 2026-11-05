extends SceneTree
## Native input coverage for the paused preview clock and its close action.
var app
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")
func ck(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("SUMMON PREVIEW: " + message)
func frames(count := 3) -> void:
	for i in count: await process_frame
func click(control: Control, touch := false) -> void:
	ck(is_instance_valid(control), "click target exists")
	if not is_instance_valid(control): return
	var point := control.get_global_rect().get_center()
	for pressed in [true, false]:
		if touch:
			var tap := InputEventScreenTouch.new()
			tap.index = 0
			tap.position = point
			tap.pressed = pressed
			root.push_input(tap)
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.global_position = point
		event.pressed = pressed
		if touch: event.device = InputEvent.DEVICE_ID_EMULATION
		root.push_input(event)
		await frames()
	await frames()
func run() -> void:
	root.size = Vector2i(1170, 540)
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await frames(16)
	app.set_process(false)
	app.model = load("res://scripts/game_model.gd").new("")
	app.model.state.resources.diamonds = 10000
	app.model.random_source = func(): return .9
	app.selected_pool = "limited_kaldi"
	app.navigate("summon")
	await frames(5)
	app._pull(1)
	await frames(5)
	var seq = app.summon_sequence
	var start := Time.get_ticks_msec()
	while seq.stage != "result" and Time.get_ticks_msec() - start < 8000: await process_frame
	ck(seq.stage == "result", "single-pull reveal reaches result")
	var saved := JSON.stringify(app.model.state)
	for touch in [false, true, false]:
		await create_timer(.4).timeout
		await click(seq._details, touch)
		ck(is_instance_valid(seq._preview), "reveal details opens preview")
		var paused_time: float = seq.sequence_time
		var paused_index: int = seq.index
		if touch:
			seq.notification(MainLoop.NOTIFICATION_APPLICATION_PAUSED)
			await create_timer(.1).timeout
			seq.notification(MainLoop.NOTIFICATION_APPLICATION_RESUMED)
			root.size = Vector2i(960, 540)
			await frames(5)
		await create_timer(.45).timeout
		ck(is_equal_approx(seq.sequence_time, paused_time), "preview keeps animation clock paused")
		await click(seq.find_child("SummonPreviewClose", true, false), touch)
		ck(not is_instance_valid(seq._preview), "return closes preview despite paused cooldown")
		ck(seq.stage == "result" and seq.index == paused_index, "return preserves revealed character")
		ck(JSON.stringify(app.model.state) == saved, "preview preserves committed currency and rewards")
		if is_instance_valid(seq._preview): break
	if not is_instance_valid(seq._preview):
		await create_timer(.4).timeout
		await click(seq._next)
		ck(seq.stage == "summary", "next still opens result summary")
		await create_timer(.45).timeout
		await click(seq._cards[0])
		ck(is_instance_valid(seq._preview), "summary card opens preview")
		await click(seq.find_child("SummonPreviewClose", true, false))
		ck(not is_instance_valid(seq._preview) and seq.stage == "summary", "summary preview returns immediately")
		await create_timer(.4).timeout
		await click(seq._accept)
		ck(app.overlay.get_child_count() == 0, "accept exits summon sequence")
		ck(JSON.stringify(app.model.state) == saved, "accept retains same committed draw")
	app.queue_free()
	await frames(4)
	print("SUMMON PREVIEW V2811: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
