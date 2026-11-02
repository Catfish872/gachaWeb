extends "res://tests/test_portrait_edges_v274.gd"
func run()->void:
	if DisplayServer.get_name()=="headless":quit(2);return
	app=load("res://main.tscn").instantiate();root.add_child(app);await frames(12);app.set_process(false);fresh();root.size=Vector2i(960,540);await frames(8)
	app.selected_pool="limited_selin";app.navigate("summon");await frames();app.summon_results=[{"charId":"selin","rarity":5,"isNew":true,"shards":0}];app._reveal_summon();await frames(6);app.summon_sequence._enter("result");await frames(8)
	var portrait=app.find_child("SummonRevealPortrait",true,false)
	ck(portrait.material is ShaderMaterial,"reveal fade shader bound")
	ck(float(portrait.get_meta("bottom_fade_pixels",0))==30,"reveal fades only final thirty pixels")
	ck(float(portrait.material.get_shader_parameter("fade_height"))==30,"active shader fade distance")
	ck(float(portrait.material.get_shader_parameter("frame_bottom"))>0,"fade follows actual draw bottom")
	var framed=Bust.new();framed.configure("selin");ck(framed.material==null,"framed portraits remain unfaded");framed.free()
	await capture("960-summon-reveal-soft-edge")
	app._clear_overlay();app.queue_free();await frames();print("REVEAL FADE V274: %d checks, %d failures"%[checks,failures]);quit(0 if failures==0 else 1)
