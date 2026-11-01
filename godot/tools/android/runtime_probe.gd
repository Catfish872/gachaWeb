# Included only in the temporary emulator APK; never in the delivered ARM APK.
extends "res://scripts/main.gd"

var _probe_clock := 0.0
var _probe_sequence := 0
var _android_bridge: Dictionary = {}
var _probe_back_events: Array = []

func _ready() -> void:
	super._ready()
	# Deterministic UI fixture only in the isolated emulator APK. Seed 2 exposes
	# an ordinary deterministic expedition map; no items or victories are granted.
	model.rng.seed = 2
	if OS.get_name() == "Android":
		_android_bridge = updater.probe_android_bridge()

func _process(delta: float) -> void:
	super._process(delta)
	_probe_clock += delta
	if _probe_clock < (0.1 if extraction_searching or is_instance_valid(summon_sequence) else 0.5) or not _ready_done:
		return
	_probe_clock = 0.0
	_emit_probe()

func _notification(what: int) -> void:
	var before_back := overlay.get_child_count() if _ready_done and what == NOTIFICATION_WM_GO_BACK_REQUEST else -1
	# Object.notification already invokes the base script before this observer.
	# Calling super here would dispatch every native notification twice.
	if before_back >= 0:
		_probe_back_trace("notification", before_back)
	if _ready_done and what in [NOTIFICATION_APPLICATION_PAUSED,NOTIFICATION_APPLICATION_RESUMED]:
		_emit_probe("paused" if what==NOTIFICATION_APPLICATION_PAUSED else "resumed")

func _unhandled_input(event: InputEvent) -> void:
	var is_back: bool = event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE
	var before_back := overlay.get_child_count() if _ready_done and is_back else -1
	super._unhandled_input(event)
	if before_back >= 0:
		_probe_back_trace("escape", before_back)

func _probe_back_trace(source: String, before: int) -> void:
	# Observe the real native ingress without dispatching or changing any input.
	var entry := {"source": source, "monotonic_ms": Time.get_ticks_msec(), "observed_overlay": overlay.get_child_count(), "screen": current_screen}
	if source == "escape":entry["before_overlay"] = before
	_probe_back_events.append(entry)
	if _probe_back_events.size() > 16:_probe_back_events.pop_front()
	print("ANDROID_SMOKE_BACK " + JSON.stringify(entry))

func _emit_probe(event: String="frame") -> void:
	_probe_sequence += 1
	var controls: Array = []
	_probe_controls(self, controls)
	var canvases := _probe_canvases(controls)
	var loot := _probe_loot(controls)
	var inventory := _probe_inventory(controls)
	var scroll := main_body.get_parent() as ScrollContainer
	var payload := Marshalls.utf8_to_base64(JSON.stringify({
		"seq": _probe_sequence, "probe_event":event, "application_paused":bool(get_meta("application_paused",false)), "monotonic_ms": Time.get_ticks_msec(), "loot": loot, "inventory": inventory, "modal_scrolls": _probe_scrolls(), "page_scrolls": _probe_page_scrolls(), "screen": current_screen, "window": [get_window().size.x, get_window().size.y],
		"logical": [size.x, size.y], "overlay": overlay.get_child_count(), "system_back_events": _probe_back_events,
		"renderer": {"method": RenderingServer.get_current_rendering_method(), "driver": RenderingServer.get_current_rendering_driver_name(), "adapter": RenderingServer.get_video_adapter_name()},
		"summon": _probe_summon(), "relics": _probe_relics(),
		"battle_state": {"phase":str(battle.state.get("phase","")),"auto":battle_auto,"is_service_guard":bool(battle_config.get("isServiceGuard",false))},
		"scroll": scroll.scroll_vertical, "scroll_max": scroll.get_v_scroll_bar().max_value - scroll.get_v_scroll_bar().page,
		"page_width": main_body.size.x, "scroll_width": scroll.size.x,
		"scroll_rect": _probe_rect(scroll), "scrollbar_rect": _probe_rect(scroll.get_v_scroll_bar()), "buttons": controls, "extraction": _probe_extraction(), "android_bridge": _android_bridge, "canvases": canvases
	}))
	# Android/Godot log output truncates long lines. Each ASCII record stays
	# below 700 bytes, independent of Unicode menu labels and number of controls.
	var chunk_count := ceili(payload.length() / 600.0)
	for index in range(chunk_count):
		print("ANDROID_SMOKE_CHUNK %d %d %d %d %s" % [_probe_sequence, index, chunk_count, payload.length(), payload.substr(index * 600, 600)])

func _probe_rect(control: Control) -> Array:
	var transform := get_viewport().get_screen_transform() * control.get_global_transform_with_canvas()
	var a := transform * Vector2.ZERO
	var b := transform * control.size
	return [a.x, a.y, b.x - a.x, b.y - a.y]

