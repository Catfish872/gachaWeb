extends SceneTree
var app
var checks:=0
var failures:=0
const OUT="res://validation/caster-dot-v264/"
func _initialize()->void:call_deferred("run")
func ck(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func frames(n:int=5)->void:
	for i in n:await process_frame
func capture(label:String)->void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT+label+".png")
func run()->void:
	if DisplayServer.get_name()=="headless":quit(2);return
	DirAccess.make_dir_recursive_absolute(OUT)
	app=load("res://main.tscn").instantiate();root.add_child(app);await frames(12);app.set_process(false)
	app.sound_enabled=false;app.extraction_reduced_motion=false;app.battle_speed=4.0
	for resolution in [Vector2i(2048,945),Vector2i(960,540)]:
		root.size=resolution;await frames()
		app.model=load("res://scripts/game_model.gd").new("");app.battle=load("res://scripts/battle_model.gd").new(app.model.catalog)
		app._start_battle({"enemies":["boss_flame_lord"],"seed":26403});await frames()
		var target:Dictionary=app.battle.state.enemies[0];target.maxHp=1000000;target.currentHp=1000000;target.stats.maxHp=1000000
		var caster:Dictionary=app.battle.state.allies[0];caster.stats.atk=1000
		app.battle.apply_status(target,"burn",2,null,caster)
		for i in 100:app.battle.apply_status(target,"poison",2,null,caster)
		app.battle._events=[];app.battle._end_round()
		var events:Array=app.battle._events.filter(func(e):return e.get("type","")=="damage")
		ck(events.filter(func(e):return e.get("status","")=="poison").size()==1,"100 layers emit one poison hit")
		events.push_front({"type":"damage","actor":caster.uid,"target":target.uid,"amount":321})
		for i in 100:events.append({"type":"damage","actor":caster.uid,"target":target.uid,"amount":2,"follow_up":true})
		var display:Array=app._combat_display_events(events)
		ck(display.size()==4,"direct, added, burn and 100-layer poison are four channels")
		ck(display.filter(func(e):return e.get("feedbackChannel","")=="follow_up")[0].amount==200,"repeated extra damage summed without omission")
		app._render_battle();await frames()
		var strip=app.find_child("BattleStatuses_"+str(target.uid),true,false)
		ck(strip!=null,"actual enemy status strip")
		if strip!=null:
			var poison:Array=strip.states.filter(func(s):return s.id=="poison")
			ck(poison.size()==1 and int(poison[0].stacks)==100,"permanent poison compact badge aggregates all layers")
			ck("∞" in strip.counter_text(poison[0]),"poison duration visibly permanent")
			ck(strip.tooltip_text.split("\n").size()<=2,"100 poison layers have one concise tooltip row")
		await app._show_combat_events(events);await frames(1)
		var panels:Array=[]
		for channel in ["direct","burn","poison","follow_up"]:
			var panel=app.find_child("CombatDamage_"+channel,true,false);ck(panel!=null,"source damage panel "+channel)
			if panel!=null:
				panels.append(panel)
				ck(Rect2(Vector2.ZERO,app.size).encloses(panel.get_global_rect()),"source panel inside viewport")
		for i in panels.size():
			for j in range(i+1,panels.size()):ck(not panels[i].get_global_rect().intersects(panels[j].get_global_rect()),"source panels do not overlap %s %s / %s %s" % [panels[i].name,panels[i].get_global_rect(),panels[j].name,panels[j].get_global_rect()])
		await capture("feedback-"+str(resolution.x))
		await create_timer(.8).timeout
		for channel in ["direct","burn","poison","follow_up"]:ck(app.find_child("CombatDamage_"+channel,true,false)==null,"4x source panel clears without long queue")
	app.queue_free();await frames();print("CASTER DOT UI V264: %d checks, %d failures"%[checks,failures]);quit(0 if failures==0 else 1)
