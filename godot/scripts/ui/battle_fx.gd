extends Control
## Non-blocking, bounded battle presentation. Coordinates are in the overlay canvas.
var bursts: Array = []
var streaks: Array = []
var rings: Array = []
var ultimates: Array = []
var impacts: Array = []
var flash_life := 0.0
var flash_color := Color.WHITE
var reduced_motion := false
const ELEMENT_COLORS := {"fire":Color("ff9864"),"water":Color("75c8ef"),"wind":Color("80ddbd"),"thunder":Color("c5a0ff"),"lightning":Color("c5a0ff"),"ice":Color("b4e9ff"),"earth":Color("ddbc7d")}
const SKILL_IMPACTS := {
	"kaldi_normal":"flame_blade", "kaldi_skill":"dragon_flame", "kaldi_ult":"dragon_flame",
	"selin_normal":"lantern_chain", "selin_skill":"lantern_flame", "selin_ult":"lantern_flame",
	"tiya_normal":"wind_blades", "tiya_skill":"wind_sweep", "tiya_ult":"wind_blades",
	"lumi_normal":"wind_strings", "lumi_skill":"wind_bridge", "lumi_ult":"wind_strings",
	"wind_primary":"wind_pierce", "wind_gold":"wind_pierce"
}
const SIGNATURE_COLORS := {
	"flame_blade":Color("ff9864"), "dragon_flame":Color("ff9864"),
	"lantern_chain":Color("efc27d"), "lantern_flame":Color("efc27d"),
	"wind_blades":Color("71e0d0"), "wind_sweep":Color("71e0d0"),
	"wind_strings":Color("c5e6a4"), "wind_bridge":Color("c5e6a4"),
	"wind_pierce":Color("a2ecd3"), "wind_armor":Color("a2ecd3")
}

func skill_impact_kind(skill_id: String) -> String:
	return str(SKILL_IMPACTS.get(skill_id, ""))

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
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
	bursts.clear();streaks.clear();rings.clear();ultimates.clear();impacts.clear();flash_life=0
	set_process(false)
	queue_redraw()

func _process(delta: float) -> void:
	flash_life=maxf(0.0,flash_life-delta)
	for b in bursts:
		b.life-=delta
		b.p+=b.v*delta
		b.v*=exp(-4.0*delta)
	bursts=bursts.filter(func(b):return b.life>0)
	for group in [streaks,rings,ultimates,impacts]:
		for item in group:item.life-=delta
	streaks=streaks.filter(func(s):return s.life>0)
	rings=rings.filter(func(r):return r.life>0)
	ultimates=ultimates.filter(func(u):return u.life>0)
	impacts=impacts.filter(func(u):return u.life>0)
	queue_redraw()
	if bursts.is_empty() and streaks.is_empty() and rings.is_empty() and ultimates.is_empty() and impacts.is_empty() and flash_life<=0:set_process(false)

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
	for effect in impacts:_draw_impact(effect)

func _draw_ultimate(u: Dictionary) -> void:
	if str(u.actor) == "selin":
		_draw_lantern_ultimate(u)
		return
	if str(u.actor) == "kaldi":
		_draw_dragon_ultimate(u)
		return
	if str(u.actor) in ["tiya", "lumi"]:
		_draw_wind_ultimate(u, str(u.actor) == "lumi")
		return
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

## Semantic attack silhouettes, bounded independently from legacy particle bursts.
func impact(kind: String, from: Vector2, to: Vector2, critical: bool = false) -> void:
	if reduced_motion: return
	var aliases := {"burn":"fire", "freeze":"ice", "shock":"thunder", "electrify":"thunder", "lightning":"thunder", "physical":"slash", "earth":"blunt", "regen":"heal"}
	kind = str(aliases.get(kind, kind))
	if kind == "heal":
		heal_ring(to)
		return
	if kind in ["shield", "def_up", "invincible"]:
		shield_ring(to)
		return
	if not SIGNATURE_COLORS.has(kind) and not kind in ["slash", "blunt", "fire", "water", "ice", "thunder", "wind", "shield_break", "poison", "bleed", "vulnerable", "atk_up", "spd_down", "taunt", "stun", "ember_oath", "ember_lantern_burn", "ember_lantern_direct", "detonation"]: kind = "blunt"
	var color: Color = ELEMENT_COLORS.get(kind, Color("f4d8a0"))
	if SIGNATURE_COLORS.has(kind): color = SIGNATURE_COLORS[kind]
	if kind == "poison": color = Color("b6de84")
	if kind in ["bleed", "vulnerable"]: color = Color("ff8b9b")
	impacts.append({"kind":kind, "a":from, "b":to, "color":color, "critical":critical, "life":0.62})
	if impacts.size() > 24: impacts = impacts.slice(-24)
	set_process(true)
	queue_redraw()