func _probe_controls(node: Node, result: Array) -> void:
	# Story cards use real gui_input-bound panels, not BaseButton. Observe only.
	if node is Control and not node is BaseButton and node.is_visible_in_tree() and str(node.name).begins_with("StageCard_"):
		result.append({"name":str(node.name),"text":"","rect":_probe_rect(node),"clip":_probe_clip(node),"scroll_owner":_probe_scroll_owner(node),"selected":str(node.name)=="StageCard_"+selected_stage_id})
	if current_screen=="battle" and node is Button and node.is_visible_in_tree() and node.text in ["自动","手动"]:
		result.append({"name":"BattleAutoToggle","text":node.text,"rect":_probe_rect(node),"clip":_probe_clip(node)})
	if node is BaseButton and node.is_visible_in_tree() and not node.disabled and (str(node.name).begins_with("Menu") or str(node.name).begins_with("Extraction") or str(node.name).begins_with("Atlas") or str(node.name).begins_with("Summon") or str(node.name).begins_with("ShopPurchase_") or str(node.name).begins_with("Character") or str(node.name).begins_with("GrowthSelect_") or str(node.name).begins_with("Relic") or str(node.name).begins_with("Abyss") or str(node.name).begins_with("Story") or str(node.name).begins_with("StageCard_") or str(node.name).begins_with("Dialogue") or node.name in ["BackButton","BattleSettlementContinue","GrowthAutoRelics"]):
		result.append({"name": str(node.name), "text": node.text if node is Button else node.tooltip_text, "rect": _probe_rect(node), "clip": _probe_clip(node), "scroll_owner":_probe_scroll_owner(node)})
	for child in node.get_children():
		_probe_controls(child, result)

func _probe_clip(control: Control) -> Array:
	var clip := Rect2(Vector2.ZERO, Vector2(get_window().size))
	var parent := control.get_parent()
	while parent != null:
		if parent is Control and parent.clip_contents:
			var r := _probe_rect(parent)
			clip = clip.intersection(Rect2(r[0], r[1], r[2], r[3]))
		parent = parent.get_parent()
	return [clip.position.x, clip.position.y, clip.size.x, clip.size.y]

func _probe_scrolls() -> Array:
	var result: Array = []
	for node in overlay.find_children("*", "ScrollContainer", true, false):
		result.append({"rect": _probe_rect(node), "value": node.scroll_vertical, "max": node.get_v_scroll_bar().max_value - node.get_v_scroll_bar().page})
	return result

# Read-only observability: this probe never selects a route, reveals loot, grants
# items, or settles combat. It is excluded from the delivered APK.
func _probe_extraction() -> Dictionary:
	var data: Dictionary = model.state.get("extraction", {})
	var run: Dictionary = data.get("run", {})
	var graph: Dictionary = run.get("map", {})
	var containers: Array = []
	for box in run.get("containers", []):
		var unknown := 0
		var ids: Array = []
		for item in box.get("items", []):
			if not item.get("revealed", false): unknown += 1
			ids.append(str(item.uid))
		containers.append({"id": str(box.id), "items": ids, "unknown": unknown})
	var bag_ids: Array = []
	var bag_area := 0
	for item in run.get("bag", []):
		bag_ids.append(str(item.uid))
		var definition: Dictionary = model.extraction.item_def(str(item.itemId))
		bag_area += int(definition.get("width", 1)) * int(definition.get("height", 1))
	return {"interaction":model.extraction.room_interaction_status(), "phase": str(run.get("phase", "camp")), "act": int(run.get("act", 0)),
		"run_digest":JSON.stringify(run).sha256_text(), "node": int(run.get("node", 0)), "bag_count": bag_ids.size(), "bag_ids": bag_ids,
		"supplies":run.get("bag",[]).filter(func(item):return model.extraction.item_def(item.itemId).get("kind")=="consumable").map(func(item):return {"uid":str(item.uid),"item_id":str(item.itemId),"exchange_locked":bool(item.get("exchangeLocked",false))}), "loadout_ids":data.get("loadout",[]).map(func(item):return str(item.uid)),
		"bag_area": bag_area, "containers": containers, "searching": extraction_searching,
		"room_id": str(graph.get("currentRoomId", "")), "explored": int(graph.get("explored", 0)),
		"map_rooms": graph.get("rooms", []).map(func(room): return {"id": str(room.id), "type": str(room.type), "visited": bool(room.visited), "cleared": bool(room.get("cleared",false)), "unlocked": bool(room.get("unlocked",false))}), "map_edges": graph.get("edges", []),
		"room_type": str(run.get("room", {}).get("type", "")), "guard_pending":bool(run.get("room",{}).get("guardPending",false)), "growth_choices":run.get("pendingChoices",[]).map(func(choice):return str(choice.choiceId)),
		"room_actions":run.get("roomActions",[]).duplicate(true), "deposit_used":bool(run.get("room",{}).get("depositUsed",false)),
		"stash_count": data.get("stash", []).size(), "gold": int(model.state.resources.get("gold", 0))}

