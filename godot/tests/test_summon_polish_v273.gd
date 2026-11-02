extends "res://tests/test_lantern_journey_ui_v270.gd"
const Avatars=preload("res://scripts/ui/character_avatar.gd")
const OUT273="res://validation/v273-focused/"
func capture(label:String)->void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT273+label+".png")
func pause(seconds:float)->void:await create_timer(seconds).timeout
func summary(expected:int,label:String)->void:
	await pause(.65);await tap(app.find_child("SummonSkip",true,false));await pause(.45)
	ck(app.summon_sequence.stage=="summary","skip reaches summary")
	var wallet=app.find_child("SummonBalance",true,false)
	ck(wallet!=null and int(wallet.get_meta("balance",-1))==expected,"real committed balance "+str(expected))
	ck(int(app.model.state.resources.diamonds)==expected,"wallet matches model")
	fits(wallet,"summary wallet");fits(app.find_child("SummonAgain",true,false),"again action");fits(app.find_child("SummonAccept",true,false),"close action")
	await capture(label)
func run()->void:
	if DisplayServer.get_name()=="headless":quit(2);return
	DirAccess.make_dir_recursive_absolute(OUT273)
	app=load("res://main.tscn").instantiate();root.add_child(app);await frames(12);app.set_process(false);fresh();root.size=Vector2i(960,540);await frames(8)
	ck(Avatars.get_texture("selin","bust") is AtlasTexture,"Selin actual bust crop")
	ck(Avatars.region_for("selin","bust")==Rect2(175,0,650,650),"curated crown to waist crop")
	ck(Avatars.get_texture("selin","face").resource_path=="res://assets/content_v270/portraits/selin_face.png","dedicated face unchanged")
	ck(Avatars.source_path("selin")=="res://assets/content_v270/characters/selin.png","full battle source unchanged")
	for id in app.model.catalog.CharacterData:app.model.state.ownedCharacters[id]=app.model.default_character()
	app.character_filter="全部";app.navigate("party");await frames(8)
	app.find_child("PartyRosterScroll",true,false).scroll_vertical=100000;await frames(6);await capture("960-party-bust-comparison")
	app.selected_pool="limited_selin";app.navigate("summon");await frames()
	app.summon_results=[{"charId":"selin","rarity":5,"isNew":true,"shards":0}];app._reveal_summon();await frames(6);app.summon_sequence._enter("result");await frames(4)
	ck(app.find_child("SummonRevealPortrait",true,false).texture is AtlasTexture,"single reveal uses bust")
	await capture("960-selin-reveal-bust");app.summon_sequence.show_summary();await pause(.45);await capture("960-selin-summary-bust");await tap(app.find_child("SummonAccept",true,false));await frames()
	app.model.state.resources.diamonds=3700;app._pull(1);await summary(3540,"960-single-balance")
	await tap(app.find_child("SummonAgain",true,false));await summary(3380,"960-repeat-single-balance")
	await tap(app.find_child("SummonAccept",true,false));await frames();ck(app.current_screen=="summon","close returns summon")
	app._pull(10);await summary(1780,"960-ten-balance")
	await tap(app.find_child("SummonAgain",true,false));await summary(180,"960-repeat-ten-insufficient")
	ck(app.find_child("SummonAgain",true,false).disabled,"insufficient ten disabled")
	await tap(app.find_child("SummonAgain",true,false));ck(app.model.state.resources.diamonds==180,"disabled repeat cannot charge")
	await tap(app.find_child("SummonAccept",true,false));await frames();app._pull(1);await summary(20,"960-single-insufficient")
	ck(app.find_child("SummonAgain",true,false).disabled,"insufficient single disabled")
	await tap(app.find_child("SummonAccept",true,false));await frames();ck(app.current_screen=="summon" and app.overlay.get_child_count()==0,"close clears presentation")
	app.queue_free();await frames();print("SUMMON POLISH V273: %d checks, %d failures"%[checks,failures]);quit(0 if failures==0 else 1)
