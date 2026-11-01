extends SceneTree
# Geometric regression, not a substitute for rendered Android visual review.
var app
var failures: Array[String] = []
var checks := 0
const SIZES := [Vector2i(2340,1080),Vector2i(1920,1080),Vector2i(1280,720)]
func _initialize() -> void: call_deferred("run")
func frames(n: int=12) -> void:
	for i in n: await process_frame
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok: failures.append(message);push_error("REDESIGN: "+message)
func visible_rect(control: Control) -> Rect2:
	var clip:=Rect2(Vector2.ZERO,app.size)
	var parent=control.get_parent()
	while parent!=null:
		if parent is Control and (parent.clip_contents or parent is ScrollContainer):clip=clip.intersection(parent.get_global_rect())
		parent=parent.get_parent()
	return clip.intersection(control.get_global_rect())
func fits(control: Control, label: String) -> void:
	check(control!=null,label+" exists")
	if control==null:return
	check(visible_rect(control).size.is_equal_approx(control.size),label+" fully visible, including clipped ancestors")
func run() -> void:
	root.size=SIZES[0]
	app=load("res://main.tscn").instantiate();root.add_child(app)
	await frames()
	app.set_process(false)
	app.model=load("res://scripts/game_model.gd").new("")
	app.battle=load("res://scripts/battle_model.gd").new(app.model.catalog)
	for resolution in SIZES:
		root.size=resolution;await frames()
		app.model=load("res://scripts/game_model.gd").new("")
		app.battle=load("res://scripts/battle_model.gd").new(app.model.catalog)
		app.navigate("story");await frames()
		var prepared: Dictionary=app.model.prepare_stage("ch1_1")
		check(prepared.get("success",false),"real battle fixture")
		if not prepared.get("success",false):continue
		app._start_battle(prepared.config);app.battle_auto=false;app._render_battle();await frames()
		fits(app.main_body.find_child("BattleArena",true,false),str(resolution)+" battlefield")
		fits(app.main_body.find_child("BattleActions",true,false),str(resolution)+" action dock")
		for control in app.unit_cards.values():fits(control,str(resolution)+" combatant")
		for control in app.main_body.find_children("BattleSkill_*","Button",true,false):
			fits(control,str(resolution)+" skill")
			check(control.size.y>=40,"skill touch target >=40 logical pixels")
		var cast=app.main_body.find_child("CastSkill",true,false)
		if cast!=null:fits(cast,str(resolution)+" cast")
		check(app.page_scroll.get_v_scroll_bar().max_value-app.page_scroll.get_v_scroll_bar().page<=1,"battle requires no vertical scroll")
		app.battle.state={};app.navigate("home");await frames()
	app.queue_free()
	await process_frame
	await create_timer(0.3).timeout
	print("REDESIGN LAYOUT: %d checks, %d failures" %[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
