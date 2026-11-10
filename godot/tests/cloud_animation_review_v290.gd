extends Node
var app
var viewport: SubViewport
var checks := 0
var failures: Array = []
const OUT = "/workspace/scratch/8f1fc457a062/cloud-ui-review/animation-review"
func frames(n: int=4) -> void:
	for i in n:await get_tree().process_frame
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:failures.append(label)
	print("PASS " if ok else "FAIL ",label)
func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png(OUT+"/"+label+".png")
func _ready() -> void:
	if not "--test-session" in OS.get_cmdline_user_args():push_error("Requires isolated test session");get_tree().quit(2);return
	DirAccess.make_dir_recursive_absolute(OUT)
	viewport=SubViewport.new();viewport.size=Vector2i(960,540);viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(viewport)
	var display=TextureRect.new();display.texture=viewport.get_texture();display.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;display.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(display)
	app=load("res://main.tscn").instantiate();viewport.add_child(app);await frames(8);app.set_process(false)
	app.music_enabled=false;app.sound_enabled=false;app.preferred_battle_auto=false
	check(app.model.save_dir.is_empty(),"isolated model")
	for dims in [Vector2i(960,540),Vector2i(2048,945)]:
		viewport.size=dims;app.size=Vector2(dims);await frames(8)
		for gentle in [false,true]:
			app.extraction_reduced_motion=gentle
			for id in ["raisa","vika","eve"]:
				app.selected_pool="limited_"+id;app.navigate("summon");await frames()
				app.summon_results=[{"charId":id,"rarity":5,"isNew":true,"shards":0}];app._reveal_summon();await frames(6)
				var sequence=app.summon_sequence
				sequence._enter("portrait")
				for tick in range(240):
					if sequence.stage=="result":break
					await get_tree().process_frame
				check(sequence.stage=="result","live portrait to result "+id+str(dims)+str(gentle))
				await capture(str(dims.x)+"-"+id+"-reveal-"+str(gentle));app._clear_overlay();await frames()
	app.model=load("res://scripts/game_model.gd").new("")
	for id in ["raisa","vika","eve"]:app.model.state.ownedCharacters[id]=app.model.default_character()
	app.model.state.team=["raisa","vika","eve"]
	viewport.size=Vector2i(960,540);app.size=Vector2(960,540)
	app._start_battle(app.model.prepare_stage("ch1_1").config);app.battle_auto=false
	var raisa:Dictionary=app.battle.state.allies[0]
	app.battle._enter_thunder_armor(raisa);raisa.thunderArmor.unlockStage=2
	app.battle._queue=[raisa];app.battle._cursor=0;app.battle.state.phase="player_turn"
	for gentle in [false,true]:
		app.extraction_reduced_motion=gentle
		for speed in [1.0,2.0,4.0]:
			app.battle_speed=speed;app._render_battle();await frames()
			for sid in ["raisa_armor_normal","raisa_armor_skill","raisa_armor_ult"]:
				var event={"actor":raisa.uid,"skill_id":sid,"actionImage":app.model.catalog.SkillData[sid].actionImage}
				app._show_battle_action_art(event)
				var effect=app.unit_cards[raisa.uid].find_child("ThunderActionIllustration",true,false)
				check(is_equal_approx(effect.duration,.72/speed),"duration "+sid+str(speed)+str(gentle))
				await frames(1)
				if sid=="raisa_armor_ult":await capture("action-"+str(speed)+"-"+str(gentle))
				await get_tree().create_timer(.8/speed+.1).timeout
				check(not is_instance_valid(effect),"effect cleanup "+sid+str(speed)+str(gentle))
				check(app.unit_cards[raisa.uid].find_child("CharacterPortraitTexture",true,false).visible,"idle restored "+sid+str(speed)+str(gentle))
	var event={"actor":raisa.uid,"skill_id":"raisa_armor_ult","actionImage":app.model.catalog.SkillData.raisa_armor_ult.actionImage}
	app._show_battle_action_art(event);app._show_battle_action_art(event);await frames(1)
	check(app.unit_cards[raisa.uid].find_children("ThunderActionIllustration","",true,false).size()==1,"replacement has one effect")
	await get_tree().create_timer(.4).timeout
	check(app.unit_cards[raisa.uid].find_child("CharacterPortraitTexture",true,false).visible,"replacement restores idle")
	app._show_battle_action_art(event);app._render_battle();await frames(4);await get_tree().create_timer(.4).timeout
	check(app.unit_cards[raisa.uid].find_child("CharacterPortraitTexture",true,false).visible,"rerender during effect restores portrait")
	app._show_battle_action_art(event);app.unit_cards[raisa.uid].queue_free();await frames(4);app._show_battle_action_art(event);await get_tree().create_timer(.4).timeout
	check(not is_instance_valid(app.unit_cards[raisa.uid]),"removed actor safely ignored")
	app._render_battle();await frames();await capture("battle-final-restored")
	var target_uid: String=app.battle.state.enemies[0].uid
	var hits: Array=[]
	for step in range(4):hits.append({"type":"damage","actor":raisa.uid,"target":target_uid,"skill_id":"raisa_armor_ult","amount":100,"element":"thunder","presentationStep":step,"hitCount":4})
	for gentle in [false,true]:
		for speed in [1.0,2.0,4.0]:
			app.extraction_reduced_motion=gentle;app.battle_speed=speed;app._render_battle();await frames()
			app._show_combat_events(hits);await frames(2)
			app.unit_cards[target_uid].queue_free();await frames(3);await get_tree().create_timer(.7).timeout
			check(not is_instance_valid(app.unit_cards[target_uid]),"multi-hit removed target "+str(speed)+str(gentle))
	app._render_battle();await frames();await capture("after-target-removal")
	var report={"checks":checks,"failures":failures,"scope":"development fixture; constructed reveal entry; live action lifecycle"}
	FileAccess.open(OUT+"/results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	app._clear_overlay();app.queue_free();await frames(8);await get_tree().create_timer(.5).timeout
	print("ANIMATION REVIEW ",JSON.stringify(report));get_tree().quit(0 if failures.is_empty() else 1)
