extends SceneTree
const Game = preload("res://scripts/game_model.gd")
const Battle = preload("res://scripts/battle_model.gd")
const Navigation = preload("res://tools/extraction_navigation.gd")
const PROFILES = [
	{"id":"starter", "team":["ember","zeph"],"level":1,"constellation":0,"gear":false},
	{"id":"grown", "team":["ember","tide","bolt"],"level":5,"constellation":0,"gear":false},
	{"id":"limited_c0", "team":["kaldi","ayla","gus"],"level":10,"constellation":0,"gear":false},
	{"id":"limited_c0_gear25", "team":["kaldi","ayla","gus"],"level":10,"constellation":0,"gear":true},
	{"id":"limited_c6_gear25", "team":["kaldi","ayla","gus"],"level":10,"constellation":6,"gear":true},
	{"id":"damage_c6_gear25", "team":["kaldi","cinder","gus"],"level":10,"constellation":6,"gear":true},
	{"id":"optimized_c6", "team":["kaldi","ayla","gus"],"level":10,"constellation":6,"gear":true,"optimized":true},
	{"id":"legacy_awaken100", "team":["kaldi","ayla","gus"],"level":10,"constellation":6,"gear":true,"optimized":true,"awakening":100}
]
var errors: Array=[]
var seed_base:=9410000
var samples:=64
var battles:=0
var trial_hp:=0.0
var trial_atk:=0.0
var fixture_cache:Dictionary={}
var frozen_hashes:Dictionary={}
var prepared:=false
func _init() -> void:
	for p in ["scripts/extraction_model.gd","scripts/game_model.gd","scripts/battle_model.gd","data/extraction.json","data/catalog.json","tools/extraction_navigation.gd","tools/simulate_extraction_v6_holdout.gd"]: frozen_hashes[p]=FileAccess.get_sha256("res://"+p)
	var ranks:Array=[0,1,2,3,4,5]
	var profiles:Array=PROFILES
	var policies:Array=["direct","casual","shortest","poi","completionist"]
	var output:="extraction-v6-holdout.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hp="): trial_hp=float(arg.trim_prefix("--hp="))
		if arg.begins_with("--atk="): trial_atk=float(arg.trim_prefix("--atk="))
		if arg.begins_with("--samples="): samples=int(arg.trim_prefix("--samples="))
		if arg.begins_with("--seed="): seed_base=int(arg.trim_prefix("--seed="))
		if arg.begins_with("--rank="): ranks=[int(arg.trim_prefix("--rank="))]
		if arg.begins_with("--profile="): profiles=PROFILES.filter(func(p):return p.id==arg.trim_prefix("--profile="))
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=").get_file()
		if arg=="--supplies": prepared=true
		if arg.begins_with("--policy="): policies=[arg.trim_prefix("--policy=")]
		if arg=="--all-policies": policies=["shortest","poi","completionist"]
	var rows:Array=[]
	var groups:Array=[]
	for profile in profiles:
		var matched:Dictionary={"starter":0,"grown":2,"limited_c0":3,"limited_c0_gear25":4,"limited_c6_gear25":5,"damage_c6_gear25":5,"optimized_c6":5,"legacy_awaken100":5}
		for rank in [matched[profile.id]]:
			for policy in policies:
				var group:={"profile":profile.id,"risk":rank,"policy":policy,"runs":samples,"firstBoss":0,"extracted":0,"battles":0,"gold":0,"blessings":0,"rounds":0}
				for n in range(samples):
					var row:=simulate(profile,int(rank),policy,seed_base+n)
					rows.append(row)
					group.firstBoss+=int(row.bosses>=1);group.extracted+=int(row.success)
					for key in ["battles","gold","blessings","rounds"]:group[key]+=row[key]
				groups.append(group)
				print(JSON.stringify(group))
	var hashes:=frozen_hashes
	for p in hashes:
		if hashes[p]!=FileAccess.get_sha256("res://"+p):errors.append("source changed during simulation: "+p)
	var report:={"supplies":prepared,"trialHp":trial_hp,"trialAtk":trial_atk,"profiles":profiles,"samples":samples,"seed":seed_base,"groups":groups,"rows":rows,"errors":errors,"battles":battles,"hashes":hashes,"method":"Real legal 5-star +25 relic generation, all 5 slots. Optimized profiles select best of 12 legally generated rolls per slot, never inject arbitrary stats. No default awakening; separate legacy imported awakening100 scenario. Actual model routes/actions/choices/reveals/direct use/equipment, actual BattleModel auto_step. Gold net excludes relic fixture development costs, includes run procurement. No real player wall-clock or retention conclusions."}
	var f:=FileAccess.open("res://validation/"+output,FileAccess.WRITE);f.store_string(JSON.stringify(report,"\t"))
	print("V6 MATRIX ",rows.size()," runs ",battles," battles ",errors.size()," errors")
	quit(0 if errors.is_empty() else 1)
func must(result:Dictionary,label:String)->bool:
	if not result.get("success",false):errors.append(label+": "+str(result));return false
	return true
