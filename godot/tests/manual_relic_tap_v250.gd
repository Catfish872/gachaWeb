extends SceneTree
var app
var original:Dictionary={}
var opened:=false
var busy:=false
func _initialize()->void:call_deferred("run")
func frames(n:int)->void:
	for i in n:await process_frame
func run()->void:
	root.size=Vector2i(1170,540)
	root.title="Relic native tap verification"
	app=load("res://main.tscn").instantiate();root.add_child(app);await frames(15)
	app.set_process(false);app.model=load("res://scripts/game_model.gd").new("");app.model.rng.seed=250778;app.selected_character="ember"
	for i in range(15):app.model.add_relic(app.model.generate_relic(3+i%3,str(app.model.catalog.RelicSlots[i%5].id),str(app.model.catalog.RelicSets.keys()[i%6])))
	original=app.model.state.duplicate(true);app.navigate("relics")
	var timer:=Timer.new();timer.wait_time=.5;root.add_child(timer);timer.timeout.connect(observe);timer.start()
	print("NATIVE RELIC TAP READY: click 自动搭配, then 取消")
func observe()->void:
	if busy:return
	var showing:bool=app.overlay.find_child("RelicLoadoutContent",true,false)!=null
	if showing and not opened:
		busy=true;opened=true
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://validation/relic-ui-v250/native-preview.png")
		print("NATIVE PREVIEW OPENED");busy=false
	elif opened and not showing:
		busy=true
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://validation/relic-ui-v250/native-cancelled.png")
		var unchanged:bool=app.model.state==original
		print("NATIVE CANCEL PRESERVES FULL STATE: ",unchanged)
		app.queue_free();await frames(8);await create_timer(.35).timeout
		quit(0 if unchanged else 1)
