extends SceneTree
var app
var checks := 0
var failures: Array[String] = []
const SIZES := [Vector2i(1080,2400),Vector2i(1080,1920),Vector2i(720,1600),Vector2i(2400,1080),Vector2i(1920,1080)]
func _initialize() -> void:call_deferred("run")
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures.append(message);push_error("EXTRACTION UI: "+message)
func frames(count: int=5) -> void:
	for i in count:await process_frame
func descendants(node: Node) -> Array:
	var result: Array=[]
	for child in node.get_children():result.append(child);result.append_array(descendants(child))
	return result
func button(name: String) -> BaseButton:
	for node in descendants(app.overlay)+descendants(app.main_body):
		if node is BaseButton and (str(node.name)==name or str(node.name).begins_with(name)):return node
	return null
func press(name: String) -> bool:
	var b:=button(name);check(b!=null,"button "+name)
	if b==null:return false
	check(not b.disabled,"enabled "+name)
	if b.disabled:return false
	b.pressed.emit();return true
func touch(node: Control,at: Vector2,down: bool) -> void:
	var e:=InputEventScreenTouch.new();e.index=0;e.position=at;e.pressed=down;node._gui_input(e)
func drag(node: Control,at: Vector2,to: Vector2) -> void:
	touch(node,at,true)
	for i in range(1,7):
		var e:=InputEventScreenDrag.new();e.index=0;e.position=at.lerp(to,float(i)/6);e.relative=(to-at)/6;node._gui_input(e)
	touch(node,to,false)
func tap(node: Control,at: Vector2) -> void:
	touch(node,at,true);touch(node,at,false)
func texts(node: Node) -> String:
	var result:=str(node.text)+"\n" if node is Label or node is Button else ""
	for child in node.get_children():result+=texts(child)
	return result
func choose_resource_room() -> bool:
	for attempt in 50:
		if not app.model.state.extraction.run.is_empty():app.model.extraction.retreat()
		app.model.rng.seed=attempt+3
		app.model.extraction.start_run(0)
		for option in app.model.extraction.route_options():
			if option.type in ["cache","workshop","hospital","shrine"]:
				app.model.extraction.enter_room(option.id)
				app._render_screen()
				return true
	return false
