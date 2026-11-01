extends SceneTree
const Game = preload("res://scripts/game_model.gd")
const Optimizer = preload("res://scripts/relic_optimizer.gd")
var checks := 0
var failures: Array = []
func _initialize() -> void: call_deferred("run")
func ck(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); push_error(label)
func relic(uid: String,slot: String,stat: String,value: float,set_id: String="",subs: Array=[]) -> Dictionary:
	var normalized: Array=[]
	for sub in subs:
		var entry: Dictionary=sub.duplicate();entry.name=str(entry.get("name",entry.stat));normalized.append(entry)
	return {"uid":uid,"slotId":slot,"setId":set_id,"rarity":5,"level":0,"mainStat":{"stat":stat,"name":stat,"base":value,"perLevel":0},"subStats":normalized,"equippedBy":null}
func finish(search) -> Dictionary:
	var result: Dictionary = search.preview()
	while not result.done: result = search.advance(10000)
	return result
func oracle(search,slots: Array,depth: int=0,items: Array=[]) -> float:
	if depth==5: return float(search.evaluate_loadout(items).objective)
	var maximum := -INF
	for item in slots[depth]:
		var next := items.duplicate()
		if not item.is_empty(): next.append(item)
		maximum = maxf(maximum,oracle(search,slots,depth+1,next))
	return maximum
