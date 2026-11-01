extends Control
## Touch-first expedition atlas. The world is independent from the camera and
## every room keeps its model id; layout decoration never changes game state.
signal room_selected(id: String)
signal room_previewed(id: String)
var graph: Dictionary = {}
var rooms: Dictionary = {}
var selected_room_id := ""
var offset := Vector2.ZERO
var zoom := 1.0
var _last := Vector2.ZERO
var _start := Vector2.ZERO
var _pressed := false
var _dragged := false
var _touch_id := -1
var _initial := true
var _auto_fit := true
var _last_view_center := Vector2.ZERO
var _touches: Dictionary = {}
var _pinching := false
var _velocity := Vector2.ZERO
var _last_motion_ms := 0
var _toolbar: HBoxContainer
var _motion_layer: Control
var reduced_motion := false:
	set(value):
		reduced_motion = value
		if is_instance_valid(_motion_layer):
			_motion_layer.set_process(not value)
			_motion_layer.queue_redraw()
		queue_redraw()
const WORLD := Vector2(1320, 850)
const PAD := Vector2(100, 120)
const GOLD := Color("edcf94")
const CYAN := Color("91dfd4")
const MUTED := Color("71828a")
const TYPE_NAMES := {"entry":"入口", "cache":"物资", "battle":"敌人", "elite":"精英", "event":"奇遇", "rest":"营地", "boss":"首领", "hospital":"药房", "workshop":"工坊", "vault":"宝库", "shrine":"神龛", "key_vault":"钥匙房", "relay":"寄存点"}
const THEME_COLORS := {"ruins":Color("756553"), "forest":Color("3f7165"), "sanctum":Color("62648b")}

func configure(value: Dictionary, reduce_motion: bool=false) -> void:
	reduced_motion = reduce_motion
	graph = value.duplicate(true)
	rooms.clear()
	for room in graph.get("rooms", []): rooms[str(room.id)] = room
	selected_room_id = str(graph.get("currentRoomId", ""))
	_auto_fit = true
	custom_minimum_size = Vector2(0, 320)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_meta("extraction_pan", true)
	if is_inside_tree(): fit_view()
	queue_redraw()

func _ready() -> void:
	resized.connect(_resize)
	_motion_layer = RouteMotion.new()
	_motion_layer.name = "AtlasRouteMotion"
	_motion_layer.atlas = self
	_motion_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_motion_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_motion_layer)
	_motion_layer.set_process(not reduced_motion)
	_toolbar = HBoxContainer.new()
	_toolbar.name = "AtlasTools"
	_toolbar.add_theme_constant_override("separation", 5)
	_toolbar.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_toolbar)
	_tool("全图", fit_view, "AtlasFit")
	_tool("定位", focus_current, "AtlasFocus")
	_tool("−", func(): zoom_at(_view_rect().get_center(), zoom / 1.25), "AtlasZoomOut")
	_tool("＋", func(): zoom_at(_view_rect().get_center(), zoom * 1.25), "AtlasZoomIn")
	_resize()

