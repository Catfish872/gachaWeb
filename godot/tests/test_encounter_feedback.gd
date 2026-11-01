extends SceneTree
var app
var checks:=0
var failures:Array=[]
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func frames(n:int=5)->void:
	for i in n:await process_frame
func run()->void:
	root.size=Vector2i(2340,1080)
	app=load("res://main.tscn").instantiate();root.add_child(app);await frames(10)
	app.set_process(false)
	app.model=load("res://scripts/game_model.gd").new("")
	app.battle=load("res://scripts/battle_model.gd").new(app.model.catalog)
	app.model.state.ownedCharacters.tide=app.model.default_character()
	app.model.set_team(["ember","zeph","tide"])
	check(app.model.extraction.buy_supply("armor_5").get("success",false),"purchase real shield equipment")
	check(app.model.extraction.set_utility_slot("armor",app.model.extraction.state().stash.back().uid).get("success",false),"equip shield outside run")
	var found:=false
	app.model.rng.seed=77201
	app.model.extraction.start_run(0)
	var map:Dictionary=app.model.extraction.map_state()
	var route:Array=[]
	for room in map.rooms:
		if room.type in ["battle","elite"]:
			route=load("res://tools/extraction_navigation.gd").path(map,map.currentRoomId,room.id,false);break
	for id in route:
		app.model.extraction.enter_room(id)
		if app.model.extraction.run().phase=="battle":found=true;break
	check(found,"real generated adjacent battle")
	if found:
		app.battle_speed=4.0;app.battle_auto=true
		app._begin_extraction_battle();await frames()
		check(app.current_screen=="battle","actual extraction battle starts")
		for unit in app.battle.state.allies:
			var bar=app.main_body.find_child("BattleShield_"+str(unit.uid),true,false)
			check(bar!=null,"existing shield mechanic has visible bar for "+str(unit.id))
			if bar!=null:
				check(bar.value==unit.shield,"shield bar equals actual unified shield value")
				check(bar.get_global_rect().end.y<=app.size.y,"shield row fits landscape")
		app._show_unit_details(app.battle.state.allies[0]);await frames()
		var shown_atk=app.overlay.find_child("BattleDetail_atk",true,false)
		var shown_def=app.overlay.find_child("BattleDetail_def",true,false)
		check(shown_atk!=null and shown_atk.text==str(app.battle.state.allies[0].stats.atk),"unit detail displays real attack instead of missing flattened field")
		check(shown_def!=null and shown_def.text==str(app.battle.state.allies[0].stats.def),"unit detail displays real defense")
		app._clear_overlay()
		check(is_equal_approx(app.battle_clock,-0.4),"entry is readable before first accelerated action")
		var steps:int=app.battle.state.get("steps",0)
		app._process(0.35)
		check(app.battle.state.get("steps",0)==steps,"intro does not advance auto action")
		app.set_meta("application_paused",true)
		var held:float=app.battle_clock
		app._process(10.0)
		check(app.battle.state.get("steps",0)==steps and app.battle_clock==held,"background freezes combat clock")
		app.set_meta("application_paused",false)
		app._process(0.3)
		check(app.battle.state.get("steps",0)>steps,"normal 4x cadence resumes after intro")
		var guard:=0
		while app.battle.state.phase not in ["victory","defeat"] and guard<3000:
			app.battle.auto_step();guard+=1
		check(guard<3000,"real battle terminates")
		app._finish_battle()
		await create_timer(0.65).timeout;await frames()
		var button=app.overlay.find_child("ExtractionBattleContinue",true,false)
		check(button!=null,"battle result has stable continue action")
		if button!=null:
			check(button.icon!=null,"continue action has semantic icon")
			check(button.get_global_rect().end.y<=app.size.y,"continue action fits phone height")
			button.pressed.emit();await frames()
			check(app.current_screen=="extraction","continue returns to exploration")
	app.queue_free();await process_frame;await create_timer(0.3).timeout
	print("ENCOUNTER FEEDBACK: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
