extends "res://tests/test_lantern_journey_ui_v270.gd"
const Avatars=preload("res://scripts/ui/character_avatar.gd")
const Bust=preload("res://scripts/ui/character_bust.gd")
const OUT274="res://validation/v274-focused/"
func capture(label:String)->void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT274+label+".png")
func run()->void:
	if DisplayServer.get_name()=="headless":quit(2);return
	DirAccess.make_dir_recursive_absolute(OUT274)
	app=load("res://main.tscn").instantiate();root.add_child(app);await frames(12);app.set_process(false);fresh()
	ck(Avatars.get_texture("selin","face").resource_path=="res://assets/content_v270/portraits/selin_face.png","dedicated face remains original")
	ck(Avatars.source_path("selin")=="res://assets/content_v270/characters/selin.png","full battle source remains original")
	for id in app.model.catalog.CharacterData:app.model.state.ownedCharacters[id]=app.model.default_character()
	app.model.state.team=["selin","kaldi","cinder"]
	for resolution in [Vector2i(2048,945),Vector2i(960,540)]:
		root.size=resolution;await frames(8);var label:=str(resolution.x)
		for id in ["selin","kaldi","ayla","cinder"]:
			app.selected_character=id;app.growth_panel="stats";app.navigate("growth");await frames(8)
			var stage=app.find_child("PortraitEnvironment_"+id,true,false)
			ck(stage!=null,"actual growth portrait exists "+id)
			var portrait=stage.find_child("CharacterPortraitTexture",true,false)
			ck(portrait.get_meta("portrait_composition","")=="full_source_frame_clip" and not portrait.texture is AtlasTexture,"complete transparent source composed "+id)
			var rects=Bust.composition_rects(Rect2(Vector2.ZERO,portrait.size),portrait.texture.get_size(),portrait.composition_region)
			ck(rects.size()==2 and absf(rects[0].end.y-portrait.size.y)<.1,"waist continues to actual frame bottom "+id)
			ck(rects[1].position.x<portrait.composition_region.position.x or rects[1].end.x>portrait.composition_region.end.x or rects[1].end.y>portrait.composition_region.end.y+.1,"visible source extends beyond old internal box "+id)
			await capture(label+"-growth-"+id)
		app.character_filter="全部";app.navigate("party");await frames(8);await capture(label+"-party-edges")
	app.selected_pool="limited_selin";app.navigate("summon");await frames();app.summon_results=[{"charId":"selin","rarity":5,"isNew":true,"shards":0}];app._reveal_summon();await frames(6)
	app.summon_sequence._enter("result");await frames(6);await capture("960-summon-reveal-edges")
	app.summon_sequence.show_summary();await create_timer(.7).timeout;await capture("960-summon-card-edges")
	app._clear_overlay();app.queue_free();await frames();print("PORTRAIT EDGES V274: %d checks, %d failures"%[checks,failures]);quit(0 if failures==0 else 1)