func _tool(caption: String, action: Callable, node_name: String) -> void:
	var button := Button.new()
	button.name = node_name
	button.text = caption
	button.custom_minimum_size = Vector2(42 if caption in ["−","＋"] else 52, 36)
	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_color_override("font_color", Color("dbe7e6"))
	for state in ["normal", "hover", "pressed", "focus"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color("223b42") if state in ["hover", "pressed"] else Color("13272e")
		box.border_color = Color("6b9b94") if state in ["pressed", "focus"] else Color("365057")
		box.set_border_width_all(1)
		box.set_corner_radius_all(6)
		button.add_theme_stylebox_override(state, box)
	button.pressed.connect(action)
	_toolbar.add_child(button)

func _view_rect() -> Rect2:
	return Rect2(Vector2(12, 51), Vector2(maxf(1,size.x-24), maxf(1,size.y-89)))

func _resize() -> void:
	if _toolbar:
		_toolbar.position = Vector2(maxf(12,size.x-218), 8)
	if size.x > 40 and size.y > 100:
		if _initial or _auto_fit:
			# Containers can negotiate several sizes after _ready. Keep the
			# untouched map in overview until the final layout has settled.
			fit_view()
		else:
			var center_world := (_last_view_center-offset)/zoom
			zoom = maxf(zoom, _minimum_zoom())
			offset = _view_rect().get_center()-center_world*zoom
		_initial = false
		_clamp_offset()
	_last_view_center = _view_rect().get_center()
	queue_redraw()

func _unscaled_point(room: Dictionary) -> Vector2:
	var normalized := Vector2(float(room.get("x", 0.5)), float(room.get("y", 0.5)))
	return PAD + normalized * (WORLD - PAD * 2.0)

func _world_point(room: Dictionary) -> Vector2:
	return _unscaled_point(room) * zoom

func room_point(id: String) -> Vector2:
	return _world_point(rooms.get(id, {})) + offset

func adjacent_ids() -> Array:
	var result: Array = []
	var current := str(graph.get("currentRoomId", ""))
	for edge in graph.get("edges", []):
		if edge[0] == current: result.append(str(edge[1]))
		elif edge[1] == current: result.append(str(edge[0]))
	return result

func reachable_ids() -> Array:
	# Travel permission comes from the model. The fallback only preserves
	# physical-neighbor behavior for older callers and isolated previews.
	var candidates: Array = graph.get("reachableRoomIds", adjacent_ids())
	var result: Array = []
	for value in candidates:
		var id := str(value)
		if rooms.has(id) and id != str(graph.get("currentRoomId", "")) and id not in result:
			result.append(id)
	return result

func travel_path(id: String) -> Array:
	var current := str(graph.get("currentRoomId", ""))
	if id == current:return [current]
	if id not in reachable_ids():return []
	var paths: Dictionary = graph.get("travelPaths", {})
	var path: Array = paths.get(id, [current,id] if id in adjacent_ids() else []).duplicate()
	if path.size()<2 or str(path[0])!=current or str(path[-1])!=id:return []
	for index in range(path.size()):
		path[index]=str(path[index])
		if not rooms.has(path[index]):return []
		if index>0 and not _edge_exists(path[index-1],path[index]):return []
	return path

func _edge_exists(a: String,b: String) -> bool:
	for edge in graph.get("edges",[]):
		if (str(edge[0])==a and str(edge[1])==b) or (str(edge[0])==b and str(edge[1])==a):return true
	return false

func _on_path(path: Array,a: String,b: String) -> bool:
	for index in range(1,path.size()):
		if (path[index-1]==a and path[index]==b) or (path[index-1]==b and path[index]==a):return true
	return false

func frontier_ids() -> Array:
	var result: Array = []
	for id in reachable_ids():
		if not bool(rooms[id].get("visited",false)):result.append(id)
	return result

func _known(id: String) -> bool:
	# Surveyed and adjacent landmarks use full contrast. Distant rooms retain
	# their type icon so players can plan a route without seeing their loot.
	var room: Dictionary = rooms[id]
	return bool(room.get("visited",false)) or id in reachable_ids() or bool(room.get("discovered",false)) or room.get("type","") in ["boss","vault","shrine","elite","key_vault","relay"]

func _district_bounds(district_id: String) -> Rect2:
	var first := true
	var bounds := Rect2()
	for id in rooms:
		if str(rooms[id].get("districtId", "")) != district_id: continue
		var p: Vector2 = _world_point(rooms[id]) / zoom
		if first: bounds = Rect2(p, Vector2.ONE); first = false
		else: bounds = bounds.expand(p)
	return bounds.grow(65)

func _screen(world: Vector2) -> Vector2:
	return world * zoom + offset

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size), Color("0a151c"))
	# Contour lines belong to the landscape, not a graph-paper background.
	for band in range(9):
		var points := PackedVector2Array()
		for step in range(35):
			var x := float(step)*42.0
			var y := 48.0 + band*94.0 + sin(x*0.007+band*0.9)*22.0 + sin(x*0.018+band)*10.0
			points.append(_screen(Vector2(x,y)))
		draw_polyline(points,Color(0.23,0.38,0.41,0.13),1.0,true)
	for district in graph.get("districts", []): _draw_district(district)
	var adjacent := reachable_ids()
	var selected_path := travel_path(selected_room_id)
	for edge in graph.get("edges", []):
		var a := str(edge[0]); var b := str(edge[1])
		if not rooms.has(a) or not rooms.has(b): continue
		var near := (a == str(graph.get("currentRoomId","")) and b in adjacent) or (b == str(graph.get("currentRoomId","")) and a in adjacent)
		var explored := bool(rooms[a].get("visited",false)) and bool(rooms[b].get("visited",false))
		var highlighted := _on_path(selected_path,a,b)
		var color := GOLD if highlighted else (CYAN if near else (Color("738e8a") if explored else Color("384c54")))
		var from := room_point(a); var to := room_point(b)
		draw_line(from,to,Color("081217"),7.0,true)
		if near or explored or highlighted:
			draw_line(from,to,color,3.0 if highlighted else 2.5 if near else 1.6,true)
			if highlighted:
				var forward := false
				for i in range(1,selected_path.size()):
					if selected_path[i-1]==a and selected_path[i]==b:forward=true;break
				_arrow(from.lerp(to,0.56),(to-from).normalized() if forward else (from-to).normalized(),color)
			elif near: _arrow(from.lerp(to,0.56), (to-from).normalized() if a == str(graph.get("currentRoomId","")) else (from-to).normalized(),color)
		else:
			_dashed(from,to,color)
	# Draw lower priority nodes first; selected rings are always legible.
	for id in rooms:
		if id != selected_room_id: _draw_room(str(id),adjacent)
	if rooms.has(selected_room_id): _draw_room(selected_room_id,adjacent)
	_draw_chrome()
	if is_instance_valid(_motion_layer):_motion_layer.queue_redraw()