func _probe_local_rect(control: Control, local_rect: Rect2) -> Array:
	var transform := get_viewport().get_screen_transform() * control.get_global_transform_with_canvas()
	var a := transform * local_rect.position
	var b := transform * local_rect.end
	return [a.x, a.y, b.x - a.x, b.y - a.y]

func _probe_canvas_clip(control: Control) -> Array:
	var outer := _probe_clip(control)
	var rect := _probe_rect(control)
	var clip := Rect2(outer[0], outer[1], outer[2], outer[3]).intersection(Rect2(rect[0], rect[1], rect[2], rect[3]))
	return [clip.position.x, clip.position.y, clip.size.x, clip.size.y]

# Custom-drawn map nodes and room sprites expose the same real hit rectangles
# used by their controls. This only reports geometry; ADB supplies every gesture.
func _probe_canvases(controls: Array) -> Dictionary:
	var result := {}
	var map_view = main_body.find_child("ExtractionMap", true, false)
	if map_view != null:
		var clip := _probe_canvas_clip(map_view)
		if map_view.has_method("_view_rect"):
			var inner := _probe_local_rect(map_view, map_view._view_rect())
			var region := Rect2(clip[0],clip[1],clip[2],clip[3]).intersection(Rect2(inner[0],inner[1],inner[2],inner[3]))
			clip = [region.position.x,region.position.y,region.size.x,region.size.y]
		result.map = {"rect": _probe_rect(map_view), "clip": clip, "pan": [map_view.offset.x, map_view.offset.y], "zoom": map_view.zoom, "fit_zoom": map_view._minimum_zoom(), "auto_fit": map_view._auto_fit, "selected_room": map_view.selected_room_id, "can_pan_x": map_view._content_bounds().size.x * map_view.zoom > map_view._view_rect().size.x + 0.01}
		controls.append({"name": "ExtractionMapViewport", "rect": _probe_rect(map_view), "clip": _probe_clip(map_view)})
		var adjacent: Array = map_view.adjacent_ids()
		for room in map_view.graph.get("rooms", []):
			var id := str(room.id)
			var point: Vector2 = map_view.room_point(id)
			controls.append({"name": "ExtractionMapNode_" + id, "rect": _probe_local_rect(map_view, Rect2(point-Vector2(22,22), Vector2(44,44))), "clip": clip,
				"room_id": id, "type": str(room.get("type", "")), "adjacent": id in adjacent, "reachable": id in map_view.reachable_ids(), "travel_path": map_view.travel_path(id),
				"visited": bool(room.get("visited", false)), "locked": room.get("type", "") == "boss" and not map_view.graph.get("bossUnlocked", false)})
	var scene_view = main_body.find_child("ExtractionRoomScene", true, false)
	if scene_view != null:
		var clip := _probe_canvas_clip(scene_view)
		result.scene = {"rect": _probe_rect(scene_view), "clip": clip, "pan": [scene_view.pan.x, scene_view.pan.y]}
		controls.append({"name": "ExtractionSceneViewport", "rect": _probe_rect(scene_view), "clip": _probe_clip(scene_view)})
		for box in scene_view.containers:
			var point: Vector2 = scene_view.container_point(box)
			controls.append({"name": "ExtractionSceneContainer_" + str(box.id), "rect": _probe_local_rect(scene_view, Rect2(point-Vector2(20,20), Vector2(40,40))), "clip": clip, "container_id": str(box.id), "item_count": box.get("items", []).size()})
	return result

func _probe_page_scrolls() -> Array:
	var result: Array=[]
	for node in main_body.find_children("*","ScrollContainer",true,false):
		if node.is_visible_in_tree():result.append({"id":str(node.get_path()),"name":str(node.name),"clip":_probe_clip(node),"rect":_probe_rect(node),"value":node.scroll_vertical,"max":maxf(0,node.get_v_scroll_bar().max_value-node.get_v_scroll_bar().page)})
	return result

