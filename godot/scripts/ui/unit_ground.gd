extends Control
var accent:=Color("7dcac9")
var selected:=false
var active:=false
func _ready():
 mouse_filter=Control.MOUSE_FILTER_IGNORE
 resized.connect(queue_redraw)
func _draw():
 var center:=Vector2(size.x*.5,size.y-5)
 var radius:=minf(size.x*.36,70)
 draw_set_transform(center,0,Vector2(1,.22))
 draw_circle(Vector2.ZERO,radius,Color(0,0,0,.34))
 if active or selected:
  draw_circle(Vector2.ZERO,radius,Color(accent,.13))
  draw_arc(Vector2.ZERO,radius,0,TAU,48,Color(accent,.85),3,true)
  draw_arc(Vector2.ZERO,radius*.82,.2,TAU-.2,40,Color(accent,.35),1,true)