func _draw_district(district: Dictionary) -> void:
	var theme := str(district.get("theme","ruins"))
	var color: Color = THEME_COLORS.get(theme, THEME_COLORS.ruins)
	var bounds := _district_bounds(str(district.id))
	var rect := Rect2(_screen(bounds.position),bounds.size*zoom)
	# Uneven polygon shoreline, with hand-drafted silhouettes for each biome.
	var p := bounds.position
	var s := bounds.size
	var land := PackedVector2Array([p+Vector2(s.x*.08,0),p+Vector2(s.x*.8,4),p+Vector2(s.x,s.y*.16),p+Vector2(s.x*.95,s.y*.78),p+Vector2(s.x*.78,s.y),p+Vector2(s.x*.15,s.y*.96),p+Vector2(0,s.y*.7),p+Vector2(5,s.y*.2)])
	var contour := PackedVector2Array()
	for point in land: contour.append(_screen(point))
	draw_colored_polygon(contour,Color(color,0.13))
	contour.append(contour[0]);draw_polyline(contour,Color(color,0.28),1.0,true)
	for scale_factor in [.86,.72]:
		var inner := PackedVector2Array()
		for point in land:inner.append(_screen(bounds.get_center()+(point-bounds.get_center())*scale_factor))
		inner.append(inner[0]);draw_polyline(inner,Color(color,.12),1.0,true)
	for n in range(42):
		var fx := fposmod(float(n)*0.6180339+0.17,1.0)
		var fy := fposmod(float(n)*0.4142135+0.11,1.0)
		var pos := _screen(p+Vector2(s.x*fx,s.y*fy))
		var radius := 14.0*zoom
		# Keep landmarks clear rather than placing scenery below their icons.
		var near_room := false
		for id in rooms:
			if room_point(id).distance_to(pos)<34: near_room = true;break
		if near_room: continue
		if theme == "forest":
			var triangle := PackedVector2Array([pos+Vector2(0,-radius),pos+Vector2(radius*.7,radius*.6),pos+Vector2(-radius*.7,radius*.6)])
			draw_colored_polygon(triangle,Color(color,0.42))
			draw_line(pos,pos+Vector2(0,radius),Color(color.lightened(.1),.35),1.0)
		elif theme == "ruins":
			draw_rect(Rect2(pos,Vector2(radius*1.8,radius)),Color(color,.28),false,1.0)
			draw_line(pos+Vector2(radius*.5,0),pos+Vector2(radius*.5,radius),Color(color,.35),1.0)
		else:
			var crystal := PackedVector2Array([pos+Vector2(0,-radius),pos+Vector2(radius*.45,0),pos+Vector2(0,radius),pos+Vector2(-radius*.45,0),pos+Vector2(0,-radius)])
			draw_polyline(crystal,Color(color.lightened(.1),.4),1.0,true)
	var title := str(district.get("name",district.id))
	var font := get_theme_default_font()
	var title_width := font.get_string_size(title,HORIZONTAL_ALIGNMENT_LEFT,-1,13).x+24
	var title_pos := Vector2(rect.get_center().x-title_width/2,rect.position.y-23)
	var plate := Rect2(title_pos,Vector2(title_width,23))
	draw_style_box(_plate(Color("0f2027"),Color(color,.6),4),plate)
	draw_string(font,title_pos+Vector2(12,16),title,HORIZONTAL_ALIGNMENT_LEFT,-1,13,color.lightened(.38))

