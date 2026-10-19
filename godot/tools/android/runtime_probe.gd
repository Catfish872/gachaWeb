# Included only in the temporary emulator APK; never in the delivered ARM APK.
extends "res://scripts/main.gd"

var _probe_clock := 0.0
var _probe_sequence := 0

func _process(delta: float) -> void:
	super._process(delta)
	_probe_clock += delta
	if _probe_clock < 0.5 or not _ready_done:
		return
	_probe_clock = 0.0
	_probe_sequence += 1
	var controls: Array = []
	_probe_controls(self, controls)
	var scroll := main_body.get_parent() as ScrollContainer
	var payload := Marshalls.utf8_to_base64(JSON.stringify({
		"seq": _probe_sequence, "modal_scrolls": _probe_scrolls(), "screen": current_screen, "window": [get_window().size.x, get_window().size.y],
		"logical": [size.x, size.y], "overlay": overlay.get_child_count(),
		"scroll": scroll.scroll_vertical, "scroll_max": scroll.get_v_scroll_bar().max_value - scroll.get_v_scroll_bar().page,
		"page_width": main_body.size.x, "scroll_width": scroll.size.x,
		"scroll_rect": _probe_rect(scroll), "buttons": controls
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
	if node is Button and node.is_visible_in_tree() and not node.disabled and (str(node.name).begins_with("Menu") or node.name == "BackButton"):
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
