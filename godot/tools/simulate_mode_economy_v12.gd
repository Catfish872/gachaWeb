extends SceneTree
const Game=preload("res://tools/economy_fixture_game_v8.gd")
const Battle=preload("res://scripts/battle_model.gd")
const Navigation=preload("res://tools/extraction_navigation.gd")
const PROFILES=[
	{"id":"starter","team":["ember","zeph"],"level":1,"constellation":0,"gear":false,"risk":0},
	{"id":"grown","team":["ember","tide","bolt"],"level":5,"constellation":0,"gear":false,"risk":2},
	{"id":"limited_c6_gear25","team":["kaldi","ayla","gus"],"level":10,"constellation":6,"gear":true,"risk":5},
	{"id":"damage_c6_gear25","team":["kaldi","cinder","gus"],"level":10,"constellation":6,"gear":true,"risk":5},
	{"id":"optimized_c6","team":["kaldi","ayla","gus"],"level":10,"constellation":6,"gear":true,"optimized":true,"risk":5}
]
var errors:Array=[]
var fixture_cache:Dictionary={}
var battles:=0
var trial_hp:=0.0
var trial_atk:=0.0
var prepared:=false
var exit_act:=1
var paired_fixture:Dictionary={}
var decision_count:=0
var kit_mode:="none"
var sample_count:=16
var report_name:="mode-economy-v8-calibration.json"
var seed_base:=23100000
var run_modes:="all"
var supply_policy:="reserve_locked"
func _init()->void:
	var profiles:Array=PROFILES.duplicate(true)
	var samples:=4
	var base:=34100000
	var target:=50
	var output:="mode-economy-v12-smoke.json"
	var force_risk:=-1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--samples="):samples=int(arg.trim_prefix("--samples="))
		if arg.begins_with("--seed-base="):base=int(arg.trim_prefix("--seed-base="))
		if arg.begins_with("--profile="):profiles=PROFILES.filter(func(p):return p.id==arg.trim_prefix("--profile=")).duplicate(true)
		if arg.begins_with("--risk="):force_risk=int(arg.trim_prefix("--risk="))
		if arg.begins_with("--target-floor="):target=int(arg.trim_prefix("--target-floor="))
		if arg.begins_with("--supply-policy="):supply_policy=arg.trim_prefix("--supply-policy=")
		if arg.begins_with("--modes="):run_modes=arg.trim_prefix("--modes=")
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=").get_file()
	var rows:Array=[]
	var hashes:Dictionary={}
	for path in ["scripts/game_model.gd","scripts/extraction_model.gd","scripts/battle_model.gd","scripts/abyss_balance.gd","scripts/expedition_events.gd","data/catalog.json","data/extraction.json","data/rogue_v2.json","tools/economy_fixture_game_v8.gd","tools/extraction_navigation.gd","tools/simulate_mode_economy_v12.gd"]:hashes[path]=FileAccess.get_sha256("res://"+path)
	kit_mode="prepared";exit_act=3
	for profile in profiles:
		var risks:Array=[profile.risk]
		if profile.id=="limited_c6_gear25":risks=[4,5]
		if force_risk>=0:risks=[force_risk]
		for risk in risks:
			for n in range(samples):
				if n%8==0:print("V12 PROGRESS ",profile.id," R",risk," ",n,"/",samples)
				var seed_value:=base+n
				rows.append(simulate(profile,int(risk),"poi",seed_value))
				var abyss_rank:int={0:0,1:0,2:1,3:1,4:2,5:3}[int(risk)]
				if run_modes=="all":
					for camp in [false,true]:rows.append_array(simulate_abyss50(profile,seed_value,abyss_rank,camp,target,int(risk)))
	for path in hashes:
		if hashes[path]!=FileAccess.get_sha256("res://"+path):errors.append("source changed "+path)
	var file=FileAccess.open("res://validation/expedition-v241/"+output,FileAccess.WRITE)
	file.store_string(JSON.stringify({"rows":rows,"errors":errors,"hashes":hashes,"seedBase":base,"targetFloor":target,"method":"First three abyss ranks cap at 50, endless rank sampled to 50 then reset. First/day-repeat and empty/maxed camp, actual daily diamonds/memory exchange. Extraction legal C6/gear fixtures, actual battle XP, guarded services. Paired reserve_locked policy keeps one best heal/repair/energy/revive via real exchange-lock APIs and manual parcel selection; default_unlocked uses default unprotected bag and automatic parcels. Both apply real automatic outgoing consumable usage. Source-size 3x4 relay / 5x5 boss parcels follow searching. Parcel items are physically moved, claimed and sold out-of-run. All retained trade assets liquidated with actual APIs; unused purchased-key cost capital adjustment is separate. Time estimates use engine steps and declared interactions, not CPU time."},"\t"))
	print("V12 ECONOMY ",rows.size()," rows ",errors.size()," errors")
	for error in errors:printerr(error)
	quit(0 if errors.is_empty() else 1)