func _draw_room(id: String, adjacent: Array) -> void:
	var room: Dictionary = rooms[id]
	var center := room_point(id)
	if not Rect2(Vector2(-60,-60),size+Vector2(120,120)).has_point(center): return
	var current: bool = id == str(graph.get("currentRoomId", ""))
	var visited := bool(room.get("visited",false))
	var kind := str(room.get("type","cache"))
	var known := _known(id)
	var boss := kind == "boss"
	var color := CYAN if id in adjacent else Color("8b9ba1")
	if kind in ["elite","battle"]: color = Color("d88b7e") if known else MUTED
	if kind in ["vault","shrine","key_vault"]: color = Color("c6a3e3")
	if boss: color = GOLD if graph.get("bossUnlocked",false) else Color("ae877a")
	if current: color = GOLD
	var radius := clampf(24 * sqrt(zoom),15,25)
	var selected := id == selected_room_id
	if id in adjacent and not visited and not current:
		draw_arc(center,radius+4,0,TAU,40,Color(CYAN,.32),1.1,true)
	if selected:
		draw_circle(center,radius+7,Color(color,.12))
		draw_arc(center,radius+6,-PI*.4,PI*.4,24,color,1.6,true)
		draw_arc(center,radius+6,PI*.6,PI*1.4,24,color,1.6,true)
	draw_circle(center+Vector2(0,2),radius+2,Color(0,0,0,.5))
	draw_circle(center,radius,Color("14272e") if known else Color("101e26"))
	draw_arc(center,radius,0,TAU,48,Color(color,.85 if known else .36),1.6,true)
	if visited: draw_arc(center,radius-3,0,TAU,48,Color(color,.18),1.0,true)
	_draw_icon(center,kind,radius*.58,color if known else MUTED)
	if current:
		var marker := center+Vector2(0,-radius-10)
		draw_colored_polygon(PackedVector2Array([marker+Vector2(-4,-4),marker+Vector2(4,-4),marker+Vector2(0,2)]),GOLD)
	if bool(room.get("cleared",false)) and not current:
		var badge := center+Vector2(radius*.75,radius*.7)
		draw_circle(badge,6,Color("132b2a"));draw_arc(badge,6,0,TAU,16,CYAN,1.0,true)
		draw_polyline(PackedVector2Array([badge+Vector2(-3,0),badge+Vector2(-1,2),badge+Vector2(3,-2)]),CYAN,1.0,true)
	if (boss and not graph.get("bossUnlocked",false)) or (kind == "key_vault" and not room.get("unlocked",false)):
		var lock := center+Vector2(radius*.7,-radius*.7)
		draw_circle(lock,7,Color("1b2228"));_draw_icon(lock,"lock",4,GOLD)
	# Only one persistent label. Full names and actions live in the adjacent
	# preview panel, keeping small maps free from overlapping text.
	if selected and zoom >= 0.5:
		var label := str(room.get("name",TYPE_NAMES.get(kind,"遗迹")))
		var font := get_theme_default_font()
		var width := minf(160,font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,13).x+18)
		var rect := Rect2(center+Vector2(-width/2,radius+11),Vector2(width,24))
		draw_style_box(_plate(Color("0a171e"),Color(color,.5),4),rect)
		draw_string(font,rect.position+Vector2(9,16),label,HORIZONTAL_ALIGNMENT_LEFT,width-18,13,color)

