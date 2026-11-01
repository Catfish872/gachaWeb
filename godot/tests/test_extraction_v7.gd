extends SceneTree
const Game=preload("res://scripts/game_model.gd")
const Battle=preload("res://scripts/battle_model.gd")
var checks:=0
var failures:=0
func ck(ok:bool,label:String)->void:
	checks+=1
	if not ok: failures+=1;printerr("FAIL: ",label)
func buy_equip(g,id:String,slot:String)->String:
	var x=g.extraction
	ck(x.buy_supply(id).success,"purchase "+id)
	var uid:String=x.state().stash.back().uid
	ck(x.set_utility_slot(slot,uid).success,"equip "+id)
	return uid
func room(x,kind:String)->void:
	x.run().phase="room"
	x.run().room.type=kind
func make(x,id:String,value:int=-1)->Dictionary:
	var item:Dictionary=x._make_item(id);item.revealed=true
	if value>=0:item.legacyValue=value
	return item
func _init()->void:
	var g=Game.new("");var x=g.extraction;g.rng.seed=13400001
	ck(g.state.version==9 and g.valid_save(g.state),"v7 defaults")
	ck(x.data.items.size()==128,"128 real item definitions")
	var armor_uid:=buy_equip(g,"armor_5","armor")
	var pack_uid:=buy_equip(g,"pack_5","backpack")
	ck(x.dimensions("bag")==Vector2i(6,10),"60-cell pack")
	ck(x.start_run().success,"depart with persistent utility")
	room(x,"cache")
	ck(x.run().bag.is_empty() and x.state().utility.armor.uid==armor_uid,"utility unique outside bag")
	var status:Dictionary=x.equipment_status()
	ck(status.armor.max==x.run().baseMaxHp*2,"200 percent base HP")
	x._generate_encounter("battle")
	var b=Battle.new(g.catalog);var result:Dictionary=x.start_battle(b)
	ck(result.success,"battle starts with equipment shield")
	var ally:Dictionary=b.state.allies[0]
	var initial:int=ally.shield
	ck(initial==int(x.run().party[0].stats.maxHp)*2,"individual existing shield amount")
	ck(b.has_status(ally,"shield"),"equipment uses existing shield status")
	b.apply_status(ally,"shield",2,0.3,ally)
	var equip_before:=0;var skill_before:=0
	for s in ally.statuses:
		if s.id!="shield":continue
		if s.get("source","")=="expedition_equipment":equip_before+=int(s.shieldHp)
		else:skill_before+=int(s.shieldHp)
	ck(equip_before==initial and skill_before>0,"skill cannot refresh equipment source")
	ck(b._absorb(ally,skill_before+7)==0,"normal shield absorption")
	var equipped_remaining:=0
	for s in ally.statuses:
		if s.get("source","")=="expedition_equipment":equipped_remaining+=int(s.shieldHp)
	ck(equipped_remaining==initial-7,"skill shield consumed before equipment")
	var hp:int=ally.currentHp;var shield:int=ally.shield
	b._status_damage(ally,3,"poison")
	ck(ally.currentHp==hp-3 and ally.shield==shield,"DOT follows existing shield bypass")
	for i in range(4):b._end_round()
	ck(b.has_status(ally,"shield") and ally.shield==shield,"equipment source does not expire")
	b._heal(ally,ally,1000,"test",false,"status")
	ck(ally.shield==shield,"healing does not repair equipment shield")
	var safety:=0
	while b.state.phase not in ["victory","defeat"] and safety<2000:b.auto_step();safety+=1
	var expected:float=float(b.state.equipmentShieldRemaining)/float(b.state.config.equipmentShieldMax)
	ck(x.settle_battle(result.config,b.state).success,"real battle settlement")
	ck(is_equal_approx(float(x.state().utility.armor.condition),expected),"durability follows actual source remainder")
	if not x.growth_choices().is_empty():ck(x.choose_growth(x.growth_choices()[0].choiceId).success,"growth independent")
	var condition:float=x.state().utility.armor.condition
	var allocations:Dictionary=x._equipment_shield_allocations();var total:=0
	for v in allocations.values():total+=int(v)
	ck(total==int(x.equipment_status().armor.current),"integer remainder conserves total shield")
	# Full backpack does not prevent field repairs, energy or resurrection.
	x.run().bag=[]
	for i in range(60):ck(x._place(x.run().bag,make(x,"dried_fruit"),x.dimensions("bag")),"full sixty cells")
	x.run().containers=[];room(x,"cache");x._container("test",1,0)
	var c:Dictionary=x.run().containers[0]
	x.state().utility.armor.condition=0.2;c.items=[make(x,"repair_kit")]
	var bag_before:Array=x.run().bag.duplicate(true)
	ck(x.use_container_item(c.id,c.items[0].uid).success,"full bag direct repair")
	ck(is_equal_approx(x.state().utility.armor.condition,0.7) and x.run().bag==bag_before,"repair affects durability only")
	c.items=[make(x,"pack_1")];var smaller_uid:String=c.items[0].uid
	var before:Dictionary=g.state.duplicate(true)
	ck(not x.equip_container_item(c.id,smaller_uid).success and g.state==before,"small pack refusal preserves all items")
	ck(not x.remove_utility_slot("backpack").success,"cannot shrink full bag")
	x.run().party[0].currentHp=0;c=x.run().containers[0];c.items=[make(x,"revival_incense")]
	ck(x.use_container_item(c.id,c.items[0].uid).success and x.run().party[0].currentHp>0,"full bag direct revival")
	x.run().party[0].energy=0;c.items=[make(x,"energy_tonic")]
	ck(x.use_container_item(c.id,c.items[0].uid).success and x.run().party[0].energy==20,"direct energy")
	x.run().party[0].cooldowns={"test":4};c.items=[make(x,"cleanse_salt")]
	ck(x.use_container_item(c.id,c.items[0].uid).success and x.run().party[0].cooldowns.test==0,"cooldown restorative")
	x.run().party[0].cooldowns={}
	ck(not x.can_use_consumable("cleanse_salt"),"no useless restorative consume")
	# One-time v6 appraisal preservation, including active physical instances.
	var old:Dictionary=g.state.duplicate(true);old.version=6
	old.extraction.run.bag[0].erase("legacyValue");old.extraction.run.bag[0].appraisalRisk=5
	var old_price:=int(x.item_def(old.extraction.run.bag[0].itemId).v6Value)*4
	g.state=g._normalize(old)
	ck(g.state.version==9 and x.item_value(x.run().bag[0])==old_price,"v6 physical value preserved")
	before=g.state.duplicate(true);g.state=g._normalize(g.state)
	ck(g.state==before,"v7 normalize idempotent")
	ck(x.retreat().success,"retreat preserves equipped utility")
	ck(x.state().utility.armor.uid==armor_uid and x.state().utility.backpack.uid==pack_uid,"no compensation duplicate on retreat")
	ck(is_equal_approx(x.state().utility.armor.condition,0.7),"retreat retains consumed condition")
	before=g.state.duplicate(true);g.save_blocked=true
	ck(not x.repair_equipment().success and g.state==before,"repair payment rollback")
	g.save_blocked=false;var cost:int=x.repair_quote().cost;var gold:int=g.state.resources.gold
	ck(x.repair_equipment().success and g.state.resources.gold==gold-cost,"proportional repair payment")
	ck(x.state().utility.armor.condition==1.0,"camp repair full")
	# Relay 5x5 parcel prioritizes value and verifies all actual occupied cells.
	ck(x.start_run().success,"deposit run")
	room(x,"relay");x.run().bag=[]
	var large:Dictionary=make(x,"vest",100);large.itemId="barrier_module"
	ck(x._place(x.run().bag,large,x.dimensions("bag")),"large deposit fixture")
	for i in range(22):ck(x._place(x.run().bag,make(x,"dried_fruit",40),x.dimensions("bag")),"small deposit fixture")
	var plan:Dictionary=x.preview_deposit()
	ck(plan.success and plan.value==940 and plan.items.size()==22,"exact highest total value")
	for item in plan.items: ck(x._fits(plan.items,item,Vector2i(5,5)),"deposit preview independent nonoverlapping placements")
	ck(not x.preview_deposit(x.run().bag.map(func(item): return item.uid)).success,"manual overflow rejected")
	var manual:Dictionary=x.preview_deposit([large.uid])
	ck(manual.success and manual.value==100,"manual chosen object preview")
	before=g.state.duplicate(true);g.save_blocked=true
	ck(not x.deposit_items(plan.planHash).success and g.state==before,"deposit atomic rollback")
	g.save_blocked=false;gold=g.state.resources.gold
	ck(x.deposit_items(plan.planHash).success,"deposit exact plan")
	ck(g.state.resources.gold==gold-plan.fee and x.run().securedValue==940,"deposit fee and banked value")
	ck(not x.deposit_items(plan.planHash).success,"deposit replay rejected")
	var stashed:int=x.state().stash.size()
	ck(x.retreat().success and x.state().stash.size()==stashed,"deposit survives retreat exactly once")
	ck(g.valid_save(g.state),"final valid")
	# New decisions persist and charge exactly once.
	ck(x.start_run().success,"event run")
	room(x,"event");x._prepare_room_actions("event",3)
	ck(not x.room_actions()[0].enabled,"full equipment shield cannot waste repair event")
	x.state().utility.armor.condition=0.3
	ck(x.choose_room_action("mend").success and is_equal_approx(x.state().utility.armor.condition,0.75),"repair event adds capacity")
	ck(not x.choose_room_action("mend").success,"event one choice")
	x._prepare_room_actions("event",4);x.state().utility.armor.condition=0.2
	ck(not x.room_actions()[0].enabled,"forge needs actual shield reserve")
	x.state().utility.armor.condition=0.8;before=g.state.duplicate(true);g.save_blocked=true
	ck(not x.choose_room_action("transmute").success and g.state==before,"forge payment and choices atomic")
	g.save_blocked=false
	ck(x.choose_room_action("transmute").success and is_equal_approx(x.state().utility.armor.condition,0.45),"forge spends shield capacity")
	ck(x.growth_choices().size()==3,"forge gold choices")
	for choice in x.growth_choices():ck(choice.rarity=="gold","forge canonical gold pool")
	ck(x.choose_growth(x.growth_choices()[0].choiceId).success,"forge choice resolve")
	x._prepare_room_actions("event",5);x.run().bag=[]
	for i in range(60):x._place(x.run().bag,make(x,"dried_fruit"),x.dimensions("bag"))
	x.run().containers=[]
	ck(x.choose_room_action("key").success,"key event with full bag")
	c=x.run().containers.back();var key_uid:String=c.items[0].uid
	ck(c.items[0].itemId==x._room_key_id(),"key matches actual district")
	ck(x.reveal_next(c.id).success,"key visible in room")
	ck(x.take_item(c.id,key_uid).success,"full bag key enters independent ring")
	ck(x.run().bag.size()==60,"key uses zero bag cells")
	ck(not x.take_item(c.id,key_uid).success,"key pickup replay refused")
	room(x,"key_vault");x._prepare_room_actions("key_vault")
	before=g.state.duplicate(true);g.save_blocked=true
	ck(not x.choose_room_action("unlock").success and g.state==before,"key and chest unlock atomic")
	g.save_blocked=false
	ck(x.choose_room_action("unlock").success and x.run().room.unlocked,"key unlock")
	var has_key:=false
	for item in x.run().bag:
		if item.uid==key_uid:has_key=true
	ck(not has_key,"one key consumed")
	ck(not x.choose_room_action("unlock").success,"key unlock replay rejected")
	room(x,"event");x._prepare_room_actions("event",5)
	var preview:Dictionary=x.room_actions()[0].encounterPreview.duplicate(true)
	var bad_actions:Array=x.run().roomActions.duplicate(true)
	bad_actions[0].erase("encounter")
	ck(not x._valid_room_actions(bad_actions),"missing event enemy config rejected")
	bad_actions=x.run().roomActions.duplicate(true);bad_actions[0].encounter.scaleMult.hpMod="bad"
	ck(not x._valid_room_actions(bad_actions),"malformed event budget rejected")
	ck(x.choose_room_action("challenge").success and x.run().activeEncounter==preview,"challenge uses displayed encounter")
	ck(x.can_prepare_supplies(),"encounter allows prebattle preparation")
	x.run().bag=[];x.state().utility.armor.condition=0.1
	var repair_item:Dictionary=make(x,"repair_kit");x._place(x.run().bag,repair_item,x.dimensions("bag"))
	ck(x.use_item(repair_item.uid).success and is_equal_approx(x.state().utility.armor.condition,0.6),"repair before confirmed fight")
	b=Battle.new(g.catalog);result=x.start_battle(b)
	ck(result.success and not x.can_prepare_supplies(),"started combat locks preparation")
	while b.state.phase not in ["victory","defeat"]:b.auto_step()
	before=g.state.duplicate(true);g.save_blocked=true
	ck(not x.settle_battle(result.config,b.state).success and g.state==before,"shield settlement save rollback")
	g.save_blocked=false
	ck(x.settle_battle(result.config,b.state).success,"shield settlement retry once")
	ck(g.valid_save(g.state),"event battle active save valid")
	if x.active():ck(x.retreat().success,"leave event test")
	condition=float(x.state().utility.armor.condition)
	g.state.ownedCharacters.ember.level=10
	ck(is_equal_approx(x.equipment_status().armor.percent,condition),"character growth cannot refill condition")
	var spare_uid:=buy_equip(g,"armor_0","armor")
	ck(x.set_utility_slot("armor",armor_uid).success,"restore same worn shield instance")
	ck(is_equal_approx(x.state().utility.armor.condition,condition),"swapping equipment does not refill old shield")
	ck(g.valid_save(g.state),"equipment swap save valid")
	# Safe travel is a graph walk through visited solved nodes, not teleportation.
	ck(x.start_run().success,"travel run")
	var m:Dictionary=x.run().map
	for r in m.rooms:
		if r.type in ["entry","boss"]:continue
		r.type="cache";r.visited=true;r.cleared=true
	m.explored=17;m.bossUnlocked=true
	var paths:Dictionary=x.map_state().travelPaths
	ck(paths.size()==18,"all solved region reachable")
	for path in paths.values():
		ck(path[0]==m.currentRoomId,"travel starts at player")
		for i in range(path.size()-1):ck(x._has_edge(m.edges,path[i],path[i+1]),"path follows real edges")
	x.run().pendingChoices=[{"id":"test"}]
	ck(x.map_state().reachableRoomIds.is_empty(),"pending choice disables travel indications")
	x.run().pendingChoices=[]
	# Current HP builds scale equipment shields once, preserving the wear fraction.
	g=Game.new("");x=g.extraction;buy_equip(g,"armor_5","armor")
	ck(x.start_run().success,"HP synergy run")
	x.state().utility.armor.condition=0.37
	var hp_reward:Dictionary=x._growth_definition("common_hp_white").duplicate(true)
	hp_reward.instanceId="hp_synergy";hp_reward.pickedAtAct=1
	x.run().blessings=[hp_reward]
	var preview_shield:Dictionary=x.equipment_status().armor
	var base_total:=0
	for unit in x.run().party:base_total+=int(int(unit.stats.maxHp)*1.1)*2
	ck(int(preview_shield.max)==base_total and preview_shield.percent==0.37,"HP blessing changes capacity not condition")
	x._generate_encounter("battle");b=Battle.new(g.catalog);result=x.start_battle(b)
	ck(result.success and b.state.equipmentShieldRemaining==preview_shield.current,"preview matches actual shield")
	ck(not x.start_battle(Battle.new(g.catalog)).success,"cannot restart active engine to refresh shield")
	for unit in b.state.allies:ck(x._equipment_shield_capacities()[unit.id]==unit.maxHp*2,"same HP multiplier as battle")
	var first_max:int=preview_shield.max
	while b.state.phase not in ["victory","defeat"]:b.auto_step()
	ck(x.settle_battle(result.config,b.state).success,"HP synergy settlement")
	if x.active():
		if not x.growth_choices().is_empty():x.choose_growth(x.growth_choices()[0].choiceId)
		x.run().blessings=[hp_reward]
		ck(x.equipment_status().armor.max==first_max,"no repeated HP compounding")
		x._generate_encounter("battle");b=Battle.new(g.catalog);result=x.start_battle(b)
		var target:Dictionary=b.state.allies[0]
		b._absorb(target,7)
		var remaining_ratio:float=float(b.state.equipmentShieldRemaining)/float(b.state.config.equipmentShieldMax)
		ck(x.retreat().success,"retreat during started battle")
		ck(is_equal_approx(x.state().utility.armor.condition,remaining_ratio),"mid-combat retreat preserves actual wear")
	# Deserialize an actual 2.2 source-generated active battle, not a v7 relabel.
	var legacy=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/extraction-v6-active.json"))
	g=Game.new("");x=g.extraction
	ck(g.valid_save(legacy),"genuine v6 active fixture accepted")
	var old_gold:int=legacy.resources.gold
	var encounter:Dictionary=legacy.extraction.run.activeEncounter.duplicate(true)
	g.state=g._normalize(legacy)
	ck(g.valid_save(g.state) and g.state.version==9,"genuine v6 active migration valid")
	ck(g.state.resources.gold==old_gold and x.run().bag.size()==30 and x.run().equipped.size()==1,"v6 full bag equipment and gold retained")
	ck(x.run().activeEncounter==encounter and x.run().blessings.size()==1,"v6 battle seed budget and build retained")
	ck(x.run().containers[0].items[0].revealed and not x.run().containers[0].items[1].revealed,"partial search retained")
	for item in x.run().bag+x.run().equipped:
		ck(item.has("legacyValue") and x.item_value(item)==int(x.item_def(item.itemId).v6Value)*4,"v6 high-risk asset value exact")
	before=g.state.duplicate(true);g.state=g._normalize(g.state)
	ck(g.state==before,"real active migration idempotent")
	b=Battle.new(g.catalog);ck(x.start_battle(b).success,"real migrated battle resumes")
	print("EXTRACTION V7: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
