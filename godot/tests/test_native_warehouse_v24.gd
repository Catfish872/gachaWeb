extends "res://tests/test_loot_v24_interactions.gd"
func probe() -> Dictionary:
	var controls:Array=[]
	var state:Dictionary=app._probe_inventory(controls)
	state.controls=controls
	return state
func control_rect(state:Dictionary,name:String)->Rect2:
	for entry in state.controls:
		if entry.name==name:
			var r:Rect2=Rect2(entry.rect[0],entry.rect[1],entry.rect[2],entry.rect[3])
			check(Rect2(entry.clip[0],entry.clip[1],entry.clip[2],entry.clip[3]).encloses(r),"native target fully visible "+name)
			return r
	check(false,"native target exists "+name)
	return Rect2()
func run()->void:
	root.size=Vector2i(1280,720)
	app=load("res://main.tscn").instantiate();app.set_script(load("res://tools/android/runtime_probe.gd"));root.add_child(app);await frames(12);app.set_process(false)
	app.navigate("extraction");await frames()
	await click(target("ExtractionTab_shop"));await click(target("ExtractionShopFilter_consumable"))
	for id in ["bandage","medkit"]:await click(target("ExtractionBuy_"+id))
	await click(target("ExtractionTab_stash"))
	var before:Dictionary=app.model.state.duplicate(true)
	var observation:Dictionary=probe()
	check(observation.items.size()==2,"native setup uses exactly two real purchases")
	check(app.model.state==before,"readonly inventory probe never changes model")
	await click(target("ExtractionStashMulti"))
	var selected:Array=[]
	for item in observation.items:
		var rect:Rect2=control_rect(probe(),"ExtractionInventoryItem_"+str(item.uid))
		var point:Vector2=root.get_screen_transform().affine_inverse()*rect.get_center()
		await click_at(point);selected.append(item.uid)
		check(probe().selected_uids==selected,"real native target selects exact UID once")
	await click(target("ExtractionStashMulti"));check(not probe().multi_select and probe().selected_uids.is_empty(),"explicit cancel clears native selection")
	var medicine:Dictionary={}
	for item in observation.items:
		if item.item_id=="medkit":medicine=item
	var rect:Rect2=control_rect(probe(),"ExtractionInventoryItem_"+str(medicine.uid))
	await click_at(root.get_screen_transform().affine_inverse()*rect.get_center())
	await click(target("ExtractionMove_"+str(medicine.uid)))
	var start:Rect2=control_rect(probe(),"ExtractionInventoryCell_4_0")
	var end:Rect2=control_rect(probe(),"ExtractionInventoryCell_6_1")
	# Exact physical target rectangles used by the Android driver, transformed back for synthetic input.
	var inverse:Transform2D=root.get_screen_transform().affine_inverse()
	await touch_drag_between(inverse*start.get_center(),inverse*end.get_center())
	check(probe().placement_mode and app.model.state==before,"native rectangle drag preserves model and placement")
	var destination:Rect2=control_rect(probe(),"ExtractionInventoryCell_4_1")
	await click_at(inverse*destination.get_center())
	var after:Dictionary=probe()
	check(not after.placement_mode,"native target tap ends placement")
	for item in after.items:
		if item.uid==medicine.uid:check(item.x==4 and item.y==1,"exact medicine reaches native target cell")
		else:check(item.x==0 and item.y==0,"other purchased supply remains untouched")
	var grid=target("ExtractionGrid_stash")
	await touch_drag_between(grid.global_position+Vector2(200,150),grid.global_position+Vector2(200,130))
	await create_timer(.5).timeout
	print("V24_AFTER_VERTICAL_DRAG touch=",grid._touch_id," pressed=",grid._pressed," dragged=",grid._dragged)
	check(grid._touch_id==-1 and not grid._pressed,"scroll ownership cancels inventory pointer before next tap")
	var chosen:Array=[]
	grid.item_selected.connect(func(uid):chosen.append(uid))
	var current:Dictionary={}
	for item in grid.items:
		if item.uid==medicine.uid:current=item
	var point:Vector2=grid.global_position+grid.visual_rect(current).get_center()
	check(app._visible_control_rect(grid).has_point(point),"post-scroll tap point is inside real clipped inventory")
	for pressed in [true,false]:
		var event:=InputEventScreenTouch.new();event.index=0;event.position=point;event.pressed=pressed
		root.push_input(event,true);await frames(2)
	await frames()
	print("V24_VERTICAL_SCROLL_TOUCH touch=",grid._touch_id," pressed=",grid._pressed," selected=",chosen)
	check(chosen==[medicine.uid],"first finger tap after scrolling over inventory selects immediately")
	await click(target("ExtractionBring_"+str(medicine.uid)))
	check(app._probe_extraction().loadout_ids.has(medicine.uid),"actual carry action retains purchased UID in departure supplies")
	check(not probe().items.any(func(item):return item.uid==medicine.uid),"carried medicine leaves warehouse once")
	await click(target("ExtractionTab_expedition"));await click(target("ExtractionStart"))
	var cache_id:=""
	for room in app.model.extraction.route_options():
		if room.type=="cache":cache_id=str(room.id);break
	check(not cache_id.is_empty(),"natural native route has a reachable ordinary cache")
	var map=target("ExtractionMap")
	await click_at(map.global_position+map.room_point(cache_id))
	map=target("ExtractionMap")
	await click_at(map.global_position+map.room_point(cache_id))
	check(app.model.extraction.run().phase=="room","real map taps enter natural cache")
	await click(target("ExtractionQuickSupplies"))
	for locked in [true,false,true]:
		await click(target("ExtractionSupplyLock_"+str(medicine.uid)))
		var supplies:Array=app._probe_extraction().supplies
		check(supplies.any(func(item):return item.uid==medicine.uid and item.exchange_locked==locked),"read-only probe observes actual lock tap on same purchased UID")
	await click(target("ExtractionSupplyClose"));await click(target("ExtractionQuickSupplies"))
	check(target("ExtractionSupplyLock_"+str(medicine.uid)).get_meta("exchange_locked",false),"exact lock persists across reopening actual supplies modal")
	await click(target("ExtractionSupplyClose"))
	app.queue_free();await frames();await create_timer(.3).timeout
	print("NATIVE WAREHOUSE V24: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
