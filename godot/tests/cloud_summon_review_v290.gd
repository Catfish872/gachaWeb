extends Node
var app
var viewport: SubViewport
var checks := 0
var failures: Array = []
var began: String
var start_ms: int
var trace: Array=[]
const OUT="/workspace/scratch/8f1fc457a062/cloud-ui-review/summon-full-review"
func frames(n: int=4) -> void:
	for i in n:await get_tree().process_frame
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures.append(label)
	print("PASS " if ok else "FAIL ",label)
func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png(OUT+"/"+label+".png")
func click(control: Control,touch: bool=false) -> void:
	check(is_instance_valid(control),"input target exists")
	if not is_instance_valid(control):return
	var pos=control.get_global_rect().get_center()
	for pressed in [true,false]:
		if touch:
			var tap=InputEventScreenTouch.new();tap.index=0;tap.position=pos;tap.pressed=pressed;viewport.push_input(tap)
		var event=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.position=pos;event.global_position=pos;event.pressed=pressed
		if touch:event.device=InputEvent.DEVICE_ID_EMULATION
		viewport.push_input(event);await frames(2)
	await frames(3)
func settle(sequence, seconds: float=.55) -> void:
	var goal: float=sequence.sequence_time+seconds
	for tick in range(360):
		if sequence.sequence_time>=goal:break
		await get_tree().process_frame
