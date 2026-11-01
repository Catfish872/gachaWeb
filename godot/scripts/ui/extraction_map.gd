extends Control
signal room_selected(id: String)
var graph: Dictionary = {}
var rooms: Dictionary = {}
var offset := Vector2.ZERO
var zoom := 1.0
var _last := Vector2.ZERO
var _start := Vector2.ZERO
var _pressed := false
var _dragged := false
var _touch_id := -1
var _initial := true
const WORLD := Vector2(940, 660)
const TYPE_NAMES := {"entry":"入口", "cache":"物资", "battle":"敌人", "elite":"精英", "event":"奇遇", "rest":"营地", "boss":"首领"}
const DISTRICT_COLORS := [Color("3c6060"),Color("5a536e"),Color("6a5b40")]

func configure(value: Dictionary) -> void:
	graph = value.duplicate(true)
	rooms.clear()
	for room in graph.get("rooms", []): rooms[str(room.id)] = room
	custom_minimum_size = Vector2(0, 340)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_meta("extraction_pan", true)
	queue_redraw()

func _ready() -> void:
	resized.connect(_resize)
	_resize()

func _resize() -> void:
	if _initial and size.x > 0:
		var current: Dictionary = rooms.get(str(graph.get("currentRoomId", "")), {})
		offset = size / 2 - _world_point(current) if not current.is_empty() else (size - WORLD) / 2
		_initial = false
	_clamp_offset()
	queue_redraw()

func _world_point(room: Dictionary) -> Vector2:
	return (Vector2(55, 60) + Vector2(float(room.get("x", 0.5)), float(room.get("y", 0.5))) * (WORLD - Vector2(110,120))) * zoom

func room_point(id: String) -> Vector2:
	return _world_point(rooms.get(id, {})) + offset

func adjacent_ids() -> Array:
	var result: Array = []
	var current := str(graph.get("currentRoomId", ""))
	for edge in graph.get("edges", []):
		if edge[0] == current: result.append(str(edge[1]))
		elif edge[1] == current: result.append(str(edge[0]))
	return result

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size), Color("0c1722"))
	for x in range(-30, int(size.x)+30, 32):
		draw_line(Vector2(x + fmod(offset.x,32),0),Vector2(x + fmod(offset.x,32),size.y),Color("142332"),1)
	for y in range(-30,int(size.y)+30,32):
		draw_line(Vector2(0,y + fmod(offset.y,32)),Vector2(size.x,y + fmod(offset.y,32)),Color("142332"),1)
	var font := get_theme_default_font()
	var district_index := 0
	for district in graph.get("districts", []):
		var center := Vector2.ZERO
		var count := 0
		for id in rooms:
			if str(rooms[id].get("districtId", "")) == str(district.id): center += room_point(id); count += 1
		if count > 0:
			center /= count
			var color: Color = DISTRICT_COLORS[district_index % DISTRICT_COLORS.size()]
			draw_circle(center, 115 * zoom, Color(color,0.13))
			draw_string(font, center-Vector2(85,90),str(district.get("name",district.id)),HORIZONTAL_ALIGNMENT_CENTER,170,17,color.lightened(0.45))
		district_index += 1
	var adjacent := adjacent_ids()
	for edge in graph.get("edges", []):
		var a := str(edge[0]); var b := str(edge[1])
		if rooms.has(a) and rooms.has(b):
			var near := a == str(graph.get("currentRoomId","")) or b == str(graph.get("currentRoomId",""))
			draw_line(room_point(a),room_point(b),Color("6baeb2") if near else Color("354353"),3 if near else 2,true)
	for id in rooms:
		var room: Dictionary = rooms[id]
		var center := room_point(id)
		var current: bool = id == str(graph.get("currentRoomId", ""))
		var visited := bool(room.get("visited",false))
		var boss: bool = id == str(graph.get("bossRoomId","")) or room.get("type", "") == "boss"
		var color := Color("7ed1d0") if id in adjacent else Color("80909c")
		if boss: color = Color("edb366") if graph.get("bossUnlocked",false) else Color("806b5c")
		if room.get("type", "") in ["elite","vault","shrine"] or room.get("highValue",false): color = Color("d9a5ef")
		if current: color = Color("f1d399")
		var radius := clampf(25 * zoom, 12, 25)
		draw_circle(center,radius,Color("20343e") if visited else Color("182431"))
		draw_arc(center,radius,0,TAU,32,color,3 if current else 1.5,true)
		if current: draw_arc(center,radius+5,0,TAU,32,Color(color,0.4),2,true)
		var symbols := {"cache":"箱","battle":"战","elite":"强","rest":"休","hospital":"药","workshop":"工","vault":"宝","shrine":"祭","event":"?"}
		var text: String = "◆" if boss else ("●" if current else ("✓" if room.get("cleared",false) else str(symbols.get(str(room.get("type","")),"◇"))))
		draw_string(font,center+Vector2(-15,7),text,HORIZONTAL_ALIGNMENT_CENTER,30,20,color)
		var title := str(room.get("name", TYPE_NAMES.get(str(room.get("type","")),"房间")))
		if zoom < 0.6 and not current: title = ""
		draw_string(font,center+Vector2(-65,44),title,HORIZONTAL_ALIGNMENT_CENTER,130,14,color)
		if current: draw_string(font,center+Vector2(-35,-36),"当前位置",HORIZONTAL_ALIGNMENT_CENTER,70,13,color)
	draw_rect(Rect2(Vector2.ZERO,size),Color("40505d"),false,1)

func _clamp_offset() -> void:
	offset.x = clampf(offset.x, minf(20,size.x-WORLD.x*zoom-20),20)
	offset.y = clampf(offset.y, minf(20,size.y-WORLD.y*zoom-20),20)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _touch_id == -1:
			_touch_id = event.index; _begin(event.position)
		elif not event.pressed and event.index == _touch_id:
			_touch_id = -1; _end(event.position)
		accept_event()
	elif event is InputEventScreenDrag and event.index == _touch_id:
		_move(event.position); accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and _touch_id == -1:
		if event.pressed: _begin(event.position)
		else: _end(event.position)
		accept_event()
	elif event is InputEventMouseMotion and _pressed and _touch_id == -1:
		_move(event.position); accept_event()

func _begin(at: Vector2) -> void:
	_pressed = true; _dragged = false; _last = at; _start = at
func _move(at: Vector2) -> void:
	if not _pressed: return
	if at.distance_to(_start) > 10: _dragged = true
	if _dragged:
		offset += at - _last; _clamp_offset(); queue_redraw()
	_last = at
func _end(at: Vector2) -> void:
	if not _pressed: return
	_pressed = false
	if not _dragged and at.distance_to(_start) < 10: _activate.call_deferred(at)
func _activate(at: Vector2) -> void:
	if not is_inside_tree(): return
	for id in rooms:
		if room_point(id).distance_to(at) <= clampf(30*zoom,15,30):
			room_selected.emit(id)
			return

func fit_view() -> void:
	zoom=clampf(minf((size.x-20)/WORLD.x,(size.y-20)/WORLD.y),0.25,1.0)
	offset=(size-WORLD*zoom)/2
	queue_redraw()

func focus_current() -> void:
	zoom=1.0
	var current: Dictionary=rooms.get(str(graph.get("currentRoomId","")),{})
	if not current.is_empty():offset=size/2-_world_point(current)
	_clamp_offset();queue_redraw()
