extends SceneTree
const Game=preload("res://scripts/game_model.gd")
const Battle=preload("res://scripts/battle_model.gd")
var checks:=0
var failures:=0
func ck(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",label)
func fresh():
	var g=Game.new("");g.rng.seed=241000
	return g
func at_floor(g,n:int,rank:int)->Dictionary:
	g.state.abyss.meta.unlockedDifficulty=3;g.state.abyss.meta.selectedDifficulty=rank
	g.prepare_abyss();g._issued_config={};g.state.abyss.rogue.activeEncounter={}
	g.state.abyss.currentFloor=n;g.state.abyss.rogue.floorsCleared=n-1
	g.state.abyss.savedPartyState=[]
	for u in g.battle_party(false):g.state.abyss.savedPartyState.append({"id":u.id,"currentHp":u.maxHp,"maxHp":u.maxHp,"energy":0,"cooldowns":{}})
	return g.prepare_abyss()
func fight(g,config:Dictionary,raid:bool=true,win:bool=true,wear:bool=false)->Dictionary:
	var e=Battle.new(g.catalog)
	if raid:ck(g.extraction.start_battle(e).success,"actual service battle starts")
	else:e.start(config,g.battle_party(true),g.rogue_effects())
	if wear:
		var opening:=0
		while e.state.phase not in ["victory","defeat"] and int(e.state.get("equipmentShieldRemaining",0))==int(e.state.config.get("equipmentShieldMax",0)*0.4) and opening<100:
			e.auto_step();opening+=1
		# One full initiative cycle guarantees normal enemy attacks before the test finish.
		for step in 20:
			if e.state.phase in ["victory","defeat"]:break
			e.auto_step()
	for u in e.state.allies if win else e.state.enemies:u.stats.atk=100000000;u.stats.spd=10000
	var steps:=0
	while e.state.phase not in ["victory","defeat"] and steps<5000:e.auto_step();steps+=1
	ck(e.state.phase==("victory" if win else "defeat"),"actual battle reaches requested terminal state")
	return e.state
func raid_room(g,kind:String,guard:float=0.0)->String:
	var x=g.extraction;ck(x.start_run().success,"raid fixture departs")
	var target:Dictionary=x.route_options()[0]
	for room in x.run().map.rooms:
		if room.id==target.id:room.type=kind;room.name=kind
	x.data.serviceGuards[kind]=guard
	return target.id
func bag_item(x,id:String,value:int=-1)->Dictionary:
	var item:Dictionary=x._make_item(id);item.revealed=true
	if value>=0:item.legacyValue=value
	ck(x._place(x.run().bag,item,x.dimensions("bag")),"item fits source bag")
	return item
func choose_growth(x)->void:
	if not x.run().pendingChoices.is_empty():ck(x.choose_growth(x.run().pendingChoices[0].choiceId).success,"resolve growth")
func test_abyss()->void:
	for rank in range(3):
		var g=fresh();var prepared:=at_floor(g,50,rank)
		ck(g.abyss_floor_cap()==50 and not prepared.config.endless and prepared.config.runLength==50,"bounded cap contract")
		ck(g.abyss_route_preview()[0].floor==41 and g.abyss_route_preview().back().floor==50,"bounded last route page")
		var battle:=fight(g,prepared.config,false);var before:Dictionary=g.state.duplicate(true);g.save_blocked=true
		ck(not g.finish_battle(prepared.config,battle).success and g.state==before,"final victory atomic rollback")
		g.save_blocked=false;var diamonds:int=g.state.resources.diamonds
		var result:Dictionary=g.finish_battle(prepared.config,battle)
		ck(result.success and result.ended and result.lastRun.outcome=="victory" and result.lastRun.floorsCleared==50,"rank completes at fifty")
		ck(not g.abyss_run_active() and g.state.abyss.currentFloor==1 and g.state.abyss.meta.runsCompleted==1,"completed run restarts cleanly")
		ck(g.state.resources.diamonds-diamonds==[900,1350,1800][rank] and not result.relic.is_empty(),"final keeps exact daily diamonds and relic")
		ck(not g.finish_battle(prepared.config,battle).success and g.valid_save(g.state),"final replay rejected and save valid")
		ck(g.prepare_abyss().config.floor==1,"next departure starts floor one")
	var g=fresh();var prepared:=at_floor(g,60,3)
	ck(g.abyss_is_endless() and g.abyss_difficulty_options()[3].name=="无尽","fourth rank named endless")
	var result:Dictionary=g.finish_battle(prepared.config,fight(g,prepared.config,false))
	ck(result.success and not result.ended and g.state.abyss.currentFloor==61 and g.abyss_run_active(),"rank three continues beyond fifty")
	for rank in range(3):
		g=fresh();at_floor(g,50,rank)
		g.state.abyss.currentFloor=61;g.state.abyss.rogue.floorsCleared=60
		g.state.abyss.rogue.activeEncounter.floor=61;g.state.abyss.rogue.activeEncounter.abyssLayer=61;g.state.abyss.maxFloor=80
		g.state.abyss.rogue.metaEarned=300;g.state.abyss.meta.currency=300;g.state.abyss.meta.totalEarned=500;g.state.abyss.meta.runsCompleted=7
		var before:Dictionary=g.state.duplicate(true)
		ck(g.valid_save(before),"legacy high floor accepted before normalization")
		g.state=g._normalize(JSON.parse_string(JSON.stringify(before)))
		ck(g.valid_save(g.state) and g.state.abyss.lastRun.outcome=="legacy_completion" and not g.abyss_run_active(),"legacy above cap settled safely")
		for key in ["resources","relics","ownedCharacters","stats"]:ck(JSON.parse_string(JSON.stringify(g.state[key]))==JSON.parse_string(JSON.stringify(before[key])),"legacy assets unchanged "+key)
		ck(JSON.parse_string(JSON.stringify(g.state.abyss.meta))==JSON.parse_string(JSON.stringify(before.abyss.meta)) and JSON.parse_string(JSON.stringify(g.state.abyss.daily))==JSON.parse_string(JSON.stringify(before.abyss.daily)) and g.state.abyss.maxFloor==80,"legacy counters daily and historical best preserved")
		before=g.state.duplicate(true);g.state=g._normalize(g.state);ck(g.state==before,"cap migration idempotent")
	g=fresh();prepared=at_floor(g,60,3);var before:Dictionary=g.state.duplicate(true)
	g.state=g._normalize(g.state);ck(g.state==before,"endless legacy run and battle untouched")
func test_guards()->void:
	for kind in ["rest","hospital","workshop","relay","shrine"]:
		var g=fresh();var id:=raid_room(g,kind,1.0);var x=g.extraction
		x.state().utility.armor=x._make_item("armor_5");x.state().utility.armor.condition=0.4
		var before:Dictionary=g.state.duplicate(true);g.save_blocked=true
		ck(not x.enter_room(id).success and g.state==before,"guard roll transaction rollback")
		g.save_blocked=false;var entered:Dictionary=x.enter_room(id)
		ck(entered.success and x.run().phase=="battle" and x.run().room.guardPending,"service guard intercepts first visit "+kind)
		ck(x.room_actions().is_empty() and x.room_scene().containers.is_empty() and not x.preview_deposit().success,"guard closes service and loot")
		ck(not x.enter_room(x.run().map.rooms[0].id).success and not x.advance_room().success and not x.choose_room_action("recover").success,"guard cannot be bypassed by travel or interaction")
		ck(g.valid_save(g.state),"pending guard save validates")
		var bypass:Dictionary=g.state.duplicate(true);bypass.extraction.run.phase="room";bypass.extraction.run.activeEncounter={}
		ck(not g.valid_save(bypass),"forged room phase cannot skip saved guard")
		bypass=g.state.duplicate(true);bypass.extraction.run.activeEncounter.guardRoomId="wrong-room"
		ck(not g.valid_save(bypass),"guard credential stays bound to exact service")
		var persisted:Dictionary=JSON.parse_string(JSON.stringify(g.state));var resume=fresh()
		resume.state=resume._normalize(persisted);x=resume.extraction
		ck(resume.valid_save(resume.state) and x.run().room.guardPending and x.prepare_battle().config.token==entered.config.token,"guard resumes exact saved encounter")
		var battle:=fight(resume,entered.config,true,true,true);before=resume.state.duplicate(true);resume.save_blocked=true
		ck(not x.settle_battle(entered.config,battle).success and resume.state==before,"guard victory rollback retains encounter")
		resume.save_blocked=false;var settled:Dictionary=x.settle_battle(entered.config,battle)
		var condition:float=float(battle.equipmentShieldRemaining)/float(battle.config.equipmentShieldMax)
		ck(condition<0.4 and is_equal_approx(float(x.state().utility.armor.condition),condition),"guard uses real shield loss settlement")
		ck(settled.rewards.exp==45 and x.run().expEarned==45 and x.run().growthBattles==1,"guard grants ordinary battle progression exactly once")
		ck(settled.success and x.run().phase=="room" and not x.run().room.guardPending,"guard victory restores original room")
		ck(x.run().room.type==kind and (kind=="relay" or x.run().roomActions.size()==3),"original service restored "+kind)
		ck(x.run().containers.is_empty() if kind in ["rest","relay"] else x.run().containers.size() in [1,2],"only original service loot spawned")
		ck(not x.settle_battle(entered.config,battle).success,"guard settlement replay rejected")
		choose_growth(x)
		var actions:Array=x.run().roomActions.duplicate(true);var loot:Array=x.run().containers.duplicate(true);var xp:int=x.run().expEarned
		ck(x.enter_room(x.run().map.rooms[0].id).success and x.enter_room(id).success,"cleared service supports real reentry")
		ck(x.run().roomActions==actions and x.run().containers==loot and x.run().expEarned==xp and x.run().phase=="room","reentry preserves service without duplicate loot XP or guard")
		if kind=="relay":
			var parcel_item:=bag_item(x,"wire");var quote:Dictionary=x.preview_deposit([parcel_item.uid])
			ck(quote.success and x.deposit_items(quote.planHash,[parcel_item.uid]).success,"cleared relay service mails parcel")
		else:
			for action in x.run().roomActions:ck(not action.used,"guard preserves unconsumed original service choices")
			var action_id:String="meditate" if kind in ["rest","hospital"] else ("study" if kind=="workshop" else "leave")
			ck(x.choose_room_action(action_id).success,"cleared guard original service works")
			choose_growth(x)
		ck(x.enter_room(x.run().map.rooms[0].id).success and x.enter_room(id).success,"used service reentry")
		if kind=="relay":ck(not x.preview_deposit().success,"used guarded relay parcel remains spent")
		else:
			for action in x.room_actions():ck(action.used and not action.enabled,"used guarded service cannot repeat reward")
		ck(resume.valid_save(resume.state),"restored service remains serializable")
	# Already visited pre-update services retain actions and containers without new guards.
	for kind in ["rest","hospital","workshop","relay","shrine"]:
		var legacy=fresh();var legacy_id:=raid_room(legacy,kind,0.0);var lx=legacy.extraction
		lx.enter_room(legacy_id)
		for room in lx.run().map.rooms:room.erase("guardRolled");room.erase("guardPending")
		lx.run().room.erase("guardRolled");lx.run().room.erase("guardPending")
		var actions:Array=lx.run().roomActions.duplicate(true);var loot:Array=lx.run().containers.duplicate(true)
		legacy.state=legacy._normalize(legacy.state);lx.data.serviceGuards[kind]=1.0
		ck(lx.enter_room(lx.run().map.rooms[0].id).success and lx.enter_room(legacy_id).success,"legacy visited service reentry")
		ck(lx.run().phase=="room" and lx.run().roomActions==actions and lx.run().containers==loot,"legacy visited service remains safe and unconsumed")
	# Same persisted random state yields exactly the same guard outcome and encounter.
	var g=fresh();var id:=raid_room(g,"relay",0.15);var saved:Dictionary=g.state.duplicate(true)
	var first:Dictionary=g.extraction.enter_room(id);var snapshot:Dictionary=g.extraction.run().duplicate(true)
	g.state=saved;var second:Dictionary=g.extraction.enter_room(id)
	ck(first==second and g.extraction.run()==snapshot,"seeded guard decision and loot deterministic")
	for withdraw in [false,true]:
		g=fresh();id=raid_room(g,"workshop",1.0);g.extraction.enter_room(id)
		g.extraction.state().mailbox=[{"uid":"old-mail","itemId":"wire","x":0,"y":0,"rotated":false,"revealed":true}]
		var result:Dictionary
		if withdraw:result=g.extraction.retreat()
		else:
			var config:Dictionary=g.extraction.run().activeEncounter.duplicate(true)
			result=g.extraction.settle_battle(config,fight(g,config,true,false))
		ck(result.success and not g.extraction.active() and g.extraction.state().lastRun.outcome==("retreat" if withdraw else "defeat"),"guard defeat and withdraw end run")
		ck(g.extraction.state().mailbox.size()==1 and g.valid_save(g.state),"secured mail survives guard loss")
func test_parcels()->void:
	var g=fresh();var id:=raid_room(g,"relay");var x=g.extraction;ck(x.enter_room(id).success,"enter safe relay")
	var large:=bag_item(x,"barrier_module",100)
	for n in 22:bag_item(x,"dried_fruit",40)
	var plan:Dictionary=x.preview_deposit()
	ck(plan.success and plan.width==5 and plan.height==5 and plan.items.size()==22 and plan.value==940,"relay five by five prioritizes high value with real packing")
	for item in plan.items:ck(x._fits(plan.items,item,Vector2i(5,5)),"preview items spatially non-overlapping")
	var before:Dictionary=g.state.duplicate(true)
	ck(not x.preview_deposit(x.run().bag.map(func(item):return item.uid)).success and g.state==before,"manual overcapacity preserves bag")
	ck(not x.preview_deposit([large.uid,large.uid]).success and not x.preview_deposit(["missing"]).success,"duplicate and stale UID rejected")
	ck(not x.deposit_items("stale").success and g.state==before,"stale parcel hash atomic")
	g.save_blocked=true;ck(not x.deposit_items(plan.planHash).success and g.state==before,"parcel failed persistence restores all assets")
	g.save_blocked=false;var gold:int=g.state.resources.gold
	ck(x.deposit_items(plan.planHash).success and g.state.resources.gold==gold-50 and x.run().bag.size()==1,"parcel transfers chosen instances with existing fee")
	ck(not x.deposit_items(plan.planHash).success and x.state().stash.size()==22,"parcel repeated calls transfer once")
	ck(x.retreat().success and x.state().stash.size()==22 and x.state().lastRun.securedItems==22,"parcel retained after abandonment")
	g=fresh();id=raid_room(g,"relay");x=g.extraction;x.enter_room(id)
	var a:=bag_item(x,"dragon_egg");var b:=bag_item(x,"dragon_egg")
	ck(not x.preview_deposit([a.uid,b.uid]).success,"two 3x3 objects area eighteen cannot spatially fit five by five")
	x.run().bag=[]
	a=bag_item(x,"vest");b=bag_item(x,"blade")
	plan=x.preview_deposit([a.uid,b.uid]);ck(plan.success and plan.items.size()==2,"rotation packs 2x3 plus 3x1 exactly")
	for item in plan.items:ck(x._fits(plan.items,item,Vector2i(5,5)),"rotated parcel valid")
	g.state.resources.gold=49;before=g.state.duplicate(true)
	ck(not x.preview_deposit([a.uid,b.uid]).enabled and not x.deposit_items(plan.planHash,[a.uid,b.uid]).success and g.state==before,"insufficient fee atomic")
	g.state.resources.gold=10000
	# Warehouse overflow retains identities in mailbox and survives load/re-entry.
	x.run().bag=[];a=bag_item(x,"diamond_ring",700)
	for n in 120:
		var item:Dictionary=x._make_item("wire");item.revealed=true;ck(x._place(x.state().stash,item,x.dimensions("stash")),"fill warehouse")
	plan=x.preview_deposit([a.uid]);ck(x.deposit_items(plan.planHash,[a.uid]).success,"full warehouse routes parcel to mailbox")
	ck(x.state().mailbox.size()==1 and x.state().mailbox[0].uid==a.uid and x.item_value(x.state().mailbox[0])==700,"mail preserves UID appraisal")
	before=g.state.duplicate(true);g.state=g._normalize(JSON.parse_string(JSON.stringify(before)))
	ck(g.valid_save(g.state) and x.state().mailbox[0].uid==a.uid and x.run().room.depositUsed,"deposited parcel and once flag resume")
	ck(not x.deposit_items(plan.planHash,[a.uid]).success,"resumed parcel replay rejected")
	x.retreat();x.start_run();x.run().phase="room";x.run().room.type="relay";x.run().room.depositUsed=false
	x.state().mailbox=[]
	for n in 10000:x.state().mailbox.append({"uid":"full_mail_%d"%n,"itemId":"wire","x":0,"y":0,"rotated":false,"revealed":true})
	a=bag_item(x,"wire");plan=x.preview_deposit([a.uid]);before=g.state.duplicate(true)
	ck(not x.deposit_items(plan.planHash,[a.uid]).success and g.state==before,"full mailbox and warehouse reject atomically")
	# Cashout entry points preserve past wallet proceeds and refuse new run-time cashouts.
	var legacy_gold:int=g.state.resources.gold+123;g.state.resources.gold=legacy_gold;x.run().salvageGold=123
	g.state=g._normalize(JSON.parse_string(JSON.stringify(g.state)))
	before=g.state.duplicate(true)
	ck(g.state.resources.gold==legacy_gold and x.run().salvageGold==123,"past cashout balances survive new rules migration")
	ck(not x.salvage_items([a.uid],"old-token").success and not x.sell_item(a.uid).success and not x.sell_items([a.uid]).success and not x.sell_keys("key_ruins").success and g.state==before,"all in-run sale APIs leave wallet and possessions intact")
	# Each actual boss source offers one new parcel, final source allows direct extraction.
	g=fresh();x=g.extraction;x.start_run()
	for act in [1,2,3]:
		x.run().act=act;x._generate_map();var boss:Dictionary=x.run().map.rooms.back()
		x.run().map.currentRoomId=boss.id;boss.visited=true;x.run().room=boss.duplicate(true);x.run().node=4;x.run().bossesDefeated=act-1
		x._generate_encounter("boss");var config:Dictionary=x.run().activeEncounter.duplicate(true)
		ck(x.settle_battle(config,fight(g,config)).success,"actual boss settlement")
		choose_growth(x);a=bag_item(x,"diamond_ring")
		plan=x.preview_deposit([a.uid]);ck(plan.success and plan.width==6 and plan.height==6 and x.parcel_dimensions()==Vector2i(6,6) and x.deposit_items(plan.planHash,[a.uid]).success,"boss has fresh parcel source act "+str(act))
		ck(not x.deposit_items(plan.planHash,[a.uid]).success,"boss parcel used once")
		ck(g.valid_save(g.state),"boss parcel save valid")
		if act<3:ck(x.continue_act().success,"parcel does not block next act")
	ck(x.extract().success and x.state().stash.size()==3,"final boss retains all prior parcels on extraction")
	g=fresh();x=g.extraction;x.start_run();x.run().phase="boss_exit";x.run().act=3;x.run().node=4;x.run().bossesDefeated=3
	ck(x.extract().success,"final direct extraction requires no parcel")
func _init()->void:
	test_abyss();test_guards();test_parcels()
	print("EXPEDITION RULES V241 ",checks," checks ",failures," failures")
	quit(0 if failures==0 else 1)
