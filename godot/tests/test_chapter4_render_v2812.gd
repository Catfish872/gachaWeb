extends "res://tests/test_lantern_journey_ui_v270.gd"
var callbacks:=0
func done()->void:callbacks+=1
func capture_ch4(label:String)->void:
	await RenderingServer.frame_post_draw
	ck(root.get_texture().get_image().save_png("res://validation/v2812-story/"+label+".png")==OK,"rendered screenshot saved")
func run()->void:
	if DisplayServer.get_name()=="headless":quit(2);return
	app=load("res://main.tscn").instantiate();root.add_child(app);await frames(12);app.set_process(false);fresh()
	for dims in [Vector2i(960,540),Vector2i(1280,720)]:
		root.size=dims;await frames(12)
		for entry in [["ch4_1_post",5],["ch4_interlude_1",4],["ch4_4_post",9],["ch4_10_post",12],["ch4_12_post",12]]:
			app._play_dialogue(entry[0],done);app.dialogue_index=int(entry[1]);app._render_dialogue();await frames(8)
			if app.dialogue_tween:app.dialogue_tween.kill()
			app.dialogue_prose.visible_characters=-1;await frames(4)
			fits(app.dialogue_prose,"approved prose");fits(app.find_child("DialogueNext",true,false),"continue button");fits(app.find_child("DialogueSkip",true,false),"skip button")
			ck(app.dialogue_prose.get_line_count()==app.dialogue_prose.get_visible_line_count(),"rendered lines fit")
			await capture_ch4("render-%d-%s-%d"%[dims.x,entry[0],entry[1]])
			var before:=callbacks
			var last:bool=int(entry[1])+1>=app.model.catalog.DialogueData[entry[0]].size()
			await tap(app.find_child("DialogueNext",true,false))
			ck(callbacks==before+1 if last else app.dialogue_index==int(entry[1])+1,"continue advances exactly once %s/%d"%[entry[0],dims.x])
			if last:app._play_dialogue(entry[0],done);await frames(6)
			before=callbacks;await tap(app.find_child("DialogueSkip",true,false))
			ck(callbacks==before+1 and app.dialogue_key=="","skip closes and calls once %s/%d"%[entry[0],dims.x])
			app._finish_dialogue();ck(callbacks==before+1,"repeated close leaves callback count unchanged")
	app.queue_free();await frames(6)
	print("CHAPTER4 RENDER V2812: %d checks, %d failures; renderer=%s"%[checks,failures,DisplayServer.get_name()]);quit(0 if failures==0 else 1)
