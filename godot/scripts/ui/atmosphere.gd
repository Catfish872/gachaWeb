extends Control

var elapsed := 0.0
var embers: Array = []
var accent := Color("d5a76a")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var r := RandomNumberGenerator.new()
	r.seed = 491
	for i in range(48):
		embers.append(Vector4(r.randf(), r.randf(), r.randf_range(0.15, 0.55), r.randf_range(0.7, 2.1)))

func _process(delta: float) -> void:
	elapsed += delta
	queue_redraw()

func _draw() -> void:
	var center := size * Vector2(0.78, 0.30)
	for radius in [160.0, 240.0, 320.0]:
		draw_arc(center, radius, elapsed * 0.015, TAU + elapsed * 0.015, 96, Color(accent, 0.035), 1.0, true)
	for p in embers:
		var pos := Vector2(p.x * size.x, fposmod(p.y * size.y - elapsed * p.z * 16.0, size.y))
		var opacity := 0.13 + (sin(elapsed * p.z + p.x * 30.0) + 1.0) * 0.10
		draw_circle(pos, p.w, Color(accent, opacity))
		draw_line(pos + Vector2(0, 3), pos + Vector2(0, 14), Color(accent, opacity * 0.25), 1.0)
