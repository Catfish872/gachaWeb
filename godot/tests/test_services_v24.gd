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
	for key_id in x.data.items:
		var definition:Dictionary=x.item_def(str(key_id))
		if definition.get("kind","")!="key":continue
		check(int(definition.buyPrice)==500,"every purchasable key has the requested fixed price")
		var purchase=target("ExtractionBuyKey_"+str(key_id))
		check(purchase!=null and purchase.text.contains("500"),"each actual keyring purchase control shows its price")
	check(int(x.item_def("key_ruins").buyPrice)==500,"key purchase price is the requested five hundred gold")
	check(target("ExtractionBuyKey_key_ruins").text.contains("500"),"real purchase action shows five hundred gold before purchase")
	await click(target("ExtractionBuyKey_key_ruins"));await click(target("ExtractionBuyKey_key_ruins"))
	check(x.state().keyring.size()==count_before+2,"two real purchases add two keys to existing stack")
	check(app.model.state.resources.gold==wallet_before-1000,"key purchases charge the exact external gold price")
	check(x.run().bag==full_bag,"buying keys never consumes full bag cells")
	check(target("ExtractionKeyCount_key_ruins").text=="× 3","keyring visibly displays the actual stacked quantity")
	await capture("keyring-full-bag")
	await click(target("ExtractionSupplyClose"))
	check(app.overlay.get_child_count()==0,"keyring return closes the actual modal")
	# The old 60% liquidation action is deliberately removed, not replaced by a silent payout.
	for kind in ["workshop","relay","boss"]:
		x.run().room.type=kind;x.run().room.guardPending=false
		x.run().phase="boss_exit" if kind=="boss" else "room"
		app._render_screen();await frames()
		check(target("ExtractionSalvageOpen")==null,"no removed salvage entry at "+kind)
		check(not x.can_salvage(),"legacy salvage capability remains disabled at "+kind)
		var preserved:Dictionary=app.model.state.duplicate(true)
		var uids:Array=x.run().bag.map(func(item):return str(item.uid))
		check(not x.salvage_quote(uids).get("success",false),"legacy salvage preview cannot authorize mid-run sale")
		check(not x.salvage_items(uids,"legacy-plan").get("success",false) and app.model.state==preserved,"legacy liquidation command rejects atomically and never credits gold")
		if kind=="workshop":check(target("ExtractionDepositPreview")==null,"ordinary workshop does not acquire a parcel service")
		else:check(target("ExtractionDepositPreview")!=null,"relay and every boss exit expose the physical parcel service")
	app.queue_free();await frames();await create_timer(.3).timeout
	print("SERVICES V24: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
