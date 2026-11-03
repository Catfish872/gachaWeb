extends "res://tests/test_lantern_journey_ui_v270.gd"
const Music283=preload("res://scripts/windpass_audio.gd")
const OUT283="res://validation/v283-extraction/"

func event_fixture283(kind:String="hospital"):
	var game=Game.new("");game.rng.seed=278;game.extraction.start_run()
	var ex=game.extraction
	ex.run().phase="room";ex.run().activeEncounter={};ex.run().pendingChoices=[];ex.run().containers=[]
	for unit in ex.run().party:unit.currentHp=100;unit.maxHp=1000;unit.energy=0
	ex.run().room.type=kind;ex.run().room.name="守灯药店";ex.run().room.guardPending=false
	ex._prepare_room_actions(kind)
	# Use the exact two-effect option from the reported pharmacy screen.
	if kind=="hospital":
		ex.run().roomActions[1]={"id":"resuscitate","label":"使用复苏药剂","description":"花费40金币，全队恢复50%","cost":40,"used":false,"selected":false,"effect":{"heal":0.5,"revive":true}}
	ex._container("灰烬供台",2,0);ex._container("灰烬供台",2,0)
	game.state.resources.gold=10000
	return game

func capture283(label:String)->void:
	if DisplayServer.get_name()=="headless":return
	DirAccess.make_dir_recursive_absolute(OUT283)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT283+label+".png")

func event_layout283()->void:
	for viewport in [Vector2i(960,540),Vector2i(2048,945)]:
		root.size=viewport;await frames(8)
		var heights:Array=[]
		for kind in ["hospital","workshop"]:
			fresh();app.model=event_fixture283(kind);app.extraction_panel="expedition";app.navigate("extraction");await frames(14)
			var scene=app.find_child("ExtractionRoomScene",true,false)
			var service=app.find_child("ExtractionServiceScroll",true,false)
			heights.append(service.size.y)
			ck(scene.size.y>=138,"complete container art remains visible "+kind+str(viewport))
			fits(scene,"event scenery "+kind+str(viewport));fits(service,"event effects "+kind+str(viewport))
			fits(app.find_child("ExtractionPersistentActions",true,false),"persistent actions "+kind+str(viewport))
			ck(app.shell.size.y<=app.size.y+.5,"page stays within viewport "+kind+str(viewport))
			for button in app.find_children("ExtractionRoomAction_*","Button",true,false):
				fits(button,"always-visible decision "+str(button.name)+str(viewport))
				ck(button.size.y>=44,"decision keeps full touch target")
			await capture283(str(viewport.x)+"-"+kind+"-adaptive-effects")
			if kind=="hospital":
				var before:int=app.model.state.resources.gold
				await tap(app.find_child("ExtractionRoomAction_resuscitate",true,false))
				ck(app.model.state.resources.gold==before-40,"real visible pharmacy choice commits once")
				ck(app.model.extraction.run().roomActions[1].selected,"actual selected option persists")
		ck(heights[1]>=heights[0],"extra effect rows receive available extra height")

func music_context283()->void:
	fresh();app.music_enabled=true;app.model.extraction.start_run()
	app.model.extraction.run().environmentOrder=["windpass","forest","ruins"]
	app.model.extraction.run().act=1;app.model.extraction.run().room.districtId="district_2"
	app.model.state.abyss.currentFloor=35
	for mode in ["extraction","abyss"]:
		for gallery in [false,true]:
			var background:String="res://assets/content_v280/backgrounds/"+("resonance_gallery.png" if gallery else "cloud_nest.png")
			var normal:String=app.model.extraction.environment_music_track() if mode=="extraction" else "dungeon_mystic"
			var boss_track:String="windpass_gallery" if gallery else "windpass_road"
			app.current_screen=mode;app._sync_music()
			var exploration:AudioStreamPlayer=app.music_audio
			app.current_screen="battle";app.battle_config={"isExtraction":mode=="extraction","isAbyss":mode=="abyss","enemies":["leaf_spirit"],"background":background}
			app._sync_music()
			ck(app.music_audio==exploration and app.music_audio.get_meta("track")==normal,"ordinary fight keeps exploration player "+mode+str(gallery))
			exploration.seek(8)
			await create_timer(0.1).timeout
			print("MUSIC283 before boss ",mode," ",gallery," track=",exploration.get_meta("track")," cursor=",exploration.get_playback_position()," playing=",exploration.playing," paused=",exploration.stream_paused)
			app.battle_config.enemies=["boss_highland_roc"];app.battle_config.isBoss=true;app._sync_music()
			await create_timer(1.1).timeout
			ck(app.music_audio.get_meta("track")==boss_track,"boss receives previous ordinary scene track "+mode+str(gallery))
			ck(app.music_audio.playing and not app.music_audio.stream_paused and app.music_audio.volume_db>-50,"boss stream is active after fade "+mode+str(gallery))
			ck(app.music_audio.stream.get_length()>1 and app.music_audio.stream.loop,"boss has a decoded looping stream")
			app.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
			ck(app.music_audio.stream_paused,"application pause freezes boss music")
			app.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
			ck(not app.music_audio.stream_paused,"application resume restores boss music")
			app.current_screen=mode;app._sync_music()
			await create_timer(0.1).timeout
			print("MUSIC283 returned ",mode," ",gallery," same=",app.music_audio==exploration," track=",app.music_audio.get_meta("track")," cursor=",exploration.get_playback_position()," playing=",exploration.playing," paused=",exploration.stream_paused)
			ck(app.music_audio==exploration and exploration.get_playback_position()>=7.9,"return resumes exploration cursor "+mode)
	app.current_screen="battle";app.battle_config={"enemies":["boss_highland_roc"],"isBoss":true,"background":"res://assets/content_v280/backgrounds/cloud_nest.png"};app._sync_music()
	ck(app.music_audio.get_meta("track")=="windpass_core","chapter boss keeps original score")
	app.battle_config={"isAbyss":true,"enemies":["boss_storm_witch"],"isBoss":true};app._sync_music()
	ck(app.music_audio.get_meta("track")=="determined_pursuit","other abyss boss music stays intact")
	app.music_enabled=false;app._sync_music()

func run()->void:
	app=load("res://main.tscn").instantiate();root.add_child(app);await frames(12);app.set_process(false)
	if not "--music-only" in OS.get_cmdline_user_args():await event_layout283()
	await music_context283()
	app.queue_free();await frames(8)
	print("EXTRACTION PRESENTATION V283: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