func must(result:Dictionary,label:String)->bool:
	if label in ["choose offered reward","choose route","rest recover","event","shop purchase","leave shop"]:decision_count+=1
	if not result.get("success",false):errors.append(label+": "+str(result));return false
	return true
func simulate_abyss50(profile:Dictionary,seed_value:int,rank:int,maxed:bool,target:int,raid_risk:int)->Array:
	var m=Game.new("");m.state=paired_fixture.duplicate(true);m.rng.seed=seed_value
	m.state.abyss.meta.unlockedDifficulty=rank
	must(m.set_abyss_difficulty(rank),"abyss rank")
	var camp_cost:=0
	if maxed:
		m.state.abyss.meta.currency=100000
		for definition in m.rogue_data.metaUpgrades:
			for level in range(int(definition.maxLevel)):
				var purchase:Dictionary=m.purchase_meta_upgrade(definition.id)
				must(purchase,"fixture camp upgrade");camp_cost+=int(purchase.get("cost",0))
		m.state.abyss.meta.currency=0
	var rows:Array=[]
	for attempt in range(2):
		var initial_gold:int=m.state.resources.gold
		var initial_diamonds:int=m.state.resources.diamonds
		var initial_memory:int=m.state.abyss.meta.currency
		var old_uids:Array=[]
		for relic in m.state.relics:old_uids.append(relic.uid)
		decision_count=0
		var row:={"mode":"abyss","profile":profile.id,"risk":rank,"raidReferenceRisk":raid_risk,"seed":seed_value,"camp":"maxed" if maxed else "empty","campCapitalMemory":camp_cost,"attempt":"first" if attempt==0 else "repeat","targetFloor":target,"floors":0,"steps":0,"battles":0,"success":false,"goldDirect":0,"relicSell":0,"relicCount":0,"dailyDiamonds":0,"memoryBattle":0,"memoryEvent":0,"memoryConverted":0,"xpAwardedPerCharacter":0,"xpAppliedTotal":0,"dailyAwards":[]}
		for floor_number in range(1,target+1):
			if not resolve_nodes(m,"balanced"):break
			var prep:Dictionary=m.prepare_abyss()
			if not must(prep,"abyss prepare"):break
			var battle=Battle.new(m.catalog)
			battle.start(prep.config,m.battle_party(true),m.rogue_effects())
			var guard:=0
			while battle.state.phase not in ["victory","defeat"] and guard<3000:battle.auto_step();guard+=1
			if guard>=3000:errors.append("abyss stuck");break
			row.steps+=guard;row.battles+=1
			if battle.state.phase=="victory":row.floors+=1
			var settlement:Dictionary=m.finish_battle(prep.config,battle.state)
			must(settlement,"abyss settle")
			var rewards:Dictionary=settlement.get("rewards",{})
			row.dailyDiamonds+=int(rewards.get("diamonds",0));row.memoryBattle+=int(rewards.get("meta",0));row.xpAwardedPerCharacter+=int(rewards.get("exp",0))
			if floor_number%10==0 and battle.state.phase=="victory":row.dailyAwards.append({"floor":floor_number,"amount":int(rewards.get("diamonds",0))})
			for progression in settlement.get("progression",[]):row.xpAppliedTotal+=int(progression.gained)
			if battle.state.phase=="defeat":break
		row.success=row.floors==target
		row.memoryEarned=int(m.state.abyss.meta.currency)-initial_memory
		row.memoryEvent=row.memoryEarned-row.memoryBattle
		if m.abyss_run_active():must(m.reset_abyss(),"explicit target retreat")
		if maxed and int(m.state.abyss.meta.currency)>0:
			var amount:int=m.state.abyss.meta.currency
			if must(m.exchange_memory(amount),"memory exchange"):row.memoryConverted=amount
		row.goldDirect=int(m.state.resources.gold)-initial_gold
		for relic in m.state.relics:
			if relic.uid not in old_uids:row.relicSell+=m.relic_sell_value(relic);row.relicCount+=1
		row.gold=row.goldDirect+row.relicSell
		row.diamonds=int(m.state.resources.diamonds)-initial_diamonds
		row.choices=decision_count
		row.secondsFast=row.steps*0.85/4+row.battles*1.0+decision_count*2.0+12.0+(1.5 if row.memoryConverted>0 else 0.0)
		row.secondsDeliberate=row.steps*0.85/4+row.battles*2.0+decision_count*5.0+40.0+(4.0 if row.memoryConverted>0 else 0.0)
		if row.goldDirect!=0:errors.append("abyss direct gold nonzero")
		if row.diamonds!=row.dailyDiamonds+row.memoryConverted:errors.append("diamond accounting mismatch")
		if not m.valid_save(m.state):errors.append("invalid abyss end save")
		rows.append(row)
	return rows
