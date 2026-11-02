extends Control
## Additive-looking furnace glow within the existing portrait rect; never resizes art.
var reduced_motion := false
var elapsed := 0.0
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	set_process(not reduced_motion)
func _process(delta: float) -> void:
	elapsed += delta
	queue_redraw()
func _draw() -> void:
	var pulse := 1.0 if reduced_motion else 0.88 + 0.12 * sin(elapsed * 2.2)
	var center := size * Vector2(0.50, 0.48)
	var radius := minf(size.x * 0.22, size.y * 0.24)
	for ring in range(10, 0, -1):
		draw_circle(center, radius * float(ring) / 10.0, Color(1.0, 0.69, 0.25, 0.013 * pulse))
	draw_arc(center, radius * 1.35, -2.5, -0.65, 36, Color(1.0, 0.88, 0.60, 0.72 * pulse), 1.5, true)
	draw_arc(center, radius * 1.35, 0.64, 2.49, 36, Color(1.0, 0.88, 0.60, 0.72 * pulse), 1.5, true)
	draw_circle(center, radius * 0.14, Color(1.0, 0.96, 0.82, 0.42 * pulse))
	for i in range(6):
		var angle := float(i) * TAU / 6.0
		var point := center + Vector2(cos(angle), sin(angle)) * radius * 1.58
		draw_circle(point, 1.6, Color(1.0, 0.78, 0.42, 0.65 * pulse))
