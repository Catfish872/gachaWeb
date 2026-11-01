extends SceneTree
var app
var checks:=0
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures+=1;push_error("LOOT TOUCH: "+label)
func frames(n:int=5) -> void:
	for i in n:await process_frame
func click(control:Control) -> void:
	check(control!=null,"real target exists")
	if control==null:return
	var bounds:=control.get_global_rect()
	var clip:=Rect2(Vector2.ZERO,app.size)
	var parent=control.get_parent()
	while parent!=null:
		if parent is Control and parent.clip_contents:clip=clip.intersection(parent.get_global_rect())
		parent=parent.get_parent()
	check(control.is_visible_in_tree() and clip.encloses(bounds),"real target fully visible: "+str(control.name)+" rect="+str(bounds)+" clip="+str(clip)+" app="+str(app.size)+" logical="+str(root.content_scale_size))
	await click_at(bounds.get_center())
func click_at(point:Vector2) -> void:
	for down in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT
		event.position=point;event.global_position=point;event.pressed=down
		root.push_input(event,true);await frames(2)
	await frames()
func capture(label:String) -> void:
	if DisplayServer.get_name()=="headless":return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://validation/v23-loot-"+label+".png")
func target(name:String):return app.find_child(name,true,false)
func open_box(id:String) -> void:
	# Reused fixtures may empty a node, close it, then add the next scenario's
	# items. Revisit through the visible map after completion auto-return.
	if app.model.extraction.run().get("phase","")=="route":
		var map=target("ExtractionMap")
		check(map!=null,"completed fixture exposes its actual map")
		if map!=null:
			var point:Vector2=map.global_position+map.room_point(str(app.model.extraction.run().map.currentRoomId))
			await click_at(point)
			if app.model.extraction.run().phase=="route":await click_at(point)
	await click(target("ExtractionOpenContainer_"+id))
	check(target("ExtractionContainer_"+id)!=null,"actual click opens matching spatial grid")
func select_item(id:String,uid:String) -> void:
	var grid=target("ExtractionContainer_"+id)
	check(grid!=null,"source grid remains present")
	if grid==null:return
	for item in grid.items:
		if str(item.uid)==uid:
			await click_at(grid.global_position+grid.item_rect(item).get_center())
			check(target("ExtractionPickup_"+uid)!=null,"actual item click selects exact UID")
			return
	check(false,"selected item UID is present")
