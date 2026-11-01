extends SceneTree
const Game=preload("res://scripts/game_model.gd")
const Battle=preload("res://scripts/battle_model.gd")
var checks:=0
var failures:=0
func ck(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",label)
func setup():
	var g=Game.new("");g.rng.seed=241510;var x=g.extraction;x.start_run()
	var room:Dictionary=x.route_options()[0]
	for entry in x.run().map.rooms:
		if entry.id==room.id:entry.type="cache"
	x.enter_room(room.id);x.run().bag=[];x.run().containers=[];x._container("交易箱",0,0)
	return g
func item(x,id:String)->Dictionary:
	var out:Dictionary=x._make_item(id);out.revealed=true;return out
func add_bag(x,id:String)->Dictionary:
	var out:=item(x,id);ck(x._place(x.run().bag,out,x.dimensions("bag")),"bag fixture fits");return out
func fill_trade(x)->Dictionary:
	while x.run().bag.size()<30:
		var out:=item(x,"wire")
		if not x._place(x.run().bag,out,x.dimensions("bag")):break
	var box:Dictionary=x.run().containers[0];box.width=6;box.height=8;box.items=[]
	for n in 30:
		var incoming:=item(x,"diamond_ring");ck(x._place(box.items,incoming,Vector2i(6,8)),"incoming real placement")
	box.revealed=box.items.size();return box
func count_uid(x,uid:String)->int:
	var count:=0
	for entry in x.run().bag:
		if entry.uid==uid:count+=1
	for box in x.run().containers:
		for entry in box.items:
			if entry.uid==uid:count+=1
	return count
func test_effect(kind:String)->void:
	var g=setup();var x=g.extraction;var supply:=add_bag(x,kind);var box:=fill_trade(x)
	for unit in x.run().party:unit.currentHp=unit.maxHp;unit.energy=100;unit.cooldowns={}
	x.state().utility.armor=item(x,"armor_5");x.state().utility.armor.condition=1.0
	match kind:
		"bandage":x.run().party[0].currentHp=int(x.run().party[0].maxHp*.5)
		"repair_patch":x.state().utility.armor.condition=.4
		"energy_tonic":x.run().party[0].energy=30
		"revival_incense":x.run().party[1].currentHp=0
		"cleanse_salt":x.run().party[0].cooldowns={"flame_strike":3}
	var before:Dictionary=g.state.duplicate(true);var plan:Dictionary=x.plan_smart_loot(box.id)
	ck(plan.success and plan.willUse.size()==1 and plan.willUse[0].uid==supply.uid,"preview predicts effective "+kind)
	ck(g.state==before,"preview leaves party gear and items unchanged")
	g.save_blocked=true;ck(not x.apply_smart_loot(box.id,plan.planHash).success and g.state==before,"supply exchange and healing rollback together")
	g.save_blocked=false;var result:Dictionary=x.apply_smart_loot(box.id,plan.planHash)
	ck(result.success and result.usedUIDs==[supply.uid] and count_uid(x,supply.uid)==0,"effective outgoing consumed exactly once "+kind)
	ck(result.returnedUIDs.size()==29 and result.used.size()==1,"result separates used from returned")
	match kind:
		"bandage":ck(x.run().party[0].currentHp==int(before.extraction.run.party[0].currentHp)+int(x.run().party[0].maxHp*.15),"heal actual amount")
		"repair_patch":ck(is_equal_approx(x.state().utility.armor.condition,.65),"repair actual capacity")
		"energy_tonic":ck(x.run().party[0].energy==50,"energy actual gain")
		"revival_incense":ck(x.run().party[1].currentHp==int(x.run().party[1].maxHp*.15),"revive actual health")
		"cleanse_salt":ck(x.run().party[0].cooldowns.flame_strike==0,"cooldown actually cleared")
	before=g.state.duplicate(true)
	ck(not x.apply_smart_loot(box.id,plan.planHash).success and g.state==before,"exchange replay never heals again")
	ck(g.valid_save(g.state),"consumable transaction produces valid save")
func test_full_and_sequential()->void:
	var g=setup();var x=g.extraction;var ids:Array=[]
	for kind in ["bandage","repair_patch","energy_tonic","revival_incense","cleanse_salt"]:ids.append(add_bag(x,kind).uid)
	var box:=fill_trade(x)
	for unit in x.run().party:unit.currentHp=unit.maxHp;unit.energy=100;unit.cooldowns={}
	x.state().utility.armor=item(x,"armor_5");x.state().utility.armor.condition=1.0
	var plan:Dictionary=x.plan_smart_loot(box.id);var before:Dictionary=g.state.duplicate(true)
	ck(plan.success and plan.willUse.is_empty() and plan.returned.size()==30,"full states consume no outgoing supplies")
	var result:Dictionary=x.apply_smart_loot(box.id,plan.planHash)
	ck(result.success and result.used.is_empty() and x.run().party==before.extraction.run.party and x.state().utility==before.extraction.utility,"no useless heal shield energy revive or cleanse")
	for uid in ids:ck(count_uid(x,uid)==1 and result.returnedUIDs.has(uid),"unusable outgoing supply remains in container")
	g=setup();x=g.extraction;var first:=add_bag(x,"bandage");var second:=add_bag(x,"bandage");box=fill_trade(x)
	for unit in x.run().party:unit.currentHp=unit.maxHp
	x.run().party[0].currentHp-=1
	plan=x.plan_smart_loot(box.id)
	ck(plan.willUse.size()==1 and plan.willUse[0].uid==first.uid and plan.returned.any(func(it):return it.uid==second.uid),"sequential preview uses only first effective medicine")
	result=x.apply_smart_loot(box.id,plan.planHash)
	ck(result.usedUIDs==[first.uid] and count_uid(x,first.uid)==0 and count_uid(x,second.uid)==1,"second full-health medicine is returned untouched")
	g=setup();x=g.extraction;first=add_bag(x,"bandage");second=add_bag(x,"revival_incense");box=fill_trade(x)
	for unit in x.run().party:unit.currentHp=0
	plan=x.plan_smart_loot(box.id)
	ck(plan.willUse.map(func(it):return it.uid)==[second.uid,first.uid],"preview revives before healing regardless of backpack order")
	result=x.apply_smart_loot(box.id,plan.planHash)
	ck(result.usedUIDs==[second.uid,first.uid] and x.run().party[0].currentHp==int(x.run().party[0].maxHp*.15)*2,"commit follows identical revive then heal order")

func test_lock_and_stale()->void:
	var g=setup();var x=g.extraction;var locked:=add_bag(x,"bandage");var free:=add_bag(x,"bandage");var gear:=add_bag(x,"vest");var box:=fill_trade(x)
	x.run().party[0].currentHp=1
	var before:Dictionary=g.state.duplicate(true);g.save_blocked=true
	ck(not x.set_consumable_exchange_lock(locked.uid,true).success and g.state==before,"lock persistence atomic")
	g.save_blocked=false;ck(x.set_consumable_exchange_lock(locked.uid,true).success,"lock one consumable UID")
	ck(not x.set_consumable_exchange_lock(gear.uid,true).success and not x.set_consumable_exchange_lock("missing",true).success,"lock type and UID validation")
	var plan:Dictionary=x.plan_smart_loot(box.id)
	ck(plan.success and plan.removed.any(func(it):return it.uid==free.uid) and not plan.removed.any(func(it):return it.uid==locked.uid or it.uid==gear.uid),"unlocked supplies swap while locked supplies and gear stay")
	before=g.state.duplicate(true)
	var loaded=Game.new("");loaded.state=loaded._normalize(JSON.parse_string(JSON.stringify(g.state)))
	ck(loaded.valid_save(loaded.state) and loaded.extraction.run().bag.filter(func(it):return it.uid==locked.uid)[0].exchangeLocked,"per-instance lock persists migration")
	ck(x.set_consumable_exchange_lock(locked.uid,false).success,"unlock explicit")
	var changed:Dictionary=g.state.duplicate(true)
	ck(not x.apply_smart_loot(box.id,plan.planHash).success and g.state==changed,"lock change invalidates smart plan")
	g.state=before;plan=x.plan_smart_loot(box.id);x.run().party[0].currentHp+=1;changed=g.state.duplicate(true)
	ck(not x.apply_smart_loot(box.id,plan.planHash).success and g.state==changed,"health change invalidates smart plan")
	g.state=before;plan=x.plan_smart_loot(box.id);x.run().party[0].energy=99;changed=g.state.duplicate(true)
	ck(not x.apply_smart_loot(box.id,plan.planHash).success and g.state==changed,"energy change invalidates smart plan")
	g.state=before;plan=x.plan_smart_loot(box.id);x.run().party[0].cooldowns={"flame_strike":2};changed=g.state.duplicate(true)
	ck(not x.apply_smart_loot(box.id,plan.planHash).success and g.state==changed,"cooldown change invalidates smart plan")
	g.state=before;x.state().utility.armor=item(x,"armor_5");x.state().utility.armor.condition=.5;plan=x.plan_smart_loot(box.id);x.state().utility.armor.condition=.6;changed=g.state.duplicate(true)
	ck(not x.apply_smart_loot(box.id,plan.planHash).success and g.state==changed,"armor condition change invalidates smart plan")
	g.state=before
	ck(x.use_item(locked.uid).success and count_uid(x,locked.uid)==0,"locked consumable still manually usable")
	g=setup();x=g.extraction;locked=add_bag(x,"bandage");box=fill_trade(x);x.set_consumable_exchange_lock(locked.uid,true)
	var manual:Dictionary=x.preview_exchange(box.id,box.items[0].uid,[locked.uid])
	ck(manual.success and x.exchange_items(box.id,box.items[0].uid,[locked.uid],manual.planHash).success,"lock does not prohibit deliberate manual exchange")
	ck(x._find_container(box.id).items.any(func(it):return it.uid==locked.uid and it.exchangeLocked),"manual exchange preserves lock on original instance")
	# Camp scopes keep their lock through loadout departure and mailbox/stash storage.
	g=Game.new("");x=g.extraction
	for scope in ["stash","loadout","mailbox"]:
		var supply:Dictionary={"uid":"locked_"+scope,"itemId":"bandage","x":0,"y":0,"rotated":false,"revealed":true}
		x.state()[scope].append(supply);ck(x.set_consumable_exchange_lock(supply.uid,true).success,"lock owned camp scope "+scope)
	ck(g.valid_save(g.state) and x.start_run().success and x.run().bag[0].exchangeLocked,"locked loadout retains identity at departure")
	# Starting a live battle retains the established manual-use and auto-loot restriction.
	x._generate_encounter("battle");var engine=Battle.new(g.catalog);x.start_battle(engine);before=g.state.duplicate(true)
	ck(not x.use_item(x.run().bag[0].uid).success and not x.set_consumable_exchange_lock(x.run().bag[0].uid,false).success and not x.plan_smart_loot("anything").success and g.state==before,"live battle cannot trigger potion or automatic trade")
func _init()->void:
	for kind in ["bandage","repair_patch","energy_tonic","revival_incense","cleanse_salt"]:test_effect(kind)
	test_full_and_sequential();test_lock_and_stale()
	print("SMART LOOT SUPPLIES V241 ",checks," checks ",failures," failures");quit(0 if failures==0 else 1)