func simulate(profile:Dictionary,rank:int,policy:String,seed_value:int)->Dictionary:
	var g=Game.new("");g.rng.seed=seed_value
	var cache_key:=str(profile.id)+":"+str(seed_value)
	if fixture_cache.has(cache_key):
		g.state=fixture_cache[cache_key].state.duplicate(true)
		g.rng.state=fixture_cache[cache_key].rng
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
		fixture_cache[cache_key]={"state":g.state.duplicate(true),"rng":g.rng.state}
	g.state.resources.gold=50000
	var x=g.extraction;x.state().unlockedDifficulty=rank
	if trial_hp>0:x.data.balance.rankHp[rank]=trial_hp
	if trial_atk>0:x.data.balance.rankAtk[rank]=trial_atk
	var departure_rng=g.rng.state
	if prepared:
		for purchase in range(3):
			must(x.buy_supply("medkit"),"buy medkit")
			must(x.bring_item(x.state().stash.back().uid),"bring medkit")
		g.rng.state=departure_rng
	must(x.start_run(rank),"start")
	var row:={"profile":profile.id,"risk":rank,"policy":policy,"seed":seed_value,"bosses":0,"success":false,"battles":0,"rounds":0,"gold":0,"blessings":0,"actions":0,"searches":0,"exitValues":[],"bossRounds":[],"deadAllies":0,"endingAct":1}
	var safety:=0
	while x.active() and safety<400:
		safety+=1
		if not x.growth_choices().is_empty():
			var choices:Array=x.growth_choices()
			if policy not in ["direct","casual"]: choices.sort_custom(func(a,b):return growth_score(a)>growth_score(b))
			must(x.choose_growth(choices[0].choiceId),"growth");continue
		if x.run().phase=="battle":
			var b=Battle.new(g.catalog);var result:Dictionary=x.start_battle(b)
			if not must(result,"battle start"):break
			var guard:=0
			while b.state.phase not in ["victory","defeat"] and guard<3000:b.auto_step();guard+=1
			if guard>=3000:errors.append("battle stuck");break
			battles+=1;row.battles+=1;row.rounds+=int(b.state.get("turn",0))
			row.endingAct=int(x.run().act)
			row.deadAllies=0
			for unit in b.state.allies:
				if unit.currentHp<=0:row.deadAllies+=1
			if result.config.kind=="boss": row.bossRounds.append({"act":int(x.run().act),"rounds":int(b.state.turn),"won":b.state.phase=="victory"})
			must(x.settle_battle(result.config,b.state),"settle")
			continue
		if x.run().phase=="route":must(x.view_current_room(),"view")
		for option in ([] if policy=="direct" else x.room_actions()):
			if not option.enabled:continue
			# Rest when hurt, otherwise take energy or the first free blessing.
			if policy!="casual" and option.id=="recover" and health(x)>0.75:continue
			if option.cost>0:continue
			must(x.choose_room_action(option.id),"room action");row.actions+=1;break
		if not x.growth_choices().is_empty():continue
		for container in x.containers():
			while x.reveal_next(container.id).success:row.searches+=1
			for item in x._find_container(container.id).items.duplicate(true):
				var d:Dictionary=x.item_def(item.itemId)
				if d.kind=="consumable" and health(x)<0.85 and x.can_use_consumable(item.itemId):must(x.use_container_item(container.id,item.uid),"direct heal")
				elif d.kind=="equipment" and x.run().equipped.size()<3:must(x.equip_container_item(container.id,item.uid),"direct equip")
			x.take_all_revealed(container.id)
			var plan:Dictionary=x.plan_smart_loot(container.id)
			if plan.get("success",false):must(x.apply_smart_loot(container.id,plan.get("planHash","")),"swap")
		for item in x.run().bag.duplicate(true):
			if x.item_def(item.itemId).kind=="consumable" and health(x)<0.75 and x.can_use_consumable(item.itemId):x.use_item(item.uid)
		row.bosses=int(x.run().bossesDefeated);row.blessings=x.run().blessings.size()
		if x.run().phase=="boss_exit":
			var checkpoint:=int(g.state.resources.gold)-50000
			for item in x.run().bag+x.run().equipped: checkpoint+=x.item_value(item)
			row.exitValues.append({"act":int(x.run().act),"gold":checkpoint})
			if int(x.run().act)==3:
				for item in x.run().bag+x.run().equipped:row.gold+=x.item_value(item)
				row.gold+=int(g.state.resources.gold)-50000
				row.success=must(x.extract(),"extract");break
			must(x.continue_act(),"continue");continue
		var next:=next_room(x,policy)
		if next.is_empty():errors.append("no route");break
		if not must(x.enter_room(next),"enter"):break
	if safety>=400:errors.append("navigation stuck")
	if not g.valid_save(g.state):errors.append("invalid end save")
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
		if not route.is_empty():return route[0]
	var best:="";var best_score:=-INF
	for room in m.rooms:
		if room.visited or room.type in ["entry","boss"]:continue
		var route:Array=Navigation.path(m,m.currentRoomId,room.id,false)
		if route.is_empty():continue
		var score:=-float(route.size())
		if policy=="poi":score=float({"vault":16,"shrine":14,"workshop":12,"rest":8,"cache":10,"event":8}.get(room.type,1))/route.size()
		if score>best_score:best_score=score;best=route[0]
	return best
