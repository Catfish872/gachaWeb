extends SceneTree
const Game=preload("res://scripts/game_model.gd")
const Battle=preload("res://scripts/battle_model.gd")
const Balance=preload("res://scripts/abyss_balance.gd")
class ClockGame:
	extends "res://scripts/game_model.gd"
	var clock_ms:int=1793570399999
	func _now()->int:return clock_ms
var checks:=0
var failures:=0
func ck(ok:bool,label:String):
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",label)
func at_floor(g,floor_number:int,rank:int=0)->Dictionary:
	g.reset_abyss();g.state.abyss.meta.unlockedDifficulty=3;g.state.abyss.meta.selectedDifficulty=rank
	g.prepare_abyss();g._issued_config={};g.state.abyss.rogue.activeEncounter={}
	g.state.abyss.currentFloor=floor_number;g.state.abyss.rogue.floorsCleared=floor_number-1
	g.state.abyss.savedPartyState=[]
	for unit in g.battle_party(false):g.state.abyss.savedPartyState.append({"id":unit.id,"currentHp":unit.maxHp,"maxHp":unit.maxHp,"energy":0,"cooldowns":{}})
	return g.prepare_abyss()
func won_state(g,config:Dictionary)->Dictionary:
	var engine=Battle.new(g.catalog);engine.start(config,g.battle_party(true),g.rogue_effects())
	for unit in engine.state.allies:unit.stats.atk=100000000;unit.stats.spd=10000
	var safety:=0
	while engine.state.phase not in ["victory","defeat"] and safety<5000:engine.auto_step();safety+=1
	ck(engine.state.phase=="victory","actual encounter resolved")
	return engine.state