func _draw_icon(p: Vector2, kind: String, r: float, color: Color) -> void:
	var w := maxf(1.3,r*.13)
	match kind:
		"cache","vault","relay":
			draw_rect(Rect2(p+Vector2(-r,-r*.55),Vector2(r*2,r*1.3)),color,false,w)
			draw_line(p+Vector2(-r,-r*.1),p+Vector2(r,-r*.1),color,w,true)
			draw_rect(Rect2(p+Vector2(-r*.15,-r*.25),Vector2(r*.3,r*.5)),color)
			if kind == "relay":
				_arrow(p+Vector2(0,-r*.9),Vector2.DOWN,color,r*.35)
			if kind == "vault":
				draw_line(p+Vector2(-r*.65,-r*.9),p+Vector2(r*.65,-r*.9),color,w,true)
		"battle","elite":
			for sign_value in [-1,1]:
				var direction := Vector2(float(sign_value),-1).normalized()
				draw_line(p-direction*r*.7,p+direction*r,color,w,true)
				var side := Vector2(-direction.y,direction.x)*r*.32
				draw_line(p-direction*r*.35-side,p-direction*r*.35+side,color,w,true)
			if kind == "elite": draw_arc(p,r*1.2,PI*.1,PI*.9,16,color,w,true)
		"rest":
			draw_polyline(PackedVector2Array([p+Vector2(-r,r*.7),p+Vector2(0,-r*.8),p+Vector2(r,r*.7),p+Vector2(-r,r*.7)]),color,w,true)
			draw_polyline(PackedVector2Array([p+Vector2(-r*.35,r*.7),p+Vector2(0,-r*.1),p+Vector2(r*.35,r*.7)]),color,w,true)
		"hospital":
			draw_line(p-Vector2(r*.75,0),p+Vector2(r*.75,0),color,w*2.6,true)
			draw_line(p-Vector2(0,r*.75),p+Vector2(0,r*.75),color,w*2.6,true)
		"workshop":
			draw_arc(p,r*.7,0,TAU,18,color,w,true)
			draw_circle(p,r*.22,color)
			for i in range(6):
				var v := Vector2.from_angle(i*TAU/6)
				draw_line(p+v*r*.7,p+v*r*1.1,color,w*1.6,true)
		"shrine":
			draw_polyline(PackedVector2Array([p+Vector2(0,-r),p+Vector2(r*.6,0),p+Vector2(0,r*.65),p+Vector2(-r*.6,0),p+Vector2(0,-r)]),color,w,true)
			draw_line(p+Vector2(-r,r),p+Vector2(r,r),color,w,true)
		"boss":
			draw_polyline(PackedVector2Array([p+Vector2(-r,-r*.5),p+Vector2(-r*.7,r*.6),p+Vector2(r*.7,r*.6),p+Vector2(r,-r*.5),p+Vector2(r*.4,0),p+Vector2(0,-r*.9),p+Vector2(-r*.4,0),p+Vector2(-r,-r*.5)]),color,w,true)
			draw_line(p+Vector2(-r*.7,r),p+Vector2(r*.7,r),color,w,true)
		"entry":
			draw_arc(p,r*.8,PI,TAU,20,color,w,true)
			draw_line(p+Vector2(-r*.8,0),p+Vector2(-r*.8,r),color,w,true)
			draw_line(p+Vector2(r*.8,0),p+Vector2(r*.8,r),color,w,true)
			draw_line(p,p+Vector2(0,r*.8),color,w,true)
			_arrow(p,Vector2.UP,color,r*.35)
		"key_vault":
			draw_rect(Rect2(p+Vector2(-r,-r*.9),Vector2(r*2,r*1.8)),color,false,w)
			draw_circle(p+Vector2(-r*.3,-r*.1),r*.26,color)
			draw_line(p+Vector2(-r*.1,-r*.1),p+Vector2(r*.65,-r*.1),color,w,true)
			draw_line(p+Vector2(r*.5,-r*.1),p+Vector2(r*.5,r*.3),color,w,true)
		"lock":
			draw_rect(Rect2(p+Vector2(-r,-r*.1),Vector2(r*2,r*1.2)),color,false,w)
			draw_arc(p+Vector2(0,-r*.1),r*.6,PI,TAU,12,color,w,true)
		"event":
			var star := PackedVector2Array()
			for i in range(8):star.append(p+Vector2.from_angle(-PI/2+i*PI/4)*r*(1.0 if i%2==0 else .32))
			star.append(star[0]);draw_polyline(star,color,w,true)
		_:
			draw_arc(p-Vector2(0,r*.2),r*.4,PI,TAU*1.1,16,color,w,true)
			draw_line(p+Vector2(r*.3,0),p+Vector2(0,r*.35),color,w,true)
			draw_circle(p+Vector2(0,r*.75),w*.8,color)