func simulate(profile:Dictionary,rank:int,policy:String,seed_value:int)->Dictionary:
	var g=Game.new("");g.rng.seed=seed_value
	var cache_key:=str(profile.id)+":"+str(seed_value)
	if fixture_cache.has(cache_key):
		g.state=fixture_cache[cache_key].state.duplicate(true)
		g.rng.state=fixture_cache[cache_key].rng
		g._uid_counter=int(fixture_cache[cache_key].uidCounter)
	else:
		for id in profile.team:
			g.state.ownedCharacters[id]=g.default_character();g.state.ownedCharacters[id].level=profile.level;g.state.ownedCharacters[id].constellation=profile.constellation;g.state.ownedCharacters[id].awakening=int(profile.get("awakening",0))
		g.set_team(profile.team)
		if profile.gear:
			g.state.resources.gold=10000000
			for id in profile.team:
				for slot in g.catalog.RelicSlots:
					var best:Dictionary={};var best_score:=-INF
					for trial in range(12 if profile.get("optimized",false) else 1):
						var relic:Dictionary=g.generate_relic(5,slot.id)
						must(g.add_relic(relic),"fixture relic")
						must(g.upgrade_relic_to_max(relic.uid),"fixture max")
						must(g.equip_relic(relic.uid,id),"fixture equip")
						var st:Dictionary=g.computed_stats(id)
						var score:=float(st.atk)*(1.0+float(st.cri)*maxf(0,float(st.criDmg)-1))*sqrt(float(st.maxHp))*(1.0+float(st.spd)/500)
						if score>best_score:best_score=score;best=relic
					must(g.equip_relic(best.uid,id),"fixture chosen")
					g.state.relics=g.state.relics.filter(func(r):return r.get("equippedBy")!=null)
		fixture_cache[cache_key]={"state":g.state.duplicate(true),"rng":g.rng.state,"uidCounter":g._uid_counter}
	g.state.resources.gold=50000
	paired_fixture=g.state.duplicate(true)
	var x=g.extraction;x.state().unlockedDifficulty=rank
	if trial_hp>0:x.data.balance.rankHp[rank]=trial_hp
	if trial_atk>0:x.data.balance.rankAtk[rank]=trial_atk
	var departure_rng=g.rng.state
	var capital:=0
	var paid_keys:Dictionary={}
	if kit_mode=="prepared":
		for id in ["armor_5","pack_5"]:
			capital+=int(x.item_def(id).buyPrice)
			must(x.buy_supply(id),"purchase persistent utility")
			must(x.set_utility_slot(str(x.item_def(id).slot),x.state().stash.back().uid),"equip persistent utility")
		# Capital is reported separately; repeated runs pay wear/keys, not purchase again.
		g.state.resources.gold=50000
		for id in ["key_ruins","key_forest","key_sanctum"]:
			must(x.buy_keys(id,1),"purchase key")
			paid_keys[str(x.state().keyring.back().uid)]=int(x.item_def(id).buyPrice)
		g.rng.state=departure_rng
	if prepared:
		for purchase in range(3):
			must(x.buy_supply("medkit"),"buy medkit")
			must(x.bring_item(x.state().stash.back().uid),"bring medkit")
		g.rng.state=departure_rng
	must(x.start_run(rank),"start")
	var row:={"profile":profile.id,"risk":rank,"policy":policy,"supplyPolicy":supply_policy,"seed":seed_value,"bosses":0,"success":false,"battles":0,"rounds":0,"gold":0,"blessings":0,"actions":0,"searches":0,"steps":0,"kit":kit_mode,"capital":capital,"secured":0,"travel":0,"searchSeconds":0.0,"choices":0,"exitValues":[],"bossRounds":[],"deadAllies":0,"endingAct":1,"targetAct":exit_act,"guardBattles":0,"guardVictories":0,"guardXP":0,"guardSteps":0,"guardServiceVisits":0,"parcelCount":0,"parcelCells":0,"parcelItems":0,"parcelValue":0,"parcelFees":0,"parcelHistory":[],"parcelUIDs":{},"parcelSoldValue":0,"fullRooms":0,"peakCells":0,"goldFound":[0,0,0],"redFound":[0,0,0],"goldLootFound":[0,0,0],"redLootFound":[0,0,0],"foundSeen":{},"roomsSeen":{},"keyBought":3 if kit_mode=="prepared" else 0,"keyPurchaseCost":50000-int(g.state.resources.gold),"keysUsed":0,"deposits":0,"suppliesUsed":0,"autoSuppliesUsed":0,"autoSuppliesValue":0,"autoUnusedSuppliesReturned":0,"autoUseHistory":[],"lockActions":0,"xpAwardedPerCharacter":0,"xpAppliedTotal":0,"firstFullBag":{},"firstActExitBag":{}}
	var safety:=0
	while x.active() and safety<400:
		safety+=1
		if not x.growth_choices().is_empty():
			var choices:Array=x.growth_choices()
			if policy not in ["direct","casual"]: choices.sort_custom(func(a,b):return growth_score(a)>growth_score(b))
			must(x.choose_growth(choices[0].choiceId),"growth");row.choices+=1;continue
		if x.run().phase=="battle":
			use_needed_bag(x,row)
			var b=Battle.new(g.catalog);var result:Dictionary=x.start_battle(b)
			if not must(result,"battle start"):break
			var guard:=0
			while b.state.phase not in ["victory","defeat"] and guard<3000:b.auto_step();guard+=1
			if guard>=3000:errors.append("battle stuck");break
			battles+=1;row.battles+=1;row.steps+=guard;row.rounds+=int(b.state.get("turn",0))
			row.endingAct=int(x.run().act)
			row.deadAllies=0
			for unit in b.state.allies:
				if unit.currentHp<=0:row.deadAllies+=1
			if result.config.kind=="boss": row.bossRounds.append({"act":int(x.run().act),"rounds":int(b.state.turn),"won":b.state.phase=="victory"})
			var settlement:Dictionary=x.settle_battle(result.config,b.state)
			must(settlement,"settle")
			if result.config.get("isServiceGuard",false):
				row.guardBattles+=1;row.guardSteps+=guard
				if b.state.phase=="victory":row.guardVictories+=1
				row.guardXP+=int(settlement.get("rewards",{}).get("exp",0))
			row.xpAwardedPerCharacter+=int(settlement.get("rewards",{}).get("exp",0))
			for progression in settlement.get("progression",[]):row.xpAppliedTotal+=int(progression.gained)
			continue
		if x.run().phase=="route":must(x.view_current_room(),"view")
		for option in ([] if policy=="direct" else x.room_actions()):
			if not option.enabled:continue
			# Rest when hurt, otherwise take energy or the first free blessing.
			if policy!="casual" and option.id=="recover" and health(x)>0.75:continue
			if option.cost>0:continue
			
			var keys_before:int=x.state().keyring.size()
			must(x.choose_room_action(option.id),"room action");row.keysUsed+=keys_before-x.state().keyring.size();row.actions+=1;break
		if not x.growth_choices().is_empty() or x.run().phase=="battle":continue
		for container in x.containers():
			for hidden in x._find_container(container.id).items:
				if not row.foundSeen.has(hidden.uid):
					row.foundSeen[hidden.uid]=true
					var rarity:int=x.item_def(hidden.itemId).get("rarity",0)
					if rarity==4:row.goldFound[int(x.run().act)-1]+=1
					if rarity==5:row.redFound[int(x.run().act)-1]+=1
					if x.item_def(hidden.itemId).kind=="loot":
						if rarity==4:row.goldLootFound[int(x.run().act)-1]+=1
						if rarity==5:row.redLootFound[int(x.run().act)-1]+=1
				if not hidden.get("revealed",false): row.searchSeconds+=float({0:0.45,1:0.65,2:0.95,3:1.35,4:2.0,5:2.8}.get(int(x.item_def(hidden.itemId).get("rarity",0)),0.45))+0.38
			while x.reveal_next(container.id).success:row.searches+=1
			for item in x._find_container(container.id).items.duplicate(true):
				var d:Dictionary=x.item_def(item.itemId)
				if d.kind=="consumable" and wants_supply(x,item.itemId):must(x.use_container_item(container.id,item.uid),"direct heal");row.actions+=1;row.suppliesUsed+=1
				elif d.kind=="equipment" and x.run().equipped.size()<3:must(x.equip_container_item(container.id,item.uid),"direct equip");row.actions+=1
			var take_result:Dictionary=x.take_all_revealed(container.id)
			if take_result.get("success",false):row.actions+=1
			maintain_reserves(x,row)
			var plan:Dictionary=x.plan_smart_loot(container.id)
			if plan.get("success",false):
				apply_observed_swap(x,container.id,plan,row)
			maintain_reserves(x,row)
		use_needed_bag(x,row)
		var before_cells:=bag_cells(x)
		if row.firstFullBag.is_empty() and before_cells>=x.dimensions("bag").x*x.dimensions("bag").y*0.85:
			row.firstFullBag=bag_breakdown(x)
		if x.run().phase=="boss_exit" and int(x.run().act)==1:row.firstActExitBag=bag_breakdown(x)
		maintain_reserves(x,row)
		post_parcel(x,row)
		var cells:=bag_cells(x)
		row.peakCells=maxi(row.peakCells,cells)
		var room_key:=str(x.run().act)+":"+str(x.run().room.id)
		if not row.roomsSeen.has(room_key):
			row.roomsSeen[room_key]=true
			if cells>=int(x.dimensions("bag").x*x.dimensions("bag").y)*0.85:row.fullRooms+=1
		row.bosses=int(x.run().bossesDefeated);row.blessings=x.run().blessings.size()
		if x.run().phase=="boss_exit":
			var checkpoint:=int(g.state.resources.gold)-50000+int(row.secured)
			for item in x.run().bag+x.run().equipped: checkpoint+=x.item_value(item)
			row.exitValues.append({"act":int(x.run().act),"gold":checkpoint+key_value(x),"cells":cells,"parcelValue":row.parcelValue,"secured":row.secured,"steps":row.steps,"searchSeconds":row.searchSeconds})
			if int(x.run().act)==exit_act:
				for item in x.run().bag+x.run().equipped:row.gold+=x.item_value(item)
				row.gold+=int(g.state.resources.gold)-50000+int(row.secured)
				row.success=must(x.extract(),"extract");break
			must(x.continue_act(),"continue");continue
		var next:=next_room(x,policy)
		if next.is_empty():errors.append("no route");break
		if not must(x.enter_room(next),"enter"):break
		row.travel+=1
		if x.run().room.get("guardRolled",false) and not row.get("guardSeen",{}).has(str(x.run().act)+":"+str(x.run().room.id)):
			if not row.has("guardSeen"):row.guardSeen={}
			row.guardSeen[str(x.run().act)+":"+str(x.run().room.id)]=true;row.guardServiceVisits+=1
	if safety>=400:errors.append("navigation stuck")
	if x.active():must(x.retreat(),"interrupted route retreat")
	if not g.valid_save(g.state):errors.append("invalid pre-sale save")
	row.walletDeltaBeforeSale=int(g.state.resources.gold)-50000
	row.retainedAssets=0;row.retainedByKind={};row.retainedUIDs=[]
	for item in x.state().stash+x.state().mailbox+x.state().keyring:
		row.retainedAssets+=x.item_value(item);row.retainedUIDs.append(item.uid)
		var kind:String=str(x.item_def(item.itemId).kind)
		row.retainedByKind[kind]=int(row.retainedByKind.get(kind,0))+x.item_value(item)
	row.directGoldGross=int(row.walletDeltaBeforeSale)+int(row.keyPurchaseCost)+int(row.parcelFees)
	row.keysRetained=x.state().keyring.size();row.keysRetainedValue=key_value(x)
	row.repairReserve=int(x.equipment_status().armor.repairCost)
	row.keyRetainedCapital=0;row.keyRetainedCapitalSale=0;row.keyConsumedCost=int(row.keyPurchaseCost)
	for item in x.state().keyring:
		if paid_keys.has(str(item.uid)):
			row.keyRetainedCapital+=int(paid_keys[str(item.uid)])
			row.keyRetainedCapitalSale+=x.item_value(item)
			row.keyConsumedCost-=int(paid_keys[str(item.uid)])
	row.realizedAssetGold=0;row.liquidatedItems=0;row.saleActions=0
	while not x.state().stash.is_empty() or not x.state().mailbox.is_empty():
		if not x.state().stash.is_empty():
			var uids:Array=[]
			for item in x.state().stash:
				uids.append(item.uid)
				if row.parcelUIDs.has(item.uid):row.parcelSoldValue+=x.item_value(item)
			var sale:Dictionary=x.sell_items(uids)
			if not must(sale,"actual warehouse sale"):break
			row.realizedAssetGold+=int(sale.value);row.liquidatedItems+=int(sale.count);row.saleActions+=1
		if not x.state().mailbox.is_empty():
			var claim:Dictionary=x.claim_mail()
			if not must(claim,"actual mailbox claim"):break
			row.saleActions+=1
			if int(claim.count)==0:errors.append("mailbox claim made no progress");break
	for key in x.keyring():
		if int(key.count)>0:
			var sale:Dictionary=x.sell_keys(str(key.itemId),int(key.count))
			if must(sale,"actual key liquidation"):
				row.realizedAssetGold+=int(sale.value);row.liquidatedItems+=int(sale.count);row.saleActions+=1
	row.walletDelta=int(g.state.resources.gold)-50000
	row.goldLiquidation=row.walletDelta-row.repairReserve
	row.gold=row.goldLiquidation+row.keyRetainedCapital-row.keyRetainedCapitalSale
	if row.realizedAssetGold!=row.retainedAssets:errors.append("actual asset sales differ from retained value")
	if row.parcelSoldValue!=row.parcelValue:errors.append("parcel sold value mismatch")
	if not g.valid_save(g.state):errors.append("invalid post-sale save")
	row.erase("foundSeen");row.erase("roomsSeen");row.erase("guardSeen");row.erase("parcelUIDs")
	row.manualSuppliesUsed=row.suppliesUsed-row.autoSuppliesUsed
	row.mode="extraction"
	row.secondsFast=row.steps*0.85/4+row.battles*1.4+row.searchSeconds+row.travel*1.0+row.choices*2.0+(row.actions+row.saleActions)*1.5+row.parcelItems*0.35+12.0
	row.secondsDeliberate=row.steps*0.85/4+row.battles*2.5+row.searchSeconds+row.travel*2.5+row.choices*5.0+(row.actions+row.saleActions)*4.0+row.parcelItems*0.9+40.0
	return row