func run() -> void:
	var game = Game.new("")
	var original := JSON.stringify(game.state)
	var rng_state: int = game.rng.state
	var empty = Optimizer.new(game,"ember")
	var result := finish(empty)
	ck(result.provenOptimal and result.done,"empty inventory converges")
	ck(result.improvement==0 and not result.canApply,"empty inventory preserves loadout")
	ck(original==JSON.stringify(game.state) and rng_state==game.rng.state,"preview preserves live state and RNG")
	ck(result.fingerprint==Optimizer.plan_fingerprint(game,"ember",result.context),"streaming fingerprint matches atomic validation")
	for char_id in game.catalog.CharacterData:
		game.state.ownedCharacters[char_id] = game.default_character()
		for level in [1,5,10]:
			game.state.ownedCharacters[char_id].level = level
			game.state.ownedCharacters[char_id].constellation = 6
			var search = Optimizer.new(game,char_id)
			ck(search.preview().before.stats==game.computed_stats_for_relic_loadout(char_id,[]),"exact progression "+char_id+" "+str(level))
			ck(search.preview().before.objective>0,"role objective positive "+char_id)
	game.state.ownedCharacters.ember = game.default_character()
	game.state.relics = []
	var slots: Array = []
	for slot in Optimizer.SLOTS:
		var options: Array = [{}]
		for index in range(2):
			var item := relic("case_"+slot+str(index),slot,"atk_flat",20.0+10*index,"flame_oath" if index==0 else "")
			game.state.relics.append(item); options.append(item)
		slots.append(options)
	var search = Optimizer.new(game,"ember")
	var exact := oracle(search,slots)
	result = finish(search)
	ck(absf(exact-result.lowerBound)<0.000001,"five-slot branch-bound equals exhaustive oracle")
	ck(result.provenOptimal and result.upperBound<=result.lowerBound+0.000001,"finite optimum certificate")
	ck(result.fingerprint==Optimizer.plan_fingerprint(game,"ember",result.context),"populated fingerprint matches")
	var before_change = result.fingerprint
	game.state.relics[0].level = 1
	ck(before_change!=Optimizer.plan_fingerprint(game,"ember",result.context),"level mutation stales plan")
	game.state.relics[0].level = 0
	game.active_slot = 2
	ck(before_change!=Optimizer.plan_fingerprint(game,"ember",result.context),"save slot mutation stales plan")
	game.active_slot = 1
	game.state.relics.append(relic("other_owned","chest","atk_flat",10000))
	game.state.relics.back().equippedBy = "zeph"
	game.state.ownedCharacters.zeph.equippedRelics.chest = "other_owned"
	result = finish(Optimizer.new(game,"ember"))
	ck(not result.after.relicUids.values().has("other_owned"),"other-character gear protected")
	var cancelled = Optimizer.new(game,"ember")
	cancelled.advance(100)
	result = cancelled.cancel()
	ck(result.cancelled and result.done and not result.canApply,"cooperative cancellation keeps state")
	ck(Optimizer.new(game,"gus").preview().context.targetStatuses.is_empty(),"Gus never assumes unavailable burn")
	ck(Optimizer.new(game,"bolt").preview().context.targetStatuses==["electrify"],"Bolt own conditional status only")
	# Threshold synergy beats independent single-piece selection.
	game.state.relics = []
	for slot in Optimizer.SLOTS:
		game.state.relics.append(relic("set_"+slot,slot,"atk_flat",20,"flame_oath"))
		game.state.relics.append(relic("plain_"+slot,slot,"atk_flat",30))
	search = Optimizer.new(game,"ember")
	result = finish(search)
	ck(int(result.after.counts.get("flame_oath",0))>=4,"whole-loadout threshold defeats greedy item stats")
	# Crit overflow is capped before the true damage expectation.
	game.state.ownedCharacters.ember.level = 10
	game.state.relics = [relic("crit_overflow","necklace","cri_rate",3.0),relic("attack_gain","necklace","atk_flat",1000.0)]
	result = finish(Optimizer.new(game,"ember"))
	ck(result.after.relicUids.necklace=="attack_gain","actual yield beats overflowing crit")
	game.state.ownedCharacters.ember = game.default_character()
	# Hypothetical scaling fixtures stay local to this in-memory catalog.
	for source in ["maxHp","def"]:
		var id: String = "virtual_"+str(source)
		var character: Dictionary = game.catalog.CharacterData.ember.duplicate(true)
		character.id=id; character.passiveId=""; character.skills=[]
		character.relicObjective={"type":"damage","label":"输出","referenceStatuses":[]}
		for kind in ["normal","skill","ultimate"]:
			var sid: String = id+"_"+str(kind)
			character.skills.append(sid)
			game.catalog.SkillData[sid]={"type":kind,"cooldown":2 if kind=="skill" else 0,"energyGain":20,"energyCost":100,"effects":[{"type":"damage","target":"single","scalingStat":source,"multiplier":1.0}],"element":"neutral"}
		game.catalog.CharacterData[id]=character; game.state.ownedCharacters[id]=game.default_character()
		game.state.relics=[relic("source_gain","chest","hp_flat" if source=="maxHp" else "def_flat",500),relic("irrelevant_atk","chest","atk_flat",5000)]
		result=finish(Optimizer.new(game,id))
		ck(result.after.relicUids.chest=="source_gain","future "+source+" scaling follows live formula")
	# Exhaustive upper-bound checks cover every prefix of a small adversarial set inventory.
	game.state.relics=[]; slots=[]
	for index in range(5):
		var slot: String = Optimizer.SLOTS[index]
		var options: Array = [{}]
		var a := relic("upper_a_"+slot,slot,"atk_flat",10,"thunder_hunt",[{"stat":"cri_rate","value":0.1}])
		var b := relic("upper_b_"+slot,slot,"atk_flat",12,"flame_oath",[{"stat":"energy_rate","value":0.15}])
		game.state.relics.append(a);game.state.relics.append(b);options.append(a);options.append(b);slots.append(options)
	for id in ["ember","gus","zeph","ayla","shana","lorin","tide"]:
		game.state.ownedCharacters[id]=game.default_character()
		search=Optimizer.new(game,id)
		while search._phase in ["scan","prune","prepare"]: search.advance(100)
		check_bounds(search,slots,0,[],search._zeros(),{})
		var exhaustive := oracle(search,slots)
		result=finish(search)
		ck(absf(result.lowerBound-exhaustive)<0.000001,"auto oracle with energy and sets "+id)
	# Auto and optimal manual policies are distinct; optimistic bounds retain both.
	game.state.relics=[]
	var auto_search=Optimizer.new(game,"ayla",{"actions":6,"initialEnergy":100})
	var manual_search=Optimizer.new(game,"ayla",{"actions":6,"initialEnergy":100,"policy":"optimal"})
	ck(auto_search.preview().context.policy=="auto","default matches actual auto priority")
	ck(manual_search.preview().before.objective>=auto_search.preview().before.objective,"manual policy is a valid upper bound")
	ck(auto_search.preview().before.objective>0,"potential healing remains meaningful with no battle HP input")
	# Equality keeps the equipped physical item, even if another UID sorts first.
	game.state.relics=[relic("z_equipped","chest","atk_flat",10),relic("a_other","chest","atk_flat",10)]
	game.state.relics[0].equippedBy="ember";game.state.ownedCharacters.ember.equippedRelics={"chest":"z_equipped"}
	search=Optimizer.new(game,"ember")
	ck(search.preview().before.is_empty(),"large inventory baseline is deferred until cooperative scan")
	result=finish(search)
	ck(result.after.relicUids.chest=="z_equipped" and not result.canApply,"exact ties retain current equipment")
	# Every shipped set receives a whole-loadout exhaustive oracle, including C6.
	var owners: Dictionary={"flame_oath":"ember","aurora_prayer":"shana","thunder_hunt":"gus","wind_voyager":"zeph","stone_bastion":"lorin","star_watch":"tide"}
	for set_id in owners:
		var id: String=owners[set_id]
		game.state.ownedCharacters[id]=game.default_character()
		game.state.ownedCharacters[id].constellation=6
		game.state.relics=[];slots=[]
		for index in range(5):
			var slot: String=Optimizer.SLOTS[index]
			var options: Array=[{}]
			var first:=relic("fullset_"+slot,slot,"atk_flat",10,set_id,[{"stat":"hp_pct","value":0.1},{"stat":"def_pct","value":0.1},{"stat":"energy_rate","value":0.08},{"stat":"spd","value":1.0}])
			var second:=relic("stronger_"+slot,slot,"atk_flat",14,"",[{"stat":"hp_pct","value":0.11},{"stat":"def_pct","value":0.11},{"stat":"cri_rate","value":0.12}])
			game.state.relics.append(first);game.state.relics.append(second);options.append(first);options.append(second);slots.append(options)
		search=Optimizer.new(game,id,{"otherSpeed":130.0})
		var exact_set:=oracle(search,slots)
		result=finish(search)
		ck(absf(exact_set-result.lowerBound)<0.000001,"all thresholds C6 exhaustive "+set_id)
		ck(result.provenOptimal and result.upperBound==result.lowerBound,"full certificate "+set_id)
	# Pure defensive gains fill empty slots while preserving the damage primary.
	game.state.ownedCharacters.ember=game.default_character()
	game.state.relics=[relic("free_hp","helmet","hp_flat",500),relic("free_def","belt","def_flat",100)]
	result=finish(Optimizer.new(game,"ember"))
	ck(result.improvement==0.0 and result.filledEmptySlots==2 and result.usefulChange and result.canApply,"free HP/DEF fills empty damage-role slots without weighting primary")
	# Floors and passive-dependent caches preserve upper bounds at extreme references.
	game.state.relics=[];game.state.ownedCharacters.ember=game.default_character()
	for defense in [100000.0,1000000000.0]:
		search=Optimizer.new(game,"ember",{"enemyDefense":defense})
		result=finish(search)
		ck(result.lowerBound==6.0 and result.upperBound==6.0 and result.provenOptimal,"minimum-one hit floor stays inside certificate "+str(defense))
	var future: Dictionary=game.catalog.CharacterData.gus.duplicate(true)
	future.id="future_energy_passive";game.catalog.CharacterData[future.id]=future
	game.state.ownedCharacters[future.id]=game.default_character()
	search=Optimizer.new(game,future.id)
	while search._phase in ["scan","prune","prepare"]:search.advance(100)
	for crit in [0.0,1.0]:
		var stats: Dictionary=game.computed_stats_for_relic_loadout(future.id,[])
		stats.cri=crit;stats.critRate=crit
		var lower: float=search._evaluate(stats,[])
		var upper: float=search._fast_upper(stats,[])
		ck(upper+0.000001>=lower,"future passiveId energy cache crit "+str(crit))
	future.skills=["gus_normal","gus_ult","gus_skill"]
	game.catalog.CharacterData[future.id]=future
	search=Optimizer.new(game,future.id,{"actions":1,"initialEnergy":100})
	var stats: Dictionary=game.computed_stats_for_relic_loadout(future.id,[])
	stats.cri=0.0
	var predicted: float=search._evaluate(stats,[])
	var reference: Dictionary=search._reference(stats,[])
	search._battle._events=[];search._battle._execute_skill(reference.actor,"gus_ult")
	var live:=0.0
	for event in search._battle._events:
		if event.type=="damage":live+=int(event.amount)
	ck(predicted==live,"future skill-array ordering respects ultimate-first actual auto")
	# Legacy numeric semantics stay unchanged; unsafe integer domains never earn proof.
	game.state.ownedCharacters.ember=game.default_character()
	game.state.relics=[relic("a_huge","chest","atk_flat",1.0e15,"",[{"stat":"atk_pct","value":1.0e15}]),relic("z_safe","chest","atk_flat",1000)]
	ck(game._valid_relic(game.state.relics[0]),"extreme-number counterexample is a legal legacy item")
	var preserved:=JSON.stringify(game.state)
	result=finish(Optimizer.new(game,"ember"))
	ck(result.phase=="error" and not result.provenOptimal and not result.canApply,"integer-overflow domain returns an explicit unproven error")
	ck(result.pruned==0 and JSON.stringify(game.state)==preserved,"numeric-domain protection keeps original inventory/formula untouched")
	# Self-shield declarations participate in the defensive objective and cache.
	var shield_character: Dictionary=game.catalog.CharacterData.lorin.duplicate(true)
	shield_character.id="future_atk_shield";shield_character.skills=["future_atk_shield_skill"]
	game.catalog.SkillData.future_atk_shield_skill={"type":"skill","energyGain":15,"cooldown":3,"effects":[{"type":"status","statusId":"shield","target":"self","scalingStat":"atk","multiplier":2.0}]}
	game.catalog.CharacterData[shield_character.id]=shield_character;game.state.ownedCharacters[shield_character.id]=game.default_character()
	game.state.relics=[relic("atk_shield_gain","chest","atk_flat",1000)]
	result=finish(Optimizer.new(game,shield_character.id))
	ck(result.after.relicUids.get("chest","")=="atk_shield_gain" and result.improvement>0,"future ATK shield affects survival source, candidate pruning and cache")
	# The artificial normalization source has its own overflow guard and fallback.
	var huge_multiplier: Dictionary=game.catalog.CharacterData.ember.duplicate(true)
	huge_multiplier.id="future_multiplier";huge_multiplier.passiveId="";huge_multiplier.skills=["future_multiplier_normal"];huge_multiplier.relicObjective.referenceStatuses=[]
	game.catalog.SkillData.future_multiplier_normal={"type":"normal","energyGain":15,"effects":[{"type":"damage","target":"single","scalingStat":"atk","multiplier":1.0e12}]}
	game.catalog.CharacterData[huge_multiplier.id]=huge_multiplier;game.state.ownedCharacters[huge_multiplier.id]=game.default_character();game.state.relics=[]
	search=Optimizer.new(game,huge_multiplier.id)
	while search._phase in ["scan","prune","prepare"]:search.advance(100)
	result=finish(search)
	ck(not search._normalizer_safe and result.provenOptimal and result.upperBound==result.lowerBound and result.lowerBound>1.0e12,"unsafe artificial normalizer falls back to exact real-source policy")
	var energy_subs: Array=[]
	for index in range(2000):energy_subs.append({"stat":"energy_rate","value":1.0e15})
	game.state.relics=[relic("huge_energy","necklace","cri_rate",0.1,"",energy_subs)]
	ck(game._valid_relic(game.state.relics[0]),"extreme energy sum uses individually legal legacy values")
	result=finish(Optimizer.new(game,"ember"))
	ck(result.phase=="error" and not result.provenOptimal,"energy-gain integer conversion is included in safe domain")
	game.state.relics=[]
	game.catalog.CharacterData[huge_multiplier.id].relicObjective.type="healing"
	result=finish(Optimizer.new(game,huge_multiplier.id))
	ck(result.provenOptimal and result.lowerBound==0.0 and not result.canApply,"a healing profile with zero healing has zero potential rather than mixed-stat weight")
	# Cache keys and state digests keep sub-JSON-precision threshold differences.
	game.state.ownedCharacters.ember=game.default_character()
	game.state.relics=[relic("precision_speed","boots","spd",5.0)]
	var fingerprint_a:=Optimizer.plan_fingerprint(game,"ember")
	game.state.relics[0].mainStat.base=5.0+0.0000000000001
	ck(fingerprint_a!=Optimizer.plan_fingerprint(game,"ember"),"lossless fingerprint detects a tiny legal speed change")
	search=Optimizer.new(game,"ember")
	var speed_stats: Dictionary=game.computed_stats_for_relic_loadout("ember",[])
	var speed_effects: Array=[{"type":"damageWhenFasterThanTarget","value":0.2}]
	speed_stats.spd=100.0
	var at_threshold: float=search._evaluate(speed_stats,speed_effects)
	speed_stats.spd=100.0+0.0000000000001
	var above_threshold: float=search._evaluate(speed_stats,speed_effects)
	search._evaluation_cache.clear()
	ck(above_threshold>at_threshold and above_threshold==search._evaluate(speed_stats,speed_effects),"lossless cache respects strict speed threshold below displayed decimal precision")
	var key_a: String=search._objective_key(speed_stats,speed_effects,false)
	speed_stats.cri+=0.0000000000001
	ck(key_a!=search._objective_key(speed_stats,speed_effects,false),"objective cache preserves complete critical probability bits")
	# Effective target speed, including status modifiers, stays in the shared formula.
	game.state.relics=[];game.state.ownedCharacters.zeph=game.default_character()
	search=Optimizer.new(game,"zeph",{"otherSpeed":180.0,"targetStatuses":["spd_down"]})
	var modified_speed: Dictionary=game.computed_stats_for_relic_loadout("zeph",[])
	modified_speed.spd=115.0
	var slow_value: float=search._evaluate(modified_speed,[])
	modified_speed.spd=135.0
	var fast_value: float=search._evaluate(modified_speed,[])
	search._evaluation_cache.clear()
	ck(fast_value>slow_value and fast_value==search._evaluate(modified_speed,[]),"raw speed cache honors status-modified average-speed passive threshold")
	# A tiny legal inventory edit that changes a live wind-set condition stales apply.
	game.state.ownedCharacters.ember=game.default_character();game.state.relics=[]
	for slot in ["helmet","chest","belt","boots"]:
		var item:=relic("micro_"+str(slot),str(slot),"spd" if slot=="boots" else "atk_flat",5.0 if slot=="boots" else 1.0,"wind_voyager")
		item.equippedBy="ember";game.state.relics.append(item);game.state.ownedCharacters.ember.equippedRelics[slot]=item.uid
	game.state.relics.append(relic("micro_better_chest","chest","atk_flat",100,"wind_voyager"))
	var boundary: float=game.computed_stats("ember").spd
	result=finish(Optimizer.new(game,"ember",{"otherSpeed":boundary}))
	ck(result.canApply,"precision stale fixture has a real improved plan")
	game.state.relics[3].mainStat.base+=0.0000000000001
	var owner_map: Dictionary=game.state.ownedCharacters.ember.equippedRelics.duplicate()
	ck(float(game.computed_stats("ember").spd)>boundary,"tiny legal edit crosses actual wind-set strict speed boundary")
	var applied: Dictionary=game.apply_relic_loadout(result,true)
	ck(not applied.success and game.state.ownedCharacters.ember.equippedRelics==owner_map,"micro-threshold mutation rejects the displayed stale plan atomically")
	print("RELIC OPTIMIZER V250: %d checks; %d failures"%[checks,failures.size()])
	quit(1 if not failures.is_empty() else 0)

func check_bounds(search,slots: Array,depth: int,items: Array,vector: PackedFloat64Array,counts: Dictionary) -> void:
	var bound: float = search._bound(vector,counts,depth)
	var exact := oracle(search,slots,depth,items)
	ck(bound+0.000001>=exact,"upper covers every descendant at depth "+str(depth))
	if depth>=3: return
	for item in slots[depth]:
		var next := items.duplicate()
		var next_counts := counts.duplicate()
		var next_vector := vector.duplicate()
		if not item.is_empty():
			next.append(item)
			var candidate: Dictionary=search._candidate(item,depth)
			next_vector=search._add(vector,candidate.v)
			var set_id: String=item.get("setId","")
			if not set_id.is_empty(): next_counts[set_id]=int(next_counts.get(set_id,0))+1
		check_bounds(search,slots,depth+1,next,next_vector,next_counts)
