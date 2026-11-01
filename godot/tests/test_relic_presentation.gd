extends SceneTree
var app
var checks:=0
var failures:Array=[]
func _initialize()->void:call_deferred("run")
func ck(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
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
func tap(control:Control)->void:
	fits(control,"input "+str(control.name))
	var point:=control.get_global_rect().get_center()
	for down in [true,false]:
		var e:=InputEventMouseButton.new();e.button_index=MOUSE_BUTTON_LEFT;e.pressed=down;e.position=point;e.global_position=point
		root.push_input(e,true);await frames(2)
	await frames()
func capture(label:String)->void:
	if DisplayServer.get_name()=="headless":return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("/workspace/scratch/8f1fc457a062/relics-review")
	root.get_texture().get_image().save_png("/workspace/scratch/8f1fc457a062/relics-review/"+label+".png")
func run()->void:
	root.size=Vector2i(2340,1080)
	app=load("res://main.tscn").instantiate();root.add_child(app);await frames(15);app.set_process(false)
	app.model=load("res://scripts/game_model.gd").new("");app.model.rng.seed=193522
	app._toast("获得遗物",app.GOLD)
	ck(app.toast_layer.get_child_count()==1,"feedback is created immediately")
	ck(app.toast_layer.get_child(0).mouse_filter==Control.MOUSE_FILTER_IGNORE,"new feedback is non-blocking before any rendering delay")
	for i in range(20):
		var item:Dictionary=app.model.generate_relic(3+i%3,app.model.catalog.RelicSlots[i%5].id)
		ck(app.model.add_relic(item).get("success",false),"real relic fixture")
	for resolution in [Vector2i(2340,1080),Vector2i(1920,1080)]:
		root.size=resolution;await frames()
		app.relic_filter="全部";app.relic_slot_filter="全部";app.navigate("relics");await frames()
		for slot in app.model.catalog.RelicSlots:
			var texture:Texture2D=app._relic_texture(slot.id)
			ck(texture!=null and texture.resource_path=="res://assets/ui/relics/"+str(slot.id)+".png","actual illustrated slot "+str(slot.id))
		var sc:ScrollContainer=app.main_body.find_child("RelicRosterScroll",true,false)
		sc.scroll_vertical=99999;await frames();var remembered:int=sc.scroll_vertical
		var uid:String=app.model.state.relics.back().uid
		await tap(app.main_body.find_child("RelicCard_"+uid,true,false))
		ck(app.selected_relic==uid,"tap selects exact relic UID")
		sc=app.main_body.find_child("RelicRosterScroll",true,false)
		ck(abs(sc.scroll_vertical-remembered)<=1,"selecting bottom relic retains list position")
		var upgrade:Button=app.main_body.find_child("RelicUpgrade",true,false)
		fits(upgrade,"fixed upgrade action");fits(app.main_body.find_child("RelicEquip",true,false),"fixed equip action")
		await capture("inventory-"+str(resolution.x))
		var old_level:int=app.model.get_relic(uid).level
		var before_gold:int=app.model.state.resources.gold
		var cost:int=app.model.relic_upgrade_cost(old_level)
		await tap(upgrade)
		ck(app.model.get_relic(uid).level==old_level+1 and app.model.state.resources.gold==before_gold-cost,"upgrade charges exact displayed model cost once")
		var notice:Control=app.toast_layer.find_child("FeedbackToast",true,false)
		ck(notice==null or not notice.get_global_rect().intersects(app.main_body.find_child("RelicUpgrade",true,false).get_global_rect()),"success feedback never covers fixed upgrade actions")
		ck(notice==null or notice.mouse_filter==Control.MOUSE_FILTER_IGNORE,"success feedback never intercepts input")
		await tap(app.main_body.find_child("RelicEquip",true,false))
		fits(app.overlay.find_child("RelicEquipFor_ember",true,false),"real character equip target")
		fits(app.overlay.find_child("RelicEquipFor_zeph",true,false),"second initial character target")
		await capture("equip-"+str(resolution.x))
		var prior:Dictionary=app.model.state.duplicate(true)
		await tap(app.overlay.find_child("RelicEquipCancel",true,false))
		ck(app.model.state==prior and app.overlay.get_child_count()==0,"cancel preserves inventory equipment and gold")
		await tap(app.main_body.find_child("RelicEquip",true,false))
		await tap(app.overlay.find_child("RelicEquipFor_ember",true,false))
		ck(app.model.get_relic(uid).equippedBy=="ember" and app.overlay.get_child_count()==0,"equip exact relic and dismiss")
		app.selected_character="ember";app.growth_panel="gear";app.navigate("growth");await frames()
		for slot in app.model.catalog.RelicSlots:ck(app.main_body.find_child("RelicArt_"+str(slot.id),true,false)!=null,"growth equipment slot art "+str(slot.id))
		await capture("growth-gear-"+str(resolution.x))
	app.queue_free();await process_frame;await create_timer(0.3).timeout
	print("RELIC PRESENTATION: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