func _draw_impact(effect: Dictionary) -> void:
	var t := clampf(1.0-float(effect.life)/0.62, 0.0, 1.0)
	var alpha := sin(t*PI)
	var p: Vector2 = effect.b
	var scale_factor := 1.3 if bool(effect.critical) else 1.0
	var r := (16.0+t*30.0)*scale_factor
	var c := Color(effect.color, alpha)
	if SIGNATURE_COLORS.has(str(effect.kind)):
		_draw_signature_impact(str(effect.kind), p, t, r, c)
		return
	match str(effect.kind):
		"ember_oath", "ember_lantern_burn", "ember_lantern_direct", "detonation":
			var gold := Color(1.0, 0.83, 0.49, alpha * 0.65)
			var radius := 10.0 + t * 8.0
			draw_circle(p, radius, Color(1.0, 0.78, 0.38, alpha * 0.07))
			draw_arc(p, radius, 0.25, PI - 0.25, 20, gold, 1.2, true)
			draw_arc(p, radius, PI + 0.25, TAU - 0.25, 20, gold, 1.2, true)
			draw_circle(p, 2.0, Color(1.0, 0.96, 0.79, alpha * 0.55))
		"slash":
			for i in range(2):
				var offset := Vector2(i*10, i*4)
				draw_line(p+offset+Vector2(-r,r*0.8), p+offset+Vector2(r,-r*0.8), c, (3.0-i)*scale_factor, true)
		"blunt":
			var points := PackedVector2Array()
			for i in range(17):
				var angle := i*TAU/16.0
				points.append(p+Vector2.from_angle(angle)*r*(1.0 if i%2 == 0 else 0.4))
			draw_polyline(points,c,2.2,true)
		"fire":
			for i in range(3):
				var x := (i-1)*18.0
				var base := p+Vector2(x,12-t*20)
				var points := PackedVector2Array([base+Vector2(-9,0),base+Vector2(-12,-15),base+Vector2(2,-r),base+Vector2(1,-14),base+Vector2(10,-23),base+Vector2(9,0),base+Vector2(-9,0)])
				draw_polyline(points,c,2.0,true)
		"water":
			for i in range(3):
				draw_set_transform(p+Vector2(0,i*10),0,Vector2(1,0.4))
				draw_arc(Vector2.ZERO,r+i*9,0,TAU,32,c,2.0,true)
			draw_set_transform(Vector2.ZERO)
		"ice":
			for i in range(6):
				var direction := Vector2.from_angle(i*TAU/6)
				var side := direction.orthogonal()*8
				var base := p+direction*(8+t*10)
				draw_colored_polygon(PackedVector2Array([base-side,base+direction*r,base+side]),Color(c,alpha*0.22))
				draw_polyline(PackedVector2Array([base-side,base+direction*r,base+side,base-side]),c,1.5,true)
		"thunder":
			var points := PackedVector2Array([p+Vector2(10,-r*1.4),p+Vector2(-10,-6),p+Vector2(11,-6),p+Vector2(-11,r*1.2)])
			draw_polyline(points,Color(c,alpha*0.18),10,true)
			draw_polyline(points,c,3.0,true)
		"wind":
			for i in range(3): draw_arc(p+Vector2(i*7, i*9-10),r-i*5,t*2+i,t*2+i+PI*1.2,28,c,2.0,true)
		"shield_break":
			for i in range(6):
				var direction := Vector2.from_angle(i*TAU/6-PI/2)
				var center := p+direction*(12+t*38)
				var side := direction.orthogonal()*9
				draw_polyline(PackedVector2Array([center-side,center+direction*14,center+side]),c,2.4,true)
		"poison":
			for i in range(5):
				var center := p+Vector2((i-2)*13, sin(i*3.0)*10-t*32)
				draw_circle(center,4.0+float(i%3)*2,Color(c,alpha*0.2))
				draw_arc(center,4.0+float(i%3)*2,0,TAU,16,c,1.5,true)
		"bleed":
			for i in range(3):
				var center := p+Vector2((i-1)*15,t*30)
				draw_colored_polygon(PackedVector2Array([center+Vector2(0,-13),center+Vector2(5,3),center+Vector2(-5,3)]),c)
		"vulnerable":
			draw_polyline(PackedVector2Array([p+Vector2(0,-r),p+Vector2(-8,-5),p+Vector2(8,5),p+Vector2(0,r)]),c,3.0,true)
		"atk_up", "spd_down":
			var sign_y := -1.0 if str(effect.kind)=="atk_up" else 1.0
			for i in range(2):
				var center := p+Vector2(0,sign_y*(t*20+i*16))
				draw_polyline(PackedVector2Array([center+Vector2(-12,-sign_y*9),center,center+Vector2(12,-sign_y*9)]),c,2.5,true)
		"taunt":
			draw_arc(p,r,0,TAU,32,c,2.0,true)
			draw_line(p-Vector2(r+6,0),p+Vector2(r+6,0),c,1.5,true)
			draw_line(p-Vector2(0,r+6),p+Vector2(0,r+6),c,1.5,true)
		"stun":
			for i in range(3):
				var center := p+Vector2(cos(i*TAU/3+t)*r,sin(i*TAU/3+t)*r*0.4-20)
				draw_line(center-Vector2(5,0),center+Vector2(5,0),c,2,true)
				draw_line(center-Vector2(0,5),center+Vector2(0,5),c,2,true)