func _init():
	var g=ClockGame.new("");g.rng.seed=30100000
	ck(g.state.version==9 and g.valid_save(g.state),"v9 defaults valid")
	ck(g.abyss_daily_status().resetAt==1793570400000,"2026-11-02 UTC8 six equals Nov1 UTC22")
	var prep:=at_floor(g,10);var result_state:=won_state(g,prep.config)
	var before:Dictionary=g.state.duplicate(true);g.save_blocked=true
	ck(not g.finish_battle(prep.config,result_state).success and g.state==before,"daily reward rollback including relic XP")
	g.save_blocked=false;var gold:int=g.state.resources.gold;var diamonds:int=g.state.resources.diamonds
	var r:Dictionary=g.finish_battle(prep.config,result_state)
	ck(r.success and r.rewards.gold==0 and g.state.resources.gold==gold,"abyss no direct gold")
	ck(r.dailyAward.amount==675 and g.state.resources.diamonds==diamonds+675,"first milestone grant")
	ck(not r.relic.is_empty() and g.get_relic(r.relic.uid)==r.relic and not r.progression.is_empty(),"actual relic and progression returned")
	ck(not g.finish_battle(prep.config,result_state).success,"settlement replay blocked")
	prep=at_floor(g,10);r=g.finish_battle(prep.config,won_state(g,prep.config))
	ck(r.dailyAward.amount==0 and not r.relic.is_empty() and r.rewards.exp>0,"repeat retains XP relic not daily diamonds")
	prep=at_floor(g,10,2);r=g.finish_battle(prep.config,won_state(g,prep.config))
	ck(r.dailyAward.amount==675 and r.dailyAward.totalPaid==1350,"higher difficulty difference only")
	prep=at_floor(g,10,0);r=g.finish_battle(prep.config,won_state(g,prep.config))
	ck(r.dailyAward.amount==0,"lower difficulty cannot claim again")
	var day:int=g.abyss_daily_status().dayKey
	g.clock_ms=(day+1)*86400000-7200000-1
	ck(g.abyss_daily_status().dayKey==day,"one millisecond before fixed UTC8 six")
	g.clock_ms+=1
	ck(g.abyss_daily_status().dayKey==day+1 and g.abyss_daily_status().paidToday==0,"exact reset boundary")
	prep=at_floor(g,10);r=g.finish_battle(prep.config,won_state(g,prep.config))
	ck(r.dailyAward.amount==675,"new day eligible")
	g.clock_ms-=86400000
	prep=at_floor(g,10);r=g.finish_battle(prep.config,won_state(g,prep.config))
	ck(r.dailyAward.amount==0 and g.abyss_daily_status().dayKey==day+1,"clock rollback cannot reset claims")
	prep=at_floor(g,20);r=g.finish_battle(prep.config,won_state(g,prep.config))
	ck(r.success and not r.ended and g.state.abyss.currentFloor==21 and g.abyss_run_active(),"twenty continues no hard ending")
	ck(g.state.abyss.meta.unlockedDifficulty>=1 and g.valid_save(g.state),"milestone unlock persists valid")
	prep=at_floor(g,50);r=g.finish_battle(prep.config,won_state(g,prep.config))
	ck(r.success and g.state.abyss.currentFloor==51 and g.valid_save(g.state),"fifty is not cap")
	prep=at_floor(g,10010)
	ck(prep.success and g.valid_save(g.state),"five digit floors valid")
	ck(Balance.scale(10020).hpMod>Balance.scale(10010).hpMod,"no old 10000 curve plateau")
	ck(g.abyss_route_preview().size()==10 and g.abyss_route_preview()[0].floor==10008,"bounded preview of endless route")
	g.reset_abyss();g.state.abyss.meta.currency=200
	ck(not g.exchange_memory(20).success,"unmaxed memory cannot convert")
	for upgrade in g.rogue_data.metaUpgrades:g.state.abyss.meta.upgrades[upgrade.id]=upgrade.maxLevel
	before=g.state.duplicate(true);g.save_blocked=true
	ck(not g.exchange_memory(100).success and g.state==before,"memory conversion save rollback")
	g.save_blocked=false;diamonds=g.state.resources.diamonds
	ck(g.exchange_memory(100).success and g.state.resources.diamonds==diamonds+100 and g.state.abyss.meta.currency==100,"memory one to one")
	ck(not g.exchange_memory(101).success,"memory overdraft blocked")
	g.prepare_abyss();ck(not g.exchange_memory(1).success,"memory only outside expedition");g.reset_abyss()
	prep=g.prepare_stage("ch1_1")
	ck(prep.success and not g.memory_exchange_status().enabled,"prepared story correctly locks memory conversion")
	before=g.state.duplicate(true);g.save_blocked=true
	ck(not g.abandon_battle(prep.config).success and not g._issued_config.is_empty() and g.state==before,"failed story cancellation retains lock and state")
	g.save_blocked=false
	ck(g.abandon_battle(prep.config).success and g._issued_config.is_empty() and g.memory_exchange_status().enabled,"proper story cancellation clears stale lock")
	var relic:Dictionary=g.generate_relic(5,"helmet");relic.level=10;g.state.relics=[relic]
	var old:Dictionary=g.state.duplicate(true);old.version=8;g.state=g._normalize(old)
	ck(g.relic_sell_value(g.state.relics[0])==1000,"old relic full appraisal preserved")
	g.state.relics[0].level=11
	ck(g.relic_sell_value(g.state.relics[0])==1012,"new upgrade adds new refund only")
	var fresh:Dictionary=g.generate_relic(5,"helmet");fresh.level=10
	ck(g.relic_sell_value(fresh)==600,"new relic sixty percent resale")
	# Full blessing inventory must resolve to an explicit supply/continue choice.
	g=ClockGame.new("");g.prepare_abyss()
	g.state.abyss.rogue.selectedRewards=[]
	for definition in g.catalog.AbyssData.rogue.rewards:
		for n in range(3):g.state.abyss.rogue.selectedRewards.append(definition.duplicate(true))
	g._set_after_floor(30)
	ck(g.state.abyss.rogue.pendingChoices.is_empty() and g.node_options().options.size()==2,"exhausted blessings have explicit alternative")
	var coins:int=g.state.abyss.rogue.temporaryCurrency
	ck(g.choose_abyss_node("echo_supply").success and g.state.abyss.rogue.temporaryCurrency==coins+50,"supply resolves exhausted pool")
	# A real v8 persisted floor20 battle keeps its token/enemies but settles under
	# the new reward rules and continues instead of silently terminating.
	var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/abyss-v8-floor20.json"))
	g=ClockGame.new("")
	ck(g.valid_save(fixture),"released v8 live abyss fixture accepted")
	var original_encounter:Dictionary=fixture.abyss.rogue.activeEncounter.duplicate(true)
	g.state=g._normalize(fixture)
	ck(g.valid_save(g.state) and JSON.parse_string(JSON.stringify(g.state.abyss.rogue.activeEncounter))==original_encounter,"old battle credential and enemies preserved")
	before=g.state.duplicate(true);g.state=g._normalize(g.state)
	ck(g.state==before,"v9 migration idempotent")
	prep=g.prepare_abyss();gold=g.state.resources.gold
	r=g.finish_battle(prep.config,won_state(g,prep.config))
	ck(r.success and not r.ended and g.state.abyss.currentFloor==21 and g.state.resources.gold==gold,"legacy gold config cannot bypass zero-gold and endless rules")
	# Raid XP upgrades permanent characters, then next encounter uses the new level
	# with the departure gear snapshot, retained injury ratio, and shield wear.
	g=ClockGame.new("");g.state.ownedCharacters.ember.exp=45;g.state.ownedCharacters.zeph.exp=45
	var x=g.extraction;x.start_run();x.run().phase="room"
	x.state().utility.armor=x._make_item("armor_5");x.state().utility.armor.condition=.4
	for unit in x.run().party:unit.currentHp=int(unit.maxHp*.5)
	var old_stats:Dictionary=x.run().party[0].stats.duplicate(true)
	x._generate_encounter("battle");var engine=Battle.new(g.catalog);var started:Dictionary=x.start_battle(engine)
	for unit in engine.state.allies:unit.stats.atk=100000000
	var safety:=0
	while engine.state.phase not in ["victory","defeat"] and safety<5000:engine.auto_step();safety+=1
	ck(engine.state.phase=="victory","actual raid victory")
	var hp_ratio:float=float(engine.state.allies[0].currentHp)/float(engine.state.allies[0].maxHp)
	var remaining_ratio:float=float(engine.state.equipmentShieldRemaining)/float(engine.state.config.equipmentShieldMax)
	before=g.state.duplicate(true);g.save_blocked=true
	ck(not x.settle_battle(started.config,engine.state).success and g.state==before,"raid XP rollback with gear durability")
	g.save_blocked=false;r=x.settle_battle(started.config,engine.state)
	ck(r.success and r.rewards.exp==45 and r.progression[0].newLevel==2,"raid real XP progression")
	ck(x.run().party[0].stats==g.computed_stats("ember") and x.run().party[0].stats.atk>old_stats.atk,"next fight level stats fully applied")
	ck(is_equal_approx(float(x.state().utility.armor.condition),remaining_ratio),"levelup never repairs equipment condition")
	var grown_stats:Dictionary=x.run().party[0].stats.duplicate(true)
	var projected:int=x.equipment_status().armor.max
	# A later outside inventory change must not leak into the departure snapshot.
	g.state.ownedCharacters.ember.awakening=20
	x.run().pendingChoices=[];x._generate_encounter("battle");engine=Battle.new(g.catalog);started=x.start_battle(engine)
	ck(started.success and engine.state.allies[0].stats.maxHp==grown_stats.maxHp,"next battle uses upgraded frozen gear stats")
	ck(absf(float(engine.state.allies[0].currentHp)/engine.state.allies[0].maxHp-hp_ratio)<.01,"levelup retains injury proportion")
	ck(engine.state.config.equipmentShieldMax==projected and absf(float(engine.state.equipmentShieldRemaining)/projected-remaining_ratio)<.001,"new shield capacity and preserved wear agree")
	ck(g.valid_save(g.state),"upgraded raid save valid")
	var container_variants:Dictionary={}
	for seed_value in range(16):
		var prior_backgrounds:Array=[]
		for act in [1,2,3]:
			g=ClockGame.new("");g.rng.seed=30510000+seed_value;x=g.extraction;x.start_run();x.run().act=act;x._generate_map()
			var map:Dictionary=x.run().map
			for district in map.districts:
				if act>1:ck(district.background.ends_with("_act%d.webp"%act),"district showcases current act")
			var current_backgrounds:Array=[]
			for index in [0,1,18]:
				var background:String=map.rooms[index].background
				if act>1:ck(background.ends_with("_act%d.webp"%act),"entry first cache and boss guarantee new scene")
				ck(not background in prior_backgrounds,"key scene differs from previous act")
				current_backgrounds.append(background)
			prior_backgrounds.append_array(current_backgrounds)
			x._container("independent",3,0)
			var container:Dictionary=x.run().containers.back()
			container_variants[str(container.sceneX)+":"+str(container.sceneY)]=true
	ck(container_variants.size()==16,"container placement remains independently random")
	print("ECONOMY V9 ",checks," checks ",failures," failures");quit(0 if failures==0 else 1)
