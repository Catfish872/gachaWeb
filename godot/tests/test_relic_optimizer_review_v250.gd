extends SceneTree
const Game = preload("res://scripts/game_model.gd")
const Optimizer = preload("res://scripts/relic_optimizer.gd")
const Battle = preload("res://scripts/battle_model.gd")
var checks := 0
var failures: Array = []
var random = RandomNumberGenerator.new()
var minimum_margin := INF
var audited_boxes := 0
var audited_leaves := 0

func _initialize() -> void: call_deferred("run")
func ck(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL: ",label)
func relic(uid: String,slot: String,set_id: String,subs: Array) -> Dictionary:
	return {"uid":uid,"slotId":slot,"setId":set_id,"rarity":5,"level":0,"mainStat":{"stat":"atk_flat","name":"ATK","base":0.0,"perLevel":0.0},"subStats":subs,"equippedBy":null}
func prepare(search) -> void:
	while search._phase in ["scan","prune","prepare"]: search.advance(100)
func finish(search) -> Dictionary:
	var result: Dictionary=search.preview()
	while not result.done: result=search.advance(10000)
	return result
func oracle(search,slots: Array,depth: int=0,items: Array=[]) -> float:
	if depth==5: return float(search.evaluate_loadout(items).objective)
	var result:=-INF
	for item in slots[depth]:
		var next:=items.duplicate()
		if not item.is_empty(): next.append(item)
		result=maxf(result,oracle(search,slots,depth+1,next))
	return result
func leaves(search,slot: int,index: int) -> Array:
	var node: Dictionary=search._trees[slot][index]
	if node.count==1: return [index]
	var result:=leaves(search,slot,node.left)
	result.append_array(leaves(search,slot,node.right))
	return result
func check_leaf_bounds(search,slots: Array,depth: int=0,box: Array=[],items: Array=[]) -> void:
	if depth==5:
		var actual:float=search.evaluate_loadout(items).objective
		var upper:float=search._box_upper(box)
		minimum_margin=minf(minimum_margin,upper-actual)
		audited_leaves+=1
		ck(upper+0.000001>=actual,"leaf upper covers exact auto score %s U=%s L=%s box=%s"%[search._char_id,upper,actual,box])
		return
	for index in slots[depth]:
		var item:Dictionary=search._trees[depth][index].item.relic
		var next_items:=items.duplicate();var next_box:=box.duplicate()
		next_box.append(index)
		if not item.is_empty(): next_items.append(item)
		check_leaf_bounds(search,slots,depth+1,next_box,next_items)
func check_random_boxes(search,samples: int) -> void:
	for sample in samples:
		var box:Array=search._tree_roots.duplicate()
		var candidates:Array=[]
		for slot in 5:
			for step in random.randi_range(0,3):
				var node:Dictionary=search._trees[slot][box[slot]]
				if node.count==1: break
				box[slot]=node.left if random.randf()<0.5 else node.right
			var items:Array=[]
			for index in leaves(search,slot,box[slot]): items.append(search._trees[slot][index].item.relic)
			candidates.append(items)
		var actual:=oracle(search,candidates)
		var upper:float=search._box_upper(box)
		minimum_margin=minf(minimum_margin,upper-actual)
		audited_boxes+=1
		ck(upper+0.000001>=actual,"box upper covers exhaustive descendants %s U=%s L=%s box=%s"%[search._char_id,upper,actual,box])
func run() -> void:
	random.seed=250110113
	for id in ["kaldi","ayla","gus","shana","lorin","ember","zeph","bolt","tide","cinder"]:
		for constellation in [0,6]:
			var game=Game.new("")
			game.state.ownedCharacters[id]=game.default_character()
			game.state.ownedCharacters[id].constellation=constellation
			game.state.ownedCharacters[id].level=1 if constellation==0 else 10
			game.state.relics=[]
			var slots:Array=[]
			var set_a:String="aurora_prayer" if id in ["ayla","shana"] else ("stone_bastion" if id in ["tide","lorin"] else "flame_oath")
			var set_b:String="star_watch" if id in ["tide","lorin"] else ("wind_voyager" if id in ["zeph","cinder"] else "thunder_hunt")
			for slot in Optimizer.SLOTS:
				var options:Array=[{}]
				for variant in 2:
					var attrs:Array=[]
					for key in ["atk_flat","hp_flat","def_flat","atk_pct","hp_pct","def_pct","cri_rate","cri_dmg","energy_rate","spd"]:
						var amount:float=random.randi_range(0,4)*([0.01,0.08,0.2,0.37,0.5][random.randi_range(0,4)] if key.ends_with("pct") or key in ["cri_rate","cri_dmg","energy_rate"] else 20.0)
						attrs.append({"stat":key,"name":key,"value":amount})
					var item:=relic("review_%s_%s_%d"%[id,slot,variant],slot,set_a if variant==0 else set_b,attrs)
					options.append(item);game.state.relics.append(item)
				slots.append(options)
			var before:=JSON.stringify(game.state);var rng_before:int=game.rng.state
			var search=Optimizer.new(game,id,{"initialEnergy":random.randi_range(0,100)})
			prepare(search)
			var exact:=oracle(search,slots)
			var retained:Array=[]
			for slot in 5: retained.append(leaves(search,slot,search._tree_roots[slot]))
			check_leaf_bounds(search,retained)
			check_random_boxes(search,16)
			var result:=finish(search)
			ck(absf(exact-float(result.lowerBound))<0.000001,"raw inventory oracle equals certified optimizer %s C%d exact=%s found=%s"%[id,constellation,exact,result.lowerBound])
			ck(result.provenOptimal and result.done and result.upperBound==result.lowerBound,"exhausted search supplies exact certificate %s C%d"%[id,constellation])
			ck(before==JSON.stringify(game.state) and rng_before==game.rng.state,"complete preview and oracle preserve live state/RNG "+id)
			print("REVIEW CASE ",id," C",constellation," boxes=",audited_boxes," leaves=",audited_leaves)
	test_pareto_schedules()
	test_future_sources()
	test_numeric_certificate()
	test_normalizer_numeric_domain()
	test_lossless_numeric_keys()
	test_status_modified_speed_key()
	test_minimum_damage()
	test_future_passive_cache()
	test_future_auto_order()
	print("RELIC OPTIMIZER REVIEW V250: %d checks; %d leaves; %d boxes; minimum margin %s; %d failures"%[checks,audited_leaves,audited_boxes,minimum_margin,failures.size()])
	quit(0 if failures.is_empty() else 1)
func test_minimum_damage() -> void:
	var game=Game.new("")
	for id in ["ember","zeph","cinder"]:
		game.state.ownedCharacters[id]=game.default_character()
		for defense in [100.0,100000.0,1000000000.0]:
			var search=Optimizer.new(game,id,{"enemyDefense":defense})
			prepare(search)
			var leaf:Dictionary=search.evaluate_loadout([])
			ck(search._fast_upper(leaf.stats,leaf.ownerEffects)+0.000001>=float(leaf.objective),"normalization respects minimum-one direct damage %s DEF%s"%[id,defense])
func test_future_passive_cache() -> void:
	var game=Game.new("")
	var ch:Dictionary=game.catalog.CharacterData.gus.duplicate(true)
	ch.id="review_gus_passive";ch.relicObjective={"type":"damage","referenceStatuses":[]}
	game.catalog.CharacterData[ch.id]=ch;game.state.ownedCharacters[ch.id]=game.default_character()
	var search=Optimizer.new(game,ch.id)
	prepare(search)
	var stats:Dictionary=search.evaluate_loadout([]).stats
	for crit in [0.0,1.0,0.5]:
		stats.cri=crit;stats.critRate=crit
		var upper:float=search._fast_upper(stats,[])
		var score:float=search._evaluate(stats,[],false)
		ck(upper+0.000001>=score,"future passive-driven crit energy cache U=%s L=%s crit=%s"%[upper,score,crit])
func test_future_auto_order() -> void:
	var game=Game.new("")
	var ch:Dictionary=game.catalog.CharacterData.ember.duplicate(true)
	ch.id="review_order";ch.passiveId="";ch.skills=["review_normal","review_ult","review_skill"];ch.baseStats.cri=0.0;ch.relicObjective={"type":"damage","referenceStatuses":[]}
	for kind in ["normal","skill","ult"]:
		game.catalog.SkillData["review_"+kind]={"type":"ultimate" if kind=="ult" else kind,"energyGain":0,"energyCost":100,"cooldown":0,"element":"neutral","effects":[{"type":"damage","target":"single","multiplier":9.0 if kind=="ult" else (2.0 if kind=="skill" else 1.0)}]}
	game.catalog.CharacterData[ch.id]=ch;game.state.ownedCharacters[ch.id]=game.default_character()
	var search=Optimizer.new(game,ch.id,{"actions":1,"initialEnergy":100,"enemyDefense":0.0})
	var snap:Dictionary=search.evaluate_loadout([])
	var battle=Battle.new(game.catalog)
	battle.start({"enemies":["boss_flame_lord"],"seed":50},[{"id":ch.id,"stats":snap.stats,"energy":100}])
	battle.state.enemies[0].stats.def=0;battle.state.enemies[0].element="neutral";battle.state.currentActor=battle.state.allies[0].uid
	var result:Dictionary=battle.auto_step()
	var actual:int=result.events.filter(func(e):return e.type=="damage")[0].amount
	ck(absf(float(snap.objective)-actual)<0.000001,"future skill-array order follows actual auto ultimate priority objective=%s live=%s"%[snap.objective,actual])

func test_future_sources() -> void:
	for spec in [["damage","maxHp"],["damage","def"],["healing","maxHp"],["healing","def"],["survival","atk"]]:
		var game=Game.new("")
		var profile:String=spec[0];var source:String=spec[1]
		var id:="review_%s_%s"%[profile,source]
		var character:Dictionary=game.catalog.CharacterData.ember.duplicate(true)
		character.id=id;character.passiveId="";character.skills=[];character.relicObjective={"type":profile,"referenceStatuses":[]}
		for kind in ["normal","skill","ultimate"]:
			var sid:=id+"_"+str(kind)
			var effect:Dictionary={"type":"damage","target":"single","scalingStat":source,"multiplier":0.8 if kind=="normal" else (1.2 if kind=="skill" else 3.0)}
			if profile=="healing" and kind!="normal":effect.type="heal";effect.target="all_allies"
			if profile=="survival" and kind!="normal":effect={"type":"status","target":"self","statusId":"shield","scalingStat":source,"multiplier":2.0,"duration":2,"chance":1.0}
			game.catalog.SkillData[sid]={"type":kind,"energyGain":20,"energyCost":100,"cooldown":2 if kind=="skill" else 0,"effects":[effect],"element":"neutral"}
			character.skills.append(sid)
		game.catalog.CharacterData[id]=character;game.state.ownedCharacters[id]=game.default_character();game.state.relics=[]
		var stat_prefix:="hp" if source=="maxHp" else source
		var slots:Array=[]
		for slot in Optimizer.SLOTS:
			var options:Array=[{}]
			for variant in 2:
				var attrs:Array=[{"stat":stat_prefix+"_flat","name":"source","value":10.0 if variant==0 else 100.0},{"stat":"cri_rate","name":"crit","value":0.0 if variant==0 else 0.2},{"stat":"energy_rate","name":"energy","value":0.25 if variant==0 else 0.0}]
				var item:=relic(id+slot+str(variant),slot,"thunder_hunt" if variant==0 else ("aurora_prayer" if profile=="healing" else "star_watch"),attrs)
				game.state.relics.append(item);options.append(item)
			slots.append(options)
		var search=Optimizer.new(game,id,{"initialEnergy":75})
		prepare(search)
		var exact:=oracle(search,slots)
		var retained:Array=[]
		for slot in 5:retained.append(leaves(search,slot,search._tree_roots[slot]))
		check_leaf_bounds(search,retained);check_random_boxes(search,16)
		var result:=finish(search)
		ck(absf(exact-float(result.lowerBound))<0.000001,"future source exhaustive optimum "+id)
		ck(result.provenOptimal,"future source optimum certificate "+id)
		print("REVIEW FUTURE ",id," score=",result.lowerBound)
		if profile=="survival":
			var stats:Dictionary=search.evaluate_loadout([]).stats
			stats.atk+=1000
			var cached:float=search._evaluate(stats,[],false)
			search._evaluation_cache.clear();search._cache_keys.clear()
			var fresh:float=search._evaluate(stats,[],false)
			ck(absf(cached-fresh)<0.000001,"future ATK shield source included in survival cache")
func test_numeric_certificate() -> void:
	var game=Game.new("")
	var high:=relic("a_high","chest","",[{"stat":"atk_flat","name":"ATK","value":1e15},{"stat":"atk_pct","name":"ATK%","value":1e15}])
	var moderate:=relic("z_moderate","chest","",[{"stat":"atk_flat","name":"ATK","value":1000.0}])
	game.state.relics=[high,moderate]
	ck(game._valid_relic(high) and game._valid_relic(moderate),"extreme numeric fixture is accepted by original relic schema")
	var search=Optimizer.new(game,"ember")
	var exact:float=search.evaluate_loadout([moderate]).objective
	var result:=finish(search)
	ck(not result.provenOptimal or float(result.lowerBound)+0.000001>=exact,"numeric overflow domain never issues a false optimum certificate")
	ck(result.get("success",false) or not result.get("canApply",false),"unsupported numeric domain keeps equipment mutation unavailable")

func test_normalizer_numeric_domain() -> void:
	var game=Game.new("")
	var ch:Dictionary=game.catalog.CharacterData.ember.duplicate(true)
	ch.id="review_large_coefficient";ch.skills=["review_large_normal"];ch.passiveId="";ch.relicObjective={"type":"damage","referenceStatuses":[]}
	game.catalog.SkillData.review_large_normal={"type":"normal","energyGain":15,"effects":[{"type":"damage","target":"single","scalingStat":"atk","multiplier":1e12}],"element":"neutral"}
	game.catalog.CharacterData[ch.id]=ch;game.state.ownedCharacters[ch.id]=game.default_character()
	var search=Optimizer.new(game,ch.id)
	prepare(search)
	var leaf:Dictionary=search.evaluate_loadout([])
	ck(search._phase=="error" or search._fast_upper(leaf.stats,leaf.ownerEffects)+0.000001>=float(leaf.objective),"normalizer artificial source respects integer conversion domain")

func test_lossless_numeric_keys() -> void:
	var game=Game.new("")
	var search=Optimizer.new(game,"ember",{"otherSpeed":100.0})
	var stats:Dictionary=search.evaluate_loadout([]).stats
	var effect:Array=[{"type":"damageWhenFasterThanTarget","value":0.2}]
	stats.spd=100.0
	var equal:float=search._evaluate(stats,effect,false)
	stats.spd=100.0+1e-13
	var cached:float=search._evaluate(stats,effect,false)
	search._evaluation_cache.clear();search._cache_keys.clear()
	var actual:float=search._evaluate(stats,effect,false)
	ck(actual>equal and absf(cached-actual)<0.000001,"lossless cache keys preserve strict speed threshold across adjacent floating values")
	var item:=relic("precision","boots","",[{"stat":"spd","name":"SPD","value":100.0}])
	game.state.relics=[item]
	var before:=Optimizer.plan_fingerprint(game,"ember")
	item.subStats[0].value=100.0+1e-13
	ck(before!=Optimizer.plan_fingerprint(game,"ember"),"plan snapshot detects representable stat mutation across JSON rounding boundary")

func test_status_modified_speed_key() -> void:
	var game=Game.new("")
	game.state.ownedCharacters.zeph=game.default_character()
	var search=Optimizer.new(game,"zeph",{"otherSpeed":180.0,"targetStatuses":["spd_down"]})
	var stats:Dictionary=search.evaluate_loadout([]).stats
	stats.spd=115.0
	var first:float=search._evaluate(stats,[],false)
	stats.spd=135.0
	var cached:float=search._evaluate(stats,[],false)
	search._evaluation_cache.clear();search._cache_keys.clear()
	var actual:float=search._evaluate(stats,[],false)
	ck(actual>first and absf(cached-actual)<0.000001,"speed cache retains target status-modified passive threshold")

func test_pareto_schedules() -> void:
	for id in ["gus","ayla"]:
		var game=Game.new("")
		game.state.ownedCharacters[id]=game.default_character();game.state.relics=[]
		var slots:Array=[]
		for slot in Optimizer.SLOTS:
			var worse:=relic("z_worse_"+slot,slot,"",[{"stat":"atk_flat","name":"ATK","value":20.0},{"stat":"cri_rate","name":"crit","value":0.2}])
			var better:=relic("a_better_"+slot,slot,"",[{"stat":"atk_flat","name":"ATK","value":30.0},{"stat":"cri_rate","name":"crit","value":0.2}])
			var different:=relic("b_energy_"+slot,slot,"",[{"stat":"atk_flat","name":"ATK","value":40.0},{"stat":"cri_rate","name":"crit","value":0.8},{"stat":"energy_rate","name":"energy","value":0.5}])
			game.state.relics.append_array([worse,better,different]);slots.append([{},worse,better,different])
		var search=Optimizer.new(game,id)
		var worse:Dictionary=search._candidate(slots[0][1],0)
		var better:Dictionary=search._candidate(slots[0][2],0)
		var energy:Dictionary=better.duplicate(true);energy.v[10]=0.5
		var critical:Dictionary=better.duplicate(true);critical.v[8]=0.8
		ck(search._dominates(better,worse),"same energy/crit schedule permits monotone source dominance "+id)
		ck(not search._dominates(energy,worse),"automatic energy schedule difference survives Pareto "+id)
		ck(not search._dominates(critical,worse),"automatic critical trigger schedule difference survives Pareto "+id)
		var expected:=oracle(search,slots)
		var before:=JSON.stringify(game.state);var rng_before:int=game.rng.state
		var result:=finish(search)
		ck(absf(expected-float(result.lowerBound))<0.000001,"actual Pareto removal matches full raw oracle "+id)
		ck(result.pruned>=5 and result.provenOptimal,"Pareto fixture exercises real candidate removal "+id)
		ck(before==JSON.stringify(game.state) and rng_before==game.rng.state,"Pareto proof preserves state/RNG "+id)
