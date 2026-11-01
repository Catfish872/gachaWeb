extends Control
signal container_selected(id: String)
signal battle_requested
signal service_requested(id: String)
var service_rect := Rect2()
var service_id := ""
var service_sprite: Texture2D
var enemies: Array = []
var enemy_sprites: Dictionary = {}
var enemy_rects: Array[Rect2] = []
var reduced_motion := false
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

func configure(room: Dictionary, boxes: Array, selection: String = "", guards: Array = [], reduce_motion: bool = false) -> void:
	enemies=guards.duplicate(true);reduced_motion=reduce_motion
	for enemy in enemies:
		var path:="res://assets/enemies/"+str(enemy.get("id",""))+".png"
		if ResourceLoader.exists(path):enemy_sprites[str(enemy.id)]=load(path)
	scene = room.duplicate(true); containers = boxes.duplicate(true); selected = selection
	service_id="" if scene.get("servicesLocked",false) or not enemies.is_empty() else "relay" if scene.get("type","")=="relay" else "unlock" if scene.get("type","")=="key_vault" and not scene.get("unlocked",false) else ""
	var service_path:="res://assets/items/expedition_v230/relay_chest.png" if service_id=="relay" else "res://assets/extraction/containers/rune_vault.png"
	if not service_id.is_empty() and ResourceLoader.exists(service_path):service_sprite=load(service_path)
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
	var animate:=not reduced_motion and not enemies.is_empty()
	if not reduced_motion:
		for box in containers:
			if container_state(box)=="unsearched":animate=true;break
	if not _pressed and _pan_velocity.length()>3:
		animate=true
		var before:=pan
		pan+=_pan_velocity*delta
		_clamp_pan()
		_pan_velocity*=exp(-8.0*delta)
		if pan==before:_pan_velocity=Vector2.ZERO
	if animate:queue_redraw()

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
	var point:=Vector2(float(box.get("sceneX",0.5)),float(box.get("sceneY",0.65))) * canvas_size + pan
	# Compact service layouts still show the complete search badge, sprite and name.
	point.y=clampf(point.y,76,maxf(76,size.y-62))
	return point

func container_visual_rect(box: Dictionary) -> Rect2:
	return Rect2(container_point(box)+Vector2(-58,-76),Vector2(116,136))

func container_state(box: Dictionary) -> String:
	if box.get("items",[]).is_empty():return "empty"
	for item in box.get("items",[]):
		if not item.get("revealed",false):return "unsearched"
	return "remaining"

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("16232c"))
	if backdrop != null:
		var texture_size:=Vector2(backdrop.get_size())
		var scale:=maxf(canvas_size.x/texture_size.x,canvas_size.y/texture_size.y)
		var region_size:=canvas_size/scale
		draw_texture_rect_region(backdrop,Rect2(pan,canvas_size),Rect2((texture_size-region_size)/2,region_size))
	var font := get_theme_default_font()
	enemy_rects.clear()
	for i in enemies.size():
		var enemy: Dictionary=enemies[i]
		var texture=enemy_sprites.get(str(enemy.get("id","")))
		var point:=Vector2(size.x/2+(i-(enemies.size()-1)/2.0)*minf(150,size.x/(enemies.size()+1)),size.y-36)
		var tall:=minf(220,maxf(60,size.y-52))
		var rect:=Rect2(point-Vector2(tall*.39,tall),Vector2(tall*.78,tall))
		if not reduced_motion:rect.position.y+=sin(_pulse*1.7+i)*1.8
		enemy_rects.append(rect.grow(8))
		draw_set_transform(point,0,Vector2(1,.25));draw_circle(Vector2.ZERO,tall*.26,Color(0.02,.015,.025,.5));draw_set_transform(Vector2.ZERO)
		draw_arc(point+Vector2(0,-3),tall*.26,0,TAU,40,Color(.88,.37,.30,.35),2,true)
		if texture is Texture2D:
			var ts:=Vector2(texture.get_size());var factor:=minf(rect.size.x/ts.x,rect.size.y/ts.y)
			var draw_size:=ts*factor
			draw_texture_rect(texture,Rect2(Vector2(rect.get_center().x-draw_size.x/2,rect.end.y-draw_size.y),draw_size),false)
		var label:=Rect2(point+Vector2(-55,8),Vector2(110,24))
		draw_style_box(_label_box(),label)
		draw_string(font,label.position+Vector2(3,17),str(enemy.get("name","守卫")),HORIZONTAL_ALIGNMENT_CENTER,104,13,Color("efb5a0"))
	for box in containers:
		var point := container_point(box)
		var empty: bool = box.get("items",[]).is_empty()
		var searched:=true
		for item in box.get("items",[]):
			if not item.get("revealed",false):searched=false;break
		var chosen := str(box.id) == selected
		var color := Color("dfc589") if chosen else Color("b4d8cc")
		if empty: color = Color("7f8a86")
		draw_circle(point+Vector2(0,17),31,Color(0,0,0,0.30))
		if not empty and not searched:
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
		var title := str(box.get("name","容器"))
		var state_text:="已取空" if empty else "已搜 · 剩 %d 件" % box.get("items",[]).size() if searched else "待搜索"
		var badge:=Rect2(point+Vector2(-45,-76),Vector2(90,20))
		draw_style_box(_label_box(),badge)
		var state_color:=Color("8e9b9c") if empty else Color("ddbd7f") if searched else Color("9ee8de")
		draw_string(font,badge.position+Vector2(3,14),state_text,HORIZONTAL_ALIGNMENT_CENTER,84,11,state_color)
		if searched:
			var tick:=point+Vector2(36,-43)
			draw_circle(tick,9,Color("162a31"))
			draw_line(tick+Vector2(-4,0),tick+Vector2(-1,3),state_color,2,true)
			draw_line(tick+Vector2(-1,3),tick+Vector2(5,-4),state_color,2,true)
		var label_rect := Rect2(point+Vector2(-58,35),Vector2(116,25))
		draw_style_box(_label_box(),label_rect)
		draw_string(font,point+Vector2(-56,53),title,HORIZONTAL_ALIGNMENT_CENTER,112,14,color)
	service_rect=Rect2()
	if not service_id.is_empty() and service_sprite!=null:
		var center:=Vector2(size.x*0.52,clampf(size.y*.5,65,maxf(65,size.y-86)))
		service_rect=Rect2(center-Vector2(60,65),Vector2(120,120))
		draw_circle(center+Vector2(0,35),48,Color(.04,.04,.08,.3))
		draw_texture_rect(service_sprite,service_rect,false)
		var label:=Rect2(center+Vector2(-65,58),Vector2(130,25))
		draw_style_box(_label_box(),label)
		draw_string(font,label.position+Vector2(3,17),"信使翼匣" if service_id=="relay" else "封印宝库",HORIZONTAL_ALIGNMENT_CENTER,124,14,Color("e0c98d"))
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
	if not service_id.is_empty() and service_rect.grow(10).has_point(at):service_requested.emit(service_id);return
	for rect in enemy_rects:
		if rect.has_point(at):battle_requested.emit();return
	for box in containers:
		if container_visual_rect(box).has_point(at):
			container_selected.emit(str(box.id))
			return
