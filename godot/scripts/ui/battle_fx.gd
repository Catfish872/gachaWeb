extends Control

var bursts: Array = []
var streaks: Array = []
var flash_life := 0.0
var flash_color := Color.WHITE

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func burst(at: Vector2, color: Color, big: bool = false) -> void:
	for i in range(16 if big else 9):
		var a := float(i) * TAU / float(16 if big else 9)
		bursts.append({"p": at, "v": Vector2(cos(a), sin(a)) * (150.0 if big else 85.0), "life": 0.65, "color": color})
	queue_redraw()

func streak(from: Vector2, to: Vector2, color: Color) -> void:
	streaks.append({"a": from, "b": to, "life": 0.30, "color": color})

func flash(color: Color) -> void:
	flash_color = color
	flash_life = 0.4

func _process(delta: float) -> void:
	flash_life = maxf(0.0, flash_life - delta)
	for b in bursts:
		b.life -= delta
		b.p += b.v * delta
		b.v *= 0.94
	bursts = bursts.filter(func(b): return b.life > 0)
	for s in streaks:
		s.life -= delta
	streaks = streaks.filter(func(s): return s.life > 0)
	queue_redraw()

func _draw() -> void:
	if flash_life > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(flash_color, flash_life * 0.3))
	for s in streaks:
		var alpha: float = s.life / 0.30
		draw_line(s.a, s.b, Color(s.color, alpha * 0.2), 17.0, true)
		draw_line(s.a, s.b, Color(s.color, alpha), 3.0, true)
	for b in bursts:
		var alpha: float = b.life / 0.65
		draw_circle(b.p, 2.0 + alpha * 2.0, Color(b.color, alpha))
		draw_line(b.p, b.p - b.v * 0.07, Color(b.color, alpha * 0.4), 2.0, true)
