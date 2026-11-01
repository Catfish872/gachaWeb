extends SceneTree
var failures:=0
var checks:=0
func _initialize() -> void:call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error("INVENTORY: "+label)
func touch(grid,at: Vector2,down: bool) -> void:
	var e:=InputEventScreenTouch.new();e.index=0;e.position=at;e.pressed=down;grid._gui_input(e)
func move(grid,at: Vector2) -> void:
	var e:=InputEventScreenDrag.new();e.index=0;e.position=at;grid._gui_input(e)
func run() -> void:
	var model=load("res://scripts/game_model.gd").new("")
	var grid=load("res://scripts/ui/inventory_grid.gd").new();root.add_child(grid)
	var defs: Dictionary=model.extraction.data.items
	var ids: Array=defs.keys()
	var small_ids: Array=ids.filter(func(id):return int(defs[id].get("width",1))==1 and int(defs[id].get("height",1))==1)
	var items: Array=[]
	for i in 3:items.append({"uid":"item%d"%i,"itemId":small_ids[i],"x":i*2,"y":0})
	grid.size=Vector2(252,210);grid.configure(6,5,items,defs)
	await process_frame
	await process_frame
	for id in ids:check(grid.textures.has(id),"texture loaded "+str(id))
	check(grid.item_rect(items[0]).grow(-5).size.x>=24,"one-cell icon has readable drawable area")
	var p=grid.item_rect(items[0]).get_center()
	check(not grid.allow_multi_select,"ordinary grids default to single-item interaction")
	for context in ["bag","search"]:
		grid.name="ExtractionGrid_"+context
		touch(grid,p,true)
		var single_hold_start:=Time.get_ticks_msec()
		while Time.get_ticks_msec()-single_hold_start<600:await process_frame
		check(not grid.multi_select and grid.selected_uids.is_empty(),context+" long hold cannot enter warehouse multiselect")
		touch(grid,p,false)
		check(not grid.multi_select and grid.selected_uids.is_empty(),context+" release does not retain batch selection")
	# Production warehouse explicitly opts in; ordinary bag and search stay single-item.
	grid.name="ExtractionGrid_stash"
	grid.allow_multi_select=true
	touch(grid,p,true)
	var hold_start:=Time.get_ticks_msec()
	while Time.get_ticks_msec()-hold_start<600:await process_frame
	check(grid.multi_select,"long hold enters multiselect")
	check(grid.selected_uids.has("item0"),"held item selected")
	# A single fast motion must select the crossed middle cell too.
	move(grid,grid.item_rect(items[2]).get_center())
	touch(grid,grid.item_rect(items[2]).get_center(),false)
	check(grid.selected_uids.size()==3,"sweep selects all crossed items")
	touch(grid,p,true);move(grid,p);touch(grid,p,false)
	check(not grid.selected_uids.has("item0") and grid.selected_uids.size()==2,"repeat sweep toggles once per gesture")
	grid.queue_free();await process_frame
	print("REDESIGN INVENTORY: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
