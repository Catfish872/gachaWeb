extends Control
signal container_selected(id: String)
var scene: Dictionary = {}
var containers: Array = []
var selected := ""
var backdrop: Texture2D
var sprites: Dictionary = {}
var pan := Vector2.ZERO
var canvas_size := Vector2(680,400)
var _press := Vector2.ZERO
var _last := Vector2.ZERO
var _pressed := false
var _dragged := false
var _touch_id := -1
var _pan_velocity := Vector2.ZERO
var _motion_time := 0
var _pulse := 0.0

func configure(room: Dictionary, boxes: Array, selection: String = "") -> void:
	scene = room.duplicate(true); containers = boxes.duplicate(true); selected = selection
	var path := str(room.get("background", ""))
	if ResourceLoader.exists(path): backdrop = load(path)
	for box in containers:
		var sprite := str(box.get("sprite", ""))
		if ResourceLoader.exists(sprite): sprites[str(box.id)] = load(sprite)
	custom_minimum_size = Vector2(0,300)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	set_meta("extraction_pan", true)
	queue_redraw()

func _ready() -> void:
	resized.connect(_resize_room)
	_resize_room()

func _process(delta: float) -> void:
	_pulse+=delta
	if not _pressed and _pan_velocity.length()>3:
		var before:=pan
		pan+=_pan_velocity*delta
		_clamp_pan()
		_pan_velocity*=exp(-8.0*delta)
		if pan==before:_pan_velocity=Vector2.ZERO
	queue_redraw()

func _resize_room() -> void:
	canvas_size = Vector2(maxf(size.x,600),maxf(size.y,340))
	pan = Vector2((size.x-canvas_size.x)/2,(size.y-canvas_size.y)/2)
	if not containers.is_empty():
		var focus: Dictionary = containers[0]
		for box in containers:
			if str(box.id)==selected: focus=box
		pan.x=size.x/2-float(focus.get("sceneX",0.5))*canvas_size.x
	_clamp_pan(); queue_redraw()

func container_point(box: Dictionary) -> Vector2:
	return Vector2(float(box.get("sceneX",0.5)),float(box.get("sceneY",0.65))) * canvas_size + pan

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("16232c"))
	if backdrop != null:
		var texture_size:=Vector2(backdrop.get_size())
		var scale:=maxf(canvas_size.x/texture_size.x,canvas_size.y/texture_size.y)
		var region_size:=canvas_size/scale
		draw_texture_rect_region(backdrop,Rect2(pan,canvas_size),Rect2((texture_size-region_size)/2,region_size))
	var font := get_theme_default_font()
	for box in containers:
		var point := container_point(box)
		var empty: bool = box.get("items",[]).is_empty()
		var chosen := str(box.id) == selected
		var color := Color("dfc589") if chosen else Color("b4d8cc")
		if empty: color = Color("7f8a86")
		draw_circle(point+Vector2(0,17),31,Color(0,0,0,0.30))
		if not empty:
			var glow:=0.12+0.04*sin(_pulse*2.5)
			draw_circle(point+Vector2(0,6),43,Color(0.5,0.9,0.84,glow))
			draw_arc(point+Vector2(0,8),40,-0.7,0.7,20,Color(color,0.65),2,true)
		var image = sprites.get(str(box.id))
		if image is Texture2D:
			draw_texture_rect(image,Rect2(point-Vector2(45,58),Vector2(90,90)),false,Color(0.65,0.65,0.65) if empty else Color.WHITE)
		else:
			draw_rect(Rect2(point-Vector2(27,30),Vector2(54,48)),Color("746546"))
			draw_rect(Rect2(point-Vector2(27,30),Vector2(54,48)),color,false,2)
			draw_line(point-Vector2(27,10),point+Vector2(27,-10),color,2)
		if chosen: draw_arc(point+Vector2(0,10),41,0,TAU,40,Color(color,0.8),2,true)
		var title := "已搜空" if empty else str(box.get("name","容器"))
		var label_rect := Rect2(point+Vector2(-58,35),Vector2(116,25))
		draw_style_box(_label_box(),label_rect)
		draw_string(font,point+Vector2(-56,53),title,HORIZONTAL_ALIGNMENT_CENTER,112,14,color)
	draw_rect(Rect2(Vector2.ZERO,size),Color("536659"),false,1)

func _label_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.03,0.06,0.08,0.86)
	box.corner_radius_top_left = 6; box.corner_radius_bottom_right = 6
	return box

func _clamp_pan() -> void:
	pan.x = clampf(pan.x,minf(0,size.x-canvas_size.x),0)
	pan.y = clampf(pan.y,minf(0,size.y-canvas_size.y),0)

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
	_press=at;_last=at;_pressed=true;_dragged=false;_pan_velocity=Vector2.ZERO;_motion_time=Time.get_ticks_msec()
func _move(at: Vector2) -> void:
	if not _pressed: return
	if at.distance_to(_press)>10: _dragged=true
	if _dragged:
		var elapsed:=maxf(0.008,float(Time.get_ticks_msec()-_motion_time)/1000.0)
		_pan_velocity=_pan_velocity.lerp((at-_last)/elapsed,0.5).limit_length(1100)
		pan += at-_last; _clamp_pan(); queue_redraw()
	_motion_time=Time.get_ticks_msec()
	_last=at
func _end(at: Vector2) -> void:
	if not _pressed:return
	_pressed=false
	if Time.get_ticks_msec()-_motion_time>90:_pan_velocity=Vector2.ZERO
	if not _dragged and at.distance_to(_press)<10: _activate.call_deferred(at)
func _activate(at: Vector2) -> void:
	if not is_inside_tree():return
	for box in containers:
		if Rect2(container_point(box)-Vector2(48,60),Vector2(96,120)).has_point(at):
			container_selected.emit(str(box.id))
			return