func health(x)->float:
	var hp:=0.0;var max_hp:=0.0
	for unit in x.run().party:hp+=float(unit.currentHp);max_hp+=float(unit.maxHp)
	return hp/maxf(1,max_hp)
func growth_score(r:Dictionary)->float:
	var score:float={"white":1.0,"blue":2.0,"gold":3.0}.get(r.rarity,1.0)
	for effect in r.effects:
		if effect.type in ["victoryHealPct","statusAfterHeal","lifesteal"]:score+=3
		if effect.type=="stat" and effect.get("stat")=="atkMult":score+=1
	return score
func next_room(x,policy:String)->String:
	if policy=="direct": return Navigation.shortest_gate_step(x.map_state())
	var m:Dictionary=x.map_state();var target:=6 if policy in ["shortest","direct","casual"] else (10 if policy=="poi" else 17)
	if int(m.explored)>=target and m.bossUnlocked:
		var route:Array=Navigation.path(m,m.currentRoomId,m.bossRoomId,true)
		if not route.is_empty():return reachable_endpoint(m,route)
	var best:="";var best_score:=-INF
	for room in m.rooms:
		if room.visited or room.type in ["entry","boss"]:continue
		var route:Array=Navigation.path(m,m.currentRoomId,room.id,false)
		if route.is_empty():continue
		var score:=-float(route.size())
		if policy=="poi":score=float({"vault":16,"shrine":14,"workshop":12,"rest":8,"cache":10,"event":8}.get(room.type,1))/route.size()
		if score>best_score:best_score=score;best=reachable_endpoint(m,route)
	return best
