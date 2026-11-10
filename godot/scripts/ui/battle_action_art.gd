extends Control
## Action-only illustration. This node never changes combat state or catalog art.
var texture: Texture2D
var idle_portrait: CanvasItem
var skill_id := ""
var source_path := ""
var duration := 0.68
var elapsed := 0.0
var reduced_motion := false

func configure(path: String, action_id: String, speed: float, reduced: bool) -> void:
	source_path=path
	skill_id=action_id
	texture=load(path)
	duration=0.72/maxf(1.0,speed)
	reduced_motion=reduced
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	set_meta("action_image",path)
	set_meta("skill_id",action_id)

func _process(delta: float) -> void:
	elapsed+=delta
	if elapsed>=duration:finish();return
	queue_redraw()

func finish() -> void:
	if is_instance_valid(idle_portrait):idle_portrait.visible=true
	set_process(false)
	queue_free()

func _draw() -> void:
	if texture==null or size.x<=0 or size.y<=0:return
	var source:=Rect2(Vector2.ZERO,texture.get_size())
	# The lunging illustration has deliberate headroom; use its complete action silhouette.
	if skill_id=="raisa_armor_normal":source=Rect2(0,285,1024,980)
	var factor:=minf(size.x/source.size.x,size.y/source.size.y)
	var drawn:=source.size*factor
	var offset:=(size-drawn)*0.5
	var t:=clampf(elapsed/duration,0.0,1.0)
	if not reduced_motion:offset.x+=sin(t*PI)*minf(8.0,size.x*.04)
	var alpha:=1.0 if t<.8 else (1.0-t)/.2
	draw_texture_rect_region(texture,Rect2(offset,drawn),source,Color(1,1,1,alpha))
