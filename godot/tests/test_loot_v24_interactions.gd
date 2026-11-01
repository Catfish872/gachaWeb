extends "res://tests/test_redesign_loot_interactions.gd"
func capture(label:String) -> void:
	if DisplayServer.get_name()=="headless":return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://validation/v24-loot-"+label+".png")
func drag_trace(stage:String) -> void:
	var grid=target("ExtractionGrid_search_bag")
	if grid!=null:
		print("V24_DRAG ",stage," mode=",grid.placement_mode," pressed=",grid._pressed," dragged=",grid._dragged," touch=",grid._touch_id," press=",grid._press," bag=",JSON.stringify(app.model.extraction.run().bag))
func touch_drag_between(origin:Vector2,destination:Vector2) -> void:
	drag_trace("before")
	var down:=InputEventScreenTouch.new();down.index=0;down.position=origin;down.pressed=true
	root.push_input(down,true);drag_trace("down-sync");await frames(2);drag_trace("down-frames")
	var previous:=origin
	for step in range(1,5):
		var point:Vector2=origin.lerp(destination,float(step)/4)
		var drag:=InputEventScreenDrag.new();drag.index=0;drag.position=point;drag.relative=point-previous
		root.push_input(drag,true);drag_trace("drag-%d-sync"%step);previous=point;await frames(1);drag_trace("drag-%d-frame"%step)
	var up:=InputEventScreenTouch.new();up.index=0;up.position=destination;up.pressed=false
	root.push_input(up,true);drag_trace("up-sync");await frames(3);drag_trace("up-frames")
func select_bag(uid:String) -> void:
	var grid=target("ExtractionGrid_search_bag")
	for item in grid.items:
		if str(item.uid)==uid:
			await click_at(grid.global_position+grid.item_rect(item).get_center());return
	check(false,"bag contains selected exact UID")
func visible_control(control:Control,label:String) -> void:
	check(control!=null,label+" exists")
	if control==null:return
	var clip:=Rect2(Vector2.ZERO,app.size)
	var parent=control.get_parent()
	while parent!=null:
		if parent is Control and parent.clip_contents:clip=clip.intersection(parent.get_global_rect())
		parent=parent.get_parent()
	check(control.is_visible_in_tree() and clip.encloses(control.get_global_rect()),label+" stays within the actual viewport and clipped parents")
func fill_wire(x,count:int) -> void:
	x.run().bag=[]
	for i in count:
		var item:Dictionary=x._make_item("wire");item.revealed=true
		check(x._place(x.run().bag,item,x.dimensions("bag")),"place exact cheap filler")
