extends SceneTree
## Real frame-clock and native input regression; GL runs also save temporal frames.
var app
var checks := 0
var failures := 0
var evidence: Array = []
var frame_hashes: Array = []
var random_values: Array = []
const OUT := "res://validation/summon-v25"

func _initialize() -> void: call_deferred("run")
func ck(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("SUMMON SEQUENCE: " + message)
func frames(count := 2) -> void:
	for i in count: await process_frame
func find(needle: String): return app.find_child(needle, true, false)
func mouse(point: Vector2, pressed: bool, emulated := false) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = point
	event.global_position = point
	event.pressed = pressed
	if emulated: event.device = InputEvent.DEVICE_ID_EMULATION
	root.push_input(event)
	await frames()
func click(control: Control) -> void:
	ck(is_instance_valid(control), "native click target exists")
	if not is_instance_valid(control): return
	var point := control.get_global_rect().get_center()
	await mouse(point, true)
	await mouse(point, false)
	await frames()
func wait_stage(wanted: String, limit := 8.0) -> void:
	var begin := Time.get_ticks_msec()
	while is_instance_valid(app.summon_sequence) and app.summon_sequence.stage != wanted and Time.get_ticks_msec()-begin < limit*1000:
		await process_frame
	ck(is_instance_valid(app.summon_sequence) and app.summon_sequence.stage == wanted, "reached " + wanted)
func wait_clock(seconds: float) -> void:
	var seq = app.summon_sequence
	var target: float = seq.sequence_time + seconds
	var begin := Time.get_ticks_msec()
	while is_instance_valid(seq) and seq.sequence_time < target and Time.get_ticks_msec()-begin < seconds*2000+3000: await process_frame
	ck(is_instance_valid(seq) and seq.sequence_time >= target, "visible clock advances %.2fs" % seconds)
func capture(label: String) -> void:
	if not is_instance_valid(app.summon_sequence):
		ck(false,"capture requires a live sequence: "+label)
		return
	var state: Dictionary = app.summon_sequence.debug_state()
	state.label = label
	state.window = [root.size.x, root.size.y]
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var path := OUT.path_join(label+".png")
		ck(image.save_png(path) == OK, "saved temporal frame " + label)
		state.image_hash = hash(image.get_data())
		frame_hashes.append(state.image_hash)
	evidence.append(state)
func fresh(roll: float = .9, gentle := false) -> void:
	app._clear_overlay()
	app.model.random_source = Callable()
	app.model = load("res://scripts/game_model.gd").new("")
	app.model.state.resources.diamonds = 10000
	app.model.random_source = func(): return roll
	app.selected_pool = "limited_kaldi"
	app.extraction_reduced_motion = gentle
	app.navigate("summon")
	await frames(4)
func assert_committed(before: Dictionary, count: int) -> void:
	ck(app.model.state.resources.diamonds == int(before.resources.diamonds)-160*count, "exact currency charge")
	ck(app.model.state.stats.totalPulls == int(before.stats.totalPulls)+count, "exact pull count")
	for result in app.summon_results:
		ck(app.model.state.ownedCharacters.has(result.charId), "committed ownership " + str(result.charId))
		if not result.isNew: ck(int(result.shards)>0, "duplicate has committed shards")

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.size = Vector2i(1170,540)
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await frames(16)
	app.set_process(false)
	for entry in [[3,.9,false],[4,.1,false],[5,0.0,false],[5,0.0,true]]:
		await fresh(float(entry[1]),bool(entry[2]))
		var before: Dictionary = app.model.state.duplicate(true)
		var music = app.music_audio
		await click(find("SummonPull_1"))
		ck(app.music_audio==music, "ritual preserves background music player/context")
		assert_committed(before,1)
		var seq = app.summon_sequence
		ck(seq.rarity()==int(entry[0]), "deterministic rarity " + str(entry[0]))
		ck(seq.stage in ["preparing","opening"], "cold first display starts at opening")
		await wait_stage("opening")
		ck(seq._ready_frames==2, "two visible preparation frames")
		ck(seq._audio_history.is_empty(), "opening never plays a rarity reveal sound")
		var label := "r%d_%s" % [int(entry[0]),"gentle" if entry[2] else "full"]
		await wait_clock(.13)
		await capture(label+"_opening")
		await click(find("SummonSkip"))
		ck(seq.stage=="opening", "initiating/early skip retains readable opening")
		await wait_stage("unseal")
		await wait_clock(.33)
		await capture(label+"_midflip")
		if int(entry[0])==5:
			await wait_stage("legendary")
			await wait_clock(.4)
			await capture(label+"_legendary")
		await wait_stage("portrait")
		await wait_clock(.3)
		await capture(label+"_portrait")
		await wait_stage("result")
		ck(seq._audio_history.size()==1 and seq._audio_history[0].stage==("legendary" if int(entry[0])==5 else "portrait"), "one rarity cue at actual reveal/climax")
		ck(seq.stage_history[1].time >= .85, "opening lasts at least 0.85 visible seconds")
		ck(seq.sequence_time >= (4.1 if int(entry[0])==5 else 3.3), "full ritual time remains visible")
		assert_committed(before,1)
		await click(find("SummonNext"))
		ck(seq.stage=="summary", "explicit next opens final result")
		await wait_clock(.6)
		await capture(label+"_summary")
		await click(find("SummonAccept"))
		ck(app.overlay.get_child_count()==0, "accept cleans sequence")
	# A full mixed ten-pull continues automatically, then stagger reveals all ten.
	await fresh()
	random_values = [.0,.0,.0, .1,.0,.0, .9,.0, .9,.0, .9,.0, .9,.0, .9,.0, .9,.0, .9,.0, .9,.0]
	app.model.random_source = func(): return random_values.pop_front() if not random_values.is_empty() else .9
	var before: Dictionary = app.model.state.duplicate(true)
	await click(find("SummonPull_10"))
	assert_committed(before,10)
	var seq = app.summon_sequence
	ck(app.summon_results.map(func(r): return r.rarity).has(3) and app.summon_results.map(func(r): return r.rarity).has(4) and app.summon_results.map(func(r): return r.rarity).has(5), "ten-pull fixture includes all rarities")
	await wait_stage("result")
	await wait_clock(2.4)
	ck(seq.index==1 and seq.stage=="seal", "continuous ten-pull advances after readable portrait")
	await capture("ten_continuous_second")
	var stable: String = JSON.stringify(app.model.state)
	var epoch: int = seq.stage_epoch
	var clock: float = seq.sequence_time
	app.notification(MainLoop.NOTIFICATION_APPLICATION_PAUSED)
	seq.notification(MainLoop.NOTIFICATION_APPLICATION_PAUSED)
	await create_timer(.25).timeout
	ck(is_equal_approx(seq.sequence_time,clock), "background preserves presentation clock")
	ck(not is_instance_valid(seq._voice) or not seq._voice.playing, "background stops transient reveal voice")
	app.notification(MainLoop.NOTIFICATION_APPLICATION_RESUMED)
	seq.notification(MainLoop.NOTIFICATION_APPLICATION_RESUMED)
	await frames(2)
	ck(seq.sequence_time-clock < .11 and seq.stage_epoch==epoch, "resume never catches up unseen stages")
	root.size = Vector2i(960,540)
	await frames(10)
	ck(app.summon_sequence==seq and JSON.stringify(app.model.state)==stable, "resize preserves sequence and all committed state")
	await wait_stage("result")
	await wait_clock(.1)
	await click(find("SummonSkip"))
	ck(seq.stage=="summary", "skip targets real committed summary")
	ck(seq._audio_history[-1].stage=="summary" and seq._audio_history[-1].rarity==5 and seq.find_children("SummonRevealVoice","AudioStreamPlayer",false,false).size()==1, "skip plays one highest-rarity cue on one voice")
	await wait_clock(.19)
	ck(seq._cards[0].modulate.a>seq._cards[9].modulate.a, "summary cards enter with visible stagger")
	await capture("ten_summary_stagger")
	await wait_clock(1.0)
	ck(seq.debug_state().visible_cards==10, "all ten cards finish entering")
	await capture("ten_summary_complete")
	for card in seq._cards:
		ck(Rect2(Vector2.ZERO,app.size).encloses(card.get_global_rect()), "result card fully on screen")
	var old_skip := Vector2(app.size.x-140,46)
	for i in 4:
		await mouse(old_skip,true)
		await mouse(old_skip,false)
	ck(JSON.stringify(app.model.state)==stable and seq.stage=="summary", "rapid old skip taps never reroll or accept")
	await click(seq._cards[0])
	ck(is_instance_valid(find("SummonPreviewClose")), "summary card opens inspectable traveller")
	await click(find("SummonPreviewClose"))
	ck(seq.stage=="summary" and seq._cards.size()==10, "preview returns to same summary")
	await wait_clock(.4)
	await click(find("SummonAccept"))
	assert_committed(before,10)
	# A press armed in one epoch cannot release into the next stage.
	await fresh()
	await click(find("SummonPull_1"))
	await wait_stage("opening")
	await wait_clock(.7)
	var skip_point: Vector2 = find("SummonSkip").get_global_rect().get_center()
	await mouse(skip_point,true)
	await wait_stage("constellation")
	await mouse(skip_point,false)
	ck(app.summon_sequence.stage=="constellation", "late release from old epoch ignored")
	# Touch and synthetic mouse are the same explicit input gesture.
	var touch := InputEventScreenTouch.new()
	touch.index=0;touch.position=skip_point;touch.pressed=true;root.push_input(touch)
	await mouse(skip_point,true,true)
	touch=InputEventScreenTouch.new();touch.index=0;touch.position=skip_point;touch.pressed=false;root.push_input(touch)
	await mouse(skip_point,false,true)
	await frames(4)
	ck(app.summon_sequence.stage=="summary", "touch plus emulated mouse skips once")
	ck(app.model.state.stats.totalPulls==1, "touch emulation preserves one draw")
	# Leaving and Android Back dispose the clock, ownership remains in the save.
	stable = JSON.stringify(app.model.state)
	app.navigate("home")
	await create_timer(.8).timeout
	ck(app.overlay.get_child_count()==0 and JSON.stringify(app.model.state)==stable, "leaving produces no late cards or state changes")
	await fresh()
	await click(find("SummonPull_1"))
	stable = JSON.stringify(app.model.state)
	app.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await create_timer(.2).timeout
	ck(app.overlay.get_child_count()==0 and JSON.stringify(app.model.state)==stable, "Android Back preserves committed reward")
	# Slot change removes stale presentation; reload proves the old committed save.
	await fresh()
	await click(find("SummonPull_1"))
	var old_state: Dictionary = app.model.state.duplicate(true)
	ck(app.model.load_slot(2).success, "switch save slot")
	await frames(4)
	ck(app.overlay.get_child_count()==0, "slot change cancels old sequence")
	ck(app.model.load_slot(1).success and app.model.state.resources==old_state.resources and app.model.state.ownedCharacters==old_state.ownedCharacters and app.model.state.pityCounters==old_state.pityCounters, "committed currency ownership and pity reload exactly")
	# Persistence failure rolls back the complete draw before visual creation.
	await fresh()
	app.model.save_blocked = true
	stable = JSON.stringify(app.model.state)
	app._pull(10)
	await frames(4)
	ck(JSON.stringify(app.model.state)==stable and app.overlay.get_child_count()==0, "failed save rolls back resources ownership pity and presentation")
	app.model.save_blocked = false
	app.model.state.resources.diamonds = 0
	stable = JSON.stringify(app.model.state)
	app._pull(1)
	ck(JSON.stringify(app.model.state)==stable and app.overlay.get_child_count()==0, "unaffordable draw leaves state and presentation untouched")
	# Full default ten-card playback reaches its final grid without another press.
	root.size=Vector2i(740,540)
	await fresh()
	# Compact hub scroll position is separate from this overlay's layout contract.
	app._pull(10)
	await frames(4)
	seq=app.summon_sequence
	await wait_stage("result")
	await capture("small_landscape_portrait")
	await wait_stage("summary",48.0)
	ck(seq.stage_history.filter(func(entry):return entry.stage=="result").size()==10, "default continuous playback reads every one of ten committed cards")
	await wait_clock(1.2)
	await capture("small_landscape_ten_summary")
	for card in seq._cards:
		ck(Rect2(Vector2.ZERO,app.size).encloses(card.get_global_rect()), "small landscape result fits")
	ck(seq._audio_history.filter(func(entry):return entry.stage=="portrait" or entry.stage=="legendary").size()==10, "each actually revealed traveller receives one cue")
	await click(find("SummonAccept"))
	# Destroy during a cold preparation callback and reuse the scene normally.
	await fresh()
	app._pull(1)
	app.queue_free()
	await frames(5)
	app=load("res://main.tscn").instantiate();root.add_child(app)
	await frames(12)
	ck(app.overlay.get_child_count()==0, "new scene has no stale sequence callbacks")
	app.queue_free()
	await frames(4)
	await create_timer(.3).timeout
	if not frame_hashes.is_empty():
		var unique := {}
		for value in frame_hashes: unique[value]=true
		ck(unique.size()==frame_hashes.size(), "all captured temporal frames are distinct")
	var output := FileAccess.open(OUT.path_join("temporal-%s.json" % ("headless" if DisplayServer.get_name()=="headless" else "gl")), FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks":checks,"failures":failures,"renderer":DisplayServer.get_name(),"frames":evidence},"\t"))
	print("SUMMON SEQUENCE V25: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
