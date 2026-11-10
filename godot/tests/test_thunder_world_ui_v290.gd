extends "res://tests/test_lantern_journey_ui_v270.gd"
const OUT290 := "res://validation/v290-thunder/"
const Audio = preload("res://scripts/thunder_audio.gd")
func capture(label: String) -> void:
	if DisplayServer.get_name()=="headless":return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT290+label+".png")
func expedition(label: String) -> void:
	fresh();var ex=app.model.extraction;ck(ex.start_run().success,"new expedition starts")
	ex.run().environmentOrder=["thunder_city","ruins","forest"];ex.run().act=1;ex._generate_map();ex._routes()
	app.navigate("extraction");await frames(6)
	ck(ex.map_state().districts.size()==3,"thunder map has three districts")
	await capture(label+"-thunder-map")
	for depth in range(3):
		var room: Dictionary=ex.run().map.rooms[depth*6+1]
		ex.run().room=room.duplicate(true);ex.run().room.type="cache";ex.run().room.guardPending=false
		ex.run().map.currentRoomId=room.id;ex.run().phase="room";ex.run().activeEncounter={};ex.run().roomActions=[];ex.run().pendingChoices=[];ex.run().containers=[]
		for kind in ex.data.environmentThemes.thunder_city.containers.slice(depth*2,depth*2+2):
			var definition: Dictionary=ex.data.environmentContainers[kind];ex._container(definition.name,0,0)
			var box: Dictionary=ex.run().containers.back();box.kind=kind;box.sprite=definition.sprite;box.sceneX=.3+.4*(ex.run().containers.size()-1);box.sceneY=.65
		ex.run().bag=[];var count:=0
		for id in ex.data.items:
			var definition: Dictionary=ex.data.items[id]
			if definition.get("environmentTheme","")!="thunder_city" or definition.get("kind","")!="loot" or int(definition.rarity) not in [depth*2,depth*2+1]:continue
			var item: Dictionary=ex._make_item(id);item.revealed=true
			if ex._place(ex.run().bag,item,ex.dimensions("bag")):count+=1
		ck(count>=4,"theme items use actual bag renderer")
		app._render_screen();await frames(6)
		ck(app._music_track_for_context()==["thunder_city_gate","thunder_city_street","thunder_city_core"][depth],"actual area music binding")
		await capture(label+"-thunder-room-"+str(depth))
	var boss_room: Dictionary=ex.run().map.rooms.back();ex.run().room=boss_room.duplicate(true);ex.run().map.currentRoomId=boss_room.id
	ex._generate_encounter("boss");var config: Dictionary=ex.prepare_battle().config
	app._start_battle(config);app.battle_auto=false;await frames(6)
	ck(app.battle.state.enemies.size()==3,"three independently selectable boss targets")
	ck(config.background.ends_with("rift_core.png") and app._music_track_for_context()=="thunder_boss","actual boss scene and music")
	for unit in app.battle.state.enemies:
		ck(app.unit_cards.has(unit.uid),"selectable target card "+str(unit.id))
		fits(app.unit_cards[unit.uid],"thunder boss target card")
	fits(app.find_child("BattleActions",true,false),"boss action controls")
	await capture(label+"-thunder-boss")
func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT290)
	app=load("res://main.tscn").instantiate();root.add_child(app);await frames(8);app.set_process(false)
	for resolution in [Vector2i(960,540),Vector2i(2048,945)]:
		root.size=resolution;await frames(6);await expedition(str(resolution.x))
	app.queue_free();await frames(3)
	# Let the audio mixer release stopped playback resources before quitting.
	await create_timer(0.3).timeout
	print("THUNDER WORLD UI V290: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
