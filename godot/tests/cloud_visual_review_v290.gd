extends Node
var app
var review_viewport: SubViewport
var start_ms: int
const OUT = "/workspace/scratch/8f1fc457a062/cloud-ui-review/cg-fit-after"
func frames(n: int=8) -> void:
	for i in n: await get_tree().process_frame
func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	review_viewport.get_texture().get_image().save_png(OUT+"/"+label+".png")
func _ready() -> void:
	start_ms=Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute(OUT)
	review_viewport=SubViewport.new();review_viewport.size=Vector2i(960,540);review_viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(review_viewport)
	var display=TextureRect.new();display.texture=review_viewport.get_texture();display.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;display.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(display)
	app=load("res://main.tscn").instantiate()
	review_viewport.add_child(app);await frames()
	app.test_session=true;app.set_process(false)
	app.model=load("res://scripts/game_model.gd").new("")
	app.battle=load("res://scripts/battle_model.gd").new(app.model.catalog)
	app.music_enabled=false;app.sound_enabled=false;app.preferred_battle_auto=false
	for id in ["raisa","vika","eve"]:app.model.state.ownedCharacters[id]=app.model.default_character()
	app.model.state.team=["raisa","vika","eve"]
	for dims in [Vector2i(960,540),Vector2i(2048,945)]:
		review_viewport.size=dims;app.size=Vector2(dims);await frames(12)
		var prefix=str(dims.x)+"-"
		app.navigate("story")
		for key in ["ch5_interlude_1","ch5_interlude_2","ch5_interlude_3"]:
			app._play_dialogue(key,func():pass);await frames()
			if app.dialogue_tween:app.dialogue_tween.kill()
			app.dialogue_prose.visible_characters=-1;await frames(2);await capture(prefix+key);app._finish_dialogue()
	print("CLOUD VISUAL REVIEW SECONDS ",float(Time.get_ticks_msec()-start_ms)/1000.0)
	get_tree().quit()
