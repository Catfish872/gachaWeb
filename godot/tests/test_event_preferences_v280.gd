extends "res://tests/test_lantern_journey_ui_v270.gd"
const EventChoice = preload("res://scripts/ui/event_choice.gd")
const View = preload("res://scripts/ui/extraction_view.gd")
const OUT280 = "res://validation/v280-event-preferences/"
func fixture():
	var game = Game.new("")
	game.rng.seed=278
	game.extraction.start_run()
	var ex=game.extraction
	ex.run().phase="room";ex.run().activeEncounter={};ex.run().pendingChoices=[];ex.run().containers=[]
	for unit in ex.run().party:unit.currentHp=100;unit.maxHp=1000;unit.energy=0
	ex.run().room.type="rest";ex.run().room.name="留灯休憩处";ex.run().room.guardPending=false
	ex._prepare_room_actions("rest")
	return game
func capture280(label:String)->void:
	if DisplayServer.get_name()=="headless":return
	DirAccess.make_dir_recursive_absolute(OUT280)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT280+label+".png")
func run()->void:
	app=load("res://main.tscn").instantiate();root.add_child(app);await frames(10);app.set_process(false);fresh()
	var preference_file: String = "/tmp/voidrift-ui-preferences-%d.cfg" % Time.get_ticks_usec()
	app.model.state.extraction.unlockedDifficulty=5
	app._set_extraction_difficulty(4)
	app._set_battle_auto(true)
	app._cycle_battle_speed()
	app._cycle_battle_speed()
	app._save_preferences(preference_file)
	app.extraction_difficulty=0;app.battle_auto=false;app.preferred_battle_auto=false;app.battle_speed=1.0
	app._load_preferences(preference_file)
	ck(app.extraction_difficulty==4 and app.battle_auto and app.preferred_battle_auto and app.battle_speed==4.0,"difficulty auto and speed restored from persistent file")
	# Temporary trial/manual safeguards leave the user's explicit auto preference intact.
	app.battle_auto=false
	app._save_preferences(preference_file)
	app._load_preferences(preference_file)
	ck(app.battle_auto,"temporary manual mode does not overwrite saved auto preference")
	app._set_battle_auto(false);app._cycle_battle_speed();app._save_preferences(preference_file)
	app.battle_auto=true;app.battle_speed=4.0;app._load_preferences(preference_file)
	ck(not app.battle_auto and app.battle_speed==1.0,"later manual and speed choices replace old preferences")
	var config:=ConfigFile.new();config.set_value("extraction","difficulty",99);config.set_value("battle","speed",3.0);config.save(preference_file)
	app._load_preferences(preference_file)
	ck(app.extraction_difficulty==app.model.extraction.max_difficulty() and app.battle_speed==1.0,"invalid saved values safely bounded")
	app.model.state.extraction.unlockedDifficulty=1;app._set_extraction_difficulty(5)
	ck(app.extraction_difficulty==1,"selection respects active save unlock")
	for viewport in [Vector2i(2048,945),Vector2i(960,540),Vector2i(390,844)]:
		root.size=viewport;await frames(8);fresh();app.model=fixture();app.extraction_panel="expedition";app.navigate("extraction");await frames(10)
		var scene=app.find_child("ExtractionRoomScene",true,false)
		ck(scene!=null and scene.size.y>=180,"event scenery retains substantial height "+str(viewport))
		var cards=app.find_children("ExtractionEventCard_*","",true,false)
		ck(cards.size()==3,"three event choices remain available")
		var hidden_ids: Array=[]
		for option in app.model.extraction.room_actions():
			for item_id in EventChoice.effect(option).get("items",[]):hidden_ids.append(item_id)
		for card in cards:
			var shown:=text_under(card)
			for item_id in hidden_ids:ck(not shown.contains(str(app.model.extraction.item_def(str(item_id)).name)),"unselected cards hide exact item names")
			if app.size.x>=900:
				for button in card.find_children("ExtractionRoomAction_*","Button",true,false):fits(button,"visible event decision "+str(viewport))
		if app.size.x>=900:fits(scene,"scenery in landscape viewport")
		await capture280(str(viewport.x)+"-event-layout")
		var body:VBoxContainer=app._vbox(app.overlay,2)
		var option={"label":"领取补给","description":"草药绷带","presentationEffect":{"items":["bandage","ration"]}}
		EventChoice.heading(app,body,option,"coin",app.CYAN);EventChoice.benefits(app,body,option,"coin",app.CYAN)
		ck(not text_under(body).contains("草药绷带") and not text_under(body).contains("旅人干粮") and text_under(body).contains("补给 ×2"),"generic supplies summary hides concrete contents")
		for node in body.find_children("*","Label",true,false):ck(not node.tooltip_text.contains("草药绷带"),"tooltip keeps contents hidden")
		app._clear_overlay()
	app.queue_free();await frames();print("EVENT PREFERENCES V280: %d checks, %d failures"%[checks,failures]);quit(0 if failures==0 else 1)