func resolve_nodes(m: Variant, style: String) -> bool:
	for safe in range(20):
		var kind := str(m.state.abyss.rogue.nextStep.type)
		match kind:
			"none": return true
			"reward":
				var choices: Array = m.state.abyss.rogue.pendingChoices.duplicate(true)
				choices.sort_custom(func(a,b): return reward_score(str(a.id), style) > reward_score(str(b.id), style))
				if not must(m.choose_abyss_reward(choices[0].choiceId), "choose offered reward"): return false
			"route":
				var choices: Array = m.node_options().options
				var selected := str(choices[0].id)
				for choice in choices:
					if choice.id in ["rest", "shop"]: selected = choice.id
				if not must(m.choose_abyss_node(selected), "choose route"): return false
			"rest":
				if not must(m.choose_abyss_node("recover"), "rest recover"): return false
			"event":
				var choices: Array = m.node_options().options
				var picked := false
				for choice in choices:
					if choice.enabled:
						picked = must(m.choose_abyss_node(choice.id), "event")
						break
				if not picked: return false
			"shop":
				var items: Array = m.abyss_shop_items()
				items.sort_custom(func(a,b): return (1000 if a.id == "heal" else reward_score(str(a.get("rewardId", "")), style)) > (1000 if b.id == "heal" else reward_score(str(b.get("rewardId", "")), style)))
				for item in items:
					for current in m.abyss_shop_items():
						if current.id == item.id and current.enabled:
							if not must(m.purchase_abyss_item(current.id), "shop purchase"): return false
				if not must(m.leave_abyss_shop(), "leave shop"): return false
			_:
				errors.append("unknown node: " + kind)
				return false
	errors.append("node resolution exceeded bound")
	return false

