extends "res://tests/test_extraction_ui.gd"
const View=preload("res://scripts/ui/extraction_view.gd")
func capture(label:String)->void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://").path_join("../validation/loot-recovery-ui").path_join(label+".png"))
func run()->void:
	root.size=Vector2i(960,540)
	app=load("res://main.tscn").instantiate();root.add_child(app);await frames(12)
	app.extraction_sound=false;app.music_enabled=false;app.extraction_auto_pick=false;app.extraction_reduced_motion=false
	app.navigate("extraction");check(choose_resource_room(),"generated room");await frames(8);await capture("scene-960")
	var ex=app.model.extraction
	var box:Dictionary=ex._find_container(str(ex.containers()[0].id))
	var entries:Array=[]
	var ids=["thunder_city_boundary","general_crown_1","general_lens_1","thunder_city_badge"]
	var positions=[Vector2i(0,0),Vector2i(1,0),Vector2i(3,0),Vector2i(3,1)]
	for i in ids.size():
		var item:Dictionary=ex._make_item(ids[i]);item.x=positions[i].x;item.y=positions[i].y;item.revealed=false;entries.append(item)
	var selected_uid:String=str(entries[0].uid)
	box.items=entries;box.revealed=0
	View._open_container(app,str(box.id));await frames(2);await capture("hidden-960")
	await create_timer(12).timeout
	check(not app.extraction_searching,"search completes");await capture("revealed-960")
	View._select_container_item(app,str(box.id),selected_uid);await frames(5);await capture("detail-960")
	var detail=app.overlay.find_child("ExtractionSearchDetail",true,false)
	check("居民返回街上" in texts(detail),"long description visible")
	for n in ["ExtractionCloseContainer","ExtractionTakeAll","ExtractionSmartLoot"]:
		var b=button(n);check(b!=null and b.is_visible_in_tree() and Rect2(Vector2.ZERO,root.size).encloses(b.get_global_rect()),"reachable "+n)
	var sc=detail.get_parent().get_parent()
	var stress=Label.new();stress.text="测试滚动区域\n".repeat(18);detail.add_child(stress);detail.move_child(stress,1);await frames(5)
	if sc is ScrollContainer:sc.scroll_vertical=999
	await frames(5);check(sc is ScrollContainer and sc.scroll_vertical>0,"overflow scroll");await capture("stress-scrolled-960")
	stress.queue_free();await frames(5);sc.scroll_vertical=0
	root.size=Vector2i(2048,945);await frames(8);await capture("detail-wide-2048")
	root.size=Vector2i(960,540);await frames(8)
	press("ExtractionTakeAll");await frames(8);check(ex.run().bag.size()==4,"all four acquired")
	View._select_search_bag_item(app,str(box.id),selected_uid);await frames(5);await capture("search-bag-detail-960")
	press("ExtractionCloseContainer");await frames(4);press("ExtractionTab_bag");await frames(8);app.extraction_scope="bag";app.extraction_selected=selected_uid;app._render_screen();await frames(8);await capture("bag-960")
	print("RECOVERY RENDER QA checks=",checks," failures=",failures)
	app.queue_free();await frames();quit(0 if failures.is_empty() else 1)
