extends SceneTree
const Game=preload("res://scripts/game_model.gd")
const IDS=["bolts","blade","royal_scepter","barrier_module","vest","servo_arm","dragon_egg"]
var game
var x
var checks:=0
var failures:=0
func ck(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",label)

var combinations:=0
var feasible:=0
var false_rejections:Array=[]
var max_nodes:=0
var worst:Array=[]
var max_ms:=0.0
var times:Array=[]
var bounds:=Vector2i(5,5)
func visit(index:int,left:int,selected:Array)->void:
	if index<IDS.size():
		var id:String=IDS[index];var d:Dictionary=x.item_def(id);var area:int=d.width*d.height
		for count in range(int(left/area)+1):
			var next:Array=selected.duplicate()
			for k in count:next.append(id)
			visit(index+1,left-count*area,next)
		return
	var items:Array=[]
	for id in selected:
		items.append({"uid":str(items.size()),"itemId":id,"x":0,"y":0,"rotated":false,"revealed":true})
	# Unit cells fill every remaining gap; fitting does not depend on their identity.
	for n in left:items.append({"uid":str(items.size()),"itemId":"wire","x":0,"y":0,"rotated":false,"revealed":true})
	var start:int=Time.get_ticks_usec();var layout:Array=x._pack_parcel(items,bounds)
	var duration:float=(Time.get_ticks_usec()-start)/1000.0;times.append(duration);max_ms=maxf(max_ms,duration)
	combinations+=1
	if layout.size()==items.size():
		for placed_item in layout:ck(x._fits(layout,placed_item,bounds),"every packed rectangle is inside bounds without overlap")
		var actual:Array=layout.map(func(entry):return entry.uid);actual.sort()
		var expected:Array=items.map(func(entry):return entry.uid);expected.sort()
		ck(actual==expected,"exact physical UID multiset preserved")
		feasible+=1;return
	var pending:Array=items.duplicate(true)
	pending.sort_custom(func(a,b):
		var sa:Vector2i=x._size(a);var sb:Vector2i=x._size(b)
		return sa.x*sa.y>sb.x*sb.y if sa.x*sa.y!=sb.x*sb.y else maxi(sa.x,sa.y)>maxi(sb.x,sb.y))
	var board:Array=[];board.resize(bounds.y);board.fill(0)
	var search:Dictionary={"nodes":0,"limit":1000000,"memo":{}};var oracle:Array=[]
	var possible:bool=x._pack_search(pending,0,bounds,board,oracle,0,search)
	ck(search.nodes<=search.limit,"independent reference search resolves within generous budget")
	if search.nodes>max_nodes:max_nodes=search.nodes;worst=selected.duplicate()
	if possible:feasible+=1;false_rejections.append({"shapes":selected,"reference_nodes":search.nodes,"ms":duration})
func _init()->void:
	game=Game.new("");x=game.extraction
	for dim in [Vector2i(5,5),Vector2i(6,6)]:
		bounds=dim;combinations=0;feasible=0;false_rejections=[];max_nodes=0;worst=[];max_ms=0;times=[]
		visit(0,bounds.x*bounds.y,[]);times.sort()
		print(JSON.stringify({"bounds":[bounds.x,bounds.y],"combinations":combinations,"feasible":feasible,"false_rejections":false_rejections,"reference_worst_nodes":max_nodes,"reference_worst_shapes":worst,"median_ms":times[times.size()/2],"p95_ms":times[int(ceil(times.size()*.95))-1],"max_ms":max_ms}))
		ck(false_rejections.is_empty(),"every reference-feasible catalog shape multiset packs within production budget")
	# Source dimensions, oversized objects, impossible equal-area shapes and long thin tiles.
	game.extraction.start_run();x.run().phase="room";x.run().room.type="relay"
	var hard:Array=[]
	for id in ["bolts","bolts","bolts","bolts","bolts","bolts","bolts","bolts","bolts","blade","royal_scepter"]:
		var entry:Dictionary=x._make_item(id);entry.revealed=true
		ck(x._place(x.run().bag,entry,x.dimensions("bag")),"hard valid source layout")
		hard.append(entry.uid)
	var plan:Dictionary=x.preview_deposit(hard)
	ck(plan.success and plan.items.size()==11 and plan.width==5 and plan.height==5,"known valid 25-cell combination escapes old 30601-node ordering trap")
	for entry in plan.items:ck(x._fits(plan.items,entry,Vector2i(5,5)),"hard packing actual cell validity")
	x.run().bag=[]
	for n in 2:
		var entry:Dictionary=x._make_item("dragon_egg");entry.revealed=true;x._place(x.run().bag,entry,x.dimensions("bag"))
	ck(not x.preview_deposit(x.run().bag.map(func(entry):return entry.uid)).success,"two 3x3 objects cannot occupy 5x5 despite area18")
	plan=x.preview_deposit();ck(plan.success and plan.items.size()==1 and not plan.optimal,"automatic spatial fallback honestly reports heuristic selection")
	# Crossing bit 31 is real geometry: 36 one-cell items must occupy all 36 distinct cells.
	x.run().room.type="boss";x.run().phase="boss_exit";x.run().bag=[]
	x.state().utility.backpack=x._make_item("pack_5")
	for n in 60:
		var entry:Dictionary=x._make_item("wire");entry.revealed=true;ck(x._place(x.run().bag,entry,x.dimensions("bag")),"sixty-cell full source")
	plan=x.preview_deposit();ck(plan.success and plan.width==6 and plan.height==6 and plan.items.size()==36 and plan.optimal,"boss packs all 36 actual cells above 32-bit boundary")
	var occupied:int=0
	for entry in plan.items:
		ck(x._fits(plan.items,entry,Vector2i(6,6)),"36-cell no overlap")
		occupied|=1<<(int(entry.y)*6+int(entry.x))
	ck(occupied==(1<<36)-1,"36 bits preserve high row without truncation")
	var overlap:Array=plan.items.duplicate(true);overlap[1].x=overlap[0].x;overlap[1].y=overlap[0].y
	ck(not x._fits(overlap,overlap[1],Vector2i(6,6)),"explicit illegal overlap rejected")
	# Two synthetic 4x4 objects have area32 but cannot coexist inside6x6.
	x.data.items.synthetic_square={"name":"geometry test","kind":"loot","width":4,"height":4,"value":1000}
	x.run().bag=[]
	for n in 2:
		var entry:Dictionary=x._make_item("synthetic_square");entry.revealed=true;ck(x._place(x.run().bag,entry,x.dimensions("bag")),"source holds two four-square objects")
	ck(not x.preview_deposit(x.run().bag.map(func(entry):return entry.uid)).success,"area alone cannot fit two4x4 into6x6")
	plan=x.preview_deposit();ck(plan.success and plan.items.size()==1 and not plan.optimal,"boss geometric fallback remains honest")
	x.data.items.synthetic_oversize={"name":"oversize test","kind":"loot","width":7,"height":1,"value":1000000}
	x.run().bag=[];var oversized:Dictionary=x._make_item("synthetic_oversize");oversized.revealed=true;x._place(x.run().bag,oversized,x.dimensions("bag"))
	for boss in [false,true]:
		x.run().room.type="boss" if boss else "relay";x.run().phase="boss_exit" if boss else "room"
		ck(not x.preview_deposit([oversized.uid]).success,"oversized manual rectangle rejected in both orientations")
		plan=x.preview_deposit();ck(plan.success and plan.items.is_empty() and not plan.enabled,"oversized automatic rectangle excluded")
	print("PARCEL PACKING V241 ",checks," checks ",failures," failures")
	quit(0 if failures==0 else 1)
