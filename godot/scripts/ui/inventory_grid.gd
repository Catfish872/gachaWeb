extends Control
## Touch-friendly grid: select an item, then tap an empty cell to relocate it.
signal item_selected(uid: String)
signal cell_selected(x: int, y: int)
const COLORS := [Color("9ca7b5"), Color("74bc9a"), Color("68ade8"), Color("bc8be8"), Color("efc774"), Color("ed7884")]
var columns := 6
var rows := 5
var items: Array = []
var definitions: Dictionary = {}
var textures: Dictionary = {}
var selected_uid := ""
var cell := 44.0
var _press := Vector2.ZERO
var _pressed := false

func configure(width: int, height: int, contents: Array, defs: Dictionary, selection: String = "") -> void:
	columns = width
	rows = height
	items = contents.duplicate(true)
	definitions = defs
	textures.clear()
	for id in defs:
		var path := str(defs[id].get("icon", "res://assets/items/extraction/" + str(id) + ".svg"))
		if ResourceLoader.exists(path): textures[id] = load(path)
	selected_uid = selection
	custom_minimum_size = Vector2(0, rows * 44)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_PASS
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	queue_redraw()

func _ready() -> void:
	resized.connect(_resize_grid)
	_resize_grid()

func _resize_grid() -> void:
	cell = clampf(floorf(size.x / float(columns)), 24, 64)
	custom_minimum_size.y = rows * cell
	queue_redraw()

func item_size(item: Dictionary) -> Vector2i:
	var d: Dictionary = definitions.get(str(item.get("itemId", "")), {})
	var w := int(d.get("width", 1))
	var h := int(d.get("height", 1))
	return Vector2i(h, w) if item.get("rotated", false) else Vector2i(w, h)

func _draw() -> void:
	var font := get_theme_default_font()
	for y in rows:
		for x in columns:
			draw_rect(Rect2(x * cell + 1, y * cell + 1, cell - 2, cell - 2), Color("111d2b"))
			draw_rect(Rect2(x * cell + 1, y * cell + 1, cell - 2, cell - 2), Color("29394a"), false, 1)
	for item in items:
		var d: Dictionary = definitions.get(str(item.get("itemId", "")), {})
		var dims := item_size(item)
		var rect := Rect2(int(item.get("x", 0)) * cell + 2, int(item.get("y", 0)) * cell + 2, dims.x * cell - 4, dims.y * cell - 4)
		var color: Color = COLORS[clampi(int(d.get("rarity", 0)), 0, 5)]
		draw_rect(rect, color.darkened(0.82))
		draw_rect(rect, Color.WHITE if str(item.get("uid", "")) == selected_uid else color.darkened(0.15), false, 2.5 if str(item.get("uid", "")) == selected_uid else 1.5)
		draw_rect(Rect2(rect.position, Vector2(rect.size.x, 3)), color)
		var center := rect.get_center()
		var radius := minf(rect.size.x, rect.size.y) * 0.16
		match str(d.get("kind", "loot")):
			"unknown":
				draw_arc(center, radius, 0.3, 5.8, 20, color, 2)
			"equipment":
				var points := PackedVector2Array([center + Vector2(-radius, -radius), center + Vector2(radius, -radius), center + Vector2(radius, radius * 0.4), center + Vector2(0, radius * 1.4), center + Vector2(-radius, radius * 0.4)])
				draw_colored_polygon(points, color.darkened(0.1))
			"consumable":
				draw_rect(Rect2(center - Vector2(radius * 0.3, radius), Vector2(radius * 0.6, radius * 2)), color)
				draw_rect(Rect2(center - Vector2(radius, radius * 0.3), Vector2(radius * 2, radius * 0.6)), color)
			_:
				draw_colored_polygon(PackedVector2Array([center + Vector2(0, -radius), center + Vector2(radius, 0), center + Vector2(0, radius), center + Vector2(-radius, 0)]), color)
		var texture = textures.get(str(item.get("itemId", "")))
		if texture is Texture2D:
			var icon_side := minf(rect.size.x - 8, rect.size.y - 28)
			if icon_side >= 18:
				draw_rect(Rect2(center - Vector2(icon_side, icon_side) / 2, Vector2(icon_side, icon_side)), color.darkened(0.82))
				draw_texture_rect(texture, Rect2(center - Vector2(icon_side, icon_side) / 2 + Vector2(0, 3), Vector2(icon_side, icon_side)), false)
		var label_size := 12 if cell < 45 else 14
		var chars := maxi(1, int(rect.size.x / label_size))
		var title := str(d.get("name", "物资"))
		if title.length() > chars: title = title.left(chars)
		draw_string(font, rect.position + Vector2(4, label_size + 5), title, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 8, label_size, color.lightened(0.3))
		if rect.size.y > 45 and d.get("kind", "") != "unknown":
			draw_string(font, Vector2(rect.position.x + 4, rect.end.y - 5), str(d.get("value", 0)), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 8, 12, color)

func _get_tooltip(at_position: Vector2) -> String:
	var item := _item_at(at_position)
	if item.is_empty(): return "空格 · 选中物品后点击此处放置"
	var d: Dictionary = definitions.get(str(item.get("itemId", "")), {})
	if d.get("kind", "") == "unknown": return "未搜索物资"
	return "%s · %d × %d · 售价 %d" % [d.get("name", "物资"), d.get("width", 1), d.get("height", 1), d.get("value", 0)]

func _item_at(point: Vector2) -> Dictionary:
	var pos := Vector2i(floori(point.x / cell), floori(point.y / cell))
	for item in items:
		if Rect2i(Vector2i(int(item.get("x", 0)), int(item.get("y", 0))), item_size(item)).has_point(pos): return item
	return {}

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press = event.position
			_pressed = true
		elif _pressed:
			_pressed = false
			if event.position.distance_to(_press) < 12: _activate.call_deferred(event.position)
	elif event is InputEventScreenTouch:
		if event.pressed:
			_press = event.position
			_pressed = true
		elif _pressed:
			_pressed = false
			if event.position.distance_to(_press) < 12: _activate.call_deferred(event.position)
	elif event is InputEventScreenDrag and event.position.distance_to(_press) >= 12:
		_pressed = false

func _activate(point: Vector2) -> void:
	if not is_inside_tree(): return
	var item := _item_at(point)
	if not item.is_empty():
		item_selected.emit(str(item.uid))
	else:
		var x := floori(point.x / cell)
		var y := floori(point.y / cell)
		if x >= 0 and y >= 0 and x < columns and y < rows: cell_selected.emit(x, y)