func _ready() -> void:
	if not "--test-session" in OS.get_cmdline_user_args():push_error("Requires isolated test session");get_tree().quit(2);return
	began=Time.get_datetime_string_from_system(true);start_ms=Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute(OUT)
	viewport=SubViewport.new();viewport.size=Vector2i(960,540);viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(viewport)
	var display=TextureRect.new();display.texture=viewport.get_texture();display.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;display.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(display)
	app=load("res://main.tscn").instantiate();viewport.add_child(app);await frames(8);app.set_process(false);app.music_enabled=false;app.sound_enabled=false
	check(app.model.save_dir.is_empty(),"isolated model")
	if "--quick-next" in OS.get_cmdline_user_args():await next_review();return
	for gentle in [false,true]:
		app.model=load("res://scripts/game_model.gd").new("");app.model.state.resources.diamonds=4800;app.model.random_source=func():return 0.0
		app.extraction_reduced_motion=gentle;app.selected_pool="limited_raisa";app.navigate("summon");await frames(5)
		app._pull(10);await frames(2)
		var sequence=app.summon_sequence
		check(sequence.results.size()==10,"committed ten results "+str(gentle))
		check(app.model.state.resources.diamonds==3200,"initial ten charged once "+str(gentle))
		var committed=JSON.stringify(app.model.state)
		var last_stage="";var captured: Dictionary={};var wait_start=Time.get_ticks_msec()
		while sequence.stage!="summary" and Time.get_ticks_msec()-wait_start<150000:
			var key=str(sequence.index)+"-"+sequence.stage
			if key!=last_stage:
				trace.append({"mode":gentle,"stage":sequence.stage,"index":sequence.index,"elapsed_ms":Time.get_ticks_msec()-start_ms});last_stage=key
			if sequence.index==0 and sequence.stage!="preparing" and sequence.stage_time>.2 and not captured.has(sequence.stage):
				captured[sequence.stage]=true;await capture(str(gentle)+"-opening-"+sequence.stage)
			await get_tree().process_frame
		check(sequence.stage=="summary" and sequence.index==9,"complete ten auto reveal "+str(gentle))
		for required in ["opening","constellation","seal","unseal","legendary","portrait","result"]:check(captured.has(required),"rendered full stage "+required+str(gentle))
		await settle(sequence,1.3)
		check(sequence.debug_state().visible_cards==10,"ten summary cards visible "+str(gentle))
		check(JSON.stringify(app.model.state)==committed,"animation preserves committed rewards "+str(gentle))
		await capture(str(gentle)+"-ten-summary")
		await click(sequence._cards[0],gentle)
		check(is_instance_valid(sequence._preview),"summary preview opens "+str(gentle))
		if is_instance_valid(sequence._preview):
			var paused: float=sequence.sequence_time;await get_tree().create_timer(.7).timeout
			check(is_equal_approx(paused,sequence.sequence_time),"preview pauses sequence "+str(gentle));await capture(str(gentle)+"-summary-preview")
			await click(sequence.find_child("SummonPreviewClose",true,false),gentle)
			check(not is_instance_valid(sequence._preview) and sequence.stage=="summary","preview returns to ten summary "+str(gentle))
		await settle(sequence)
		await click(sequence._again,gentle);await frames(4);sequence=app.summon_sequence
		check(sequence.results.size()==10 and app.model.state.resources.diamonds==1600,"repeat ten charged once "+str(gentle))
		await settle(sequence,.7);await click(sequence._skip,gentle);await settle(sequence,1.3)
		check(sequence.stage=="summary" and sequence.debug_state().visible_cards==10,"skip reaches complete summary "+str(gentle))
		await click(sequence._again,gentle);await frames(4);sequence=app.summon_sequence
		check(app.model.state.resources.diamonds==0,"second repeat spends final balance "+str(gentle))
		await settle(sequence,.7);await click(sequence._skip,gentle);await settle(sequence,1.3)
		check(sequence._again.disabled,"insufficient balance disables repeat "+str(gentle));await capture(str(gentle)+"-insufficient-summary")
		await click(sequence._again,gentle);check(app.model.state.resources.diamonds==0,"disabled repeat leaves balance unchanged "+str(gentle))
		await click(sequence._accept,gentle);await frames(4)
		check(app.overlay.get_child_count()==0 and app.current_screen=="summon","accept returns to banner "+str(gentle));await capture(str(gentle)+"-returned-banner")
	var report={"started_utc":began,"finished_utc":Time.get_datetime_string_from_system(true),"elapsed_seconds":float(Time.get_ticks_msec()-start_ms)/1000.0,"checks":checks,"failures":failures,"trace":trace}
	FileAccess.open(OUT+"/results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	app.queue_free();await frames(8);await get_tree().create_timer(.5).timeout
	print("SUMMON FULL REVIEW ",checks," checks ",failures);get_tree().quit(0 if failures.is_empty() else 1)

func next_review() -> void:
	for gentle in [false,true]:
		app.model=load("res://scripts/game_model.gd").new("");app.model.state.resources.diamonds=3200;app.model.random_source=func():return 0.0
		app.extraction_reduced_motion=gentle;app.selected_pool="limited_raisa";app.navigate("summon");await frames(5);await click(app.find_child("SummonPull_10",true,false),gentle);await frames(3)
		var sequence=app.summon_sequence
		var wait_start=Time.get_ticks_msec()
		while sequence.stage!="result" and Time.get_ticks_msec()-wait_start<30000:await get_tree().process_frame
		check(sequence.stage=="result" and sequence.index==0,"complete opening reaches first result "+str(gentle))
		var committed=JSON.stringify(app.model.state)
		await click(sequence._details,gentle)
		check(is_instance_valid(sequence._preview),"individual reveal opens preview "+str(gentle))
		if is_instance_valid(sequence._preview):
			await get_tree().create_timer(.5).timeout;await click(sequence.find_child("SummonPreviewClose",true,false),gentle)
			check(not is_instance_valid(sequence._preview) and sequence.index==0,"individual preview returns same card "+str(gentle))
		await settle(sequence,.4);await click(sequence._next,gentle)
		check(sequence.index==1 and sequence.stage!="summary","next advances one card "+str(gentle))
		check(JSON.stringify(app.model.state)==committed,"next preserves committed wallet "+str(gentle));await capture(str(gentle)+"-manual-next")
		await settle(sequence,.7);await click(sequence._skip,gentle);await settle(sequence,1.3)
		check(sequence.stage=="summary" and sequence.debug_state().visible_cards==10,"next then skip retains all results "+str(gentle))
		await click(sequence._accept,gentle);await frames(4)
	var report={"started_utc":began,"finished_utc":Time.get_datetime_string_from_system(true),"elapsed_seconds":float(Time.get_ticks_msec()-start_ms)/1000.0,"checks":checks,"failures":failures}
	FileAccess.open(OUT+"/next-results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	app.queue_free();await frames(8);await get_tree().create_timer(.5).timeout
	print("SUMMON NEXT REVIEW ",checks," checks ",failures);get_tree().quit(0 if failures.is_empty() else 1)