func reward_score(id: String, style: String) -> int:
	var preferred: Array = ["common_victory_heal_blue", "common_vampiric_blue", "common_overdrive_gold", "common_open_energy_gold", "common_atk_white", "common_crit_blue"]
	if style == "shield": preferred = ["common_victory_heal_blue", "common_shield_edge_white", "common_open_shield_blue", "common_vampiric_blue", "common_guard_gold", "common_atk_white"]
	var index := preferred.find(id)
	return 100 - index if index >= 0 else 1

func reachable_endpoint(map:Dictionary,route:Array)->String:
	if not map.has("reachableRoomIds"):return str(route[0])
	var best:=str(route[0])
	for id in route:
		if id in map.reachableRoomIds:best=str(id)
		else:break
	return best

func bag_cells(x)->int:
	var n:=0
	for item in x.run().bag:
		var size:Vector2i=x._size(item);n+=size.x*size.y
	return n
func key_value(x)->int:
	var n:=0
	for item in x.state().keyring:n+=x.item_value(item)
	return n
func reserve_supply_uids(x)->Array:
	var keep:Dictionary={}
	for field in ["heal","repair","energy","revive"]:
		if field=="repair" and x.equipment_status().armor.item.is_empty():continue
		var best_uid:="";var best_score:=0.0
		for item in x.run().bag:
			var d:Dictionary=x.item_def(item.itemId)
			if d.kind!="consumable":continue
			var score:float=float(d.get(field,0))/(x._size(item).x*x._size(item).y)
			if score>best_score:best_score=score;best_uid=item.uid
		if not best_uid.is_empty():keep[best_uid]=true
	return keep.keys()

