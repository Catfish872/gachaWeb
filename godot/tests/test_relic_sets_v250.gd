extends SceneTree
const Game = preload("res://scripts/game_model.gd")
const Sets = preload("res://scripts/relic_sets.gd")
const Battle = preload("res://scripts/battle_model.gd")
var checks := 0
var failures := 0
func ck(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",label)
func blank(g, set_id: String, slot: String, uid: String) -> Dictionary:
	var relic: Dictionary = g.generate_relic(5,slot,set_id)
	relic.uid=uid
	relic.mainStat={"stat":"atk_flat","name":"攻击","base":0.0,"perLevel":0.0}
	relic.subStats=[]
	return relic
func loadout(g, set_id: String, count: int=5) -> Array:
	var result: Array=[]
	for index in range(count):result.append(blank(g,set_id,str(g.catalog.RelicSlots[index].id),"test_"+set_id+str(index)))
	return result
func equip(g, who: String, items: Array) -> void:
	for relic in items:
		ck(g.add_relic(relic).success,"add "+str(relic.uid))
		ck(g.equip_relic(str(relic.uid),who).success,"equip "+str(relic.uid))
func won(g,config:Dictionary)->Dictionary:
	var battle=Battle.new(g.catalog)
	battle.start(config,g.battle_party(true),g.rogue_effects())
	for unit in battle.state.allies:
		unit.stats.atk=100000000
		unit.stats.spd=10000
	var guard:=0
	while battle.state.phase not in ["victory","defeat"] and guard<5000:
		battle.auto_step();guard+=1
	ck(battle.state.phase=="victory","real encounter victory")
	return battle.state
func floor_ready(g,floor_number:int,rank:int)->Dictionary:
	g.state.abyss.meta.unlockedDifficulty=3
	g.state.abyss.meta.selectedDifficulty=rank
	g._issued_config={}
	g.state.abyss.rogue=g.default_rogue()
	g.state.abyss.currentFloor=1
	g.state.abyss.savedPartyState=null
	g.prepare_abyss()
	g._issued_config={}
	g.state.abyss.rogue.activeEncounter={}
	g.state.abyss.currentFloor=floor_number
	g.state.abyss.rogue.floorsCleared=floor_number-1
	g.state.abyss.savedPartyState=[]
	for unit in g.battle_party(false):g.state.abyss.savedPartyState.append({"id":unit.id,"maxHp":unit.maxHp,"currentHp":unit.maxHp,"energy":0,"cooldowns":{}})
	return g.prepare_abyss()
func _init() -> void:
	set_thresholds()
	migration()
	frozen_growth()
	targeted_rewards()
	actual_floor_rewards()
	prepared_party_freeze()
	drop_statistics()
	print("RELIC SETS V250: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
func set_thresholds() -> void:
	var g=Game.new("")
	ck(g.catalog.RelicSets.size()==6,"six stable set definitions")
	var base:Dictionary=g.computed_stats("ember")
	var attrs:Dictionary={}
	for id in g.catalog.RelicSets:
		var items:=loadout(g,id)
		for count in range(6):
			var selected:Array=items.slice(0,count)
			var before:Dictionary=g.state.duplicate(true)
			var rng_before:int=g.rng.state
			var value:Dictionary=g.relic_loadout_snapshot("ember",selected)
			ck(value.activeBonuses.size()==(2 if count>=4 else (1 if count>=2 else 0)),"thresholds exactly once "+id+str(count))
			ck(g.state==before and g.rng.state==rng_before,"pure evaluation "+id+str(count))
			if count>=4:attrs[id]=value
		var duplicated:Array=items.duplicate(true);duplicated.append(items[0]);duplicated.append(blank(g,id,"helmet","other_uid"))
		ck(Sets.evaluate(g.catalog,duplicated).counts[id]==5,"duplicate UID and slot excluded "+id)
	ck(attrs.flame_oath.stats.atk==int(floor(base.atk*1.12)),"flame two additive attack percentage")
	ck(is_equal_approx(attrs.thunder_hunt.stats.cri,base.cri+.08) and is_equal_approx(attrs.thunder_hunt.stats.criDmg,base.criDmg+.25),"thunder critical percentage points")
	ck(is_equal_approx(attrs.wind_voyager.stats.spd,base.spd*1.12),"wind speed percentage")
	ck(attrs.stone_bastion.stats.def==int(floor(base.def*1.2)),"stone defense percentage")
	ck(attrs.star_watch.stats.maxHp==int(floor(base.maxHp*1.15)),"star maximum HP percentage")
	ck(attrs.aurora_prayer.ownerEffects.size()==3,"aurora both additive healing thresholds and one energy effect")
	var mixed:Array=loadout(g,"flame_oath",2)
	mixed.append(blank(g,"stone_bastion","belt","mixed1"));mixed.append(blank(g,"stone_bastion","boots","mixed2"))
	ck(Sets.evaluate(g.catalog,mixed).activeBonuses.size()==2,"two plus two mixed sets")
	var old:Array=loadout(g,"",5)
	ck(g.computed_stats_for_relic_loadout("ember",old)==base,"loose pieces preserve original formula")
	equip(g,"ember",loadout(g,"flame_oath",4))
	var party:Array=g.battle_party()
	ck(party[0].ownerEffects.size()==1 and party[1].ownerEffects.is_empty(),"owner effects only on wearer")
	ck(g.computed_stats("ember")==g.computed_stats_for_relic_loadout("ember",g.equipped_relics("ember")),"live and proposed stat paths match")
	g.state.ownedCharacters.ember.level=10
	var old_crit:=float(g.catalog.CharacterData.ember.baseStats.criDmg)*pow(1.1,9)
	ck(is_equal_approx(g.computed_stats("ember").criDmg,old_crit),"original level critical damage growth preserved")
func migration() -> void:
	var g=Game.new("")
	for rarity in [3,4,5]:
		for slot in g.catalog.RelicSlots:
			var relic:Dictionary=g.generate_relic(rarity,slot.id,"")
			relic.level=17
			relic.legacySellValue=900+rarity
			relic.legacySellLevel=17
			g.state.relics.append(relic)
	g.equip_relic(g.state.relics[0].uid,"ember")
	var before:Dictionary=g.state.duplicate(true)
	var migrated:Dictionary=g._normalize(g.state)
	ck(migrated.relics==before.relics,"all old UID attrs owners levels and legacy appraisal retained")
	ck(g.valid_save(migrated),"old loose pieces remain valid")
	for relic in migrated.relics:ck(not relic.has("setId") and g.relic_sell_value(relic)==900+int(relic.rarity),"no random migration and preserved legacy value")
	var raw:Dictionary=g.state.duplicate(true);raw.version=8
	for relic in raw.relics:relic.erase("legacySellValue");relic.erase("legacySellLevel")
	var older:Dictionary=g._normalize(raw)
	for relic in older.relics:ck(g.relic_sell_value(relic)==int({3:50,4:200,5:800}[int(relic.rarity)])+340,"pre economy migration appraisal preserved")
	var unknown:Dictionary=before.duplicate(true);unknown.relics[0].setId="unknown"
	ck(not g.valid_save(unknown),"unknown set rejected")
	for rarity in [3,4,5]:
		var item:Dictionary=g.generate_relic(rarity,"helmet","flame_oath")
		ck(g.relic_sell_value(item)==int({3:30,4:120,5:480}[rarity]),"new relic sale unchanged")
func frozen_growth() -> void:
	var g=Game.new("")
	equip(g,"ember",loadout(g,"thunder_hunt",4))
	var frozen:Dictionary=g.growth_snapshot("ember")
	ck(g.valid_relic_growth_snapshot(frozen),"growth set snapshot validates")
	ck(g.extraction.start_run().success,"extraction departs with frozen set")
	var departure:Dictionary=g.extraction.run().party[0].duplicate(true)
	ck(departure.permanentGrowth==frozen and departure.ownerEffects==frozen.ownerEffects,"departure freezes owner effects and set stats")
	for slot in g.catalog.RelicSlots:g.unequip_relic("ember",slot.id)
	ck(g.computed_stats("ember",1,frozen)==departure.stats,"out of run equipment changes leave frozen stats")
	ck(g.extraction.run().party[0]==departure,"equipment changes leave exploration snapshot")
	var prior:Dictionary=frozen.duplicate(true);prior.erase("ownerEffects");prior.erase("relicSetBonuses");prior.erase("relicSets")
	equip(g,"ember",loadout(g,"star_watch",4))
	ck(g.computed_stats("ember",1,prior).maxHp==850,"old frozen snapshot never acquires current set")
	ck(g.valid_save(g.state),"exploration frozen set remains valid after external equipment change")
func targeted_rewards() -> void:
	var g=Game.new("")
	g.rng.seed=2500001
	ck(g.set_abyss_relic_set("star_watch").success,"camp target selection")
	var prep:Dictionary=floor_ready(g,10,3)
	ck(prep.success and prep.config.targetRelicSetId=="star_watch" and prep.config.rewards.relicDrop.item.setId=="star_watch","issued milestone locks selected target")
	ck(g.valid_save(g.state),"prepared reward item save validates")
	var before:Dictionary=g.state.duplicate(true)
	ck(not g.set_abyss_relic_set("flame_oath").success and g.state==before,"active run target locked")
	var encoded:Dictionary=JSON.parse_string(JSON.stringify(g.state))
	var restored=Game.new("");restored.state=restored._normalize(encoded)
	var resumed:Dictionary=restored.prepare_abyss()
	ck(resumed.resumed and resumed.config==prep.config,"reloaded prepared reward retained exactly")
	var rng_before:int=restored.rng.state
	ck(restored.prepare_abyss().config==resumed.config and restored.rng.state==rng_before,"repeat prepare zero reroll")
	var battle_state:Dictionary=won(restored,resumed.config)
	var state_before:Dictionary=restored.state.duplicate(true)
	restored.save_blocked=true
	ck(not restored.finish_battle(resumed.config,battle_state).success and restored.state==state_before,"failed reward save rolls entire state back")
	restored.save_blocked=false
	var issued_item:Dictionary=resumed.config.rewards.relicDrop.item.duplicate(true)
	var got:Dictionary=restored.finish_battle(resumed.config,battle_state)
	ck(got.success and got.relic==issued_item,"real reward matches complete issued item after failed retry")
	ck(got.rewards.gold==0 and got.dailyAward.amount==2200 and got.rewards.exp==85,"direct gold and XP unchanged; daily award revised")
	ck(not restored.finish_battle(resumed.config,battle_state).success,"duplicate reward blocked")
	var legacy:Dictionary=before.duplicate(true)
	legacy.abyss.rogue.erase("targetRelicSetId");legacy.abyss.rogue.erase("relicRewardVersion")
	legacy.abyss.rogue.activeEncounter.erase("targetRelicSetId");legacy.abyss.rogue.activeEncounter.erase("relicRewardVersion")
	legacy.abyss.rogue.activeEncounter.rewards.relicDrop={"slotId":"helmet","rarity":5}
	var old=Game.new("")
	ck(old.valid_save(legacy),"old issued encounter validates")
	old.state=old._normalize(legacy)
	var old_prep:Dictionary=old.prepare_abyss()
	ck(old_prep.config.rewards.relicDrop=={"slotId":"helmet","rarity":5} and old.abyss_relic_drop_info().legacy,"old drop plan and legacy run policy retained")
	var old_result:Dictionary=old.finish_battle(old_prep.config,won(old,old_prep.config))
	ck(old_result.success and not old_result.relic.has("setId"),"old issued reward remains loose piece")
	var failgame=Game.new("");var failed_prep:Dictionary=failgame.prepare_abyss();var failbefore:int=failgame.state.relics.size()
	ck(failgame.finish_battle(failed_prep.config,{"phase":"defeat"}).success and failgame.state.relics.size()==failbefore,"defeat gives no relic")
	var bad:Dictionary=before.duplicate(true);bad.abyss.rogue.activeEncounter.rewards.relicDrop.item.setId="flame_oath"
	ck(not g.valid_save(bad),"issued target mismatch rejected")
	bad=before.duplicate(true);bad.abyss.meta.selectedRelicSetId="unknown"
	ck(not g.valid_save(bad),"unknown camp target rejected")
func drop_statistics() -> void:
	var g=Game.new("")
	var rng_before:int=g.rng.state
	var summary:Array=[]
	for rank in range(4):
		var info:Dictionary=g.abyss_relic_drop_info(rank)
		ck(is_equal_approx(info.expectedPer50,10.0+4.0*rank),"linear expected relic count "+str(rank))
		ck(is_equal_approx(info.expectedSellGoldPer50,3000.0+768.0*rank),"linear sale economy "+str(rank))
		var count:=0;var four:=0;var five:=0;var sold:=0
		const RUNS:=2000
		for run in range(RUNS):
			for floor_number in range(1,51):
				var drop:Dictionary=g._abyss_relic_drop(floor_number,rank,"flame_oath",run*1009+floor_number*7919,"sample_%d_%d_%d"%[rank,run,floor_number])
				if drop.is_empty():continue
				count+=1;four+=int(drop.rarity==4);five+=int(drop.rarity==5)
				sold+=g.relic_sell_value(drop.item)
				ck(drop.item.setId=="flame_oath","every generated sample targets selected set")
				if floor_number%10==0:ck(drop.rarity==5,"ten-floor five-star guarantee")
				elif floor_number%5==0:ck(drop.rarity==4,"five-floor four-star guarantee")
		ck(abs(float(count)/RUNS-float(info.expectedPer50))<.25,"seeded count sample within confidence range "+str(rank))
		ck(abs(float(four)/RUNS-float(info.expectedFourStarPer50))<.25 and abs(float(five)/RUNS-float(info.expectedFiveStarPer50))<.20,"seeded rarity sample within confidence range "+str(rank))
		summary.append({"rank":rank,"runs":RUNS,"meanCount":float(count)/RUNS,"meanFourStar":float(four)/RUNS,"meanFiveStar":float(five)/RUNS,"meanSellGold":float(sold)/RUNS,"theory":info})
	ck(g.rng.state==rng_before,"reward sampling leaves global RNG untouched")
	print("DROP STATISTICS ",JSON.stringify(summary))

func actual_floor_rewards() -> void:
	for rank in range(4):
		var g=Game.new("")
		g.rng.seed=2500100+rank
		g.set_abyss_relic_set("aurora_prayer")
		var xp:=0;var direct_gold:=0;var rewards:=0
		for floor_number in range(1,51):
			var prep:Dictionary=floor_ready(g,floor_number,rank)
			ck(prep.success and g.valid_save(g.state),"actual issued floor valid "+str(floor_number))
			var result:Dictionary=g.finish_battle(prep.config,won(g,prep.config))
			ck(result.success and g.valid_save(g.state),"actual settled floor valid "+str(floor_number))
			xp+=int(result.rewards.exp);direct_gold+=int(result.rewards.gold)
			if not result.relic.is_empty():
				rewards+=1
				ck(result.relic.setId=="aurora_prayer" and result.relic==prep.config.rewards.relicDrop.item,"actual targeted payout equals prepared item")
			if floor_number%10==0:ck(result.relic.rarity==5,"actual boss five-star guarantee")
			elif floor_number%5==0:ck(result.relic.rarity==4,"actual elite four-star guarantee")
			if floor_number==50:ck(result.ended==(rank<3),"three finite ranks and final endless rank")
		ck(xp==8125 and direct_gold==0,"per-50 actual XP and no direct gold unchanged")
		ck(int(g.abyss_daily_status().paidToday)==[4500,6750,9000,11000][rank],"per-50 actual revised daily diamonds")
		ck(rewards>=10 and (rank!=0 or rewards==10),"actual sweep retains guaranteed count")
		if rank==3:
			var endless:Dictionary=floor_ready(g,100,3)
			var result:Dictionary=g.finish_battle(endless.config,won(g,endless.config))
			ck(result.success and not result.ended and result.relic.rarity==5 and g.state.abyss.currentFloor==101,"endless floor100 target guarantee and continuation")

func prepared_party_freeze() -> void:
	var g=Game.new("")
	equip(g,"ember",loadout(g,"star_watch",4))
	var prep:Dictionary=g.prepare_abyss()
	var issued:Array=prep.config.partySnapshot.duplicate(true)
	for slot in g.catalog.RelicSlots:g.unequip_relic("ember",slot.id)
	ck(g.battle_party(true)==issued and g.valid_save(g.state),"issued party keeps exact stats and owner effects after equipment changes")
	g.state=g._normalize(JSON.parse_string(JSON.stringify(g.state)))
	ck(g.prepare_abyss().config.partySnapshot==issued,"reload preserves prepared gear snapshot")
	var result:Dictionary=g.finish_battle(prep.config,won(g,prep.config))
	ck(result.success,"frozen geared battle settles")
	# The next floor uses current equipment while preserving the carried HP ratio.
	g.state.abyss.rogue.pendingChoices=[];g.state.abyss.rogue.pendingNode={};g.state.abyss.rogue.nextStep={"type":"none","floor":1}
	prep=g.prepare_abyss()
	ck(prep.success and g.valid_save(g.state) and g.battle_party(true)[0].ownerEffects.is_empty(),"next encounter adopts current gear and validates old carried maxHP")
	var old_rng:int=g.rng.state;var old_state:Dictionary=g.state.duplicate(true)
	g.relic_loadout_snapshot("ember",[])
	ck(g.rng.state==old_rng and g.state==old_state,"preview leaves signed battle and RNG intact")
