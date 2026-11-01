extends SceneTree
var app
var checks:=0
var failures:=0
func _initialize():call_deferred("run")
func ck(ok:bool,label:String):
	checks+=1
	if not ok:failures+=1;push_error(label)
func run():
	app=load("res://main.tscn").instantiate();root.add_child(app)
	for i in 10:await process_frame
	app.set_process(false);app.sound_enabled=true
	app._last_ui_sound_msec=-10000
	app._ui_sound("tap");app._ui_sound("coin")
	ck(app._last_ui_sound_clip=="coin" and app.ui_audio.stream.resource_path.ends_with("coin.ogg"),"successful sale sound is not swallowed by preceding button tap")
	app._ui_sound("tap")
	ck(app._last_ui_sound_clip=="coin","tap cannot interrupt success feedback in the same frame")
	app._ui_sound("equip")
	ck(app._last_ui_sound_clip=="equip","different success action may replace tap or preceding UI sound")
	for element in ["fire","water","wind","thunder"]:
		ck(app._battle_sound_clip([{"type":"damage","amount":10,"element":element}])==element,"damage selects "+element)
	ck(app._battle_sound_clip([{"type":"damage","amount":10,"skill_id":"kaldi_normal","element":"fire"}])=="slash","sword normal uses slash")
	ck(app._battle_sound_clip([{"type":"damage","amount":10,"skill_id":"ayla_normal","element":"water"}])=="ice","ice skill uses ice")
	ck(app._battle_sound_clip([{"type":"heal","amount":20}])=="heal","healing sound")
	ck(app._battle_sound_clip([{"type":"status","statusId":"shield"}])=="shield_cast","shield cast sound")
	ck(app._battle_sound_clip([{"type":"damage","amount":10,"isCrit":true}])=="critical","critical accent")
	ck(app._battle_sound_clip([{"type":"skill","skill_id":"kaldi_ult"},{"type":"damage","amount":10}])=="ultimate","ultimate only one action-level accent")
	app.battle.state={"allies":[{"uid":"ally_0","id":"ember","shield":10}],"enemies":[]}
	ck(app._battle_sound_clip([{"type":"shield","target":"ally_0","amount":20}])=="shield_hit","shield absorbs hit")
	app.battle.state.allies[0].shield=0
	ck(app._battle_sound_clip([{"type":"shield","target":"ally_0","amount":20}])=="shield_break","complete shield break distinct sound")
	var events:Array=[]
	for i in 6:events.append({"type":"damage","element":"fire","amount":10})
	app._last_battle_sound_msec=-10000
	var before:int=app._battle_audio_history.size()
	app._play_battle_sound(events)
	ck(app._battle_audio_history.size()==before+1,"AoE emits one sound not one per target")
	app._play_battle_sound(events)
	ck(app._battle_audio_history.size()==before+1,"same-frame duplicates throttled")
	for i in 12:
		app._last_battle_sound_msec=-10000;app._play_battle_sound(events)
	ck(get_nodes_in_group("battle_audio").size()<=2,"4x combat polyphony bounded to two voices")
	app.sound_enabled=false;before=app._battle_audio_history.size();app._last_battle_sound_msec=-10000;app._play_battle_sound(events)
	ck(app._battle_audio_history.size()==before,"sound off prevents combat sounds")
	app.sound_enabled=true;app.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	app._last_battle_sound_msec=-10000;app._play_battle_sound(events)
	ck(app._battle_audio_history.size()==before,"background cannot emit new combat sounds")
	app.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	app._stop_reveal_voices();await process_frame
	ck(get_nodes_in_group("battle_audio").is_empty(),"paused voices do not replay on return")
	app.queue_free();await process_frame;await create_timer(.3).timeout
	print("COMBAT AUDIO V24: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