func _draw_signature_impact(kind: String, p: Vector2, t: float, r: float, c: Color) -> void:
	match kind:
		"flame_blade", "dragon_flame":
			var count := 2 if kind == "flame_blade" else 4
			for i in range(count):
				var angle := -PI * 0.7 + float(i) * 0.46
				draw_arc(p + Vector2((i-1)*7, 0), r, angle, angle + PI * 0.85, 24, Color(c, c.a * 0.14), 10.0, true)
				draw_arc(p + Vector2((i-1)*7, 0), r, angle, angle + PI * 0.85, 24, c, 2.6, true)
				var tip := p + Vector2.from_angle(angle + PI * 0.85) * r
				draw_colored_polygon(PackedVector2Array([tip+Vector2(-5,5),tip+Vector2(0,-14-t*12),tip+Vector2(5,5)]),Color("ffe6ad",c.a*.75))
		"lantern_chain", "lantern_flame":
			var offset := Vector2(-r * 0.65, -r * 0.35)
			for i in range(6):
				var angle := -PI * 0.7 + float(i) * 0.22
				draw_arc(p + offset + Vector2.from_angle(angle)*r, 3.0, 0, TAU, 10, Color(c,c.a*.75), 1.2, true)
			var at := p + Vector2(0, -t*12)
			draw_circle(at, 21.0, Color(c, c.a * 0.08))
			draw_polyline(PackedVector2Array([at+Vector2(-8,-10),at+Vector2(8,-10),at+Vector2(11,10),at+Vector2(-11,10),at+Vector2(-8,-10)]),c,1.8,true)
			draw_arc(at+Vector2(0,-12),4.0,PI,TAU,12,c,1.4,true)
			draw_colored_polygon(PackedVector2Array([at+Vector2(0,-7),at+Vector2(4,2),at+Vector2(0,7),at+Vector2(-4,2)]),Color("fff1ca",c.a))
			if kind == "lantern_flame":
				for i in range(3):
					var spark := p + Vector2((i-1)*22, -18-t*32)
					draw_line(spark,spark+Vector2(0,-9),Color(c,c.a*.7),2.0,true)
		"wind_blades", "wind_sweep":
			for blade in range(2):
				var side := -1.0 if blade == 0 else 1.0
				var center := p + Vector2(side*9,side*5)
				var start := (-0.82 if blade == 0 else PI-0.82) + t*0.6
				draw_arc(center,r+10,start,start+PI*.92,28,Color(c,c.a*.13),10.0,true)
				draw_arc(center,r+10,start,start+PI*.92,28,c,2.4,true)
				draw_arc(center,r+15,start+.12,start+PI*.65,20,Color("e9fff2",c.a*.75),1.0,true)
			if kind == "wind_sweep":
				draw_arc(p,r+23,-.3+t,PI*1.4+t,32,Color(c,c.a*.55),1.5,true)
		"wind_strings", "wind_bridge":
			for string_index in range(4):
				var points := PackedVector2Array()
				for i in range(17):
					var f := float(i)/16.0
					points.append(p+Vector2((f-.5)*(r*2.8),float(string_index-2)*10+sin(f*PI*2-t*TAU+string_index)*5*sin(f*PI)))
				draw_polyline(points,Color(c,c.a*.1),6.0,true)
				draw_polyline(points,c,1.3,true)
			if kind == "wind_bridge":
				draw_arc(p+Vector2(0,12),r+8,PI,TAU,28,Color(c,c.a*.8),2.0,true)
			for side in [-1.0,1.0]:
				var leaf := p+Vector2(side*r*.9,-16-t*8)
				draw_colored_polygon(PackedVector2Array([leaf+Vector2(-7,0),leaf+Vector2(0,-4),leaf+Vector2(7,0),leaf+Vector2(0,4)]),Color(c,c.a*.65))
		"wind_pierce":
			draw_line(p-Vector2(r+12,0),p+Vector2(r+12,0),Color(c,c.a*.15),8.0,true)
			draw_line(p-Vector2(r+12,0),p+Vector2(r+12,0),c,1.8,true)
			for i in range(2):
				var at := p+Vector2((t-.5)*30+i*16,0)
				draw_polyline(PackedVector2Array([at+Vector2(-7,-6),at,at+Vector2(-7,6)]),c,1.8,true)
		"wind_armor":
			for side in [-1.0,1.0]:
				var at := p+Vector2(side*(5+t*15),0)
				draw_polyline(PackedVector2Array([at+Vector2(0,-19),at+Vector2(side*13,-11),at+Vector2(side*10,10),at+Vector2(0,21)]),c,2.0,true)
			draw_polyline(PackedVector2Array([p+Vector2(3,-18),p+Vector2(-4,-4),p+Vector2(4,3),p+Vector2(-3,18)]),Color("efffe5",c.a),1.6,true)

