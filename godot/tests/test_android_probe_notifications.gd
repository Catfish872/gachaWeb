extends SceneTree

var checks := 0
var failures := 0
func _initialize() -> void:call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks += 1
	if not ok:failures += 1;push_error("PROBE NOTIFICATIONS: " + label)
func frames() -> void:
	for i in 8:await process_frame
func run() -> void:
	root.size = Vector2i(1280,720)
	for use_probe in [false,true]:
		var app = load("res://main.tscn").instantiate()
		if use_probe:app.set_script(load("res://tools/android/runtime_probe.gd"))
		root.add_child(app);await frames();app.set_process(false)
		app._show_navigation()
		check(app.overlay.find_child("MenuNav_story",true,false) != null,"actual menu ready")
		# Use Object's real notification dispatch: it visits every script layer.
		app.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
		check(app.overlay.get_child_count() == 0,"one native notification dismisses exactly one menu; probe="+str(use_probe))
		app.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
		check(app.overlay.get_child_count() > 0,"a second distinct notification immediately opens exit confirmation")
		app.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
		check(app.overlay.get_child_count() == 0,"a third distinct notification immediately dismisses confirmation")
		app._play_dialogue("ch1_1_pre",Callable())
		check(app.dialogue_key == "ch1_1_pre","real story dialogue is open")
		app.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
		check(app.dialogue_key.is_empty() and app.overlay.get_child_count() == 0,"one notification closes dialogue without opening exit confirmation")
		app.model.rng.seed = 2
		check(app.model.extraction.start_run(0).get("success",false),"real expedition starts")
		for room in app.model.extraction.route_options():
			if room.type == "cache":app.model.extraction.enter_room(room.id);break
		app.navigate("extraction")
		await frames()
		var box:Dictionary = app.model.extraction.containers()[0]
		load("res://scripts/ui/extraction_view.gd")._open_container(app,box.id)
		await frames()
		var grid = app.overlay.find_child("ExtractionContainer_"+str(box.id),true,false)
		check(app.extraction_searching and grid != null and not grid.scan_uid.is_empty(),"real automatic search is scanning")
		var scanned:String = grid.scan_uid
		var progress:float = grid.scan_progress
		var sequence:int = app._probe_sequence if use_probe else 0
		app.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
		check(app.get_meta("application_paused",false),"base pause processing precedes observer")
		if use_probe:check(app._probe_sequence == sequence+1,"pause emits exactly one observation")
		await create_timer(.2).timeout
		check(grid.scan_uid == scanned and is_equal_approx(grid.scan_progress,progress),"actual Object pause freezes the same scanning item")
		app.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
		check(not app.get_meta("application_paused",true),"base resume processing precedes observer")
		if use_probe:check(app._probe_sequence == sequence+2,"resume emits exactly one observation")
		await create_timer(.1).timeout
		check(grid.scan_uid != scanned or grid.scan_progress > progress,"search advances after actual Object resume")
		app.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
		check(app.overlay.get_child_count() == 0 and not app.extraction_searching,"one real Back closes and cancels search")
		app.queue_free();await frames();await create_timer(.3).timeout
	print("PROBE NOTIFICATIONS: %d checks; %d failures" % [checks,failures])
	quit(1 if failures else 0)
