extends Control
## Spatial inventory. Selection and scan effects never rebuild its parent UI.
signal item_selected(uid: String)
signal cell_selected(x: int, y: int)
signal selection_changed(uids: Array)
const COLORS := [Color("9ca7b5"), Color("74bc9a"), Color("68ade8"), Color("bc8be8"), Color("efc774"), Color("ed7884")]
var columns := 6
var rows := 5
var items: Array = []
var definitions: Dictionary = {}
var textures: Dictionary = {}
var selected_uid := ""
var selected_uids: Array = []
var multi_select := false
var allow_multi_select := false
var preferred_cell := 42.0
var cell := 42.0
var scan_uid := ""
var scan_progress := 0.0
var flash_uid := ""
var flash_time := 0.0
var _press := Vector2.ZERO
var _pressed := false
var _press_time := 0.0
var _swept: Array = []
var _touch_id := -1
var _dragged := false
var _last_point := Vector2.ZERO
var _pointer_global := Vector2.ZERO

func configure(width: int, height: int, contents: Array, defs: Dictionary, selection: String = "") -> void:
	columns = width; rows = height; items = contents.duplicate(true); definitions = defs; selected_uid = selection
	for id in defs:
		if textures.has(id): continue
		var path := str(defs[id].get("icon", "res://assets/items/extraction/" + str(id) + ".png"))
		if ResourceLoader.exists(path): textures[id] = load(path)
	custom_minimum_size = Vector2(columns * 28, rows * preferred_cell)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_PASS
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_resize_grid()

func _ready() -> void:
	resized.connect(_resize_grid)
	_resize_grid()

func _resize_grid() -> void:
	cell = minf(preferred_cell, maxf(24, floorf(size.x / float(columns)))) if size.x > 0 else preferred_cell
	custom_minimum_size.y = rows * cell
	queue_redraw()

func _process(delta: float) -> void:
	if flash_time > 0:
		flash_time = maxf(0, flash_time-delta); queue_redraw()
	if _pressed and multi_select:
		var ancestor=get_parent()
		while ancestor!=null and not ancestor is ScrollContainer:ancestor=ancestor.get_parent()
		if ancestor is ScrollContainer:
			var visible: Rect2=ancestor.get_global_rect()
			var speed:=0.0
			if _pointer_global.y<visible.position.y+26:speed=-180.0
			elif _pointer_global.y>visible.end.y-26:speed=180.0
			if speed!=0:
				ancestor.scroll_vertical+=roundi(speed*delta)
				_sweep(_pointer_global-global_position)
	if allow_multi_select and _pressed and not _dragged and not multi_select and Time.get_ticks_msec()/1000.0-_press_time > 0.45:
		var item := _item_at(_press)
		if not item.is_empty():
			multi_select=true; set_meta("inventory_selection",true); _sweep(_press); accept_event()

func set_scan(uid: String, progress: float) -> void:
	scan_uid=uid; scan_progress=progress; queue_redraw()

func reveal_flash(uid: String) -> void:
	flash_uid=uid; flash_time=0.55; queue_redraw()

func item_size(item: Dictionary) -> Vector2i:
	var d: Dictionary=definitions.get(str(item.get("itemId","")),{})
	var w:=int(d.get("width",1));var h:=int(d.get("height",1))
	return Vector2i(h,w) if item.get("rotated",false) else Vector2i(w,h)

func item_rect(item: Dictionary) -> Rect2:
	var dims:=item_size(item)
	return Rect2(int(item.get("x",0))*cell+2,int(item.get("y",0))*cell+2,dims.x*cell-4,dims.y*cell-4)

