extends Control
## Non-blocking, bounded battle presentation. Coordinates are in the overlay canvas.
var bursts: Array = []
var streaks: Array = []
var rings: Array = []
var ultimates: Array = []
var flash_life := 0.0
var flash_color := Color.WHITE
var reduced_motion := false
const ELEMENT_COLORS := {"fire":Color("ff9864"),"water":Color("75c8ef"),"wind":Color("80ddbd"),"thunder":Color("c5a0ff"),"lightning":Color("c5a0ff"),"ice":Color("b4e9ff"),"earth":Color("ddbc7d")}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)

func burst(at: Vector2, color: Color, big: bool = false) -> void:
	if reduced_motion: return
	var count := 14 if big else 7
	for i in range(count):
		var a := float(i) * TAU / float(count)
		bursts.append({"p":at,"v":Vector2(cos(a),sin(a))*(130.0 if big else 72.0),"life":0.55,"color":color})
	if bursts.size()>160: bursts=bursts.slice(-160)
	set_process(true)
	queue_redraw()

func streak(from: Vector2, to: Vector2, color: Color) -> void:
	if reduced_motion: return
	streaks.append({"a":from,"b":to,"life":0.34,"color":color})
	if streaks.size()>16: streaks=streaks.slice(-16)
	set_process(true)

func flash(color: Color) -> void:
	if reduced_motion: return
	flash_color=color
	flash_life=0.35
	set_process(true)

func heal_ring(at: Vector2) -> void:
	_add_ring(at,Color("8de2be"),false)

func shield_ring(at: Vector2) -> void:
	_add_ring(at,Color("93cbe9"),true)

func _add_ring(at: Vector2,color: Color,shield: bool) -> void:
	if reduced_motion:return
	rings.append({"p":at,"color":color,"shield":shield,"life":0.85})
	if rings.size()>16:rings=rings.slice(-16)
	set_process(true)

func ultimate(actor_id: String,element: String,from: Vector2,to: Vector2) -> void:
	if reduced_motion:return
	var color: Color=ELEMENT_COLORS.get(element,Color("ddbc7d"))
	ultimates.append({"actor":actor_id,"element":element,"a":from,"b":to,"color":color,"life":1.1})
	if ultimates.size()>4:ultimates=ultimates.slice(-4)
	burst(to,color,true)
	set_process(true)

func clear_effects() -> void:
	bursts.clear();streaks.clear();rings.clear();ultimates.clear();flash_life=0
	set_process(false)
	queue_redraw()

func _process(delta: float) -> void:
	flash_life=maxf(0.0,flash_life-delta)
	for b in bursts:
		b.life-=delta
		b.p+=b.v*delta
		b.v*=exp(-4.0*delta)
	bursts=bursts.filter(func(b):return b.life>0)
	for group in [streaks,rings,ultimates]:
		for item in group:item.life-=delta
	streaks=streaks.filter(func(s):return s.life>0)
	rings=rings.filter(func(r):return r.life>0)
	ultimates=ultimates.filter(func(u):return u.life>0)
	queue_redraw()
	if bursts.is_empty() and streaks.is_empty() and rings.is_empty() and ultimates.is_empty() and flash_life<=0:set_process(false)

func _draw() -> void:
	if flash_life>0:
		# Brief low-opacity tint preserves the combatants and HUD throughout.
		draw_rect(Rect2(Vector2.ZERO,size),Color(flash_color,flash_life*0.17))
	for s in streaks:
		var t: float=1.0-float(s.life)/0.34
		var tip: Vector2=s.a.lerp(s.b,minf(1.0,t*2.4))
		var tail: Vector2=s.a.lerp(s.b,maxf(0.0,t*2.4-0.65))
		var alpha: float=1.0-t
		draw_line(tail,tip,Color(s.color,alpha*0.14),12,true)
		draw_line(tail,tip,Color(s.color,alpha),2.3,true)
		draw_circle(tip,3.0,Color("fff2d5",alpha))
	for b in bursts:
		var alpha: float=float(b.life)/0.55
		draw_line(b.p,b.p-b.v*0.065,Color(b.color,alpha),1.5,true)
		draw_circle(b.p,1.0+alpha,Color(b.color,alpha))
	for r in rings:
		var t: float=1.0-float(r.life)/0.85
		var alpha: float=sin(t*PI)*0.8
		var radius: float=24.0+t*42.0
		if bool(r.shield):
			var points:=PackedVector2Array()
			for i in range(7):
				var angle:=float(i)*TAU/6.0-PI/2
				points.append(r.p+Vector2(cos(angle),sin(angle))*radius)
			draw_polyline(points,Color(r.color,alpha),2.0,true)
		else:
			draw_arc(r.p,radius,0,TAU,48,Color(r.color,alpha),2.0,true)
			for i in range(6):
				var angle:=float(i)*TAU/6.0
				var p: Vector2=r.p+Vector2(cos(angle)*radius,sin(angle)*radius*0.5-t*25)
				draw_line(p-Vector2(3,0),p+Vector2(3,0),Color(r.color,alpha),1.8,true)
				draw_line(p-Vector2(0,3),p+Vector2(0,3),Color(r.color,alpha),1.8,true)
	for u in ultimates:_draw_ultimate(u)

func _draw_ultimate(u: Dictionary) -> void:
	var t:=1.0-float(u.life)/1.1
	var alpha:=sin(t*PI)
	var c: Color=u.color
	var center: Vector2=u.b
	if str(u.actor)=="ayla" or str(u.element)=="water":
		for band in range(3):
			var points:=PackedVector2Array()
			for i in range(33):
				var x:=float(i)/32.0*size.x
				var y:=center.y-65+band*24+sin(x/125+t*TAU+band)*22
				points.append(Vector2(x,y))
			draw_polyline(points,Color(c,alpha*0.11),24,true)
			draw_polyline(points,Color(c,alpha*0.5),1.5,true)
	elif str(u.element) in ["thunder","lightning"]:
		for ray in range(3):
			var points:=PackedVector2Array()
			for i in range(9):
				var p: Vector2=u.a.lerp(center,float(i)/8.0)
				if i>0 and i<8:p.y+=sin(i*7.1+ray*2.3)*23*alpha
				points.append(p+Vector2(0,(ray-1)*8))
			draw_polyline(points,Color(c,alpha*0.17),9,true)
			draw_polyline(points,Color(c,alpha),1.5,true)
	else:
		var radius:=26+t*95
		for layer in range(3):
			var start:=t*2.5+layer*TAU/3.0
			draw_arc(center,radius-layer*13,start,start+PI*1.35,40,Color(c,alpha*(0.8-layer*0.2)),3.5-layer*0.7,true)
		if str(u.actor)=="kaldi" or str(u.element)=="fire":
			var path:=PackedVector2Array()
			for i in range(30):
				var f:=float(i)/29.0
				var p: Vector2=u.a.lerp(center,f)
				p.y+=sin(f*PI*3-t*7)*24*sin(f*PI)
				path.append(p)
			draw_polyline(path,Color(c,alpha*0.12),24,true)
			draw_polyline(path,Color(c,alpha*0.7),4,true)
