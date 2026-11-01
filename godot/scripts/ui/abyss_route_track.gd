extends Control
var floor_number:=1
var active:=false
var floor_cap:=0
var route:Array=[]
func _ready()->void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	custom_minimum_size=Vector2(130,120)
	size_flags_vertical=Control.SIZE_EXPAND_FILL
func window_start()->int:
	return int(route[0].get("floor",1)) if not route.is_empty() else maxi(1,floor_number-2)
func visible_floors()->Array[int]:
	var values:Array[int]=[]
	if not route.is_empty():
		for entry in route:
			var number:=int(entry.get("floor",1))
			if floor_cap==0 or number<=floor_cap:values.append(number)
	else:
		for i in range(10):
			var number:=window_start()+i
			if floor_cap==0 or number<=floor_cap:values.append(number)
	return values
func _draw()->void:
	var font:=get_theme_default_font()
	var inset:=Vector2(28,18)
	var step:=Vector2(maxf(60,size.x-56),maxf(20,(size.y-40)/4.0))
	var numbers:=visible_floors()
	var points:=PackedVector2Array()
	for i in range(numbers.size()):
		var row:=i/2
		var col:=i%2 if row%2==0 else 1-i%2
		points.append(inset+Vector2(col*step.x,row*step.y))
	if points.size()>1:draw_polyline(points,Color("283343"),3,true)
	for i in range(numbers.size()):
		var p:=points[i]
		var number:=numbers[i]
		var current:=active and number==floor_number
		var passed:=active and number<floor_number
		var color:=Color("d6bd82") if number%10==0 else Color("a68bce") if number%5==0 else Color("6e8598")
		if passed:color=Color("73b8b1")
		draw_circle(p,12,Color("101a29"))
		draw_arc(p,12,0,TAU,24,color,2 if current else 1,true)
		if current:draw_arc(p,15,0,TAU,24,Color("e8cf94"),1,true)
		var text:="%02d"%number
		var width:=font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,11).x
		draw_string(font,p+Vector2(-width/2,4),text,HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color.WHITE if current else color)
