extends "res://tests/test_lantern_journey_ui_v270.gd"
var callbacks := 0
func done() -> void: callbacks += 1
func run() -> void:
	app=load("res://main.tscn").instantiate();app.music_enabled=false;app.sound_enabled=false;root.add_child(app);await frames(6);app.set_process(false);fresh()
	var game=app.model
	ck(not game.get_stage("ch5_1").unlocked,"chapter five begins locked")
	for stage in game.stage_list():
		if not str(stage.id).begins_with("ch5_"):game.state.stageProgress[stage.id]={"cleared":true,"stars":3,"bestTurns":5}
	game.state.dialogueSeen.ch4_12_post=true
	var old_progress:Dictionary=game.state.stageProgress.duplicate(true)
	var owned:Array=game.state.ownedCharacters.keys()
	ck(game.get_stage("ch5_1").unlocked and not game.get_stage("ch5_2").unlocked,"old chapter completion unlocks exactly first stage")
	var chapter:Dictionary=game.catalog.StageData.chapters.back()
	var keys:Array=[]
	for stage in chapter.stages:
		game.state.resources.stamina=120
		var prepared:Dictionary=game.prepare_stage(stage.id)
		ck(prepared.success,"stage prepares "+stage.id)
		ck(game.state.resources.stamina==120-int(stage.staminaCost),"exact stamina cost "+stage.id)
		var battle=Battle.new(game.catalog);battle.start(prepared.config,game.battle_party())
		ck(battle.state.enemies.size()==stage.waves[0].enemies.size(),"encounter count "+stage.id)
		for i in battle.state.enemies.size():ck(battle.state.enemies[i].id==stage.waves[0].enemies[i],"enemy order "+stage.id)
		var result:Dictionary=game.finish_battle(prepared.config,{"phase":"victory","turn":5,"allies":[{"currentHp":1}]})
		ck(result.success and result.firstClear,"first clear settlement "+stage.id)
		ck(result.rewards.diamonds==stage.firstClearRewards.diamonds and result.gift.is_empty(),"exact first reward without character gift "+stage.id)
		if stage.has("firstClearRelic"):ck(result.relic.setId==stage.firstClearRelic.setId and result.relic.rarity==5,"fixed relic awarded "+stage.id)
		ck(not game.finish_battle(prepared.config,{"phase":"victory"}).success,"duplicate settlement rejected "+stage.id)
		game.state.resources.stamina=120
		var repeat:Dictionary=game.prepare_stage(stage.id)
		var replay:Dictionary=game.finish_battle(repeat.config,{"phase":"victory","turn":9})
		ck(replay.success and not replay.firstClear and replay.rewards.diamonds==0,"repeat excludes first reward "+stage.id)
		ck(game.state.stageProgress[stage.id].bestTurns==5,"replay retains best result "+stage.id)
		keys.append(str(stage.id)+"_pre");keys.append_array(app._stage_post_dialogue_keys(stage))
	ck(keys.size()==40,"all forty scene routes")
	for key in old_progress:ck(game.state.stageProgress[key]==old_progress[key],"old stage retained "+key)
	ck(game.state.dialogueSeen.ch4_12_post and game.state.ownedCharacters.keys()==owned,"old dialogue and roster retained")
	for dims in [Vector2i(960,540),Vector2i(2048,945)]:
		root.size=dims;app.size=Vector2(dims);await frames(3)
		app.selected_chapter=4;app.current_screen="story"
		for stage in chapter.stages:
			app.selected_stage_id=stage.id
			ck(app._background_path()==stage.background,"stage backdrop "+stage.id)
		for key in keys:
			app._play_dialogue(key,done)
			var lines:Array=game.catalog.DialogueData[key]
			var longest:=0
			for i in lines.size():
				if str(lines[i].text).length()>str(lines[longest].text).length():longest=i
			app.dialogue_index=longest;app._render_dialogue();await frames(2)
			if app.dialogue_tween:app.dialogue_tween.kill()
			app.dialogue_prose.visible_characters=-1;await frames(1)
			ck(app.dialogue_prose.text==lines[longest].text,"approved longest line renders "+key)
			fits(app.find_child("DialogueNext",true,false),"next "+key)
			fits(app.find_child("DialogueSkip",true,false),"skip "+key)
			ck(app.dialogue_prose.get_line_count()==app.dialogue_prose.get_visible_line_count(),"longest line unclipped "+key)
			var meta:Dictionary=game.catalog.DialogueMeta[key]
			ck(app._dialogue_background_path()==meta.get("illustration",meta.background),"scene/CG background "+key)
			ck(app._music_track_for_context()==preload("res://scripts/thunder_audio.gd").scene_track(meta.background),"scene music "+key)
			app._finish_dialogue()
	ck(callbacks==80,"forty scenes finish once at both sizes")
	ck(preload("res://scripts/thunder_audio.gd").scene_track(game.catalog.DialogueMeta.ch5_epilogue_1.background)=="thunder_city_street","old street epilogue leaves tower music")
	var ending:Array=chapter.stages.back().postDialogueKeys
	for key in ending:game.state.dialogueSeen.erase(key)
	app._play_dialogue_sequence(ending,done,true)
	for key in ending:
		ck(app.dialogue_key==key,"ending sequence order "+key);app._finish_dialogue()
	ck(callbacks==81,"ending callback once")
	app._play_dialogue_sequence(ending,done,true)
	ck(callbacks==82 and app.dialogue_key.is_empty(),"seen ending is skipped")
	app._play_dialogue_sequence(ending,done,false)
	for key in ending:
		ck(app.dialogue_key==key,"review replays ending "+key);app._finish_dialogue()
	ck(callbacks==83,"review callback once")
	app._finish_dialogue();ck(callbacks==83,"repeated skip remains idempotent")
	for player in app.find_children("*", "AudioStreamPlayer", true, false):
		player.stop();player.stream=null
	await create_timer(0.15).timeout
	app.queue_free();await frames(2)
	print("CHAPTER5 V290: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
