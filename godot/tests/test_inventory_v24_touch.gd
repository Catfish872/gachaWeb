extends "res://tests/test_loot_v24_interactions.gd"
func touch_tap(point:Vector2) -> void:
	for pressed in [true,false]:
		var event:=InputEventScreenTouch.new();event.index=0;event.position=point;event.pressed=pressed
		root.push_input(event,true)
	await frames()
func scroll_edge(scroll:ScrollContainer,to_bottom:bool) -> void:
	for attempt in 8:
		var bar=scroll.get_v_scroll_bar()
		if (to_bottom and bar.value>=bar.max_value-bar.page-1) or (not to_bottom and bar.value<=1):break
		var rect:=scroll.get_global_rect()
		var start:=rect.position+Vector2(rect.size.x-24,rect.size.y*(.8 if to_bottom else .2))
		var finish:=rect.position+Vector2(rect.size.x-24,rect.size.y*(.2 if to_bottom else .8))
		await touch_drag_between(start,finish)
	await frames(10)
func run() -> void:
	root.size=Vector2i(2340,1080)
	app=load("res://main.tscn").instantiate();root.add_child(app);await frames(12)
	app.extraction_reduced_motion=false
	var x=app.model.extraction
	x.state().stash=[]
	var golden:Dictionary={"uid":app.model._uid("stash_test"),"itemId":"gold_watch","revealed":true,"rotated":false,"x":5,"y":8}
	var book:Dictionary={"uid":app.model._uid("stash_test"),"itemId":"pocket_book","revealed":true,"rotated":false,"x":6,"y":9}
	var large:Dictionary={"uid":app.model._uid("stash_test"),"itemId":"medkit","revealed":true,"rotated":false,"x":0,"y":0}
	x.state().stash=[golden,book,large]
	app.extraction_panel="stash";app.navigate("extraction");await frames(12)
	var grid=target("ExtractionGrid_stash")
	var scroll=grid.get_parent()
	while not scroll is ScrollContainer:scroll=scroll.get_parent()
	check(scroll.get_v_scroll_bar().max_value>scroll.get_v_scroll_bar().page,"real stash has scrollable geometry")
	await scroll_edge(scroll,true)
	check(scroll.scroll_vertical>0,"real finger drag scrolls warehouse")
	var observed:Dictionary={"uids":[]}
	grid.item_selected.connect(func(uid):observed.uids.append(str(uid)))
	for item in [golden,book]:
		var point:Vector2=grid.global_position+grid.visual_rect(item).get_center()
		var before_signals:int=observed.uids.size()
		await click_at(point)
		check(observed.uids.size()==before_signals+1 and observed.uids.back()==str(item.uid),"mouse emits exactly the visible UID once")
		check(str(app.extraction_selected)==str(item.uid),"mouse click selects the visible scrolled exact UID "+str(item.itemId))
		before_signals=observed.uids.size()
		await touch_tap(point)
		check(observed.uids.size()==before_signals+1 and observed.uids.back()==str(item.uid),"finger emits exactly the visible UID once")
		check(str(app.extraction_selected)==str(item.uid),"finger tap selects the visible scrolled exact UID "+str(item.itemId))
	await click(target("ExtractionStashMulti"))
	check(grid.multi_select and grid.selected_uid.is_empty(),"entering multiselect clears misleading single-item focus")
	await touch_tap(grid.global_position+grid.visual_rect(book).get_center())
	check(grid.selected_uids==[str(book.uid)],"only the tapped book UID is checked")
	await touch_tap(grid.global_position+grid.visual_rect(golden).get_center())
	check(grid.selected_uids.size()==2 and grid.selected_uids.has(str(golden.uid)) and grid.selected_uids.has(str(book.uid)),"gold and book have actual checked UIDs")
	var checked_before:Array=grid.selected_uids.duplicate()
	var emulated_point:Vector2=grid.global_position+grid.visual_rect(golden).get_center()
	for pressed in [true,false]:
		var emulated:=InputEventMouseButton.new();emulated.device=-1;emulated.button_index=MOUSE_BUTTON_LEFT;emulated.pressed=pressed;emulated.position=emulated_point;emulated.global_position=emulated_point
		root.push_input(emulated,true)
	await frames()
	check(grid.selected_uids==checked_before,"touch-generated emulated mouse cannot toggle the same selection twice")
	await capture("stash-gold-book-checked")
	# Crossing the same item twice during one gesture toggles it only once.
	var origin:Vector2=grid.global_position+grid.visual_rect(golden).get_center()
	var destination:Vector2=grid.global_position+grid.visual_rect(book).get_center()
	var down:=InputEventScreenTouch.new();down.index=0;down.position=origin;down.pressed=true;root.push_input(down,true)
	await frames(1)
	for point in [destination,origin]:
		var drag:=InputEventScreenDrag.new();drag.index=0;drag.position=point;drag.relative=point-origin;root.push_input(drag,true);await frames(1)
	var up:=InputEventScreenTouch.new();up.index=0;up.position=origin;up.pressed=false;root.push_input(up,true);await frames()
	check(grid.selected_uids.is_empty(),"a repeated sweep crossing each selected item toggles each once")
	await click(target("ExtractionStashMulti"));await scroll_edge(scroll,false)
	await touch_tap(grid.global_position+grid.visual_rect(large).get_center())
	check(str(app.extraction_selected)==str(large.uid),"finger tap selects a visible 2x2 item after scrolling back")
	await click_at(grid.global_position+grid.visual_rect(large).get_center())
	check(str(app.extraction_selected)==str(large.uid),"mouse click selects the same 2x2 UID")
	# Keep the animation's visible and destination positions far apart.
	golden.x=6;golden.y=1;book.x=4;book.y=0
	app._render_screen();await frames(12);grid=target("ExtractionGrid_stash")
	var sort_button=target("ExtractionSort_stash")
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.position=sort_button.get_global_rect().get_center();event.global_position=event.position
		root.push_input(event,true)
	await process_frame
	var moving:Dictionary={}
	for item in grid.items:
		if item.uid==golden.uid:moving=item
	var seen:Rect2=grid.visual_rect(moving)
	check(grid.movements.has(str(golden.uid)) and not grid.item_rect(moving).has_point(seen.get_center()),"sorting has a visible item away from its final cell")
	var visible_point:Vector2=grid.global_position+seen.get_center()
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.position=visible_point;event.global_position=visible_point
		root.push_input(event,true)
	await frames()
	check(str(app.extraction_selected)==str(golden.uid),"tapping the artwork while sorting selects that visible UID, not an invisible destination")
	app.queue_free();await frames();await create_timer(.3).timeout
	print("INVENTORY V24 TOUCH: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