func _draw_dragon_ultimate(u: Dictionary) -> void:
	var t := clampf(1.0-float(u.life)/1.1,0.0,1.0)
	var alpha := sin(t*PI)
	var path := PackedVector2Array()
	var travel := minf(1.0,t*2.4)
	for i in range(33):
		var f := float(i)/32.0*travel
		var point: Vector2 = u.a.lerp(u.b,f)
		point.y += sin(f*PI*2-t*4)*25*sin(f*PI)
		path.append(point)
	draw_polyline(path,Color("ff7f43",alpha*.13),26.0,true)
	draw_polyline(path,Color("ffb264",alpha*.8),4.0,true)
	draw_polyline(path,Color("ffe8b2",alpha*.8),1.2,true)
	var direction: Vector2 = (u.b-u.a).normalized()
	if direction.is_zero_approx(): direction=Vector2.RIGHT
	var normal := direction.orthogonal()
	var wing: Vector2 = u.a.lerp(u.b,travel*.58)
	for side in [-1.0,1.0]:
		var points := PackedVector2Array([wing-direction*30,wing+normal*side*52-direction*5,wing+normal*side*20+direction*8,wing+direction*30])
		draw_polyline(points,Color("ffb264",alpha*.65),2.0,true)
	var head: Vector2 = path[path.size()-1]
	var jaw := PackedVector2Array([head-direction*20-normal*12,head+direction*16-normal*7,head+direction*23,head+direction*10+normal*6,head-direction*18+normal*13])
	draw_colored_polygon(jaw,Color("ff9d51",alpha*.12))
	draw_polyline(jaw,Color("ffe0a0",alpha),2.0,true)
	draw_line(head-direction*10-normal*10,head-direction*24-normal*28,Color("ffe0a0",alpha),2.0,true)
	draw_circle(head+direction*3-normal*4,2.0,Color("fff6d3",alpha))

