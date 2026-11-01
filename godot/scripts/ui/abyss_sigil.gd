extends Control
var color:=Color("bba2dc")
var symbol:=0
var edge:=58
func _ready()->void:
	custom_minimum_size=Vector2(edge,edge)
	mouse_filter=Control.MOUSE_FILTER_IGNORE
func _draw()->void:
	var c:=size/2
	var r:=minf(size.x,size.y)*0.35
	draw_circle(c,r+6,Color(color,0.07))
	draw_arc(c,r,0,TAU,40,Color(color,0.5),1,true)
	var p:=PackedVector2Array()
	var count:=3+posmod(symbol,4)
	for i in range(count+1):
		var a:=TAU*i/count-PI/2
		p.append(c+Vector2(cos(a),sin(a))*r*0.7)
	draw_polyline(p,color,1.8,true)
	draw_circle(c,3,color)
	for i in range(4):
		var a:=PI/4+i*PI/2
		draw_line(c+Vector2(cos(a),sin(a))*(r+3),c+Vector2(cos(a),sin(a))*(r+7),color,1.5,true)
