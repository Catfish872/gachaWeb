extends "res://tests/test_lantern_journey_ui_v270.gd"
var callbacks:=0
func done()->void:callbacks+=1
func run()->void:
	app=load("res://main.tscn").instantiate();root.add_child(app);await frames(12);app.set_process(false);fresh()
	var changed:Array=[]
	var scene_count:=0
	for key in app.model.catalog.DialogueData:
		if not str(key).begins_with("ch4_"):continue
		scene_count+=1
		var lines:Array=app.model.catalog.DialogueData[key]
		for index in lines.size():changed.append({"key":str(key),"index":index,"new":str(lines[index].text)})
	ck(scene_count==28,"fourth chapter retains 28 scenes")
	ck(changed.size()==294,"fourth chapter retains 294 entries")
	for dims in [Vector2i(960,540),Vector2i(1280,720)]:
		root.size=dims;app.size=Vector2(dims);await frames(5)
		var current:=""
		for entry in changed:
			var key:String=entry.key
			if key!=current:
				if current!="":app._finish_dialogue()
				app._play_dialogue(key,done);current=key
			app.dialogue_index=int(entry.index);app._render_dialogue();await frames(3)
			if app.dialogue_tween:app.dialogue_tween.kill()
			app.dialogue_prose.visible_characters=-1;await frames(2)
			ck(app.dialogue_prose.text==entry.new,"actual approved text renders "+key)
			fits(app.dialogue_prose,"actual prose "+key)
			fits(app.find_child("DialogueNext",true,false),"next "+key)
			fits(app.find_child("DialogueSkip",true,false),"skip "+key)
			ck(app.dialogue_prose.get_line_count()==app.dialogue_prose.get_visible_line_count(),"actual text unclipped "+key+"/"+str(entry.index))
		app._finish_dialogue()
	ck(callbacks==56,"all 28 scenes close once at each size")
	app._play_dialogue("ch4_10_post",done);await frames(4)
	if app.dialogue_tween:app.dialogue_tween.kill()
	app.dialogue_prose.visible_characters=-1
	app._next_dialogue();ck(app.dialogue_index==1,"next advances once")
	var count:=callbacks;app._finish_dialogue();app._finish_dialogue()
	ck(callbacks==count+1,"repeat skip closes once")
	app.queue_free();await frames();print("CHAPTER4 COPY V2812 HEADLESS LAYOUT: %d checks, %d failures"%[checks,failures]);quit(0 if failures==0 else 1)
