extends SceneTree
const Game=preload("res://scripts/game_model.gd")
const Battle=preload("res://scripts/battle_model.gd")
var checks:=0
var failures:=0
func ck(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",label)
func model():
	var g=Game.new("");g.rng.seed=2411156
	for id in ["kaldi","ayla","gus"]:
		g.state.ownedCharacters[id]=g.default_character();g.state.ownedCharacters[id].level=10
	g.set_team(["kaldi","ayla","gus"]);g.extraction.state().unlockedDifficulty=5
	return g
func natural_fight(g)->Dictionary:
	var b=Battle.new(g.catalog);var start:Dictionary=g.extraction.start_battle(b)
	ck(start.success,"natural fight starts from actual config and unchanged owned party")
	var steps:=0
	while b.state.phase not in ["victory","defeat"] and steps<5000:b.auto_step();steps+=1
	ck(b.state.phase in ["victory","defeat"],"natural battle terminates")
	ck(g.extraction.settle_battle(start.config,b.state).success,"natural battle real settlement")
	return b.state
func test_fixed_depth()->void:
	var g=model();var x=g.extraction;x.start_run()
	for rank in 6:
		for act in [1,2,3]:
			for tier in [1,2,3,4]:
				for kind in ["battle","elite","boss"]:
					x.run().difficulty=rank;x.run().act=act;x.run().node=tier
					var snapshot:Dictionary=g.state.duplicate(true)
					x.data.balance.withinActTierGrowth=0.0;x.data.balance.finalBossStatMultiplier=1.0
					x._generate_encounter(kind);var old:Dictionary=x.run().activeEncounter.duplicate(true)
					g.state=snapshot.duplicate(true)
					x.data.balance.withinActTierGrowth=.02;x.data.balance.finalBossStatMultiplier=1.15
					x._generate_encounter(kind);var current:Dictionary=x.run().activeEncounter.duplicate(true)
					var expected:float=1.0 if kind=="boss" else 1.0+.02*(tier-1)
					for stat in ["hpMod","atkMod","defMod","spdMod"]:
						ck(is_equal_approx(current.scaleMult[stat],old.scaleMult[stat]*expected),"exact same-seed four-stat increase; boss never compounds tier bonus")
					ck(current.enemies==old.enemies and current.seed==old.seed and current.id==old.id and current.token==old.token,"numeric update consumes zero additional RNG or IDs")
					ck(current.depthStatMultiplier==(1.0 if kind=="boss" else 1.0+.02*(tier-1)),"depth marker uses only fixed tier")
					ck(current.finalBossStatMultiplier==(1.15 if kind=="boss" and act==3 else 1.0),"only last boss carries raised-speed marker")
					var old_b=Battle.new(g.catalog);old_b.start(old,x.battle_party(),[])
					var new_b=Battle.new(g.catalog);new_b.start(current,x.battle_party(),[])
					for index in new_b.state.enemies.size():
						var enemy:Dictionary=new_b.state.enemies[index];var base:Dictionary=g.catalog.EnemyData[enemy.dataId].baseStats
						var unit_factor:=1.15 if kind=="boss" and act==3 and enemy.isBoss else 1.0
						ck(enemy.maxHp==maxi(1,int(base.hp*current.scaleMult.hpMod*unit_factor)),"actual HP exact once, integer rounding")
						ck(enemy.stats.atk==maxi(1,int(base.atk*current.scaleMult.atkMod*unit_factor)) and enemy.stats.def==maxi(0,int(base.def*current.scaleMult.defMod*unit_factor)),"actual ATK DEF exact once")
						var cap:=138.0 if unit_factor==1.15 else 120.0
						ck(is_equal_approx(enemy.stats.spd,minf(cap,float(base.spd)*float(current.scaleMult.spdMod)*unit_factor)),"actual SPD uses scoped cap")
						ck(enemy.stats.cri==old_b.state.enemies[index].stats.cri and enemy.stats.criDmg==old_b.state.enemies[index].stats.criDmg,"crit properties unchanged")
						if kind=="boss" and act==3:
							ck(is_equal_approx(enemy.stats.spd,old_b.state.enemies[index].stats.spd*unit_factor),"actual old capped speed receives15 percent only on boss")
							if not enemy.isBoss:ck(enemy.stats==old_b.state.enemies[index].stats,"high-risk final boss escorts retain every old stat")
					if rank==0 and ((tier==4 and kind=="boss") or (tier in [1,4] and kind=="battle")):print(JSON.stringify({"act":act,"tier":tier,"kind":kind,"sameSeed":current.seed,"enemy":current.enemies[0],"before":old_b.state.enemies[0].stats,"after":new_b.state.enemies[0].stats}))
					# Rebuilding the same fixed map tier after arbitrary visits does not pursue the player.
					g.state=snapshot.duplicate(true);x.run().roomsCleared+=100;x.run().growthBattles+=50
					x._generate_encounter(kind)
					ck(x.run().activeEncounter==current,"exploration and battle counts do not inflate encounter stats or change RNG")
func test_guard_reentry()->void:
	var g=model();var x=g.extraction;x.start_run()
	var entry_id:String=x.run().map.currentRoomId;var target:Dictionary=x.route_options()[0]
	for room in x.run().map.rooms:
		if room.id==target.id:room.type="workshop";room.tier=4
	x.data.serviceGuards.workshop=1.0
	ck(x.enter_room(target.id).success,"enter fixed tier4 service guard")
	ck(x.run().activeEncounter.get("isServiceGuard",false) and is_equal_approx(x.run().activeEncounter.depthStatMultiplier,1.06),"service guard receives ordinary6 percent fixed-depth bonus")
	var before:Dictionary=g.state.duplicate(true);var config:Dictionary=x.run().activeEncounter.duplicate(true)
	ck(not x.enter_room(entry_id).success and g.state==before,"battle reentry cannot reroll or escape stronger guard")
	g.state=g._normalize(JSON.parse_string(JSON.stringify(g.state)))
	ck(x.run().activeEncounter==JSON.parse_string(JSON.stringify(config)),"save normalize preserves issued guard rather than recalculating growth")
	var result:=natural_fight(g);ck(result.phase=="victory","legal level10 no-gear team defeats rank0 service guard")
	if not x.active():return
	if not x.growth_choices().is_empty():x.choose_growth(x.growth_choices()[0].choiceId)
	var actions:Array=x.run().roomActions.duplicate(true);var loot:Array=x.run().containers.duplicate(true);var xp:int=g.state.stats.totalBattles
	ck(x.enter_room(entry_id).success and x.enter_room(target.id).success,"cleared service can be revisited")
	ck(x.run().phase=="room" and x.run().roomActions==actions and x.run().containers==loot and g.state.stats.totalBattles==xp,"reentry restores original service without new monster loot or XP")
func test_real_final_boss()->void:
	var g=model();var x=g.extraction;x.start_run()
	x.run().act=3;x.run().node=4;x.run().bossesDefeated=2;x._generate_map()
	var room:Dictionary=x.run().map.rooms.back();room.visited=true;x.run().map.currentRoomId=room.id;x.run().room=room.duplicate(true)
	x._generate_encounter("boss");var result:=natural_fight(g)
	ck(result.config.finalBossStatMultiplier==1.15 and result.config.depthStatMultiplier==1.0,"real final-boss config only marks requested15 percent uplift")
	ck(result.phase=="victory","legal level10 no-equipment no-constellation team completes isolated rank0 final boss")
	if not x.active():return
	if not x.growth_choices().is_empty():x.choose_growth(x.growth_choices()[0].choiceId)
	ck(x.can_deposit() and x.parcel_dimensions()==Vector2i(6,6),"genuine final boss exposes36-cell parcel")
	ck(x.extract().success,"genuine final boss can directly extract without forced postage")
func test_keys()->void:
	var g=model();var x=g.extraction;g.state.resources.gold=10000
	for id in ["key_ruins","key_forest","key_sanctum"]:
		ck(x.item_def(id).buyPrice==500 and x.keyring().filter(func(row):return row.itemId==id)[0].buyPrice==500,"all key catalog and supply quotes cost500")
		var before:Dictionary=g.state.duplicate(true);g.save_blocked=true
		ck(not x.buy_supply(id).success and g.state==before,"camp key failed persistence atomic")
		g.save_blocked=false;var gold:int=g.state.resources.gold
		ck(x.buy_supply(id).success and g.state.resources.gold==gold-500,"camp supply key charges500")
	var uid:String=x.state().keyring[0].uid;x.state().keyring[0].legacyValue=123
	g.state=g._normalize(JSON.parse_string(JSON.stringify(g.state)))
	ck(x.state().keyring[0].uid==uid and x.item_value(x.state().keyring[0])==123,"old key UID and appraisal retained")
	var gold:int=g.state.resources.gold
	ck(x.sell_keys("key_ruins").success and g.state.resources.gold==gold+123,"sale retains actual legacy appraisal rather than new purchase price")
	x.start_run()
	for kind in ["workshop","relay","boss"]:
		x.run().room.type=kind;x.run().phase="boss_exit" if kind=="boss" else "room"
		gold=g.state.resources.gold
		ck(x.buy_keys("key_ruins",2).success and g.state.resources.gold==gold-1000,"all in-run key vendors charge500 each")
		var before:Dictionary=g.state.duplicate(true);g.save_blocked=true
		ck(not x.buy_keys("key_forest",2).success and g.state==before,"bulk field key transaction rollback")
		g.save_blocked=false
	g.state.resources.gold=499;var before:Dictionary=g.state.duplicate(true)
	ck(not x.buy_keys("key_sanctum").success and g.state==before,"499 gold cannot buy one key")
func _init()->void:
	test_fixed_depth();test_guard_reentry();test_real_final_boss();test_keys()
	print("EXTRACTION DEPTH V241 ",checks," checks ",failures," failures")
	quit(0 if failures==0 else 1)
