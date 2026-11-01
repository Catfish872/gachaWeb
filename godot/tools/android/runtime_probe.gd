# Included only in the temporary emulator APK; never in the delivered ARM APK.
extends "res://scripts/main.gd"

var _probe_clock := 0.0
var _probe_sequence := 0
var _android_bridge: Dictionary = {}

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
	if _probe_clock < 0.5 or not _ready_done:
		return
	_probe_clock = 0.0
	_probe_sequence += 1
	var controls: Array = []
	_probe_controls(self, controls)
	var canvases := _probe_canvases(controls)
	var scroll := main_body.get_parent() as ScrollContainer
	var payload := Marshalls.utf8_to_base64(JSON.stringify({
		"seq": _probe_sequence, "modal_scrolls": _probe_scrolls(), "screen": current_screen, "window": [get_window().size.x, get_window().size.y],
		"logical": [size.x, size.y], "overlay": overlay.get_child_count(),
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
	if node is Button and node.is_visible_in_tree() and not node.disabled and (str(node.name).begins_with("Menu") or str(node.name).begins_with("Extraction") or node.name == "BackButton"):
		result.append({"name": str(node.name), "text": node.text, "rect": _probe_rect(node), "clip": _probe_clip(node)})
	for child in node.get_children():
		_probe_controls(child, result)

func _probe_clip(control: Control) -> Array:
	var clip := Rect2(Vector2.ZERO, Vector2(get_window().size))
	var parent := control.get_parent()
	while parent != null:
		if parent is ScrollContainer:
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
	return {"phase": str(run.get("phase", "camp")), "act": int(run.get("act", 0)),
		"node": int(run.get("node", 0)), "bag_count": bag_ids.size(), "bag_ids": bag_ids,
		"bag_area": bag_area, "containers": containers, "searching": extraction_searching,
		"room_id": str(graph.get("currentRoomId", "")), "explored": int(graph.get("explored", 0)),
		"map_rooms": graph.get("rooms", []).map(func(room): return {"id": str(room.id), "type": str(room.type), "visited": bool(room.visited)}), "map_edges": graph.get("edges", []),
		"room_type": str(run.get("room", {}).get("type", "")),
		"stash_count": data.get("stash", []).size(), "credits": int(data.get("credits", 0))}

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
		result.map = {"rect": _probe_rect(map_view), "clip": clip, "pan": [map_view.offset.x, map_view.offset.y]}
		controls.append({"name": "ExtractionMapViewport", "rect": _probe_rect(map_view), "clip": _probe_clip(map_view)})
		var adjacent: Array = map_view.adjacent_ids()
		for room in map_view.graph.get("rooms", []):
			var id := str(room.id)
			var point: Vector2 = map_view.room_point(id)
			controls.append({"name": "ExtractionMapNode_" + id, "rect": _probe_local_rect(map_view, Rect2(point-Vector2(22,22), Vector2(44,44))), "clip": clip,
				"room_id": id, "type": str(room.get("type", "")), "adjacent": id in adjacent,
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
