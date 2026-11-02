extends SceneTree
const Game=preload("res://scripts/game_model.gd")
var checks:=0
var failures:=0
func ck(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func _initialize()->void:
	var game=Game.new("");game.state.resources.gold=1000000
	var ex=game.extraction
	ck(ex.buy_supply("pack_5").success,"purchase actual large bag")
	ck(ex.set_utility_slot(str(ex.item_def("pack_5").slot),str(ex.state().stash.back().uid)).success,"equip actual bag")
	ck(ex.start_run().success,"start actual run")
	var id:String=ex.route_options()[0].id
	for room in ex.run().map.rooms:
		if room.id==id:room.type="cache";room.guardPending=false
	ck(ex.enter_room(id).success,"enter actual cache")
	ex.run().phase="room";ex.run().activeEncounter={};ex.run().pendingChoices=[];ex.run().containers=[]
	ex._container("回归箱",0,0)
	var box:Dictionary=ex.run().containers[0]
	var incoming:Dictionary=ex._make_item("reactor");incoming.revealed=true;incoming.appraisalRisk=5
	box.items=[incoming];box.revealed=1
	ex.run().bag=[]
	for i in 15:
		var item:Dictionary=ex._make_item("barrier_module");item.revealed=true;item.appraisalRisk=5
		ex.run().bag.append(item)
	ex.run().bag=ex._packed_copy(ex.run().bag,ex.dimensions("bag"))
	var worn_before:String=JSON.stringify(ex.run().equipped)
	var plan:Dictionary=ex.plan_smart_loot(str(box.id))
	ck(plan.success and plan.gain==1026,"idle equipment replacement exact gain")
	if plan.success:
		ck(ex.apply_smart_loot(str(box.id),str(plan.planHash)).success,"actual planned swap commits")
		ck(ex.run().bag.any(func(i):return i.uid==incoming.uid),"incoming equipment enters bag")
		ck(box.items.any(func(i):return i.itemId=="barrier_module"),"outgoing equipment retained in container")
		ck(JSON.stringify(ex.run().equipped)==worn_before,"worn equipment unchanged")
		ck(not ex.apply_smart_loot(str(box.id),str(plan.planHash)).success,"stale repeat swap rejected")
	# Fixed previously diagnosed 59-cell geometry, no search for random cases.
	var ids=["forest_root_monolith","sanctum_eclipse_fossil","crown","ration_5","sanctum_sapphire_scepter","sanctum_meteor_shard","sanctum_constellation_slate","ruins_copper_lamp","crystal","injector","research_notes","hologram","injector","hologram","wire","ruins_frayed_linen"]
	var greedy:Array=[];var rejected:Array=[]
	for i in ids.size():
		var item:Dictionary=ex._make_item(ids[i]);item.revealed=true
		var shape:Vector2i=ex._size(item);item.legacyValue=(1000-i)*shape.x*shape.y
		if not ex._place(greedy,item.duplicate(true),ex.dimensions("bag")):rejected.append(item)
	ck(greedy.size()==15 and rejected.size()==1,"fixed greedy layout rejects final item")
	ex.run().bag=greedy;box.items=rejected;box.revealed=rejected.size()
	plan=ex.plan_smart_loot(str(box.id))
	ck(plan.success and plan.packed.size()==16 and plan.removed.is_empty(),"production geometry repack fits all 16 without loss")
	for item in plan.get("packed",[]):ck(ex._fits(plan.packed,item,ex.dimensions("bag")),"legal non-overlapping final placement")
	# Locked consumables are hard-protected; unlocking permits exchange.
	ex.run().bag=[]
	for i in 60:
		var item:Dictionary=ex._make_item("injector");item.revealed=true;item.appraisalRisk=5;item.exchangeLocked=true
		ex.run().bag.append(item)
	ex.run().bag=ex._packed_copy(ex.run().bag,ex.dimensions("bag"));box.items=[incoming];box.revealed=1
	ck(not ex.plan_smart_loot(str(box.id)).success,"locked consumables protected")
	for item in ex.run().bag:item.exchangeLocked=false
	for member in ex.run().party:member.currentHp=maxi(1,int(member.maxHp)*0.2)
	plan=ex.plan_smart_loot(str(box.id))
	ck(plan.success and plan.removed.size()==4,"unlocked consumables exchange normally")
	if plan.success:
		var before_hp:int=ex.run().party[0].currentHp
		var applied:Dictionary=ex.apply_smart_loot(str(box.id),str(plan.planHash))
		ck(applied.success,"unlocked consumable replacement commits: "+str(applied.get("error","")))
		ck(applied.get("used",[]).size()>0 and ex.run().party[0].currentHp>before_hp,"outgoing usable consumables automatically heal")
	print("SMART LOOT INTEGRATED V268: %d checks, %d failures"%[checks,failures]);quit(0 if failures==0 else 1)