func _probe_loot(controls: Array) -> Dictionary:
	var id:=str(overlay.get_meta("extraction_container",""))
	var result:Dictionary={"container_id":id,"source":[],"bag":[],"scan_uid":"","scan_progress":0.0}
	if id.is_empty():return result
	for pair in [["source","ExtractionContainer_"+id],["bag","ExtractionGrid_search_bag"]]:
		var grid=overlay.find_child(pair[1],true,false)
		if not is_instance_valid(grid):continue
		var clip:=_probe_canvas_clip(grid)
		if pair[0]=="source":result.scan_uid=grid.scan_uid;result.scan_progress=grid.scan_progress
		for item in grid.items:
			var definition:Dictionary=grid.definitions.get(str(item.itemId),{})
			var known:bool=definition.get("kind","")=="unknown" if pair[0]=="source" else false
			var entry:Dictionary={"uid":str(item.uid),"revealed":not known,"name":str(definition.get("name","")) if not known else "", "icon_loaded":grid.textures.has(str(item.itemId)),"rect":_probe_local_rect(grid,grid.item_rect(item)),"clip":clip}
			result[pair[0]].append(entry)
			if pair[0]=="source" and not known:controls.append({"name":"ExtractionLootItem_"+str(item.uid),"rect":entry.rect,"clip":clip})
	return result

# Read-only warehouse geometry for real Android selection and placement gestures.
func _probe_inventory(controls: Array) -> Dictionary:
	var grid=main_body.find_child("ExtractionGrid_stash",true,false)
	if not is_instance_valid(grid):return {}
	var clip:=_probe_canvas_clip(grid)
	var items:Array=[]
	for item in grid.items:
		var entry:Dictionary={"uid":str(item.uid),"item_id":str(item.itemId),"x":int(item.x),"y":int(item.y),"rotated":bool(item.get("rotated",false)),"rect":_probe_local_rect(grid,grid.visual_rect(item)),"clip":clip,"icon_loaded":grid.textures.has(str(item.itemId))}
		items.append(entry)
		controls.append({"name":"ExtractionInventoryItem_"+str(item.uid),"rect":entry.rect,"clip":clip})
	if grid.placement_mode:
		for y in range(grid.rows):
			for x in range(grid.columns):
				var rect:=_probe_local_rect(grid,Rect2(Vector2(x,y)*grid.cell+Vector2.ONE*3,Vector2.ONE*(grid.cell-6)))
				if Rect2(clip[0],clip[1],clip[2],clip[3]).encloses(Rect2(rect[0],rect[1],rect[2],rect[3])):
					controls.append({"name":"ExtractionInventoryCell_%d_%d"%[x,y],"rect":rect,"clip":clip})
	return {"items":items,"selected_uids":grid.selected_uids.duplicate(),"selected_uid":grid.selected_uid,"multi_select":grid.multi_select,"placement_mode":grid.placement_mode,"placement_uid":grid.placement_uid,"rect":_probe_rect(grid),"clip":clip}

# Presentation observations only; no RNG draws, model mutations or synthetic input.
func _probe_summon() -> Dictionary:
	var transaction:Dictionary={"diamonds":int(model.state.resources.diamonds),"total_pulls":int(model.state.stats.totalPulls),"pity":model.state.pityCounters.duplicate(true),"owned":model.state.ownedCharacters.duplicate(true)}
	var result:Dictionary={"active":is_instance_valid(summon_sequence),"diamonds":transaction.diamonds,"total_pulls":transaction.total_pulls,"transaction_digest":JSON.stringify(transaction).sha256_text(),"owned_ids":model.state.ownedCharacters.keys()}
	if is_instance_valid(summon_sequence):
		result.merge(summon_sequence.debug_state())
		result["history"]=summon_sequence.stage_history.duplicate(true)
		result["results"]=summon_sequence.results.duplicate(true)
	return result

func _probe_relics() -> Dictionary:
	var result:Dictionary={"inventory":model.state.relics.slice(0,100).duplicate(true),"inventory_count":model.state.relics.size(),"inventory_digest":JSON.stringify(model.state.relics).sha256_text(),"target":model.abyss_relic_drop_info(),"equipped":{}}
	for id in model.state.ownedCharacters:result.equipped[id]=model.state.ownedCharacters[id].get("equippedRelics",{}).duplicate(true)
	var content=overlay.find_child("RelicLoadoutContent",true,false)
	if content!=null:
		var panel:Node=content
		while panel!=null:
			if panel.has_meta("relic_displayed_plan"):
				result["displayed_plan"]=panel.get_meta("relic_displayed_plan").duplicate(true);break
			panel=panel.get_parent()
	result["art"]=[]
	for texture in find_children("RelicArt_*","TextureRect",true,false):
		if texture.is_visible_in_tree() and texture.texture!=null:result.art.append({"set_id":str(texture.get_meta("relic_set_id","")),"resource":texture.texture.resource_path,"rect":_probe_rect(texture),"clip":_probe_clip(texture)})
	result["recommendations_visible"]=overlay.find_child("CharacterRelicRecommendations",true,false)!=null
	return result

func _probe_scroll_owner(node:Node)->String:
	var parent=node.get_parent()
	while parent!=null:
		if parent is ScrollContainer:return str(parent.get_path())
		parent=parent.get_parent()
	return ""
