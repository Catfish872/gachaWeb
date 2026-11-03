extends "res://tests/test_lantern_journey_ui_v270.gd"
const NEW_OUT="res://validation/recovered-events-v278-focused/"
func capture(label:String)->void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(NEW_OUT+label+".png")
func icon_count(node:Node)->int:
	var n:int=1 if node is TextureRect and node.texture!=null else 0
	for child in node.get_children():n+=icon_count(child)
	return n
func inspect(prefix:String)->void:
	var cards:Array=app.find_children(prefix+"*","",true,false);ck(cards.size()==3,"three visible choices")
	for card in cards:fits(card,"whole choice including title/button");ck(icon_count(card)>0,"actual loaded choice icons")
func fixture_abyss():
	var g=Game.new("");g.rng.seed=278;g.prepare_abyss();g._issued_config={};g.state.abyss.rogue.activeEncounter={};g.state.abyss.rogue.temporaryCurrency=1000;g.state.abyss.savedPartyState=[]
	for u in g.battle_party(true):g.state.abyss.savedPartyState.append({"id":u.id,"currentHp":100,"maxHp":1000,"energy":0,"cooldowns":{"x":3}})
	return g
func fixture_expedition():
	var g=Game.new("");g.rng.seed=278;g.extraction.start_run();var ex=g.extraction;ex.run().phase="room";ex.run().activeEncounter={};ex.run().pendingChoices=[];ex.run().containers=[]
	for u in ex.run().party:u.currentHp=100;u.maxHp=1000;u.energy=0
	return g
func run()->void:
	if DisplayServer.get_name()=="headless":quit(2);return
	app=load("res://main.tscn").instantiate();root.add_child(app);await frames(12);app.set_process(false)
	root.size=Vector2i(2048,945);await frames(10);fresh();app.model=fixture_abyss();app.abyss_panel="expedition";app.abyss_auto_continue=false
	app.model.state.abyss.rogue.nextStep={"type":"event","floor":2};app.model.state.abyss.rogue.pendingNode={"id":"event_2","type":"event","eventId":"ancient_forge","eventOptionIds":["forge","overload","tune"]}
	app.navigate("abyss");await frames(12);inspect("AbyssEventCard_")
	var b=app.find_child("NodeChoice_overload",true,false);ck(b.disabled and b.text=="生命不足" and not b.tooltip_text.is_empty(),"short disabled reason")
	await capture("2048-forge")
	root.size=Vector2i(960,540);await frames(10);app.model.state.abyss.rogue.nextStep={"type":"rest","floor":2};app.model.state.abyss.rogue.pendingNode={"id":"rest_2","type":"rest","restOptionIds":["recover","meditate","study"]}
	app._render_screen();await frames(12);inspect("AbyssEventCard_");await capture("960-camp")
	await tap(app.find_child("NodeChoice_recover",true,false));ck(app.model.state.abyss.savedPartyState[0].currentHp==450,"actual camp button heals")
	fresh();app.model=fixture_expedition();var ex=app.model.extraction;ex.run().room.type="hospital";ex.run().room.name="林间药房";ex.run().room.guardPending=false;ex._prepare_room_actions("hospital")
	app.extraction_panel="expedition";app.navigate("extraction");await frames(12);inspect("ExtractionEventCard_");fits(app.find_child("ExtractionPersistentActions",true,false),"fixed backpack actions")
	await capture("960-hospital");var id:String=ex.run().roomActions[2].id;await tap(app.find_child("ExtractionRoomAction_"+id,true,false));ck(not ex.run().containers.is_empty(),"actual supply button creates container")
	app.queue_free();await frames();print("RECOVERED EVENT UI V278: %d checks, %d failures"%[checks,failures]);quit(0 if failures==0 else 1)