func _arrow(p: Vector2, direction: Vector2, color: Color, radius: float=4.0) -> void:
	var side := Vector2(-direction.y,direction.x)
	draw_polyline(PackedVector2Array([p-direction*radius+side*radius*.7,p+direction*radius,p-direction*radius-side*radius*.7]),color,1.5,true)

func _dashed(a: Vector2, b: Vector2, color: Color) -> void:
	var length := a.distance_to(b)
	if length < 1: return
	for n in range(int(length/10.0)+1):
		var start := float(n)*10.0
		draw_line(a.lerp(b,start/length),a.lerp(b,minf(start+5,length)/length),color,1.2,true)

func _plate(background: Color, border: Color, corner: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color=background;style.border_color=border
	style.set_corner_radius_all(corner);style.set_border_width_all(1)
	return style

func _draw_chrome() -> void:
	var font := get_theme_default_font()
	draw_rect(Rect2(0,0,size.x,49),Color("0d1c24"))
	draw_line(Vector2(0,49),Vector2(size.x,49),Color("2b424a"),1)
	draw_string(font,Vector2(15,22),"遗境地图",HORIZONTAL_ALIGNMENT_LEFT,maxf(20,size.x-242),15,GOLD)
	if size.x>430:draw_string(font,Vector2(15,40),"拖动探索 · 双指缩放",HORIZONTAL_ALIGNMENT_LEFT,190,11,MUTED)
	draw_rect(Rect2(0,size.y-34,size.x,34),Color("0d1c24"))
	draw_line(Vector2(0,size.y-34),Vector2(size.x,size.y-34),Color("2b424a"),1)
	var x := 17.0
	for entry in [[CYAN,"可前往"],[Color("c6a3e3"),"珍稀点"],[Color("d88b7e"),"危险"]]:
		draw_circle(Vector2(x,size.y-16),3,entry[0])
		draw_string(font,Vector2(x+9,size.y-12),entry[1],HORIZONTAL_ALIGNMENT_LEFT,-1,11,entry[0])
		x+=76
	if size.x>360:
		draw_string(font,Vector2(size.x-104,size.y-12),"探索 %d / %d" % [int(graph.get("explored",0)),rooms.size()-1],HORIZONTAL_ALIGNMENT_RIGHT,88,11,MUTED)
	draw_rect(Rect2(Vector2.ZERO,size),Color("35515a"),false,1)

func _clamp_offset() -> void:
	var view := _view_rect()
	var content := _content_bounds()
	var centered := view.get_center() - content.get_center()*zoom
	for axis in range(2):
		var extent: float = content.size[axis]*zoom
		# Vector2 uses float32 while zoom is float64: fitted extents can be
		# a few ulps above the viewport. Do not unlock the 24px pan margin
		# for invisible subpixel overflow at the exact fitted boundary.
		if extent <= view.size[axis] + 0.01:
			# fit_view uses the same content center. A first drag must never
			# jump from content-centered to decorative-world-centered framing.
			offset[axis] = centered[axis]
		else:
			var lower: float = view.end[axis] - content.end[axis]*zoom - 24.0
			var upper: float = view.position[axis] - content.position[axis]*zoom + 24.0
			offset[axis] = clampf(offset[axis], lower, upper)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index]=event.position
			if _touches.size()==1: _touch_id=event.index;_begin(event.position)
			else: _pinching=true;_dragged=true;_velocity=Vector2.ZERO
		else:
			_touches.erase(event.index)
			if _touches.is_empty():
				if _pinching: _pressed=false
				else: _end(event.position)
				_touch_id=-1;_pinching=false
			elif _touches.size()==1:
				_touch_id=int(_touches.keys()[0]);_last=_touches[_touch_id]
		accept_event()
	elif event is InputEventScreenDrag and _touches.has(event.index):
		if _touches.size()>=2:
			var ids := _touches.keys()
			var before_a: Vector2=_touches[ids[0]];var before_b: Vector2=_touches[ids[1]]
			_touches[event.index]=event.position
			var after_a: Vector2=_touches[ids[0]];var after_b: Vector2=_touches[ids[1]]
			var old_distance := before_a.distance_to(before_b)
			if old_distance>5:zoom_at((before_a+before_b)/2,zoom*after_a.distance_to(after_b)/old_distance)
			offset+=(after_a+after_b-before_a-before_b)/2;_clamp_offset();queue_redraw()
		else:
			_touches[event.index]=event.position;_move(event.position)
		accept_event()
	elif event is InputEventMouseButton and _touch_id==-1:
		if event.button_index==MOUSE_BUTTON_LEFT:
			if event.pressed:_begin(event.position)
			else:_end(event.position)
			accept_event()
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			zoom_at(event.position,zoom*(1.12 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1.0/1.12));accept_event()
	elif event is InputEventMouseMotion and _pressed and _touch_id==-1:
		_move(event.position);accept_event()
	elif event is InputEventMagnifyGesture:
		zoom_at(event.position,zoom*event.factor);accept_event()