func maintain_reserves(x,row:Dictionary)->void:
	if supply_policy!="reserve_locked" or not x.active() or x.run().phase=="battle":return
	var keep:=reserve_supply_uids(x)
	for item in x.run().bag.duplicate(true):
		if x.item_def(item.itemId).kind!="consumable":continue
		var wanted:bool=item.uid in keep
		if bool(item.get("exchangeLocked",false))==wanted:continue
		if must(x.set_consumable_exchange_lock(str(item.uid),wanted),"reserve supply lock"):
			row.lockActions+=1;row.actions+=1

func resource_snapshot(x)->Dictionary:
	var snapshot:={"armor":float(x.equipment_status().armor.percent),"party":[]}
	for unit in x.run().party:snapshot.party.append({"id":unit.id,"hp":unit.currentHp,"maxHp":unit.maxHp,"energy":unit.energy,"cooldowns":unit.cooldowns.duplicate(true)})
	return snapshot

func apply_observed_swap(x,container_id:String,plan:Dictionary,row:Dictionary)->void:
	var before:=resource_snapshot(x)
	var result:Dictionary=x.apply_smart_loot(container_id,plan.get("planHash",""))
	if not must(result,"swap"):return
	row.actions+=1
	var used:Array=result.get("used",[]);var returned:Array=result.get("returned",[])
	var value:=0;var interesting:=false
	for item in plan.removed:
		if x.item_def(item.itemId).kind=="consumable":interesting=true
	for item in used:value+=x.item_value(item)
	for item in returned:
		if x.item_def(item.itemId).kind=="consumable":row.autoUnusedSuppliesReturned+=1
	row.autoSuppliesUsed+=used.size();row.suppliesUsed+=used.size();row.autoSuppliesValue+=value
	if interesting:
		var bag_uids:Array=[];var container_uids:Array=[]
		for item in x.run().bag:bag_uids.append(item.uid)
		for item in x._find_container(container_id).items:container_uids.append(item.uid)
		row.autoUseHistory.append({"act":int(x.run().act),"roomType":str(x.run().room.type),"container":container_id,"before":before,"after":resource_snapshot(x),"removed":plan.removed.duplicate(true),"previewWillUse":plan.get("willUse",[]).duplicate(true),"used":used.duplicate(true),"returned":returned.duplicate(true),"usedUIDs":result.get("usedUIDs",[]).duplicate(),"returnedUIDs":result.get("returnedUIDs",[]).duplicate(),"bagAfterUIDs":bag_uids,"containerAfterUIDs":container_uids})

