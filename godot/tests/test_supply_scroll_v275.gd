extends "res://tests/test_lantern_journey_ui_v270.gd"
const View=preload("res://scripts/ui/extraction_view.gd")
const OUT275="res://validation/supply-scroll-focused/"
func capture(label:String)->void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT275+label+".png")
func click_named(id:String)->void:
	var button=app.find_child(id,true,false);ck(button!=null,"button present "+id)
	button.emit_signal("pressed");await frames(8)
func run()->void:
	if DisplayServer.get_name()=="headless":quit(2);return
	DirAccess.make_dir_recursive_absolute(OUT275);app=load("res://main.tscn").instantiate();root.add_child(app);await frames(12);app.set_process(false)
	for resolution in [Vector2i(960,540),Vector2i(640,960)]:
		fresh();app.shop_list_positions.clear();root.size=resolution;await frames(8);app.model.state.resources.gold=100000;app.extraction_panel="shop";app.navigate("extraction");await frames(10)
		var scroll=app.find_child("ExtractionSupplyScroll",true,false);scroll.scroll_vertical=100000;app.page_scroll.scroll_vertical=100000;await frames(6)
		var y:int=scroll.scroll_vertical;var outer:int=app.page_scroll.scroll_vertical;ck(y>0,"supply actually scrolled")
		var buys=app.find_children("ExtractionBuy_*","Button",true,false);var name:String=buys.back().name;var id:=name.trim_prefix("ExtractionBuy_");var price:int=app.model.extraction.item_def(id).buyPrice
		var gold:int=app.model.state.resources.gold
		for i in 2:
			await click_named(name);ck(app.find_child("ExtractionSupplyScroll",true,false).scroll_vertical==y,"purchase retains inner position");ck(app.page_scroll.scroll_vertical==outer,"purchase retains outer position")
		ck(app.model.state.resources.gold==gold-2*price,"two purchases charge twice exactly")
		await click_named("ExtractionShopFilter_consumable");await click_named("ExtractionShopFilter_all");ck(app.find_child("ExtractionSupplyScroll",true,false).scroll_vertical==y,"filter return restores position")
		await capture(str(resolution.x)+"-supply-retained")
		app.model.state.resources.gold=0;var snapshot:Dictionary=app.model.state.duplicate(true);await click_named(name);ck(app.model.state==snapshot,"insufficient purchase leaves state unchanged")
		app.model.state.resources.gold=100000;app.find_child(name,true,false).emit_signal("pressed");app.navigate("home");await frames(8);ck(app.current_screen=="home" and app.page_scroll.scroll_vertical==0,"old restore cannot write next page")
		app.navigate("extraction");await frames(8);View._keyring(app);await frames(8);var keys=app.find_child("ExtractionKeyringScroll",true,false);keys.scroll_vertical=100000;await frames(4);var ky:int=keys.scroll_vertical;ck(ky>0,"key list actually scrolled")
		var kb=app.find_children("ExtractionBuyKey_*","Button",true,false);var kn:String=kb.back().name;var keyid:=kn.trim_prefix("ExtractionBuyKey_");var starting:int=app.model.state.resources.gold
		for i in 2:
			await click_named(kn);ck(app.find_child("ExtractionKeyringScroll",true,false).scroll_vertical==ky,"key purchase keeps bottom")
		ck(app.model.state.resources.gold==starting-1000,"two keys exact thousand gold")
		await click_named("ExtractionSupplyClose");View._keyring(app);await frames(8);ck(app.find_child("ExtractionKeyringScroll",true,false).scroll_vertical==ky,"key reopen restores bottom")
		await capture(str(resolution.x)+"-keyring-retained");app._clear_overlay()
	app.queue_free();await frames();print("SUPPLY SCROLL: %d checks, %d failures"%[checks,failures]);quit(0 if failures==0 else 1)
