extends "res://tests/test_loot_v24_interactions.gd"
func run() -> void:
	root.size=Vector2i(1920,1080)
	app=load("res://main.tscn").instantiate();root.add_child(app);await frames(12)
	var x=app.model.extraction
	x.state().stash=[];x.state().collection=["wire"]
	var ids:Dictionary={}
	for key in ["gold_low","gold_high","dragon_egg","pocket_book","medkit","scope"]:
		var item_id:String="gold_watch" if key.begins_with("gold_") else key
		var item:Dictionary={"uid":app.model._uid("collection_test"),"itemId":item_id,"revealed":true,"rotated":false,"x":0,"y":0,"appraisalRisk":5 if key=="gold_high" else 0}
		x._place(x.state().stash,item,x.dimensions("stash"));ids[key]=item.uid
	app.extraction_panel="stash";app.navigate("extraction");await frames()
	await click(target("ExtractionTab_shop"))
	for category in ["all","armor","backpack","equipment","consumable","key"]:
		await click(target("ExtractionShopFilter_"+category))
		var category_count:int=0
		for item_id in x.data.items:
			var definition:Dictionary=x.item_def(str(item_id))
			if int(definition.get("buyPrice",0))<=0:continue
			var expected_category:String=str(definition.get("slot","")) if str(definition.get("slot","")) in ["armor","backpack"] else str(definition.get("kind",""))
			var should_show:bool=category=="all" or category==expected_category
			check((target("ExtractionBuy_"+str(item_id))!=null)==should_show,"supply filter "+category+" includes exactly its category: "+str(item_id))
			if should_show:
				category_count+=1
				check(target("ExtractionSupplyEffect_"+str(item_id)).text==str(definition.description),"filtered supply retains its precise effect before purchase")
		check(category_count>0,"each visible filter has actual supplies")
	await click(target("ExtractionTab_stash"))
	var stash_before:Array=x.state().stash.duplicate(true)
	await click(target("ExtractionCollectAll"))
	visible_control(target("ExtractionCollectAllConfirm"),"bulk collection confirmation")
	check(x.state().stash==stash_before,"collection preview does not consume any asset")
	await capture("bulk-collection-preview")
	await click(target("ExtractionBulkCancel"))
	check(x.state().stash==stash_before,"collection cancellation preserves all duplicates")
	await click(target("ExtractionCollectAll"));await click(target("ExtractionCollectAllConfirm"))
	check(x.state().collection.has("gold_watch") and x.state().collection.has("dragon_egg"),"bulk collection records eligible gold and red types")
	check(not x.state().stash.any(func(item):return item.uid==ids.gold_low or item.uid==ids.dragon_egg),"collection consumes one lower-value instance of each new type")
	check(x.state().stash.any(func(item):return item.uid==ids.gold_high),"collection preserves the more valuable duplicate")
	for key in ["pocket_book","medkit","scope"]:check(x.state().stash.any(func(item):return item.uid==ids[key]),"collection preserves ineligible "+key)
	await click(target("ExtractionCollectAll"))
	check(target("ExtractionCollectAllConfirm").disabled,"already collected types cannot be consumed again")
	await click(target("ExtractionBulkCancel"));await click(target("ExtractionTab_collection"))
	var eligible:int=0
	for id in x.data.items:
		var definition:Dictionary=x.item_def(str(id))
		if int(definition.rarity)>=4:eligible+=1;check(target("ExtractionCollection_"+str(id))!=null,"gold or red type has a collection card")
		else:check(target("ExtractionCollection_"+str(id))==null,"ordinary type is excluded from rare collection UI")
	check(target("ExtractionCollectionProgress").text=="金红珍藏  2 / %d"%eligible,"progress counts actual rare types and ignores old ordinary collection entries")
	var lit=target("ExtractionCollection_gold_watch").find_child("CollectionArt",true,false)
	check(lit.texture!=null and lit.modulate==Color.WHITE,"collected item artwork is visibly lit")
	var dark
	for id in x.data.items:
		if int(x.item_def(str(id)).rarity)>=4 and not x.state().collection.has(str(id)):
			dark=target("ExtractionCollection_"+str(id)).find_child("CollectionArt",true,false);break
	check(dark!=null and dark.modulate.r<.2 and dark.modulate.g<.2 and dark.modulate.b<.2,"undiscovered item artwork remains a dark silhouette")
	await capture("rare-collection-lit-locked")
	await click(target("ExtractionTab_stash"))
	check(x.buy_keys("key_ruins",1).get("success",false),"real independent key fixture")
	check(x.buy_supply("armor_1").get("success",false),"real wearable fixture purchase")
	check(x.set_utility_slot("armor",x.state().stash.back().uid).get("success",false),"real fixture moves armor to equipped slot")
	var keyring_before:Array=x.state().keyring.duplicate(true)
	var utility_before:Dictionary=x.state().utility.duplicate(true)
	var expected:int=0
	for item in x.state().stash:expected+=x.item_value(item)
	var wallet:int=app.model.state.resources.gold
	stash_before=x.state().stash.duplicate(true)
	app._render_screen();await frames();await click(target("ExtractionSellAll"))
	visible_control(target("ExtractionSellAllConfirm"),"sell-all confirmation remains reachable")
	await capture("sell-all-preview")
	await click(target("ExtractionBulkCancel"))
	check(x.state().stash==stash_before and app.model.state.resources.gold==wallet,"sell-all cancellation preserves inventory and gold")
	await click(target("ExtractionSellAll"));await click(target("ExtractionSellAllConfirm"))
	check(x.state().stash.is_empty() and app.model.state.resources.gold==wallet+expected,"explicit sell-all clears stash and credits the exact whole-stash value")
	check(x.state().keyring==keyring_before and x.state().utility==utility_before,"sell-all preserves worn gear and independent keys")
	app.queue_free();await frames();await create_timer(.3).timeout
	print("COLLECTION V24: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