func run() -> void:
	root.size=Vector2i(2340,1080)
	app=load("res://main.tscn").instantiate();root.add_child(app);await frames(12)
	if not OS.has_feature("mobile"):check(app._usable_rect()==Rect2(Vector2.ZERO,app.size),"desktop mobile simulation uses full logical window, not desktop display safe area")
	app.extraction_auto_pick=false;app.extraction_sound=false;app.extraction_reduced_motion=false
	app.model.rng.seed=2
	check(app.model.extraction.start_run(0).success,"start ordinary run")
	var x=app.model.extraction
	var found:=false
	for room in x.route_options():
		if room.type=="cache":found=x.enter_room(room.id).success;break
	check(found,"enter actual generated cache")
	app.navigate("extraction");await frames()
	var box:Dictionary=x._find_container(x.containers()[0].id)
	var id:=str(box.id)
	x.run().bag=[]
	var dimensions:Vector2i=x.dimensions("bag")
	for cell in dimensions.x*dimensions.y:
		var filler:Dictionary=x._make_item("wire");filler.revealed=true
		check(x._place(x.run().bag,filler,dimensions),"fill actual bag capacity")
	var original_bag:Array=x.run().bag.duplicate(true)
	check(not x._place(x.run().bag,x._make_item("wire"),dimensions),"bag truly cannot accept one cell")
	for unit in x.run().party:unit.currentHp=1
	var med:Dictionary=x._make_item("medkit");med.revealed=true
	box.items=[med]
	app._render_screen();await frames()
	await open_box(id);await select_item(id,str(med.uid));await capture("full-bag-direct-use")
	await click(target("ExtractionUse_"+str(med.uid)))
	check(x.run().bag==original_bag,"direct medicine never alters full bag")
	check(x.run().party[0].currentHp>1 and not box.items.any(func(item):return item.uid==med.uid),"direct medicine heals and consumes exact source UID")
	await click(target("ExtractionCloseContainer"))
	var blade:Dictionary=x._make_item("blade");blade.revealed=true
	box.items=[blade];app._render_screen();await frames()
	await open_box(id);await select_item(id,str(blade.uid));await capture("full-bag-direct-equip")
	await click(target("ExtractionEquip_"+str(blade.uid)))
	check(x.run().bag==original_bag,"direct equipment never alters full bag")
	check(x.run().equipped.any(func(item):return item.uid==blade.uid),"direct equipment equips exact source UID")
	check(not box.items.any(func(item):return item.uid==blade.uid),"equipped item removed once from source")
	await click(target("ExtractionCloseContainer"))
	# Occupied three-slot build replaces in place, returning old UID to source.
	for equipment_id in ["vest","scope"]:
		var gear:Dictionary=x._make_item(equipment_id);gear.revealed=true;x.run().equipped.append(gear)
	var incoming:Dictionary=x._make_item("shield");incoming.revealed=true
	box.items=[incoming];app._render_screen();await frames()
	await open_box(id);await select_item(id,str(incoming.uid))
	await click(target("ExtractionEquip_"+str(incoming.uid)))
	await capture("full-bag-replacement")
	await click(target("ExtractionReplace_"+str(blade.uid)))
	check(x.run().bag==original_bag,"full-bag replacement preserves bag byte-for-byte")
	check(x.run().equipped.size()==3 and x.run().equipped.any(func(item):return item.uid==incoming.uid) and not x.run().equipped.any(func(item):return item.uid==blade.uid),"replacement changes exactly the selected equipment UID")
	check(box.items.size()==1 and box.items[0].uid==blade.uid and box.items[0].revealed,"replaced equipment returns revealed to original container")
	await click(target("ExtractionCloseContainer"))
	# Permanent utility slots are distinct from the three tactical build slots.
	for utility_id in ["armor_1","pack_5"]:
		var utility:Dictionary=x._make_item(utility_id);utility.revealed=true
		box.items=[utility];app._render_screen();await frames()
		await open_box(id);await select_item(id,str(utility.uid))
		await click(target("ExtractionEquip_"+str(utility.uid)))
		var slot:=str(x.item_def(utility_id).slot)
		check(x.state().utility[slot].uid==utility.uid,"direct utility goes to persistent "+slot+" slot")
		check(x.run().equipped.size()==3,"utility does not occupy tactical build slot")
		var carried_ids:Array=x.run().bag.map(func(item):return item.uid)
		var original_ids:Array=original_bag.map(func(item):return item.uid)
		carried_ids.sort();original_ids.sort()
		check(carried_ids==original_ids,"utility equip preserves every carried UID including multiplicity")
		if slot=="backpack":
			var expanded=target("ExtractionGrid_search_bag")
			check(x.dimensions("bag")==Vector2i(6,10),"highest bag expands actual model to sixty cells")
			check(expanded.rows==10,"search bag grid exposes expanded capacity")
			await capture("expanded-backpack")
		await click(target("ExtractionCloseContainer"))
	# Toggle through real controls during scanning and during the visible dwell.
	for boundary in ["scan","dwell"]:
		x.run().bag=[]
		var loot:Dictionary=x._make_item("wire");loot.revealed=false
		box.items=[loot];box.revealed=0
		app.extraction_auto_pick=true;app.extraction_reduced_motion=false
		app._render_screen();await frames();await open_box(id)
		if boundary=="dwell":
			var reveal_deadline:=Time.get_ticks_msec()+6000
			while not box.items[0].get("revealed",false) and Time.get_ticks_msec()<reveal_deadline:await process_frame
			check(box.items[0].get("revealed",false),"observe same UID revealed before toggling off")
		await click(target("ExtractionAutoPick"))
		check(not app.extraction_auto_pick,"actual switch disables automatic pickup at "+boundary)
		var finish_deadline:=Time.get_ticks_msec()+6000
		while app.extraction_searching and Time.get_ticks_msec()<finish_deadline:await process_frame
		check(not app.extraction_searching,"automatic reveal terminates with pickup disabled")
		check(x.run().bag.is_empty() and box.items.size()==1 and box.items[0].uid==loot.uid and box.items[0].revealed,"off preserves revealed source UID at "+boundary)
		await click(target("ExtractionAutoPick"));await create_timer(.5).timeout
		check(app.extraction_auto_pick and x.run().bag.is_empty(),"enabling pickup does not silently collect historical reveals")
		await click(target("ExtractionTakeAll"))
		check(x.run().bag.size()==1 and x.run().bag[0].uid==loot.uid and box.items.is_empty(),"explicit take transfers exact historical UID once")
		await click(target("ExtractionCloseContainer"))
	# Closing while the decorative transfer is in flight must not undo or duplicate ownership.
	x.run().bag=[]
	var flying:Dictionary=x._make_item("wire");flying.revealed=false
	box.items=[flying];app.extraction_auto_pick=true;app._render_screen();await frames()
	await open_box(id)
	var transfer_deadline:=Time.get_ticks_msec()+6000
	while not x.run().bag.any(func(item):return item.uid==flying.uid) and Time.get_ticks_msec()<transfer_deadline:await process_frame
	var transfer=target("ExtractionTransfer_"+str(flying.uid))
	check(transfer!=null and transfer.mouse_filter==Control.MOUSE_FILTER_IGNORE,"live pickup animation never intercepts touch")
	await click(target("ExtractionCloseContainer"));await create_timer(.5).timeout
	check(x.run().bag.size()==1 and x.run().bag[0].uid==flying.uid and box.items.is_empty(),"closing in-flight animation preserves exact committed ownership")
	await open_box(id)
	check(not app.extraction_searching,"empty container does not restart search")
	check(x.run().bag.size()==1 and x.run().bag[0].uid==flying.uid,"reopening empty container cannot duplicate pickup")
	await click(target("ExtractionCloseContainer"))
	app.queue_free();await frames();await create_timer(.3).timeout
	print("LOOT TOUCH: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