func _draw_wind_ultimate(u: Dictionary, strings: bool) -> void:
	var t := clampf(1.0-float(u.life)/1.1,0.0,1.0)
	var alpha := sin(t*PI)
	var color := Color("c5e6a4") if strings else Color("71e0d0")
	var count := 5 if strings else 2
	for band in range(count):
		var points := PackedVector2Array()
		for i in range(33):
			var f := float(i)/32.0
			var point: Vector2 = u.a.lerp(u.b,f)
			if strings:
				point.y -= sin(f*PI)*(30+band*13)
				point.y += sin(f*PI*4-t*TAU+band)*4*sin(f*PI)
			else:
				point.y += (-1.0 if band == 0 else 1.0)*sin(f*PI)*(42+sin(t*PI)*24)
			points.append(point)
		draw_polyline(points,Color(color,alpha*.1),7.0 if strings else 13.0,true)
		draw_polyline(points,Color(color,alpha*.8),1.3 if strings else 2.6,true)
		var tip: Vector2 = points[clampi(int(t*48)+band*3,0,32)]
		draw_circle(tip,2.2,Color("f0ffe7",alpha))
	var center: Vector2 = u.b
	if strings:
		for leaf in range(5):
			var angle := float(leaf)*TAU/5-t*.7
			var at := center+Vector2.from_angle(angle)*(24+t*30)
			draw_colored_polygon(PackedVector2Array([at+Vector2(-8,0),at+Vector2(0,-4),at+Vector2(8,0),at+Vector2(0,4)]),Color(color,alpha*.8))
	else:
		for side in [-1.0,1.0]:
			draw_line(center+Vector2(-42,-side*38),center+Vector2(42,side*38),Color(color,alpha*.16),12.0,true)
			draw_line(center+Vector2(-42,-side*38),center+Vector2(42,side*38),Color("e6fff4",alpha*.85),2.0,true)

func _draw_lantern_ultimate(u: Dictionary) -> void:
	# A narrow light-road, not a dragon silhouette or a full-screen opaque cut-in.
	var t := clampf(1.0 - float(u.life) / 1.1, 0.0, 1.0)
	var fade := minf(1.0, (1.0 - t) * 4.0)
	var copper := Color("e7ac66")
	var ivory := Color("fff1ca")
	var path := PackedVector2Array()
	for i in range(33):
		var f := float(i) / 32.0
		var point: Vector2 = u.a.lerp(u.b, f)
		point.y -= sin(f * PI) * 24.0
		path.append(point)
	var shown := clampi(int(t * 64.0) + 2, 2, path.size())
	var lit_path := path.slice(0, shown)
	draw_polyline(lit_path, Color(copper, fade * 0.12), 7.0, true)
	draw_polyline(lit_path, Color(copper, fade * 0.72), 1.3, true)
	for lamp in range(5):
		var ignite := clampf((t - float(lamp) * 0.095) * 9.0, 0.0, 1.0)
		if ignite <= 0.0:continue
		var f := (float(lamp) + 0.5) / 5.0
		var at: Vector2 = u.a.lerp(u.b, f)
		at.y -= sin(f * PI) * 24.0
		var alpha := fade * ignite
		draw_circle(at, 12.0, Color(copper, alpha * 0.10))
		draw_circle(at, 7.0, Color(ivory, alpha * 0.16))
		var frame := PackedVector2Array([at + Vector2(-4,-6), at + Vector2(4,-6), at + Vector2(6,5), at + Vector2(-6,5), at + Vector2(-4,-6)])
		draw_polyline(frame, Color(copper, alpha), 1.2, true)
		draw_arc(at + Vector2(0,-7), 3.0, PI, TAU, 12, Color(ivory, alpha), 1.0, true)
		draw_line(at + Vector2(-5,7), at + Vector2(5,7), Color(copper, alpha), 1.2, true)
		draw_colored_polygon(PackedVector2Array([at+Vector2(0,-4),at+Vector2(2.5,1),at+Vector2(0,4),at+Vector2(-2.5,1)]),Color(ivory,alpha))