func run() -> void:
	root.size=Vector2i(2340,1080)
	app=load("res://main.tscn").instantiate();root.add_child(app);await frames(12)
	app.extraction_auto_pick=false;app.extraction_sound=false;app.extraction_reduced_motion=true
	app.model.rng.seed=2
	var x=app.model.extraction
	check(x.start_run(0).success,"start generated run")
	for room in x.route_options():
		if room.type=="cache":x.enter_room(room.id);break
	app.navigate("extraction");await frames()
	var box:Dictionary=x._find_container(x.containers()[0].id)
	var id:String=box.id
	var dim:Vector2i=x.dimensions("bag")
	fill_wire(x,dim.x*dim.y-1)
	var medicine:Dictionary=x._make_item("bandage");medicine.revealed=true
	check(x._place(x.run().bag,medicine,dim),"one-cell medicine occupies the final cell")
	for unit in x.run().party:unit.currentHp=1
	var golden:Dictionary=x._make_item("gold_watch");golden.revealed=true
	box.items=[golden]
	app._render_screen();await frames();await open_box(id)
	await select_bag(str(medicine.uid))
	check(target("ExtractionUse_"+str(medicine.uid))!=null,"exact bag medicine use action is available")
	for resolution in [Vector2i(2340,1080),Vector2i(1920,1080),Vector2i(1280,720)]:
		root.size=resolution;await frames(12)
		for node_name in ["ExtractionUse_"+str(medicine.uid),"ExtractionMove_"+str(medicine.uid),"ExtractionTakeAll","ExtractionSmartLoot","ExtractionCloseContainer"]:
			visible_control(target(node_name),str(resolution)+" "+node_name)
	root.size=Vector2i(2340,1080);await frames(12)
	await click(target("ExtractionUse_"+str(medicine.uid)))
	check(not x.run().bag.any(func(item):return item.uid==medicine.uid),"using medicine removes exact UID")
	check(target("ExtractionUse_"+str(medicine.uid))==null,"consumed medicine action is removed immediately")
	await capture("medicine-consumed")
	var stale_name:bool=false
	for label in target("ExtractionSearchDetail").find_children("*","Label",true,false):
		if str(x.item_def("bandage").name) in label.text:stale_name=true
	check(not stale_name,"consumed medicine name and description no longer occupy detail panel")
	check(x.run().bag.size()==dim.x*dim.y-1,"consumption leaves exactly one free cell")
	check(x.run().party[0].currentHp>1,"medicine applies real healing")
	await select_item(id,str(golden.uid))
	await click(target("ExtractionPickup_"+str(golden.uid)))
	check(x.run().bag.any(func(item):return item.uid==golden.uid),"one-cell gold enters the one free cell through real pickup")
	check(not box.items.any(func(item):return item.uid==golden.uid),"picked-up gold leaves source exactly once")
	check(x.run().bag.size()==dim.x*dim.y,"bag returns to full occupancy")
	await click(target("ExtractionCloseContainer"))
	fill_wire(x,dim.x*dim.y)
	var swap_gold:Dictionary=x._make_item("gold_watch");swap_gold.revealed=true;box.items=[swap_gold]
	var before_ids:Array=x.run().bag.map(func(item):return str(item.uid))
	app._render_screen();await frames();await open_box(id)
	await click(target("ExtractionSmartLoot"))
	check(target("ExtractionSmartConfirm")!=null,"full cheap bag offers a real profitable exchange")
	if target("ExtractionSmartConfirm")!=null:
		await click(target("ExtractionSmartConfirm"))
		check(x.run().bag.any(func(item):return item.uid==swap_gold.uid),"confirmed exchange takes exact gold UID")
		check(box.items.size()==1 and str(box.items[0].uid) in before_ids,"exact displaced cheap UID remains in source")
		check(x.run().bag.size()==dim.x*dim.y,"exchange preserves full packing")
	await click(target("ExtractionCloseContainer"))
	# Full tactical slots show per-item art and the real effect before replacement.
	x.run().equipped=[]
	var old_gear:Array=[]
	for equipment_id in ["blade","vest","scope"]:
		var gear:Dictionary=x._make_item(equipment_id);gear.revealed=true
		x.run().equipped.append(gear);old_gear.append(gear)
	var incoming:Dictionary=x._make_item("shield");incoming.revealed=true;box.items=[incoming]
	root.size=Vector2i(1920,1080)
	app._render_screen();await frames(12);await open_box(id);await select_item(id,str(incoming.uid))
	await click(target("ExtractionEquip_"+str(incoming.uid)))
	for gear in old_gear:
		var card=target("ExtractionReplacement_"+str(gear.uid))
		check(card!=null,"replacement has a card for exact equipped UID")
		if card==null:continue
		var definition:Dictionary=x.item_def(str(gear.itemId))
		var icon_found:bool=false;var description_found:bool=false
		for texture in card.find_children("*","TextureRect",true,false):
			if texture.texture!=null and texture.texture.resource_path==str(definition.icon):icon_found=true
		for label in card.find_children("*","Label",true,false):
			if label.text==str(definition.description):description_found=true
		check(icon_found,"replacement card shows its own real item artwork")
		check(description_found,"replacement card shows its exact effect description")
	await click(target("ExtractionReplace_"+str(old_gear[0].uid)))
	check(x.run().equipped.any(func(item):return item.uid==incoming.uid),"actual visible replacement action equips exact incoming UID")
	await click(target("ExtractionCloseContainer"))
	# Deliberate single-item placement changes only the chosen UID.
	x.run().bag=[];box.items=[]
	var movable:Dictionary=x._make_item("scope");movable.revealed=true
	check(x._place(x.run().bag,movable,x.dimensions("bag")),"place rotatable two-cell item")
	var blocker:Dictionary=x._make_item("wire");blocker.revealed=true;blocker.x=4;blocker.y=2
	x.run().bag.append(blocker)
	app._render_screen();await frames();await open_box(id);await select_bag(str(movable.uid))
	await click(target("ExtractionMove_"+str(movable.uid)))
	var placement_grid=target("ExtractionGrid_search_bag")
	check(placement_grid.placement_mode,"real move button enters explicit placement mode")
	await click(target("ExtractionRotate_"+str(movable.uid)))
	check(placement_grid.placement_size==Vector2i(1,2),"rotation preview uses the actual item footprint")
	await capture("move-preview")
	var before_move:Array=x.run().bag.duplicate(true)
	await click_at(placement_grid.global_position+(Vector2(4,2)+Vector2(.5,.5))*placement_grid.cell)
	check(x.run().bag==before_move and placement_grid.placement_mode,"occupied destination preserves all items and keeps retry mode")
	await click_at(placement_grid.global_position+(Vector2(3,1)+Vector2(.5,.5))*placement_grid.cell)
	var moved:Dictionary={}
	for item in x.run().bag:
		if item.uid==movable.uid:moved=item
	check(not moved.is_empty() and int(moved.x)==3 and int(moved.y)==1 and moved.rotated,"real destination tap moves exact UID and retains chosen rotation")
	check(not placement_grid.placement_mode,"successful placement exits deliberate move mode")
	await capture("move-placed")
	check(x.run().bag.any(func(item):return item.uid==blocker.uid and item.x==4 and item.y==2),"unrelated item coordinates remain unchanged")
	await select_bag(str(movable.uid));await click(target("ExtractionMove_"+str(movable.uid)))
	var before_cancel:Array=x.run().bag.duplicate(true)
	await click(target("ExtractionRotate_"+str(movable.uid)))
	await click(target("ExtractionCancelMove"))
	check(x.run().bag==before_cancel and not placement_grid.placement_mode,"cancelling rotation preview leaves original packing untouched")
	await click(target("ExtractionMove_"+str(movable.uid)))
	var trace_input:Callable=func(event:InputEvent):print("V24_GRID_EVENT ",event.as_text()," device=",event.device)
	var trace_cell:Callable=func(cx:int,cy:int):print("V24_GRID_CELL ",cx,",",cy," ticks=",Time.get_ticks_msec())
	placement_grid.gui_input.connect(trace_input);placement_grid.cell_selected.connect(trace_cell)
	for repetition in 3:
		print("V24_DRAG_REPETITION ",repetition)
		await touch_drag_between(placement_grid.global_position+Vector2(.5,.5)*placement_grid.cell,placement_grid.global_position+Vector2(2.5,1.5)*placement_grid.cell)
		check(x.run().bag==before_cancel and placement_grid.placement_mode,"finger drag while choosing a position never commits an unintended move round %d"%repetition)
	placement_grid.gui_input.disconnect(trace_input);placement_grid.cell_selected.disconnect(trace_cell)
	await click(target("ExtractionCancelMove"))
	await click(target("ExtractionCloseContainer"))
	# Container pickup can target a precise cell without rearranging other items.
	x.run().bag=[]
	var targeted:Dictionary=x._make_item("scope");targeted.revealed=true;box.items=[targeted]
	app._render_screen();await frames();await open_box(id);await select_item(id,str(targeted.uid))
	await click(target("ExtractionMove_"+str(targeted.uid)))
	var destination_grid=target("ExtractionGrid_search_bag")
	await click(target("ExtractionRotate_"+str(targeted.uid)))
	var source_before:Array=box.items.duplicate(true)
	await click_at(destination_grid.global_position+(Vector2(5,4)+Vector2(.5,.5))*destination_grid.cell)
	check(x.run().bag.is_empty() and box.items==source_before and destination_grid.placement_mode,"out-of-bounds targeted pickup keeps source and bag intact")
	await click_at(destination_grid.global_position+(Vector2(4,1)+Vector2(.5,.5))*destination_grid.cell)
	check(x.run().bag.size()==1 and x.run().bag[0].uid==targeted.uid and x.run().bag[0].x==4 and x.run().bag[0].y==1 and x.run().bag[0].rotated,"container item lands in the exact chosen rotated cell")
	check(box.items.is_empty(),"targeted pickup removes source UID once")
	await capture("targeted-pickup")
	await click(target("ExtractionCloseContainer"))
	# Regression for the real fragmented shape that first-fit used to reject.
	x.run().bag=[]
	var packing_ids:Array=[]
	for position in [Vector2i(4,3),Vector2i(1,0),Vector2i(3,0),Vector2i(2,2)]:
		var pack:Dictionary=x._make_item("medkit");pack.revealed=true;pack.x=position.x;pack.y=position.y
		x.run().bag.append(pack);packing_ids.append(str(pack.uid))
	var egg:Dictionary=x._make_item("dragon_egg");egg.revealed=true;box.items=[egg]
	app._render_screen();await frames();await open_box(id);await select_item(id,str(egg.uid))
	await capture("fragmented-before")
	await click(target("ExtractionPickup_"+str(egg.uid)))
	check(x.run().bag.size()==5 and x.run().bag.any(func(item):return item.uid==egg.uid),"real pickup solves four 2x2 medicines plus a 3x3 egg")
	for uid in packing_ids:check(x.run().bag.any(func(item):return item.uid==uid),"repacking preserves each existing medicine UID")
	for item in x.run().bag:check(x._fits(x.run().bag,item,x.dimensions("bag")),"result packing is in bounds and has no overlaps")
	await capture("fragmented-packed")
	await click(target("ExtractionCloseContainer"))
	# Protected cheap supplies remain protected automatically; explicit exchange can choose them.
	app.extraction_reduced_motion=false
	x.run().bag=[]
	for i in dim.x*dim.y:
		var cheap_med:Dictionary=x._make_item("bandage");cheap_med.revealed=true
		x._place(x.run().bag,cheap_med,dim)
	var outgoing:String=x.run().bag[0].uid
	var chosen_gold:Dictionary=x._make_item("gold_watch");chosen_gold.revealed=true;box.items=[chosen_gold]
	app._render_screen();await frames();await open_box(id)
	var protected_before:Array=x.run().bag.duplicate(true)
	await click(target("ExtractionSmartLoot"))
	check(x.run().bag==protected_before and target("ExtractionSmartConfirm")==null,"automatic exchange keeps protected supplies untouched")
	await select_item(id,str(chosen_gold.uid));await click(target("ExtractionManualExchange_"+str(chosen_gold.uid)))
	var correct_appraisal:bool=false
	var appraised_text:String=load("res://scripts/ui/extraction_view.gd")._money(x.item_value(chosen_gold))+" 金币"
	for label in target("ExtractionSearchDetail").find_children("*","Label",true,false):
		if appraised_text in label.text:correct_appraisal=true
	check(correct_appraisal,"manual exchange displays the incoming UID's actual appraised value")
	var exchange_grid=target("ExtractionGrid_search_bag")
	check(exchange_grid.multi_select,"manual exchange enters explicit bag selection")
	await select_bag(outgoing)
	check(not target("ExtractionManualExchangeConfirm").disabled,"choosing one protected supply makes exact exchange available")
	await capture("manual-exchange-preview")
	var flight_observations:Array=[]
	var observe_flight:Callable=func(node:Node):
		if not node is TextureRect:return
		# _icon adds its node before assigning the transfer UID name.
		var inspect_name:Callable=func():
			if str(node.name)=="ExtractionTransfer_"+str(chosen_gold.uid):
				flight_observations.append({"uid":str(chosen_gold.uid),"ignore":node.mouse_filter==Control.MOUSE_FILTER_IGNORE})
		node.renamed.connect(inspect_name,CONNECT_ONE_SHOT)
	self.node_added.connect(observe_flight)
	await click(target("ExtractionManualExchangeConfirm"))
	self.node_added.disconnect(observe_flight)
	check(flight_observations.size()==1 and flight_observations[0].ignore,"manual exchange creates one exact incoming UID flight without blocking input")
	check(x.run().bag.any(func(item):return item.uid==chosen_gold.uid) and not x.run().bag.any(func(item):return item.uid==outgoing),"manual exchange transfers only the chosen bag UID")
	check(box.items.any(func(item):return item.uid==outgoing),"manually exchanged supply remains recoverable in source")
	await capture("manual-exchange-done")
	# A deliberate lower-value exchange is allowed, but cancellation is inert.
	await select_item(id,outgoing);await click(target("ExtractionManualExchange_"+outgoing))
	await select_bag(str(chosen_gold.uid))
	check(not target("ExtractionManualExchangeConfirm").disabled,"explicit lower-value exchange remains available")
	var negative_label:bool=false
	for label in target("ExtractionManualExchangePreview").find_children("*","Label",true,false):
		if label.text.begins_with("背包价值 -"):negative_label=true
	check(negative_label,"lower-value exchange shows an explicit negative value change")
	var cancel_bag:Array=x.run().bag.duplicate(true);var cancel_source:Array=box.items.duplicate(true)
	await click(target("ExtractionManualExchangeCancel"))
	check(x.run().bag==cancel_bag and box.items==cancel_source,"cancelling exchange preserves both inventories exactly")
	await select_item(id,outgoing);await click(target("ExtractionManualExchange_"+outgoing));await select_bag(str(chosen_gold.uid))
	await click(target("ExtractionManualExchangeConfirm"))
	check(x.run().bag.any(func(item):return item.uid==outgoing) and box.items.any(func(item):return item.uid==chosen_gold.uid),"confirmed lower-value exchange honors the player's exact selection")
	await click(target("ExtractionCloseContainer"))
	app.extraction_reduced_motion=true
	for resolution in [Vector2i(2340,1080),Vector2i(1920,1080),Vector2i(1280,720)]:
		root.size=resolution;x.run().bag=[]
		for i in 15:
			var quick:Dictionary=x._make_item("bandage");quick.revealed=true
			x._place(x.run().bag,quick,x.dimensions("bag"))
		for unit in x.run().party:unit.currentHp=1
		var quick_uid:String=x.run().bag[0].uid
		app._render_screen();await frames(12)
		await click(target("ExtractionQuickSupplies"))
		visible_control(target("ExtractionSupplyClose"),str(resolution)+" fixed supplies return action")
		await capture("quick-supplies-"+str(resolution.x))
		await click(target("ExtractionQuickUse_"+quick_uid))
		check(not x.run().bag.any(func(item):return item.uid==quick_uid),"quick supply consumes exact UID")
		check(target("ExtractionQuickUse_"+quick_uid)==null,"quick supply removes the consumed UID button")
		visible_control(target("ExtractionSupplyClose"),str(resolution)+" fixed return after using supply")
		await click(target("ExtractionSupplyClose"))
		check(app.overlay.get_child_count()==0,"real return closes supplies")
	app.queue_free();await frames();await create_timer(.3).timeout
	print("LOOT V24: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
