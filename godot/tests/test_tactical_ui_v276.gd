extends "res://tests/test_lantern_journey_ui_v270.gd"
const OUT276="res://validation/v276-focused/"
func capture(label:String)->void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT276+label+".png")
func gear(uid:String,id:String)->Dictionary:return {"uid":uid,"itemId":id,"x":0,"y":0,"rotated":false,"revealed":true}
func run()->void:
	if DisplayServer.get_name()=="headless":quit(2);return
	DirAccess.make_dir_recursive_absolute(OUT276);app=load("res://main.tscn").instantiate();root.add_child(app);await frames(12);app.set_process(false)
	for resolution in [Vector2i(2048,945),Vector2i(960,540)]:
		fresh();root.size=resolution;await frames(8);var label:=str(resolution.x);var ex=app.model.extraction
		ex.state().stash=ex._packed_copy([gear("qa_guard","guardian_seal"),gear("qa_blade","blade"),gear("qa_scope","scope"),gear("qa_idle","guardian_seal")],Vector2i(10,12))
		for uid in ["qa_guard","qa_blade","qa_scope"]:ck(ex.equip_item(uid).success,"camp equips distinct gear")
		app.extraction_panel="expedition";app.navigate("extraction");await frames(10)
		var slots=app.find_child("ExtractionTacticalSlots",true,false);ck(slots!=null and slots.get_child_count()==3,"three compact tactical slots")
		var scroll=app.find_child("ExtractionPreparationScroll",true,false);scroll.ensure_control_visible(slots);await frames(6)
		for i in 3:fits(app.find_child("ExtractionTacticalSlot_"+str(i),true,false),"visible tactical slot "+str(i))
		fits(app.find_child("ExtractionPreparationActions",true,false),"prep bottom actions retained");fits(app.find_child("ExtractionStart",true,false),"departure action retained")
		await capture(label+"-tactical-preparation")
		await tap(app.find_child("ExtractionTacticalSlot_0",true,false));await frames(8)
		ck(app.extraction_panel=="stash" and "已穿戴" in text_under(app.main_body),"slot opens worn detail in warehouse")
		fits(app.find_child("ExtractionSellAll",true,false),"warehouse batch action retained")
		await capture(label+"-worn-warehouse-detail")
		await tap(app.find_child("ExtractionSellAll",true,false));await frames(6)
		ck("已穿戴装备保留" in text_under(app.overlay),"bulk preview explains worn protection")
		await tap(app.find_child("ExtractionSellAllConfirm",true,false));await frames(8)
		ck(ex.equipped_items().size()==3 and ex.state().stash.is_empty(),"UI sell-all keeps three worn UIDs and sells only idle copy")
	app.queue_free();await frames();print("TACTICAL UI V276: %d checks, %d failures"%[checks,failures]);quit(0 if failures==0 else 1)
