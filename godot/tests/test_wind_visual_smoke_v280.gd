extends "res://tests/test_lantern_journey_ui_v270.gd"
func capture(label:String)->void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://validation/v280-focused/"+label+".png")
func run()->void:
	app=load("res://main.tscn").instantiate();root.add_child(app);await frames(12);app.set_process(false)
	root.size=Vector2i(2048,945);await frames(8);fresh()
	var ex=app.model.extraction;ck(ex.start_run().success,"world run starts");ex.run().environmentOrder=["windpass","ruins","forest"];ex.run().act=1;ex._generate_map();ex._routes();app.navigate("extraction");await frames(12)
	ck(ex.map_state().districts.size()==3,"windpass three districts bound");await capture("windpass-map-2048")
	root.size=Vector2i(960,540);await frames(8);fresh()
	for stage in app.model.stage_list():
		if stage.id!="ch4_12":app.model.state.stageProgress[stage.id]={"cleared":true}
	var prepared:Dictionary=app.model.prepare_stage("ch4_12");ck(prepared.success,"new final chapter prepares")
	if prepared.get("success",false):
		app._start_battle(prepared.config);await frames(12)
		ck(app.battle.state.enemies.size()==3 and app.battle.state.enemies[0].id=="boss_highland_roc","actual roc and windfields shown")
		await capture("windpass-boss-960")
	app.queue_free();await frames();print("WIND VISUAL SMOKE: %d checks, %d failures"%[checks,failures]);quit(0 if failures==0 else 1)
