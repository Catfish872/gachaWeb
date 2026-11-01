extends "res://tests/test_loot_v24_interactions.gd"
func run() -> void:
	root.size=Vector2i(1920,1080)
	app=load("res://main.tscn").instantiate();root.add_child(app);await frames(12)
	app.extraction_auto_pick=false;app.extraction_sound=false
	var x=app.model.extraction
	app.model.rng.seed=2;x.start_run(0)
	for room in x.route_options():
		if room.type=="cache":x.enter_room(room.id);break
	# Isolated service UI fixture; model suites verify real service access paths.
	x.run().room.type="relay"
	for room in x.run().map.rooms:
		if room.id==x.run().room.id:room.type="relay"
	var box:Dictionary=x._find_container(x.containers()[0].id)
	fill_wire(x,x.dimensions("bag").x*x.dimensions("bag").y)
	var full_bag:Array=x.run().bag.duplicate(true)
	var found_key:Dictionary=x._make_item("key_ruins");found_key.revealed=true;box.items=[found_key]
	app.navigate("extraction");await frames();await open_box(str(box.id));await select_item(str(box.id),str(found_key.uid))
	await click(target("ExtractionPickup_"+str(found_key.uid)))
	check(x.run().bag==full_bag,"full bag stays byte-identical when a key is picked up")
	check(x.state().keyring.any(func(item):return item.uid==found_key.uid),"exact picked-up key UID enters independent keyring")
	check(box.items.is_empty(),"key pickup removes exact source instance")
	await click(target("ExtractionCloseContainer"))
	var wallet_before:int=app.model.state.resources.gold
	var count_before:int=x.state().keyring.size()
	await click(target("ExtractionKeyring"))
	for resolution in [Vector2i(2340,1080),Vector2i(1920,1080),Vector2i(1280,720)]:
		root.size=resolution;await frames(12)
		visible_control(target("ExtractionSupplyClose"),str(resolution)+" fixed keyring return")
	await click(target("ExtractionBuyKey_key_ruins"));await click(target("ExtractionBuyKey_key_ruins"))
	check(x.state().keyring.size()==count_before+2,"two real purchases add two keys to existing stack")
	check(app.model.state.resources.gold==wallet_before-2*int(x.item_def("key_ruins").buyPrice),"key purchases charge the exact external gold price")
	check(x.run().bag==full_bag,"buying keys never consumes full bag cells")
	check(target("ExtractionKeyCount_key_ruins").text=="× 3","keyring visibly displays the actual stacked quantity")
	await capture("keyring-full-bag")
	await click(target("ExtractionSupplyClose"))
	check(app.overlay.get_child_count()==0,"keyring return closes the actual modal")
	x.run().bag=[]
	var instances:Dictionary={}
	for item_id in ["wire","bandage","diamond_ring","scope"]:
		var item:Dictionary=x._make_item(item_id);item.revealed=true;x._place(x.run().bag,item,x.dimensions("bag"));instances[item_id]=item.uid
	app._render_screen();await frames();await click(target("ExtractionSalvageOpen"))
	check(target("ExtractionSalvageConfirm").disabled,"empty salvage selection cannot commit")
	await click(target("ExtractionSalvageLow"))
	check(target("ExtractionSalvageBag").selected_uids==[str(instances.wire)],"ordinary-loot shortcut excludes medicine, gear and rare treasure")
	visible_control(target("ExtractionSalvageConfirm"),"fixed salvage confirmation")
	visible_control(target("ExtractionSalvageCancel"),"fixed salvage return")
	var untouched:Array=x.run().bag.duplicate(true)
	wallet_before=app.model.state.resources.gold
	await capture("salvage-preview")
	await click(target("ExtractionSalvageCancel"))
	check(x.run().bag==untouched and app.model.state.resources.gold==wallet_before,"salvage cancellation preserves inventory and wallet")
	await click(target("ExtractionSalvageOpen"));await click(target("ExtractionSalvageLow"))
	var quote:Dictionary=app.overlay.get_meta("salvage_plan",{})
	check(quote.get("success",false),"actual selected salvage preview is valid")
	await click(target("ExtractionSalvageConfirm"))
	check(app.model.state.resources.gold==wallet_before+int(quote.value),"salvage credits exact preview gold once")
	check(x.run().bag.size()==3 and not x.run().bag.any(func(item):return item.uid==instances.wire),"salvage consumes only the explicitly selected UID")
	for item_id in ["bandage","diamond_ring","scope"]:check(x.run().bag.any(func(item):return item.uid==instances[item_id]),"salvage preserves unselected "+item_id)
	check(app.overlay.get_child_count()==0,"successful salvage closes preview")
	await click(target("ExtractionSalvageOpen"));await click(target("ExtractionSalvageSpace"))
	check(target("ExtractionSalvageBag").selected_uids.is_empty() and target("ExtractionSalvageConfirm").disabled,"space shortcut selects nothing when enough free space already exists")
	await click(target("ExtractionSalvageCancel"))
	x.run().bag=[]
	var protected_ids:Array=[];var cheap_ids:Array=[]
	for item_id in ["bandage","medkit","blade","gold_watch"]:
		var protected:Dictionary=x._make_item(item_id);protected.revealed=true
		check(x._place(x.run().bag,protected,x.dimensions("bag")),"place protected service fixture")
		protected_ids.append(str(protected.uid))
	for i in 21:
		var loot:Dictionary=x._make_item("wire");loot.revealed=true;loot.appraisalRisk=0 if i<10 else 5
		check(x._place(x.run().bag,loot,x.dimensions("bag")),"fill bag with priced loot instances")
		if i<10:cheap_ids.append(str(loot.uid))
	check(not x._place(x.run().bag,x._make_item("wire"),x.dimensions("bag")),"service policy fixture fills every physical cell")
	var policy_bag:Array=x.run().bag.duplicate(true);wallet_before=app.model.state.resources.gold
	app._render_screen();await frames();await click(target("ExtractionSalvageOpen"));await click(target("ExtractionSalvageSpace"))
	var space_selection:Array=target("ExtractionSalvageBag").selected_uids.duplicate()
	check(space_selection.size()==9,"space shortcut reaches exactly nine freed cells in a full thirty-cell bag")
	for uid in space_selection:check(uid in cheap_ids and uid not in protected_ids,"space shortcut chooses lowest per-cell appraisals and excludes protected categories")
	check(target("ExtractionSalvageCapacity").text=="腾出 9 格 · 空余 9 / 30 格","space preview displays exact physical capacity")
	check(x.run().bag==policy_bag and app.model.state.resources.gold==wallet_before,"space shortcut is only a selection preview")
	await capture("salvage-space-preview")
	await click(target("ExtractionSalvageAll"))
	var all_selection:Array=target("ExtractionSalvageBag").selected_uids.duplicate()
	check(all_selection.size()==22 and all_selection.has(str(protected_ids[3])),"all-loot shortcut includes rare treasure and all ordinary loot")
	for i in 3:check(not all_selection.has(str(protected_ids[i])),"all-loot shortcut keeps consumables and tactical gear unselected")
	check(target("ExtractionSalvageValuables").text=="含 1 件金红珍品","rare selection has an explicit count warning")
	check(x.run().bag==policy_bag and app.model.state.resources.gold==wallet_before,"all-loot shortcut never immediately sells selected items")
	await click(target("ExtractionSalvageCancel"))
	# Presentation fixture only: no commit under the synthetic boss-exit phase.
	x.run().phase="boss_exit";app._render_screen();await frames()
	await click(target("ExtractionSalvageOpen"));await click(target("ExtractionSalvageAll"))
	var boss_quote:Dictionary=app.overlay.get_meta("salvage_plan",{})
	var format_money=load("res://scripts/ui/extraction_view.gd")
	check(target("ExtractionSalvageFullValue").text=="所选物资全价 %s 金币"%format_money._money(int(boss_quote.grossValue)),"boss exit shows selected items' complete extraction value")
	check(target("ExtractionSalvagePayout").text=="%s 金币"%format_money._money(int(boss_quote.value)),"boss exit shows the exact discounted payout separately")
	var full_value_label:Label=target("ExtractionSalvageFullValue")
	var note_labels:Array=full_value_label.get_parent().find_children("*","Label",true,false)
	check(note_labels.size()>=2,"boss-exit comparison contains independent guidance and value labels")
	for label in note_labels:
		if label!=full_value_label:check(not label.get_global_rect().intersects(full_value_label.get_global_rect()),"boss-exit full value does not overlap comparison guidance")
	visible_control(target("ExtractionSalvageConfirm"),"boss-exit fixed confirm")
	visible_control(target("ExtractionSalvageCancel"),"boss-exit fixed return")
	await capture("salvage-boss-exit-comparison")
	await click(target("ExtractionSalvageCancel"));x.run().phase="room"
	check(x.run().bag==policy_bag and app.model.state.resources.gold==wallet_before,"boss comparison cancellation preserves all assets")
	app.queue_free();await frames();await create_timer(.3).timeout
	print("SERVICES V24: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
