extends "res://tests/test_room_return_v250.gd"
func run()->void:
	root.size=Vector2i(1280,720)
	app=load("res://main.tscn").instantiate();root.add_child(app);await frames(12)
	app.extraction_sound=false;app.extraction_reduced_motion=true;app.model.rng.seed=2
	var x=app.model.extraction
	check(x.start_run().success,"native fixture starts actual run")
	for room in x.route_options():
		if room.type=="cache":check(x.enter_room(room.id).success,"native fixture enters actual node");break
	baseline=app.model.state.duplicate(true)
	await reset_room();var box:=box_with();await show_room()
	check(x.choose_container(box.id).success,"native fixture selects exact source")
	View._open_container(app,box.id);await frames(12)
	var saved:Dictionary=app.model.state.duplicate(true)
	await capture("native-before-close")
	print("NATIVE ROOM RETURN READY")
	while x.run().phase!="route":await process_frame
	await frames(12)
	check(app.overlay.get_child_count()==0 and target("ExtractionMap")!=null,"native coordinate X returns to actual map")
	check(x.run().map.currentRoomId==saved.extraction.run.map.currentRoomId and x.run().containers==saved.extraction.run.containers and x.run().bag==saved.extraction.run.bag and x.run().rngState==saved.extraction.run.rngState and app.model.state.resources==saved.resources,"native close preserves node, items, RNG and coins")
	await capture("native-after-close")
	print("NATIVE ROOM RETURN: %d checks, %d failures"%[checks,failures])
	# Keep the verified map visible briefly, then release the fixture cleanly.
	await create_timer(4.0).timeout
	View._stop_search(app,false);app.queue_free();await frames();await create_timer(.2).timeout
	quit(1 if failures else 0)
