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
func fits(control:Control,label:String)->void:
	ck(control!=null,label+" exists")
	if control==null:return
	var clip:=Rect2(Vector2.ZERO,app.size);var p=control.get_parent()
	while p!=null:
		if p is Control and (p.clip_contents or p is ScrollContainer):clip=clip.intersection(p.get_global_rect())
		p=p.get_parent()
	ck(clip.encloses(control.get_global_rect()),label+" fully visible")
	if control is BaseButton:ck(control.size.y>=44,label+" minimum touch height")
func tap(control:Control)->void:
	if control==null:ck(false,"tap target exists");return
	fits(control,"tap "+str(control.name))
	var point:=control.get_global_rect().get_center()
	for down in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;event.position=point;event.global_position=point
		root.push_input(event,true);await frames(2)
	await frames()
func wait_plan()->void:
	var start:=Time.get_ticks_msec()
	while Time.get_ticks_msec()-start<20000:
		var button=app.overlay.find_child("RelicLoadoutApply",true,false)
		if button==null or button.text in ["应用搭配","当前搭配已合适","暂时无法应用"]:return
		await process_frame
	ck(false,"search reaches terminal state within focused fixture budget")
func capture(label:String)->void:
	if DisplayServer.get_name()=="headless":return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://validation/relic-ui-v250")
	root.get_texture().get_image().save_png("res://validation/relic-ui-v250/"+label+".png")
func fresh():
	var game=load("res://scripts/game_model.gd").new("")
	game.rng.seed=250778
	for i in range(15):
		var relic:Dictionary=game.generate_relic(3+i%3,str(game.catalog.RelicSlots[i%5].id),str(game.catalog.RelicSets.keys()[i%6]))
		game.add_relic(relic)
	return game