func _begin(at: Vector2) -> void:
	if not _view_rect().has_point(at):return
	_pressed=true;_dragged=false;_last=at;_start=at;_velocity=Vector2.ZERO
	_last_motion_ms=Time.get_ticks_msec()

func _move(at: Vector2) -> void:
	if not _pressed:return
	if at.distance_to(_start)>7:_dragged=true
	if _dragged:
		var now := Time.get_ticks_msec()
		var delta := maxf(.008,float(now-_last_motion_ms)/1000.0)
		_velocity=_velocity.lerp((at-_last)/delta,.6).limit_length(1800)
		var before := offset
		offset+=at-_last;_clamp_offset()
		if not offset.is_equal_approx(before): _auto_fit=false
		queue_redraw();_last_motion_ms=now
	_last=at

func _end(at: Vector2) -> void:
	if not _pressed:return
	_pressed=false
	if not _dragged and at.distance_to(_start)<7:_activate.call_deferred(at)
	elif Time.get_ticks_msec()-_last_motion_ms>120:_velocity=Vector2.ZERO

func _process(delta: float) -> void:
	if _pressed or _velocity.length()<4:return
	offset+=_velocity*delta
	_velocity=_velocity.move_toward(Vector2.ZERO,2300*delta)
	_clamp_offset();queue_redraw()

