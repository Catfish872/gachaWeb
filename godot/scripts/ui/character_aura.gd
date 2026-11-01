extends Control
var tint:=Color('dfb779')
func _ready():
 mouse_filter=Control.MOUSE_FILTER_IGNORE
 resized.connect(queue_redraw)
func _draw():
 var center:=size*Vector2(.5,.58)
 var radius:=minf(size.x*.36,size.y*.44)
 draw_arc(center,radius,0,TAU,96,Color(tint,.25),1.3,true)
 draw_arc(center,radius*.88,.35,2.6,40,Color(tint,.42),2,true)
 draw_arc(center,radius*.88,3.5,5.8,40,Color(tint,.42),2,true)
 for i in 12:
  var angle:=TAU*i/12.0
  var point:=center+Vector2(cos(angle),sin(angle))*radius
  draw_line(point-Vector2(cos(angle),sin(angle))*4,point+Vector2(cos(angle),sin(angle))*4,Color(tint,.5),1.2,true)
 draw_arc(center+Vector2(0,radius*.82),radius*.48,0,TAU,64,Color(tint,.22),1,true)
