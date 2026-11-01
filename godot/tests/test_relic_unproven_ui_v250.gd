extends SceneTree
var app
var checks:=0
var failures:Array=[]
func _initialize()->void:call_deferred("run")
func ck(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);printerr("FAIL ",label)
func frames(n:int=8)->void:
	for i in n:await process_frame
func recommendation()->Dictionary:
	var until:=Time.get_ticks_msec()+20000
	while Time.get_ticks_msec()<until:
		var panel=app.overlay.find_child("ModalPanel",true,false)
		if panel!=null:
			var plan:Dictionary=panel.get_meta("relic_displayed_plan",{})
			if bool(plan.get("canApply",false)) and not bool(plan.get("provenOptimal",false)):return plan.duplicate(true)
		await process_frame
	return {}
func click_same_frame(control:Control)->void:
	var point:=control.get_global_rect().get_center()
	for down in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;event.position=point;event.global_position=point
		root.push_input(event,true)
func fresh():
	var game=load("res://scripts/game_model.gd").new("");game.rng.seed=250508
	for i in 300:game.state.relics.append(game.generate_relic(3+i%3,str(game.catalog.RelicSlots[i%5].id),str(game.catalog.RelicSets.keys()[i%6])))
	game.equip_relic(str(game.state.relics[0].uid),"zeph")
	return game
func run()->void:
	if "--require-gl" in OS.get_cmdline_user_args() and DisplayServer.get_name()=="headless":printerr("FAIL real GL display required");quit(1);return
	root.size=Vector2i(960,540);app=load("res://main.tscn").instantiate();root.add_child(app);await frames(15);app.set_process(false)
	app.model=fresh();app.selected_character="ember";app.navigate("growth");await frames()
	var before:Dictionary=app.model.state.duplicate(true)
	app._auto_relic_loadout("ember");var displayed:Dictionary=await recommendation()
	ck(not displayed.is_empty(),"unproven recommendation becomes available while search continues")
	if displayed.is_empty():app.queue_free();await frames();quit(1);return
	var apply:Button=app.overlay.find_child("RelicLoadoutApply",true,false)
	ck(apply.text=="采用当前推荐" and not apply.disabled,"explicit adopt-current action enabled")
	ck(app.overlay.find_child("RelicLoadoutProgress",true,false).text.contains("继续比较中"),"pending search never claims completed or globally optimal")
	ck(str(displayed.fingerprint).length()==64,"recommendation has complete input fingerprint")
	ck(app.model.state==before,"pending preview remains read-only")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://validation/relic-ui-v250/unproven-preview.png")
		displayed=app.overlay.find_child("ModalPanel",true,false).get_meta("relic_displayed_plan",{}).duplicate(true)
	var snapshot:Dictionary=displayed.duplicate(true)
	click_same_frame(apply);await frames()
	ck(app.overlay.get_child_count()==0,"explicit current recommendation applied and dismissed")
	ck(app.model.relic_loadout_snapshot("ember").relicUids==displayed.after.relicUids,"applied UIDs exactly match on-screen snapshot")
	ck(displayed==snapshot and not displayed.provenOptimal and not displayed.cancelled,"UI preserves context hash and proof fields on displayed plan")
	ck(app.model.state.resources==before.resources,"current recommendation spends zero currency")
	ck(app.model.state.ownedCharacters.zeph==before.ownedCharacters.zeph,"current recommendation preserves teammate gear")
	# An explicitly adopted pending plan follows the same transactional rollback.
	app.model=fresh();app._auto_relic_loadout("ember");displayed=await recommendation();ck(not displayed.is_empty(),"rollback fixture has pending displayed plan")
	app.model.save_blocked=true;before=app.model.state.duplicate(true)
	click_same_frame(app.overlay.find_child("RelicLoadoutApply",true,false));await frames()
	ck(app.model.state==before and app.overlay.get_child_count()>0,"save failure restores all resources and ownership for unproven apply")
	app.model.save_blocked=false;app._clear_overlay()
	app.model=fresh();app._auto_relic_loadout("ember");displayed=await recommendation();ck(not displayed.is_empty(),"stale fixture has pending displayed plan")
	app.model.active_slot=2;before=app.model.state.duplicate(true)
	click_same_frame(app.overlay.find_child("RelicLoadoutApply",true,false));await frames()
	ck(app.model.state==before and app.overlay.get_child_count()>0,"stale pending recommendation refreshes without applying")
	app._clear_overlay();app.queue_free();await frames();await create_timer(.35).timeout
	print("RELIC UNPROVEN UI V250: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