func post_parcel(x,row:Dictionary)->void:
	if not x.can_deposit():return
	var keep:Array=reserve_supply_uids(x) if supply_policy=="reserve_locked" else []
	var candidates:Array=[];var selected:Array=[];var suggestion_optimal:=false
	for item in x.run().bag:
		if item.uid not in keep:candidates.append(item)
	var quote:Dictionary={}
	if supply_policy=="reserve_locked":
		var suggestion:Dictionary=x._auto_parcel(candidates,x.parcel_dimensions())
		for item in suggestion.items:selected.append(item.uid)
		if selected.is_empty():return
		suggestion_optimal=bool(suggestion.get("optimal",false))
		quote=x.preview_deposit(selected)
	else:
		quote=x.preview_deposit()
		suggestion_optimal=bool(quote.get("optimal",false))
	if not quote.get("success",false) or not quote.get("enabled",false):return
	if int(quote.value)<=int(quote.fee):return
	var before:=bag_cells(x)
	var wallet_before:int=x.host.state.resources.gold
	var history:={"act":int(x.run().act),"roomType":str(x.run().room.get("type","")),"phase":str(x.run().phase),"beforeCells":before,"value":int(quote.value),"fee":int(quote.fee),"width":int(quote.width),"height":int(quote.height),"optimal":suggestion_optimal,"selectionMode":str(quote.get("selectionMode","")),"reservedUIDs":keep.duplicate(),"items":[],"candidates":[],"cells":0}
	for item in candidates:
		var size:Vector2i=x._size(item)
		history.candidates.append({"uid":item.uid,"width":size.x,"height":size.y,"value":x.item_value(item)})
	var expected:=Vector2i(5,5) if x.run().phase=="boss_exit" else Vector2i(3,4)
	if int(quote.width)!=expected.x or int(quote.height)!=expected.y:errors.append("parcel dimensions differ from current source")
	for item in quote.items:
		var size:Vector2i=x._size(item)
		history.cells+=size.x*size.y
		history.items.append({"uid":item.uid,"id":item.itemId,"value":x.item_value(item),"x":item.x,"y":item.y,"width":size.x,"height":size.y,"rarity":x.item_def(item.itemId).rarity})
		row.parcelUIDs[item.uid]=true
	if must(x.deposit_items(quote.planHash,selected),"actual source-sized parcel"):
		if int(x.host.state.resources.gold)!=wallet_before-int(quote.fee):errors.append("parcel credited immediate gold")
		history.remainingCells=bag_cells(x)
		row.parcelCount+=1;row.parcelItems+=quote.uids.size();row.parcelValue+=int(quote.value);row.parcelFees+=int(quote.fee);row.parcelCells+=int(history.cells);row.actions+=1;row.deposits+=1;row.secured+=int(quote.value)
		row.parcelHistory.append(history)

func wants_supply(x,id:String)->bool:
	if not x.can_use_consumable(id):return false
	var d:Dictionary=x.item_def(id)
	if float(d.get("repair",0))>0 and float(x.equipment_status().armor.percent)<0.60:return true
	for unit in x.run().party:
		if unit.currentHp<=0 and float(d.get("revive",0))>0:return true
		if unit.currentHp>0:
			if float(d.get("heal",0))>0 and float(unit.currentHp)/maxf(1,float(unit.maxHp))<0.75:return true
			if float(d.get("energy",0))>0 and int(unit.energy)<=40:return true
			if float(d.get("cooldown",0))>0:
				for cooldown in unit.cooldowns.values():
					if int(cooldown)>=2:return true
	return false
func use_needed_bag(x,row:Dictionary)->void:
	for item in x.run().bag.duplicate(true):
		if x.item_def(item.itemId).kind=="consumable" and wants_supply(x,item.itemId):
			if must(x.use_item(item.uid),"use needed supply"):row.actions+=1;row.suppliesUsed+=1
func bag_breakdown(x)->Dictionary:
	var result:={"act":int(x.run().act),"roomType":str(x.run().room.get("type","")),"cells":bag_cells(x),"byKind":{},"byRarity":{},"items":[]}
	for item in x.run().bag:
		var d:Dictionary=x.item_def(item.itemId)
		var cells:int=x._size(item).x*x._size(item).y
		var value:int=x.item_value(item)
		for category in ["byKind","byRarity"]:
			var key:String=str(d.kind) if category=="byKind" else str(d.rarity)
			if not result[category].has(key):result[category][key]={"cells":0,"value":0,"count":0}
			result[category][key].cells+=cells;result[category][key].value+=value;result[category][key].count+=1
		result.items.append({"id":item.itemId,"cells":cells,"value":value,"kind":d.kind,"rarity":d.rarity})
	return result
