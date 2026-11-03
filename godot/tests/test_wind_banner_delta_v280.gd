extends "res://tests/test_lantern_journey_ui_v270.gd"
func run()->void:
	app=load("res://main.tscn").instantiate();root.add_child(app);await frames(12);app.set_process(false);root.size=Vector2i(960,540);await frames(8);fresh()
	for id in ["tiya","lumi"]:
		app.selected_pool="limited_"+id;app.navigate("summon");await frames(12)
		var stage=app.find_child("SummonStage",true,false)
		ck(stage!=null and stage.get_meta("embedded_banner_character",false),"scene embeds a large background portrait behind the full-body foreground")
		var expected_banner: String = "res://assets/content_v280/banner/%s_layered_banner.png" % id
		ck(stage!=null and stage.get_meta("portrait_background","")==expected_banner and ResourceLoader.exists(expected_banner),"scene uses the dedicated layered banner")
		var portrait=stage.find_child("CharacterPortraitTexture",true,false) if stage!=null else null
		ck(portrait!=null and portrait is TextureRect and portrait.stretch_mode==TextureRect.STRETCH_KEEP_ASPECT_CENTERED,"dedicated foreground uses the legacy full-body fit")
		fits(app.find_child("WindTrial_"+id,true,false),"solo trial visible");fits(app.find_child("WindTrial_duo",true,false),"duo trial visible")
		await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png("res://validation/v280-focused/summon-"+id+"-960-final.png")
	app.queue_free();await frames();print("WIND BANNER DELTA: %d checks, %d failures"%[checks,failures]);quit(0 if failures==0 else 1)