func run() -> void:
	root.size=SIZES[0]
	app=load("res://main.tscn").instantiate();root.add_child(app)
	await frames(10)
	app.extraction_sound=false;app.extraction_reduced_motion=true
	app.navigate("extraction");await frames()
	check(button("ExtractionStart")!=null,"camp start")
	press("ExtractionTab_shop");await frames()
	for item_id in app.model.extraction.data.items:
		var shop_def: Dictionary=app.model.extraction.item_def(str(item_id))
		if int(shop_def.get("buyPrice",0))<=0:continue
		var buy:=button("ExtractionBuy_"+str(item_id))
		check(buy!=null,"shop lists purchasable "+str(item_id))
		check(buy!=null and buy.disabled==(int(shop_def.get("buyMinRisk",0))>int(app.model.state.extraction.unlockedDifficulty)),"shop gate "+str(item_id))

	press("ExtractionTab_expedition");await frames()
	check(not "40回合" in texts(app.main_body),"detailed rules moved to help")
	press("ExtractionHelp");await frames()
	check("40" in texts(app.overlay),"help exposes battle limit")
	app._clear_overlay()
	for unit in app.model.extraction.departure_party():
		var label=app.main_body.find_child("ExtractionPartyStats_"+str(unit.id),true,false)
		check(label!=null,"party stats visible")
		for stat in [["生命",unit.stats.maxHp],["攻击",unit.stats.atk],["防御",unit.stats.def]]:
			var expected:="%s %d" % [stat[0],int(stat[1])]
			check(label!=null and descendants(label).any(func(node):return node is Label and node.text==expected and node.is_visible_in_tree() and node.size.x>0 and node.size.y>0),"dedicated stat label shows exact value: "+expected)
	var owned: Dictionary=app.model.state.ownedCharacters.duplicate(true)
	for id in app.model.state.ownedCharacters:app.model.state.ownedCharacters[id].level=10
	for unit in app.model.extraction.departure_party():
		var original: Dictionary=app.model.computed_stats(str(unit.id))
		for key in ["maxHp","atk","def","spd","cri","criDmg"]:check(float(unit.stats[key])==float(original[key]),"full growth "+str(unit.id)+key)
	app.model.state.ownedCharacters=owned
	press("ExtractionStart");await frames()
	var map=app.main_body.find_child("ExtractionMap",true,false)
	check(map!=null,"actual map control")
	check(app.model.extraction.map_state().rooms.size()>=12,"multiple rooms")
	var initial_room: String=app.model.extraction.map_state().currentRoomId
	check(is_equal_approx(map.zoom,map._minimum_zoom()),"new map starts fitted after layout")
	var offset: Vector2=map.offset
	var fit_before:="size=%s view=%s content=%s zoom=%s offset=%s auto=%s"%[map.size,map._view_rect(),map._content_bounds(),map.zoom,map.offset,map._auto_fit]
	check(app._extraction_gesture_at(app.shell,map.global_position+Vector2(100,100)),"map owns touch pan")
	drag(map,Vector2(190,170),Vector2(50,60));await frames()
	check(map.offset.is_equal_approx(offset),"fitted map stays stable on drag BEFORE "+fit_before+" AFTER size=%s view=%s content=%s zoom=%s offset=%s auto=%s"%[map.size,map._view_rect(),map._content_bounds(),map.zoom,map.offset,map._auto_fit])
	for step in 8:
		if map._content_bounds().size.x*map.zoom>map._view_rect().size.x+30:break
		press("AtlasZoomIn");await frames()
	offset=map.offset
	var anchor:Vector2=map._view_rect().get_center()
	drag(map,anchor+Vector2(40,0),anchor-Vector2(40,0));await frames()
	check(map.offset.x<offset.x-12,"zoomed map swipe visibly pans left")
	check(app.model.extraction.map_state().currentRoomId==initial_room,"swipe never enters room")
	var adjacent: Array=app.model.extraction.route_options()
	if not adjacent.is_empty():
		var id: String=adjacent[0].id
		map.offset=map.size/2-map._world_point(map.rooms[id]);map.queue_redraw()
		tap(map,map.room_point(id));await frames()
		check(app.model.extraction.map_state().currentRoomId==initial_room,"first tap previews room without movement")
		tap(map,map.room_point(id));await frames()
		check(app.model.extraction.map_state().currentRoomId==id,"tap adjacent enters actual room")
	# Choose a genuine generated resource room; do not fabricate battle rewards.
	check(choose_resource_room(),"generated reachable resource room")
	await frames()
	var scene=app.main_body.find_child("ExtractionRoomScene",true,false)
	check(scene!=null,"scene control")
	var boxes: Array=app.model.extraction.containers()
	check(not boxes.is_empty(),"scene has separate containers")
	var first: Dictionary=boxes[0]
	var bag_before: int=app.model.state.extraction.run.bag.size()
	var origin_pan: Vector2=scene.pan
	drag(scene,Vector2(200,140),Vector2(40,120));await frames()
	check(app.overlay.get_child_count()==0,"scene swipe never opens container")
	check(app.model.state.extraction.run.bag.size()==bag_before,"scene swipe grants no loot")
	check(scene.pan!=origin_pan or scene.canvas_size.x<=scene.size.x,"scene pan responds within bounds")
	scene.pan.x=clampf(scene.size.x/2-float(first.sceneX)*scene.canvas_size.x,minf(0,scene.size.x-scene.canvas_size.x),0)
	app.extraction_auto_pick=false;app.extraction_reduced_motion=false
	tap(scene,scene.container_point(first));await frames()
	check(button("ExtractionCloseContainer")!=null and app.extraction_searching,"scene tap automatically starts searching")
	check(button("ExtractionSearch")==null and button("ExtractionStopSearch")==null,"search requires no extra start or stop button")
	var grid=app.overlay.find_child("ExtractionContainer_"+str(first.id),true,false)
	check(grid!=null,"container spatial grid")
	if grid!=null:
		var item: Dictionary=grid.items[0]
		check(grid._get_tooltip(Vector2(int(item.x)*grid.cell+6,int(item.y)*grid.cell+6))=="未搜索物资","hidden tooltip")
	# Closing cancels immediately; reopening resumes with no extra search button.
	press("ExtractionCloseContainer");await frames()
	check(not app.extraction_searching,"closing immediately cancels auto search")
	app.extraction_reduced_motion=true
	press("ExtractionOpenContainer_"+str(first.id));await frames()
	await wait_search()
	check(not app.extraction_searching,"automatic sequential scan completes")
	var current: Dictionary=app.model.extraction.containers()[0]
	for item in current.items:check(item.revealed,"all items revealed")
	press("ExtractionTakeAll");await frames()
	check(app.model.state.extraction.run.bag.size()>bag_before,"take all auto packs")
	var count: int=app.model.state.extraction.run.bag.size()
	press("ExtractionTakeAll");await frames()
	check(app.model.state.extraction.run.bag.size()==count,"repeated take all no duplicates")
	press("ExtractionCloseContainer");await frames()
	press("ExtractionTab_bag");await frames()
	check(app.main_body.find_child("ExtractionGrid_bag",true,false)!=null,"bag accessible")
	press("ExtractionSort_bag");await frames()
	app._go_back();await frames()
	check(app.extraction_panel=="expedition","back returns scene")
	# Explicit scene return and map revisit keep room loot state.
	var resource_room: String=app.model.extraction.map_state().currentRoomId
	press("ExtractionAdvance");await frames()
	check(app.model.state.extraction.run.phase=="route","return map")
	map=app.main_body.find_child("ExtractionMap",true,false)
	map.offset=map.size/2-map._world_point(map.rooms[resource_room]);tap(map,map.room_point(resource_room));await frames()
	check(app.model.state.extraction.run.phase=="room","tap current revisits scene")
	check(app.model.state.extraction.run.bag.size()==count,"revisit keeps unique bag")
	# Auto pickup default loop with cancellation/navigation preserves prior reveals.
	check(choose_resource_room(),"second room fixture")
	await frames()
	boxes=app.model.extraction.containers();first=boxes[0]
	app.extraction_auto_pick=true;app.extraction_reduced_motion=false
	press("ExtractionOpenContainer_"+str(first.id));await frames()
	var stable_grid=app.overlay.find_child("ExtractionContainer_"+str(first.id),true,false)
	var stable_id: int=stable_grid.get_instance_id()
	var first_visible_at: Dictionary={}
	var visible_duration: Dictionary={}
	var source_uids: Array=_find_box(str(first.id)).items.map(func(item):return str(item.uid))
	var bag_before_auto: Array=app.model.state.extraction.run.bag.map(func(item):return str(item.uid))
	var identified: Dictionary={}
	var start_time:=Time.get_ticks_msec()/1000.0
	while app.extraction_searching and Time.get_ticks_msec()/1000.0-start_time<45.0:
		await process_frame
		var current_grid=app.overlay.find_child("ExtractionContainer_"+str(first.id),true,false)
		check(current_grid!=null and current_grid.get_instance_id()==stable_id,"continuous search preserves grid identity")
		var visible_now:Array=[]
		for visible_item in current_grid.items:
			var uid:=str(visible_item.uid)
			var definition:Dictionary=current_grid.definitions.get(str(visible_item.itemId),{})
			if definition.get("kind","")=="unknown":continue
			var bounds:Rect2=current_grid.item_rect(visible_item)
			bounds.position+=current_grid.global_position
			var clip:Rect2=Rect2(Vector2.ZERO,app.size)
			var ancestor=current_grid.get_parent()
			while ancestor!=null:
				if ancestor is Control and ancestor.clip_contents:clip=clip.intersection(ancestor.get_global_rect())
				ancestor=ancestor.get_parent()
			if clip.intersection(bounds).get_area()<bounds.get_area()*0.95:continue
			if not current_grid.textures.has(str(visible_item.itemId)):continue
			var now:=Time.get_ticks_msec()/1000.0
			if not first_visible_at.has(uid):first_visible_at[uid]=now
			visible_now.append(uid)
			visible_duration[uid]=maxf(float(visible_duration.get(uid,0)),now-first_visible_at[uid])
			identified[uid]=str(definition.get("name",""))
		for uid in first_visible_at.keys():
			if not visible_now.has(uid):first_visible_at.erase(uid)
	var verified_visible_pickups:=0
	var final_bag_uids:Array=app.model.state.extraction.run.bag.map(func(item):return str(item.uid))
	for uid in final_bag_uids:
		if bag_before_auto.has(uid):continue
		check(source_uids.has(uid),"automatic pickup retains exact source UID")
		if float(visible_duration.get(uid,0))>=0.20 and not identified.get(uid,"").is_empty():verified_visible_pickups+=1
	check(verified_visible_pickups>0,"same UID is identifiable and visible at least 200ms before exact-UID pickup")
	check(not app.extraction_searching,"continuous search completes within bounded time")
	app.extraction_reduced_motion=true
	await frames()
	check(app.model.state.extraction.run.bag.size()>0,"automatic search stores loot")
	press("ExtractionCloseContainer");await frames()
	for physical in SIZES:
		root.size=physical;await frames(12)
		for panel in ["expedition","bag","stash","collection"]:
			app.extraction_panel=panel;app._render_screen();await frames()
			check(app.main_body.size.x<=app.size.x+2,"page fits "+str(physical)+panel)
			for node in descendants(app.main_body):
				if node is Button:
					check(node.size.y>=44,"touch height "+str(node.name))
					check(node.size.x<=app.size.x+2,"button fits "+str(node.name))
	app.extraction_panel="expedition";app._render_screen();await frames()
	# Cancellation before reveal.
	check(choose_resource_room(),"cancel fixture");await frames()
	first=app.model.extraction.containers()[0]
	app.extraction_reduced_motion=false
	press("ExtractionOpenContainer_"+str(first.id));await frames()
	await create_timer(0.1).timeout
	app._go_back();await create_timer(1.2).timeout
	check(not app.extraction_searching,"back cancels search")
	check(app.model.state.extraction.run.bag.is_empty(),"cancel grants no loot")
	# Full backpack UI fixture: auto-pick must leave every unfitted item in its container.
	check(choose_resource_room(),"full backpack fixture")
	await frames()
	var one_cell := ""
	for id in app.model.extraction.data.items:
		var definition: Dictionary=app.model.extraction.item_def(str(id))
		if int(definition.width)==1 and int(definition.height)==1:one_cell=str(id);break
	check(not one_cell.is_empty(),"one-cell fixture definition")
	app.model.state.extraction.run.bag=[]
	for i in range(30):
		var item: Dictionary=app.model.extraction._make_item(one_cell)
		item.x=i%6;item.y=i/6;item.revealed=true
		app.model.state.extraction.run.bag.append(item)
	var full_before: Array=app.model.state.extraction.run.bag.duplicate(true)
	first=app.model.extraction.containers()[0]
	var container_count: int=first.items.size()
	app._render_screen();await frames()
	app.extraction_reduced_motion=true;app.extraction_auto_pick=true
	press("ExtractionOpenContainer_"+str(first.id));await frames()
	await wait_search()
	check(app.model.state.extraction.run.bag==full_before,"full bag preserves every existing item")
	var left: Dictionary=_find_box(str(first.id))
	check(left.items.size()==container_count,"unfitted items remain in container")
	for item in left.items:check(item.revealed,"full bag still reveals item safely")
	press("ExtractionCloseContainer");await frames()
	# Deterministic UI swap fixture: preserve gear/medicine, exclude hidden loot.
	check(choose_resource_room(),"smart swap fixture");await frames()
	var swap_bag: Array=[]
	for i in range(30):
		var id:="healer_charm" if i==0 else ("bandage" if i==1 else "wire")
		var item: Dictionary=app.model.extraction._make_item(id)
		item.x=i%6;item.y=i/6;item.revealed=true;swap_bag.append(item)
	app.model.state.extraction.run.bag=swap_bag
	first=app.model.extraction.containers()[0]
	var valuable: Dictionary=app.model.extraction._make_item("diamond_ring")
	valuable.x=0;valuable.y=0;valuable.revealed=true
	var hidden: Dictionary=app.model.extraction._make_item("world_seed")
	hidden.x=1;hidden.y=0;hidden.revealed=false
	var live_box: Dictionary=app.model.extraction._find_container(str(first.id))
	live_box.items=[valuable,hidden];live_box.revealed=1
	var before_swap: Array=swap_bag.duplicate(true)
	app._render_screen();await frames()
	press("ExtractionOpenContainer_"+str(first.id));await frames()
	press("ExtractionSmartLoot");await frames()
	check("价值 +" in texts(app.overlay),"swap shows gain")
	check(not str(app.model.extraction.item_def("world_seed").name) in texts(app.overlay),"swap hides unknown identity")
	press("ExtractionSmartCancel");await frames()
	check(app.model.state.extraction.run.bag==before_swap,"cancel swap preserves bag")
	check(_find_box(str(first.id)).items.size()==2,"cancel swap preserves container")
	press("ExtractionSmartLoot");await frames()
	app.model.extraction._find_container(str(first.id)).name+=" · 已整理"
	press("ExtractionSmartConfirm");await frames()
	check(app.model.state.extraction.run.bag==before_swap,"stale confirmation preserves bag")
	check(_find_box(str(first.id)).items.size()==2,"stale confirmation preserves container")

	press("ExtractionSmartLoot");await frames()
	press("ExtractionSmartConfirm");await frames()
	var swapped: Array=app.model.state.extraction.run.bag
	var ids: Array=swapped.map(func(item):return str(item.uid))
	check(ids.has(valuable.uid),"swap takes valuable item")
	check(not ids.has(hidden.uid),"swap never takes hidden item")
	check(ids.has(before_swap[0].uid) and ids.has(before_swap[1].uid),"swap protects equipment and medicine")
	var returned: Array=_find_box(str(first.id)).items
	check(returned.any(func(item):return item.itemId=="wire"),"swapped loot remains recoverable")
	var old_value:=0;var new_value:=0
	for item in before_swap:old_value+=int(app.model.extraction.item_def(str(item.itemId)).value)
	for item in swapped:new_value+=int(app.model.extraction.item_def(str(item.itemId)).value)
	check(new_value>old_value,"confirmed swap increases bag value")
	press("ExtractionCloseContainer");await frames()
	# Permanent collection affordance never annotates an unknown container item.
	var view=load("res://scripts/ui/extraction_view.gd")
	var badge_box=VBoxContainer.new();root.add_child(badge_box)
	app.model.state.extraction.collection=[]
	view._item_title(app,badge_box,app.model.extraction.item_def("wire"))
	check("新藏品" in texts(badge_box),"new collectible badge")
	badge_box.free();badge_box=VBoxContainer.new();root.add_child(badge_box)
	app.model.state.extraction.collection=["wire"]
	view._item_title(app,badge_box,app.model.extraction.item_def("wire"))
	check("已收藏" in texts(badge_box) and not "新藏品" in texts(badge_box),"owned collectible badge")
	badge_box.free();badge_box=VBoxContainer.new();root.add_child(badge_box)
	view._item_title(app,badge_box,{"name":"未搜索","kind":"unknown"})
	check(not "新藏品" in texts(badge_box) and not "已收藏" in texts(badge_box),"unknown item has no collection leak")
	app.extraction_panel="collection";app._render_screen();await frames()
	check("1 / %d" % app.model.extraction.data.items.size() in texts(app.main_body),"collection progress")
	for id in app.model.extraction.data.items:
		check(str(app.model.extraction.item_def(id).name) in texts(app.main_body),"gallery target "+str(id))
	check("待收集" in texts(app.main_body),"uncollected targets visible")
	badge_box.free()
	# Cancelling after reveal preserves loot still waiting for its pickup animation.
	app.extraction_panel="map"
	check(choose_resource_room(),"cancel-after-reveal room")
	await frames()
	var cancel_box: Dictionary=app.model.extraction.containers()[0]
	app.extraction_auto_pick=true;app.extraction_reduced_motion=false
	press("ExtractionOpenContainer_"+str(cancel_box.id));await frames()
	var pending_uid:=""
	var cancel_deadline:=Time.get_ticks_msec()+5000
	while pending_uid.is_empty() and Time.get_ticks_msec()<cancel_deadline:
		await process_frame
		for item in _find_box(str(cancel_box.id)).get("items",[]):
			if item.get("revealed",false):pending_uid=str(item.uid);break
	check(not pending_uid.is_empty(),"observe revealed pending pickup")
	press("ExtractionCloseContainer");await frames()
	var cancelled_bag: Array=app.model.state.extraction.run.bag.duplicate(true)
	await create_timer(0.7).timeout
	check(app.model.state.extraction.run.bag==cancelled_bag,"stop cancels pending pickup")
	check(_find_box(str(cancel_box.id)).get("items",[]).any(func(item):return str(item.uid)==pending_uid),"cancelled revealed item stays in container")
	app.queue_free();await frames()
	# AudioServer releases queued streaming buffers asynchronously.
	await create_timer(0.3).timeout
	print("EXTRACTION UI: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func _find_box(id: String) -> Dictionary:
	for box in app.model.extraction.containers():
		if str(box.id)==id:return box
	return {}

func wait_search(seconds: float=12.0) -> void:
	var deadline:=Time.get_ticks_msec()+int(seconds*1000)
	while app.extraction_searching and Time.get_ticks_msec()<deadline:await process_frame
	check(not app.extraction_searching,"search reaches bounded terminal state")
	await frames()
