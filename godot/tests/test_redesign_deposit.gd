extends "res://tests/test_redesign_loot_interactions.gd"
func run() -> void:
	root.size=Vector2i(1920,1080)
	app=load("res://main.tscn").instantiate();root.add_child(app);await frames(12)
	app.extraction_sound=false
	app.model.rng.seed=2
	var x=app.model.extraction
	check(x.start_run(0).success,"start deposit interaction fixture")
	for room in x.route_options():
		if room.type=="cache":x.enter_room(room.id);break
	# Isolate the UI transaction in a relay room; map reachability has separate real-map tests.
	x.run().room.type="relay";x.run().room.name="远征寄存站";x.run().room.depositUsed=false
	for room in x.run().map.rooms:
		if room.id==x.run().room.id:room.type="relay"
	x.run().bag=[]
	var original_ids:Array=[]
	for i in 26:
		var item:Dictionary=x._make_item("diamond_ring");item.revealed=true
		x._place(x.run().bag,item,x.dimensions("bag"));original_ids.append(item.uid)
	app.model.state.resources.gold=10000
	app.navigate("extraction");await frames()
	await click(target("ExtractionDepositPreview"))
	check(target("ExtractionDepositBag")!=null,"relay opens actual manual-selection bag")
	var grid=target("ExtractionDepositBag")
	for item in grid.items:
		await click_at(grid.global_position+grid.item_rect(item).get_center())
	check(target("ExtractionDepositConfirm").disabled,"twenty-six one-cell items cannot fit 5x5 and confirmation is disabled")
	check(x.run().bag.size()==26,"over-limit manual selection transfers nothing")
	await capture("deposit-over-limit")
	var omitted:Dictionary=grid.items[25]
	await click_at(grid.global_position+grid.item_rect(omitted).get_center())
	check(not target("ExtractionDepositConfirm").disabled,"deselecting twenty-sixth item enables valid twenty-five-cell deposit")
	var plan:Dictionary=app.overlay.get_meta("deposit_plan")
	var chosen:Array=plan.uids.duplicate()
	check(int(plan.width)==5 and int(plan.height)==5,"actual quoted parcel is five by five physical cells")
	check(chosen.size()==25 and not chosen.has(omitted.uid),"preview follows exact manually selected UIDs")
	var preview=target("ExtractionGrid_deposit")
	check(preview!=null and preview.items.size()==25,"preview renders all twenty-five selected instances")
	if preview!=null:
		for i in preview.items.size():
			check(preview.textures.has(str(preview.items[i].itemId)),"preview UID has a loaded icon")
			for j in range(i+1,preview.items.size()):
				check(not preview.item_rect(preview.items[i]).intersects(preview.item_rect(preview.items[j])),"different preview UIDs occupy non-overlapping visible cells")
	await capture("deposit-selected")
	var before_gold:int=app.model.state.resources.gold
	await click(target("ExtractionDepositConfirm"))
	check(app.overlay.get_child_count()==0,"successful deposit closes confirmation modal")
	check(app.model.state.resources.gold==before_gold-int(plan.fee),"confirm charges displayed quote once")
	check(x.run().bag.size()==1 and x.run().bag[0].uid==omitted.uid,"unselected source item remains in bag")
	for uid in chosen:
		check(x.state().stash.filter(func(item):return item.uid==uid).size()==1,"selected UID appears once in warehouse")
	check(x.run().room.depositUsed,"relay records completed deposit")
	check(target("ExtractionDepositPreview")!=null and target("ExtractionDepositPreview").disabled,"used relay cannot resubmit deposit")
	app.queue_free();await frames();await create_timer(.3).timeout
	print("DEPOSIT TOUCH: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
