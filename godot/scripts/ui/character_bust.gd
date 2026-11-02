extends Control
## The curated region sets scale/anchor only. Visible pixels are sampled from
## the complete illustration; the frame is the only clipping boundary.
const Avatars = preload("res://scripts/ui/character_avatar.gd")
var character_id := ""
var texture: Texture2D:
	set(value):
		texture = value
		queue_redraw()
var composition_region := Rect2()

func _init() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func configure(id: String) -> void:
	character_id = id
	composition_region = Avatars.region_for(id, "bust")
	texture = Avatars.get_texture(id, "bust")
	set_meta("portrait_mode", "bust")
	set_meta("portrait_id", id)
	set_meta("portrait_composition", "full_source_frame_clip")
	set_meta("composition_region", composition_region)

static func composition_rects(frame: Rect2, source_size: Vector2, region: Rect2) -> Array[Rect2]:
	if frame.size.x <= 0 or frame.size.y <= 0 or not region.has_area(): return []
	# Retain the established head/body scale, while allowing sleeves, hair and
	# the lower body to continue beyond the old region to the real frame edge.
	var padding := minf(8.0, frame.size.y * 0.035)
	var factor := minf(frame.size.x / region.size.x, (frame.size.y - padding) / region.size.y)
	var origin := frame.position + Vector2(frame.size.x * 0.5 - region.get_center().x * factor, padding - region.position.y * factor)
	var visible_source := Rect2((frame.position - origin) / factor, frame.size / factor).intersection(Rect2(Vector2.ZERO, source_size))
	return [Rect2(origin + visible_source.position * factor, visible_source.size * factor), visible_source]

func enable_bottom_fade(pixels: float = 30.0) -> void:
	# Only unframed reveal art opts in; card portraits keep their frame edge.
	var shader := Shader.new()
	shader.code = """shader_type canvas_item;
	varying float local_y;
	uniform float frame_bottom = 0.0;
	uniform float fade_height = 30.0;
	void vertex() { local_y = VERTEX.y; }
	void fragment() {
		COLOR.a *= 1.0 - smoothstep(frame_bottom - fade_height, frame_bottom, local_y);
	}
	"""
	var fade := ShaderMaterial.new()
	fade.shader = shader
	fade.set_shader_parameter("fade_height", pixels)
	material = fade
	set_meta("bottom_fade_pixels", pixels)
	queue_redraw()

func _draw() -> void:
	if texture == null: return
	var rects := composition_rects(Rect2(Vector2.ZERO, size), texture.get_size(), composition_region)
	if rects.size() == 2:
		if material is ShaderMaterial:
			material.set_shader_parameter("frame_bottom", rects[0].end.y)
		draw_texture_rect_region(texture, rects[0], rects[1])