func _activate(at: Vector2) -> void:
	if not is_inside_tree() or not _view_rect().has_point(at):return
	var candidate := ""
	var distance := 22.0
	for id in rooms:
		var d := room_point(id).distance_to(at)
		if d<distance: candidate=str(id);distance=d
	if candidate.is_empty():return
	var previous := selected_room_id
	selected_room_id=candidate
	room_previewed.emit(candidate)
	queue_redraw()
	# Existing callers keep single-tap navigation; split-workspace callers
	# subscribe to previews and use a clear dedicated travel button.
	if previous==candidate or room_previewed.get_connections().is_empty():room_selected.emit(candidate)

func zoom_at(anchor: Vector2, next_zoom: float) -> void:
	_auto_fit = false
	var world := (anchor-offset)/zoom
	zoom=clampf(next_zoom,_minimum_zoom(),1.8)
	offset=anchor-world*zoom
	_velocity=Vector2.ZERO;_clamp_offset();queue_redraw()

func _content_bounds() -> Rect2:
	if rooms.is_empty():return Rect2(Vector2.ZERO,WORLD)
	var first := true
	var bounds := Rect2()
	for id in rooms:
		var point := _unscaled_point(rooms[id])
		if first:bounds=Rect2(point,Vector2.ONE);first=false
		else:bounds=bounds.expand(point)
	return Rect2(bounds.position-Vector2(85,145),bounds.size+Vector2(170,235))

func _minimum_zoom() -> float:
	var view := _view_rect()
	var content := _content_bounds()
	return clampf(minf(view.size.x/content.size.x,view.size.y/content.size.y),.2,1.0)

func fit_view() -> void:
	_auto_fit = true
	zoom=_minimum_zoom()
	var view := _view_rect()
	offset=view.get_center()-_content_bounds().get_center()*zoom
	_last_view_center = view.get_center()
	_velocity=Vector2.ZERO;queue_redraw()

func focus_current() -> void:
	_auto_fit = false
	zoom=maxf(_minimum_zoom(),.75)
	var current: Dictionary=rooms.get(str(graph.get("currentRoomId","")),{})
	if not current.is_empty():offset=_view_rect().get_center()-_world_point(current)
	selected_room_id=str(graph.get("currentRoomId",""))
	_velocity=Vector2.ZERO;_clamp_offset();queue_redraw()


func _draw_route_motion(canvas: Control, phase: float) -> void:
	if reduced_motion:return
	var pulse := (sin(phase*TAU)+1.0)*0.5
	var view := _view_rect()
	for id in frontier_ids():
		var center := room_point(id)
		var radius := clampf(24*sqrt(zoom),15,25)+5.0+pulse*2.5
		if not view.grow(-radius).has_point(center):continue
		canvas.draw_arc(center,radius,0,TAU,40,Color(CYAN,.08+pulse*.20),1.4,true)
	var path := travel_path(selected_room_id)
	if path.size()<2:return
	var lengths: Array[float]=[]
	var total := 0.0
	for i in range(1,path.size()):
		var length := room_point(path[i-1]).distance_to(room_point(path[i]))
		lengths.append(length);total+=length
	if total<1:return
	# One low-speed marker travels along the entire validated route rather
	# than flashing every road or suggesting a straight-line teleport.
	var distance := fposmod(phase*72.0,total)
	for i in range(lengths.size()):
		if distance<=lengths[i]:
			var point := room_point(path[i]).lerp(room_point(path[i+1]),distance/maxf(1,lengths[i]))
			if view.grow(-5).has_point(point):
				canvas.draw_circle(point,4.0,Color(GOLD,.12))
				canvas.draw_circle(point,1.8,Color(GOLD,.8))
			break
		distance-=lengths[i]

class RouteMotion extends Control:
	var atlas
	var phase := 0.0
	var _elapsed := 0.0
	func _process(delta: float) -> void:
		if not is_instance_valid(atlas) or atlas.reduced_motion or not is_visible_in_tree():return
		phase+=delta/2.8
		_elapsed+=delta
		if _elapsed>=1.0/30.0:
			_elapsed=0.0
			if not atlas.frontier_ids().is_empty() or atlas.travel_path(atlas.selected_room_id).size()>1:queue_redraw()
	func _draw() -> void:
		if is_instance_valid(atlas):atlas._draw_route_motion(self,phase)
