extends "res://tests/test_lantern_journey_ui_v270.gd"
var callbacks:=0
func done()->void:callbacks+=1
func run()->void:
	if DisplayServer.get_name()=="headless":quit(2);return
	app=load("res://main.tscn").instantiate();root.add_child(app);await frames(12);app.set_process(false);fresh();root.size=Vector2i(960,540);await frames(8)
	for key in ["ch3_6_pre","ch3_8_post"]:
		app._play_dialogue(key,done);await frames(8)
		app.dialogue_prose.visible_characters=-1
		if app.dialogue_tween:app.dialogue_tween.kill()
		fits(app.dialogue_prose,"full prose visible");fits(app.find_child("DialogueNext",true,false),"next visible");fits(app.find_child("DialogueSkip",true,false),"skip visible")
		ck(app.dialogue_prose.get_line_count()==app.dialogue_prose.get_visible_line_count(),"no clipped prose lines")
		if key=="ch3_8_post":ck(app._dialogue_has_cg(),"real final CG bound")
		await capture("story-rewrite-"+key)
		await tap(app.find_child("DialogueNext",true,false));ck(app.dialogue_index==1,"continue advances exactly one line")
		var before:=callbacks;await tap(app.find_child("DialogueSkip",true,false));ck(callbacks==before+1 and app.dialogue_key=="","skip closes and calls once");ck(app.model.state.dialogueSeen.get(key,false),"seen recorded")
		app._finish_dialogue();ck(callbacks==before+1,"repeat close does not double callback")
	app.queue_free();await frames();print("STORY REWRITE UI: %d checks, %d failures"%[checks,failures]);quit(0 if failures==0 else 1)