func _draw() -> void:
	var font:=get_theme_default_font()
	for y in rows:
		for x in columns:
			draw_rect(Rect2(x*cell+1,y*cell+1,cell-2,cell-2),Color("101c29"))
			draw_rect(Rect2(x*cell+1,y*cell+1,cell-2,cell-2),Color("263747"),false,1)
	for item in items:
		var id:=str(item.get("itemId",""));var uid:=str(item.get("uid",""))
		var d: Dictionary=definitions.get(id,{})
		var rect:=item_rect(item)
		var unknown: bool=d.get("kind","")=="unknown"
		var color: Color=COLORS[clampi(int(d.get("rarity",0)),0,5)]
		var chosen:=uid==selected_uid or selected_uids.has(uid)
		draw_rect(rect,color.darkened(0.86))
		draw_rect(rect,Color.WHITE if chosen else color.darkened(0.35),false,2 if chosen else 1)
		if unknown:
			var c:=rect.get_center()
			draw_arc(c,7,0,TAU,24,Color("5e7182"),1.5,true)
			draw_line(c+Vector2(5,5),c+Vector2(10,10),Color("5e7182"),2,true)
		else:
			draw_rect(Rect2(rect.position,Vector2(3,rect.size.y)),color)
			var texture=textures.get(id)
			if texture is Texture2D:
				# Every occupied cell has an icon, including one-cell items at phone scale.
				var icon_rect:=rect.grow(-5)
				if rect.size.y>=70:icon_rect.size.y-=17
				var side:=minf(icon_rect.size.x,icon_rect.size.y)
				draw_texture_rect(texture,Rect2(icon_rect.get_center()-Vector2.ONE*side/2,Vector2.ONE*side),false)
			else:
				draw_circle(rect.get_center(),5,color)
			if rect.size.y>=70:
				var title:=str(d.get("name","物资"))
				draw_rect(Rect2(rect.position.x,rect.end.y-18,rect.size.x,18),Color(0.025,0.04,0.065,0.85))
				draw_string(font,Vector2(rect.position.x+4,rect.end.y-5),title,HORIZONTAL_ALIGNMENT_LEFT,rect.size.x-8,11,color.lightened(0.2))
		if uid==scan_uid:
			# Clipped diagonal scan marks give the active unknown item a distinct state.
			for stripe in range(-int(rect.size.y),int(rect.size.x),12):
				var a:=Vector2(rect.position.x+maxi(0,stripe),rect.position.y+maxi(0,-stripe))
				var extent:=minf(rect.end.x-a.x,rect.end.y-a.y)
				draw_line(a,a+Vector2(extent,extent),Color(0.4,0.7,0.75,0.16),1,true)
			var y:=rect.position.y+rect.size.y*scan_progress
			draw_rect(Rect2(rect.position,Vector2(rect.size.x,rect.size.y*scan_progress)),Color(0.35,0.85,0.9,0.10))
			draw_line(Vector2(rect.position.x,y),Vector2(rect.end.x,y),Color("9ce4e3"),2,true)
		if uid==flash_uid and flash_time>0:
			draw_rect(rect,Color(color,flash_time*0.6))
		if selected_uids.has(uid):
			draw_circle(rect.position+Vector2(10,10),8,Color("dfbd78"))
			draw_line(rect.position+Vector2(6,10),rect.position+Vector2(9,13),Color("172431"),2)
			draw_line(rect.position+Vector2(9,13),rect.position+Vector2(14,7),Color("172431"),2)

func _get_tooltip(at_position: Vector2) -> String:
	var item:=_item_at(at_position)
	if item.is_empty():return "空格"
	var d: Dictionary=definitions.get(str(item.get("itemId","")),{})
	if d.get("kind","")=="unknown":return "未搜索物资"
	return "%s · %d × %d · 金币 %d" % [d.get("name","物资"),d.get("width",1),d.get("height",1),item.get("displayValue",d.get("value",0))]

func _item_at(point: Vector2) -> Dictionary:
	var pos:=Vector2i(floori(point.x/cell),floori(point.y/cell))
	for item in items:
		if Rect2i(Vector2i(int(item.get("x",0)),int(item.get("y",0))),item_size(item)).has_point(pos):return item
	return {}

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _touch_id==-1:_touch_id=event.index;_begin(event.position)
		elif not event.pressed and event.index==_touch_id:_touch_id=-1;_end(event.position)
	elif event is InputEventScreenDrag and event.index==_touch_id:_move(event.position)
	elif event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and _touch_id==-1:
		if event.pressed:_begin(event.position)
		else:_end(event.position)
	elif event is InputEventMouseMotion and _pressed and _touch_id==-1:_move(event.position)
	if multi_select and _pressed:accept_event()

func _begin(at: Vector2) -> void:
	_press=at;_last_point=at;_pointer_global=global_position+at;_pressed=true;_dragged=false;_press_time=Time.get_ticks_msec()/1000.0;_swept.clear()
	if multi_select:set_meta("inventory_selection",true);_sweep(at)
func _move(at: Vector2) -> void:
	if not _pressed:return
	if at.distance_to(_press)>10:_dragged=true
	_pointer_global=global_position+at
	if multi_select:
		var steps:=maxi(1,ceili(at.distance_to(_last_point)/maxf(5,cell/3)))
		for step in range(1,steps+1):_sweep(_last_point.lerp(at,float(step)/steps))
		accept_event()
	_last_point=at
func _end(at: Vector2) -> void:
	if not _pressed:return
	_pressed=false
	if multi_select:return
	if not _dragged and at.distance_to(_press)<10:_activate.call_deferred(at)
func _sweep(at: Vector2) -> void:
	var item:=_item_at(at)
	if item.is_empty():return
	var uid:=str(item.uid)
	if _swept.has(uid):return
	_swept.append(uid)
	if selected_uids.has(uid):selected_uids.erase(uid)
	else:selected_uids.append(uid)
	selection_changed.emit(selected_uids.duplicate());queue_redraw()
func _activate(point: Vector2) -> void:
	if not is_inside_tree():return
	var item:=_item_at(point)
	if not item.is_empty():selected_uid=str(item.uid);queue_redraw();item_selected.emit(selected_uid)
	else:
		var x:=floori(point.x/cell);var y:=floori(point.y/cell)
		if x>=0 and y>=0 and x<columns and y<rows:cell_selected.emit(x,y)