func run()->void:
	if "--require-gl" in OS.get_cmdline_user_args() and DisplayServer.get_name()=="headless":
		printerr("FAIL real GL display required");quit(1);return
	root.size=Vector2i(1170,540)
	app=load("res://main.tscn").instantiate();root.add_child(app);await frames(15);app.set_process(false)
	app.model=fresh();app.selected_character="ember"
	for resolution in [Vector2i(960,540),Vector2i(1170,540),Vector2i(2048,945)]:
		root.size=resolution;await frames()
		app.navigate("relics");await frames()
		fits(app.main_body.find_child("RelicAutoEquip",true,false),"workshop auto action")
		fits(app.main_body.find_child("RelicEquip",true,false),"workshop equip action")
		fits(app.main_body.find_child("RelicUpgrade",true,false),"workshop upgrade action")
		await capture("workshop-"+str(resolution.x))
		await tap(app.main_body.find_child("RelicAutoEquip",true,false));await wait_plan();await frames()
		fits(app.overlay.find_child("RelicLoadoutApply",true,false),"fixed loadout apply")
		fits(app.overlay.find_child("RelicLoadoutCancel",true,false),"fixed loadout cancel")
		ck(app.overlay.find_child("RelicLoadoutRole",true,false).text.contains("输出"),"role shown from actual objective")
		for slot in app.model.catalog.RelicSlots:ck(app.overlay.find_child("RelicLoadoutSlot_"+str(slot.id),true,false)!=null,"five-slot comparison "+str(slot.id))
		await capture("preview-"+str(resolution.x))
		var preview_scroll:ScrollContainer=app.overlay.find_child("RelicLoadoutContent",true,false).get_parent()
		preview_scroll.scroll_vertical=999999;await frames()
		await tap(app.overlay.find_child("RelicLoadoutDetails",true,false))
		preview_scroll.scroll_vertical=999999;await frames()
		await capture("preview-details-"+str(resolution.x))
		var before:Dictionary=app.model.state.duplicate(true)
		await tap(app.overlay.find_child("RelicLoadoutCancel",true,false))
		ck(app.model.state==before and app.overlay.get_child_count()==0,"cancel preserves all model resources and gear")
		app.growth_panel="gear";app.navigate("growth");await frames()
		fits(app.main_body.find_child("GrowthAutoRelics",true,false),"growth auto action")
		await capture("growth-"+str(resolution.x))
		app.navigate("abyss");await frames()
		await capture("departure-"+str(resolution.x))
		fits(app.main_body.find_child("AbyssBegin",true,false),"departure action")
		fits(app.main_body.find_child("AbyssChooseRelicSet",true,false),"target set action")
		await tap(app.main_body.find_child("AbyssChooseRelicSet",true,false));await frames()
		fits(app.overlay.find_child("AbyssSetPickerClose",true,false),"set picker close")
		ck(app.overlay.find_child("AbyssRelicSetCard_star_watch",true,false)!=null,"all six target cards")
		await capture("sets-"+str(resolution.x))
		await tap(app.overlay.find_child("AbyssSetPickerClose",true,false))
	# Application is a single zero-resource mutation and protects teammate gear.
	app.model=fresh();var protected_uid:String=app.model.state.relics[0].uid;app.model.equip_relic(protected_uid,"zeph")
	app.selected_character="ember";app._auto_relic_loadout("ember");await wait_plan();await frames()
	var wallet:Dictionary=app.model.state.resources.duplicate(true)
	await tap(app.overlay.find_child("RelicLoadoutApply",true,false))
	ck(app.overlay.get_child_count()==0,"successful apply closes preview")
	ck(app.model.state.resources==wallet,"auto equip spends zero currency")
	ck(app.model.get_relic(protected_uid).equippedBy=="zeph","other character equipment protected")
	ck(app.model.equipped_relics("ember").size()==5,"all five available slots atomically equipped")
	# A preview becomes stale when a relic changes; refresh remains a preview.
	app.model=fresh();app._auto_relic_loadout("ember");await wait_plan();await frames()
	var comparison_scroll:ScrollContainer=app.overlay.find_child("RelicLoadoutContent",true,false).get_parent()
	comparison_scroll.scroll_vertical=180;await frames();var preview_offset:int=comparison_scroll.scroll_vertical
	app.model.upgrade_relic(str(app.model.state.relics[1].uid))
	var stale_state:Dictionary=app.model.state.duplicate(true)
	await tap(app.overlay.find_child("RelicLoadoutApply",true,false));await wait_plan();await frames()
	ck(app.model.state==stale_state and app.overlay.get_child_count()>0,"stale plan refreshes without equipping")
	comparison_scroll=app.overlay.find_child("RelicLoadoutContent",true,false).get_parent()
	ck(abs(comparison_scroll.scroll_vertical-preview_offset)<=1,"stale refresh retains preview scroll")
	root.size=Vector2i(960,540);await frames()
	fits(app.overlay.find_child("RelicLoadoutApply",true,false),"resize preserves fixed apply")
	fits(app.overlay.find_child("RelicLoadoutCancel",true,false),"resize preserves fixed cancel")
	app._go_back();await frames();ck(app.overlay.get_child_count()==0,"Back closes preview")
	app.model=fresh();app._auto_relic_loadout("ember");await wait_plan();await frames()
	app.model.active_slot=2;var slot_state:Dictionary=app.model.state.duplicate(true)
	await tap(app.overlay.find_child("RelicLoadoutApply",true,false));await wait_plan();await frames()
	ck(app.model.state==slot_state and app.overlay.get_child_count()>0,"saved-slot change invalidates plan before applying")
	app._clear_overlay()
	# Persistence failure rolls back before the refreshed preview is displayed.
	app.model=fresh();app._auto_relic_loadout("ember");await wait_plan();await frames()
	app.model.save_blocked=true;var prior:Dictionary=app.model.state.duplicate(true)
	await tap(app.overlay.find_child("RelicLoadoutApply",true,false));await wait_plan();await frames()
	ck(app.model.state==prior and app.overlay.get_child_count()>0,"save failure preserves all ownership and resources")
	app.model.save_blocked=false;app._clear_overlay()
	app.model=load("res://scripts/game_model.gd").new("")
	app._auto_relic_loadout("ember");await wait_plan();await frames()
	ck(app.overlay.find_child("RelicLoadoutApply",true,false).disabled,"empty inventory safely keeps current equipment")
	app._clear_overlay()
	# Cancel during preparation invalidates async work, including a replaced modal.
	app.model=fresh()
	for i in 1200:
		var relic:Dictionary=app.model.state.relics[i%15].duplicate(true);relic.uid="large_"+str(i);app.model.state.relics.append(relic)
	prior=app.model.state.duplicate(true)
	app._auto_relic_loadout("ember");app._clear_overlay();await frames(30)
	ck(app.model.state==prior and app.overlay.get_child_count()==0,"closing pending generation keeps state and overlay clear")
	# Selecting a set is transactional and the issued expedition freezes it.
	app.model=fresh();app.navigate("abyss");await frames()
	await tap(app.main_body.find_child("AbyssChooseRelicSet",true,false))
	app.model.save_blocked=true;prior=app.model.state.duplicate(true)
	await tap(app.overlay.find_child("AbyssRelicSet_aurora_prayer",true,false))
	ck(app.model.state==prior and app.overlay.get_child_count()>0,"target save failure keeps actual choice and modal")
	app.model.save_blocked=false
	await tap(app.overlay.find_child("AbyssRelicSet_aurora_prayer",true,false))
	ck(app.model.state.abyss.meta.selectedRelicSetId=="aurora_prayer","target selector saves exact set")
	app.model.prepare_abyss();app._render_screen();await frames()
	ck(app.main_body.find_child("AbyssTargetSetName",true,false).text.contains("已锁定"),"issued run target shown locked")
	await tap(app.main_body.find_child("AbyssChooseRelicSet",true,false));await frames()
	for set_id in app.model.catalog.RelicSets:ck(app.overlay.find_child("AbyssRelicSet_"+str(set_id),true,false).disabled,"active target button locked "+str(set_id))
	app._clear_overlay();app.queue_free();await frames();await create_timer(.35).timeout
	print("RELIC LOADOUT UI V250: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
