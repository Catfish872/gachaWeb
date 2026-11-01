extends SceneTree
var errors:=0
var checks:=0
func _initialize()->void:call_deferred("run")
func ck(ok:bool,label:String)->void:
	checks+=1
	if not ok:errors+=1;push_error("AUDIO: "+label)
func run()->void:
	var app=load("res://main.tscn").instantiate();root.add_child(app)
	for i in 8:await process_frame
	app.extraction_sound=true;app.sound_enabled=true
	app._stop_reveal_voices()
	app._extraction_play("search")
	ck(get_nodes_in_group("transient_audio").is_empty(),"search produces no result sound")
	app._extraction_play("red")
	ck(get_nodes_in_group("transient_audio").size()==1,"red reveal starts one voice")
	app._extraction_play("common")
	ck(get_nodes_in_group("transient_audio").size()==1,"common never masks active red")
	for i in 8:app._extraction_play("red")
	ck(get_nodes_in_group("transient_audio").size()<=3,"reveal polyphony bounded")
	app._stop_reveal_voices()
	ck(get_nodes_in_group("transient_audio").is_empty(),"mute immediately stops all reveal voices")
	app.queue_free();await process_frame;await create_timer(0.3).timeout
	print("AUDIO: %d checks, %d failures"%[checks,errors]);quit(1 if errors else 0)
