extends RefCounted
## Exact, cooperative five-slot search. Bounds certify only the declared reference.
## No inventory truncation, saves, upgrades, or calls to a live combat RNG.
const Sets = preload("res://scripts/relic_sets.gd")
const Battle = preload("res://scripts/battle_model.gd")
const ATTRS = ["hp_flat","atk_flat","def_flat","hp_pct","atk_pct","def_pct","spd","spd_pct","cri_rate","cri_dmg","energy_rate"]
const SLOTS = ["helmet","chest","belt","boots","necklace"]
const EPS = 0.00000001
var _game
var _catalog: Dictionary
var _saved: Dictionary
var _cst: Dictionary
var _char_id: String
var _context: Dictionary
var _profile: Dictionary
var _battle
var _before: Dictionary
var _best: Dictionary
var _score := 0.0
var _phase := "scan"
var _error := ""
var _fingerprint := ""
var _hash := HashingContext.new()
var _scan := 0
var _total := 0
var _visited := 0
var _removed := 0
var _cancelled := false
var _groups: Array = [{},{},{},{},{}]
var _choices: Array = [[],[],[],[],[]]
var _pending: Dictionary = {}
var _pending_index := 0
var _pending_drop := false
var _dimensions: Array = []
var _suffix: Array = []
var _set_slots: Array = []
var _stack: Array = []
var _root_upper := INF
var _build_slot := 0
var _build_keys: Array = []
var _build_key := 0
var _build_item := 0
var _seen_uids: Dictionary = {}
var _current_items: Array = []
var _highest_rarity: Array = [0,0,0,0,0]
var _slot_max: Array = []
var _slot_sets: Array = [{},{},{},{},{}]
var _memo: Dictionary = {}
var _rewards: Array = []
var _transitions: Array = []
var _skills: Array = []
var _auto_skill_order: Array = []
var _evaluation_cache: Dictionary = {}
var _evaluation_calls := 0
var _evaluation_hits := 0
var _fast_bounds := 0
var _cache_keys: Array = []
var _policy_optimal := false
var _initial_header := ""
var _ordered: Array = [[],[],[],[],[]]
var _order_slot := 0
var _seed_sets: Array = []
var _seed_index := -1
var _trees: Array = [[],[],[],[],[]]
var _tree_roots: Array = []
var _tree_slot := 0
var _tree_item := 0
var _tree_level: Array = []
var _tree_next: Array = []
var _tree_pair := 0
var _best_by_set: Array = [{},{},{},{},{}]
var _by_set_items: Array = [{},{},{},{},{}]
var _tree_group_keys: Array = []
var _tree_group_index := 0
var _tree_group_item := 0
var _coordinate_pass := 0
var _coordinate_slot := 0
var _coordinate_item := 0
var _box_cache: Dictionary = {}
var _support_specs: Array = []
var _support_source := ""
var _support_base := 0.0
var _support_crit_base := 0.0
var _support_damage_base := 0.0
var _bound_coefficients: Dictionary = {}
var _bound_profiles: Dictionary = {}
var _bound_cache_hits := 0
var _linear_floor_safe := false
var _normalizer_safe := false
var _raw_slot_max: Array = []
var _domain_set_stats: Dictionary = {}
var _wind_team_specs: Array = []
var _selin_upper := false
var _selin_rewards: Array = []
var _selin_burn_attack := 0.0
var _selin_team_damage := 0.0
var _selin_team_burn_attack := 0.0
var _selin_set_amp := 0.0
var _domain_effect_factor := 1.0
var _domain_skill_factor := 1.0
var _branch_work: Dictionary = {}
var _active_upper := -INF

static func normalized_context(input: Dictionary = {}) -> Dictionary:
	var result := {"policy":"auto","actions":6,"enemyCount":3,"enemyDefense":100.0,"otherSpeed":100.0,"targetStatuses":[],"incomingRawHit":1000,"initialEnergy":0,"allowUnproven":false,"includeEquippedByOthers":false}
	for key in input: result[key] = input[key]
	result.actions = clampi(int(result.actions), 1, 8)
	result.enemyCount = clampi(int(result.enemyCount), 1, 3)
	result.enemyDefense = maxf(0.0,float(result.enemyDefense))
	result.otherSpeed = maxf(1.0,float(result.otherSpeed))
	result.incomingRawHit = maxi(1,int(result.incomingRawHit))
	result.initialEnergy = clampi(int(result.initialEnergy),0,100)
	return result

static func context_for_character(game, char_id: String, input: Dictionary = {}) -> Dictionary:
	var result := normalized_context(input)
	if not input.has("targetStatuses"):
		var character: Dictionary = game.catalog.get("CharacterData",{}).get(char_id,{})
		var declared: Dictionary = character.get("relicObjective",{})
		if declared.has("referenceStatuses"):
			result.targetStatuses = declared.referenceStatuses.duplicate()
			return result
		var statuses: Array = []
		for sid in character.get("skills",[]):
			for effect in game.catalog.get("SkillData",{}).get(sid,{}).get("effects",[]):
				var status := str(effect.get("statusId",""))
				if status in ["burn","electrify","wind_armor"] and not statuses.has(status): statuses.append(status)
		if character.get("passiveId","")=="ember_passive" and not statuses.has("burn"): statuses.append("burn")
		if character.get("passiveId","")=="bolt_passive" and not statuses.has("electrify"): statuses.append("electrify")
		result.targetStatuses = statuses
	return result

static func _canonical_variant(value: Variant) -> Variant:
	if value is Dictionary:
		var keys: Array=value.keys(); keys.sort()
		var ordered: Dictionary={}
		for key in keys: ordered[key]=_canonical_variant(value[key])
		return ordered
	if value is Array:
		var ordered: Array=[]
		for entry in value: ordered.append(_canonical_variant(entry))
		return ordered
	return value

static func _relic_fingerprint_bytes(relic: Variant) -> PackedByteArray:
	if not relic is Dictionary: return var_to_bytes(relic)
	# Canonical ordered arrays for the hot 100k-item path; extension fields remain
	# represented through a recursively key-ordered, lossless tail.
	var main: Dictionary=relic.get("mainStat",{})
	var subs: Array=[]
	for sub in relic.get("subStats",[]): subs.append(_canonical_variant(sub))
	var extras: Dictionary={}
	for key in relic:
		if not key in ["uid","slotId","setId","rarity","level","equippedBy","mainStat","subStats"]: extras[key]=relic[key]
	return var_to_bytes([relic.get("uid"),relic.get("slotId"),relic.get("setId",""),relic.get("rarity"),relic.get("level"),relic.get("equippedBy"),_canonical_variant(main),subs,_canonical_variant(extras)])

static func _fingerprint_header(game, char_id: String, context: Dictionary) -> String:
	return var_to_bytes(_canonical_variant({"version":"relic-reference-v4-wind-team-highest-rarity","slot":game.active_slot,"charId":char_id,"character":game.state.ownedCharacters.get(char_id,{}),"context":context_for_character(game,char_id,context),"characters":game.catalog.get("CharacterData",{}),"skills":game.catalog.get("SkillData",{}),"sets":game.catalog.get("RelicSets",{}),"total":game.state.relics.size(),"team":game.state.team,"ownedCharacters":game.state.ownedCharacters})).hex_encode() + "\n"

static func plan_fingerprint(game, char_id: String, context: Dictionary = {}) -> String:
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(_fingerprint_header(game,char_id,context).to_utf8_buffer())
	for relic in game.state.relics: digest.update(_relic_fingerprint_bytes(relic))
	return digest.finish().hex_encode()

func _init(game, char_id: String, context: Dictionary = {}) -> void:
	_game = game
	_char_id = char_id
	_catalog = game.catalog
	_context = context_for_character(game,char_id,context)
	_total = game.state.relics.size()
	if not game.state.ownedCharacters.has(char_id) or not _catalog.CharacterData.has(char_id):
		_error = "角色资料不可用"; _phase = "error"; return
	if _context.includeEquippedByOthers:
		_error = "请先解除其他角色装备后重新计算"; _phase = "error"; return
	_saved = game.state.ownedCharacters[char_id].duplicate(true)
	_cst = game.constellation_bonuses(char_id).duplicate(true)
	_profile = _catalog.CharacterData[char_id].get("relicObjective",{"type":"damage","label":"输出"}).duplicate(true)
	_battle = Battle.new(_catalog)
	_dimensions = _relevant_dimensions()
	for slot in range(5): _raw_slot_max.append(_zeros())
	_domain_set_stats=Sets.empty_stat_bonuses()
	for set_id in _catalog.get("RelicSets",{}):
		for bonus in _catalog.RelicSets[set_id].bonuses:
			for effect in bonus.effects:
				if effect.type=="stat": _domain_set_stats[effect.stat]+=maxf(0.0,float(effect.value))
				elif effect.type in ["damageVsStatus","damageWhenFasterThanTarget","activeSkillHealMult","skillShieldMult"]: _domain_effect_factor*=1.0+maxf(0.0,float(effect.get("value",0)))
	for sid in _catalog.CharacterData[_char_id].skills:
		for effect in _catalog.SkillData[sid].get("effects",[]): _domain_skill_factor=maxf(_domain_skill_factor,absf(float(effect.get("multiplier",effect.get("value",1.0)) if effect.get("value")!=null else effect.get("multiplier",1.0))))
	_normalizer_safe=1000000000.0*1.15*1.7*(1.0+maxf(float(_cst.normalDmgBonus),maxf(float(_cst.skillDmgBonus),float(_cst.ultDmgBonus))))*_domain_effect_factor*_domain_skill_factor<9000000000000000000.0
	if not _numeric_domain_safe(): _error="角色数值超出可证明的计算范围，请检查存档"; _phase="error"; return
	_linear_floor_safe = _has_linear_floor_safety()
	_initial_header = _fingerprint_header(game,char_id,_context)
	_hash.start(HashingContext.HASH_SHA256)
	_hash.update(_initial_header.to_utf8_buffer())
	_best = _snapshot([])
	_score = float(_best.objective)
	if _saved.get("equippedRelics",{}).is_empty(): _before = _best.duplicate(true)
	for slot in range(5): _slot_max.append(_zeros())
	for slot in range(5):
		var empty := _candidate({},slot)
		_groups[slot][empty.group] = [empty]

func _numeric_domain_safe() -> bool:
	# Existing saves accept very large finite numbers. Keep the old combat formula,
	# and reject proof domains that could cross its signed-integer conversions.
	const SAFE_INTEGER:=9000000000000000000.0
	var vector:=_zeros()
	for item in _raw_slot_max: vector=_add(vector,item)
	var attrs:=_as_dict(vector)
	for key in _domain_set_stats: attrs[key]+=_domain_set_stats[key]
	var data: Dictionary=_catalog.CharacterData[_char_id]
	var level:=clampi(int(_saved.level),1,10); var multiplier:=pow(1.1,level-1)
	var largest:=1.0
	for key in ["hp","atk","def"]:
		var base:=floorf(floorf(float(data.baseStats[key])+float(data.growthRate[key])*(level-1))*multiplier)
		var percent:=float(_cst[key+"Percent"])+(float(_saved.get("awakening",0))*0.05 if key=="hp" else 0.0)
		var raw: float=(base*(1.0+percent)+attrs[key+"_flat"])*(1.0+attrs[key+"_pct"])
		if not is_finite(raw) or raw>SAFE_INTEGER: return false
		largest=maxf(largest,raw)
	for sid in data.skills:
		var skill: Dictionary=_catalog.SkillData[sid]
		if skill.get("type","")=="ultimate": continue
		var gain:=float(skill.get("energyGain",15))*maxf(0.0,1.0+float(attrs.energy_rate))
		if not is_finite(gain) or gain>SAFE_INTEGER: return false
	var critical:=maxf(1.0,float(data.baseStats.criDmg)*multiplier+float(attrs.cri_dmg))
	# Covers the largest current source/status/type/C6 multiplier before rounding;
	# helper calls use the same neutral reference and no external rogue effects.
	var combat_upper:=largest*1.15*1.7*(1.0+maxf(float(_cst.normalDmgBonus),maxf(float(_cst.skillDmgBonus),float(_cst.ultDmgBonus))))*_domain_effect_factor*_domain_skill_factor*critical
	return is_finite(combat_upper) and combat_upper<SAFE_INTEGER

func _has_linear_floor_safety() -> bool:
	if _char_id in ["selin", "tiya", "lumi"]: return false # Team contributions and non-critical piercing are not source-homogeneous.
	# Positive permanent attributes only increase the no-relic source. Prove all
	# scored hits/heals are above their max(1, amount) floor before normalizing.
	if _profile.type=="survival": return false
	var reference:=_reference(_stats(Sets.empty_stat_bonuses()),[])
	var actor: Dictionary=reference.actor; var target: Dictionary=reference.target
	for sid in actor.skills:
		var skill: Dictionary=_catalog.SkillData[sid]
		for effect in skill.get("effects",[]):
			if _profile.type=="damage" and effect.get("type","")=="damage":
				var count:=int(_context.enemyCount) if effect.get("target","") in ["all","all_enemies","chain3"] else 1
				var chain:=1.0
				for hit in range(count):
					var mult: float=float(effect.get("multiplier",1.0))*chain*_battle._damage_multiplier(actor,target,str(skill.type),false)
					if _battle._raw_effect_damage(actor,target,skill,effect,mult,false)<1.0: return false
					chain=maxf(0.3,chain-float(effect.get("chainDecay",0.0)))
			if _profile.type=="healing" and effect.get("type","")=="heal":
				if _battle.effect_source_value(actor,effect,actor)*float(effect.get("multiplier",1.0))<1.0: return false
	if _profile.type=="healing" and _catalog.CharacterData[_char_id].get("passiveId","")=="ayla_passive" and float(actor.stats.atk)*0.4<1.0: return false
	return true

func _relevant_dimensions() -> Array:
	if _profile.type == "survival":
		var defensive: Array=[0,2,3,5]
		for sid in _catalog.CharacterData[_char_id].skills:
			var skill: Dictionary=_catalog.SkillData[sid]
			if skill.get("type","")!="skill": continue
			for effect in skill.get("effects",[]):
				if effect.get("statusId","")=="shield" and effect.get("target","") in ["self","all_allies"] and effect.get("scalingStat","")=="atk":
					for index in [1,4,6,7]:
						if not defensive.has(index): defensive.append(index)
		return defensive
	var result: Array = [6,7,8,9,10] if _profile.type == "damage" else [6,7,8,10]
	var sources: Dictionary = {}
	for sid in _catalog.CharacterData[_char_id].skills:
		for effect in _catalog.SkillData[sid].get("effects",[]):
			if effect.get("type","") == ("heal" if _profile.type == "healing" else "damage"):
				sources[str(effect.get("scalingStat","atk"))] = true
	if _catalog.CharacterData[_char_id].get("passiveId","")=="ayla_passive" or _char_id == "gus" or _char_id == "kaldi": sources.atk = true
	for source in sources:
		for dimension in ({"atk":[1,4],"hp":[0,3],"maxHp":[0,3],"def":[2,5]}.get(source,[1,4])):
			if not result.has(dimension): result.append(dimension)
	return result

func _candidate(relic: Dictionary, slot: int) -> Dictionary:
	var bonuses := Sets.attribute_bonuses(_catalog,[] if relic.is_empty() else [relic])
	var vector := PackedFloat64Array()
	for key in ATTRS: vector.append(float(bonuses[key]))
	for index in range(ATTRS.size()): _raw_slot_max[slot][index]=maxf(_raw_slot_max[slot][index],vector[index])
	if not _numeric_domain_safe():
		_error="遗物数值超出可证明的计算范围，请检查存档"; _phase="error"; return {}
	var uid := str(relic.get("uid",""))
	return {"relic":relic.duplicate(true),"v":vector,"slot":slot,"set":str(relic.get("setId","")),"group":_group_key(str(relic.get("setId","")),bonuses),"uid":uid,"current":uid == str(_saved.get("equippedRelics",{}).get(SLOTS[slot],"")),"priority":_priority(bonuses),"useful":_useful_attributes(bonuses)}

func _group_key(set_id: String,attrs: Dictionary) -> String:
	if _profile.type=="survival" or _context.policy=="optimal": return set_id
	var base_crit:=float(_catalog.CharacterData[_char_id].baseStats.cri)*pow(1.1,int(_saved.level)-1)
	return var_to_bytes([set_id,attrs.energy_rate,minf(1.0,base_crit+float(attrs.cri_rate))]).hex_encode()

func _useful_attributes(attrs: Dictionary) -> bool:
	var positive:=false
	for key in attrs:
		if float(attrs[key])<0.0: return false
		positive=positive or float(attrs[key])>0.0
	return positive

func _tie_item(a: Dictionary,b: Dictionary) -> bool:
	var old_uid = _saved.get("equippedRelics",{}).get(SLOTS[a.slot],null)
	if old_uid==null or str(old_uid).is_empty():
		var fills_a:=not str(a.uid).is_empty() and bool(a.useful)
		var fills_b:=not str(b.uid).is_empty() and bool(b.useful)
		if fills_a!=fills_b: return fills_a
	if a.current != b.current: return a.current
	return str(a.uid) <= str(b.uid)

func _dominates(a: Dictionary,b: Dictionary) -> bool:
	# Keeping the better tie identity is essential at crit caps and integer floors.
	if not _tie_item(a,b): return false
	if _profile.type!="survival" and _context.policy!="optimal":
		# Auto ultimate timing is discontinuous: preserve different energy schedules.
		if a.v[10]!=b.v[10]: return false
		var base_crit := float(_catalog.CharacterData[_char_id].baseStats.cri)*pow(1.1,int(_saved.level)-1)
		if minf(1.0,base_crit+a.v[8])!=minf(1.0,base_crit+b.v[8]): return false
	for index in _dimensions:
		if a.v[index] < b.v[index]: return false
	return true

func advance(budget_usec: int = 4000) -> Dictionary:
	if _phase in ["done","error","cancelled"]: return preview()
	var until := Time.get_ticks_usec() + clampi(budget_usec,100,10000)
	while Time.get_ticks_usec() < until and not _phase in ["done","error","cancelled"]:
		match _phase:
			"scan", "prune": _scan_step()
			"prepare": _prepare_step()
			"seed": _seed_step()
			"search": _search_step()
	return preview()

func _scan_step() -> void:
	if not _pending.is_empty():
		var list: Array = _groups[_pending.slot][_pending.group]
		if _pending_index < list.size():
			var prior: Dictionary = list[_pending_index]
			if _dominates(prior,_pending):
				_pending_drop = true; _pending_index = list.size()
			elif _dominates(_pending,prior):
				list.remove_at(_pending_index); _removed += 1
			else: _pending_index += 1
			return
		if not _pending_drop: list.append(_pending)
		else: _removed += 1
		_pending = {}; _phase = "scan"
		return
	if _scan >= _total:
		_before = _snapshot(_current_items)
		# Seed only from the eligible highest-rarity pools. The equipped loadout
		# remains the comparison baseline, even when its immediate score is higher.
		var eligible: Array = []
		for slot_index in range(5):
			var first: Dictionary = _groups[slot_index].values()[0][0].relic
			if not first.is_empty(): eligible.append(first)
		_best = _snapshot(eligible); _score = float(_best.objective)
		_fingerprint = _hash.finish().hex_encode()
		_phase = "prepare"
		return
	if _scan >= _game.state.relics.size():
		_error = "库存已变化，请重新计算"; _phase = "error"; return
	var relic = _game.state.relics[_scan]
	_hash.update(_relic_fingerprint_bytes(relic))
	_scan += 1
	if not relic is Dictionary: return
	var owner := str(relic.get("equippedBy","") if relic.get("equippedBy") != null else "")
	if not owner.is_empty() and owner != _char_id: return
	var slot := SLOTS.find(str(relic.get("slotId","")))
	var uid := str(relic.get("uid",""))
	if slot < 0 or uid.is_empty(): return
	if _seen_uids.has(uid):
		_error = "遗物标识重复，请检查存档"; _phase = "error"; return
	_seen_uids[uid] = true
	if uid == str(_saved.get("equippedRelics",{}).get(SLOTS[slot],"")):
		_current_items.append(relic.duplicate(true))
	var rarity := int(relic.get("rarity",0))
	if rarity < int(_highest_rarity[slot]): return
	if rarity > int(_highest_rarity[slot]):
		_highest_rarity[slot] = rarity
		_groups[slot].clear()
	_pending = _candidate(relic,slot)
	if _pending.is_empty(): return
	if not _groups[slot].has(_pending.group): _groups[slot][_pending.group] = []
	_pending_index = 0; _pending_drop = false; _phase = "prune"

func _prepare_step() -> void:
	if _build_slot < 5:
		if _build_keys.is_empty(): _build_keys = _groups[_build_slot].keys()
		if _build_key < _build_keys.size():
			var items: Array = _groups[_build_slot][_build_keys[_build_key]]
			if _build_item < items.size():
				var item: Dictionary = items[_build_item]
				_heap_push(_choices[_build_slot],item)
				if not _best_by_set[_build_slot].has(item.set) or float(item.priority)>float(_best_by_set[_build_slot][item.set].priority): _best_by_set[_build_slot][item.set]=item
				for index in range(ATTRS.size()): _slot_max[_build_slot][index] = maxf(_slot_max[_build_slot][index],item.v[index])
				if not str(item.set).is_empty(): _slot_sets[_build_slot][item.set] = 1
				_build_item += 1; return
			_build_key += 1; _build_item = 0; return
		_build_slot += 1; _build_keys = []; _build_key = 0; return
	if _order_slot < 5:
		if not _choices[_order_slot].is_empty():
			var item: Dictionary=_heap_pop(_choices[_order_slot])
			_ordered[_order_slot].append(item)
			if not _by_set_items[_order_slot].has(item.set): _by_set_items[_order_slot][item.set]=[]
			_by_set_items[_order_slot][item.set].append(item)
			return
		_order_slot += 1; return
	_choices = _ordered
	if _tree_slot==0 and _tree_item==0 and _support_specs.is_empty(): _make_support_specs()
	if _tree_slot<5:
		_build_tree_step(); return
	_suffix = [[],[],[],[],[],_zeros()]
	_set_slots = [{},{},{},{},{},{}]
	for depth in range(4,-1,-1):
		var present: Dictionary = _slot_sets[depth]
		_suffix[depth] = _add(_slot_max[depth],_suffix[depth+1])
		_set_slots[depth] = _set_slots[depth+1].duplicate()
		for set_id in present: _set_slots[depth][set_id] = int(_set_slots[depth].get(set_id,0))+1
	_root_upper = _box_upper(_tree_roots)
	_stack = [{"box":_tree_roots.duplicate(),"upper":_root_upper,"priority":_root_upper}]
	_seed_sets = _catalog.get("RelicSets",{}).keys()
	_phase = "seed"

func _priority(attrs: Dictionary) -> float:
	# Traversal order only: every retained candidate still receives exact evaluation.
	var stats := _stats(attrs)
	if _profile.type=="survival": return float(stats.maxHp)*(100.0+float(stats.def))
	var base := 0.0
	for sid in _catalog.CharacterData[_char_id].skills:
		for effect in _catalog.SkillData[sid].get("effects",[]):
			if effect.get("type","") == ("heal" if _profile.type=="healing" else "damage"):
				var source := str(effect.get("scalingStat","atk"))
				base += float(stats.get("maxHp" if source=="hp" else source,stats.atk))*float(effect.get("multiplier",1.0))
	return base if _profile.type=="healing" else base*(1.0+clampf(float(stats.cri),0,1)*(float(stats.criDmg)-1.0))

func _heap_push(heap: Array,item: Dictionary) -> void:
	heap.append(item)
	var index := heap.size()-1
	while index>0:
		var parent := (index-1)/2
		if float(heap[parent].priority)>=float(item.priority): break
		heap[index] = heap[parent]; index = parent
	heap[index] = item

func _heap_pop(heap: Array) -> Dictionary:
	var result: Dictionary = heap[0]
	var last: Dictionary = heap.pop_back()
	if heap.is_empty(): return result
	var index := 0
	while index*2+1<heap.size():
		var child := index*2+1
		if child+1<heap.size() and float(heap[child+1].priority)>float(heap[child].priority): child+=1
		if float(last.priority)>=float(heap[child].priority): break
		heap[index] = heap[child]; index = child
	heap[index] = last
	return result

func _seed_step() -> void:
	if _seed_index >= _seed_sets.size(): _coordinate_step(); return
	var desired := "" if _seed_index<0 else str(_seed_sets[_seed_index])
	var items: Array = []
	for slot in range(5):
		var chosen: Dictionary = _choices[slot][0]
		if not desired.is_empty() and _best_by_set[slot].has(desired): chosen=_best_by_set[slot][desired]
		if not chosen.relic.is_empty(): items.append(chosen.relic)
	var snapshot := _snapshot(items)
	if float(snapshot.objective)>_score or (float(snapshot.objective)==_score and _prefer_loadout(snapshot,_best)):
		_best=snapshot; _score=float(snapshot.objective)
	_seed_index+=1

func _coordinate_step() -> void:
	if _coordinate_pass>=2: _phase="search"; return
	if _coordinate_slot>=5: _coordinate_pass+=1; _coordinate_slot=0; _coordinate_item=0; return
	if _coordinate_item>=_choices[_coordinate_slot].size(): _coordinate_slot+=1; _coordinate_item=0; return
	var candidate: Dictionary=_choices[_coordinate_slot][_coordinate_item]
	_coordinate_item+=1
	var items: Array=[]
	for item in _best.relics:
		if item.slotId!=SLOTS[_coordinate_slot]: items.append(item)
	if not candidate.relic.is_empty(): items.append(candidate.relic)
	var snapshot:=_snapshot(items)
	if float(snapshot.objective)>_score or (float(snapshot.objective)==_score and _prefer_loadout(snapshot,_best)):
		_best=snapshot; _score=float(snapshot.objective)

func _zeros() -> PackedFloat64Array:
	var result := PackedFloat64Array(); result.resize(ATTRS.size()); result.fill(0.0); return result

func _add(a: PackedFloat64Array,b: PackedFloat64Array) -> PackedFloat64Array:
	var result := a.duplicate()
	for index in range(result.size()): result[index] += b[index]
	return result

func _optimistic_sets(counts: Dictionary, depth: int) -> Dictionary:
	var stats := Sets.empty_stat_bonuses()
	var effects: Array = []
	var profile_key:=""
	for set_id in _catalog.get("RelicSets",{}):
		var maximum := int(counts.get(set_id,0))+int(_set_slots[depth].get(set_id,0))
		for bonus in _catalog.RelicSets[set_id].get("bonuses",[]):
			if int(bonus.pieces) > maximum: continue
			profile_key+=str(set_id)+":"+str(bonus.pieces)+";"
			for effect in bonus.effects:
				if effect.type == "stat": stats[effect.stat] += maxf(0.0,float(effect.value))
				else: effects.append(effect)
	return {"statBonuses":stats,"ownerEffects":effects,"profileKey":profile_key}

func _bound(vector: PackedFloat64Array,counts: Dictionary,depth: int) -> float:
	var optimistic := _optimistic_sets(counts,depth)
	var attrs := _as_dict(_add(vector,_suffix[depth]))
	for key in optimistic.statBonuses: attrs[key] += optimistic.statBonuses[key]
	return _fast_upper(_stats(attrs),optimistic.ownerEffects,INF,optimistic.profileKey)

func _make_support_specs() -> void:
	if _profile.type=="survival": return
	var sources: Dictionary={}
	for sid in _catalog.CharacterData[_char_id].skills:
		for effect in _catalog.SkillData[sid].get("effects",[]):
			if effect.get("type","") == ("heal" if _profile.type=="healing" else "damage"):
				var source:=str(effect.get("scalingStat","atk")); sources["maxHp" if source=="hp" else source]=true
	if _catalog.CharacterData[_char_id].get("passiveId","")=="ayla_passive": sources.atk=true
	if sources.size()!=1: return
	_support_source=str(sources.keys()[0])
	var pair: Array={"atk":[1,4],"maxHp":[0,3],"def":[2,5]}.get(_support_source,[])
	if pair.is_empty(): return
	var data: Dictionary=_catalog.CharacterData[_char_id]
	var level:=int(_saved.level); var multiplier:=pow(1.1,level-1)
	var key:="hp" if _support_source=="maxHp" else _support_source
	var raw:=floorf(floorf(float(data.baseStats[key])+float(data.growthRate[key])*(level-1))*multiplier)
	_support_base=raw*(1.0+float(_cst[key+"Percent"])+(float(_saved.get("awakening",0))*0.05 if key=="hp" else 0.0))
	_support_crit_base=float(data.baseStats.cri)*multiplier
	_support_damage_base=maxf(0.0,float(data.baseStats.criDmg)*multiplier-1.0)
	var maxima:=_zeros()
	for vector in _slot_max: maxima=_add(maxima,vector)
	var bonuses:=Sets.empty_stat_bonuses()
	for set_id in _catalog.get("RelicSets",{}):
		for bonus in _catalog.RelicSets[set_id].bonuses:
			for effect in bonus.effects:
				if effect.type=="stat": bonuses[effect.stat]+=maxf(0.0,float(effect.value))
	var roots: Array=[_support_base+maxima[pair[0]]+bonuses[ATTRS[pair[0]]],1.0+maxima[pair[1]]+bonuses[ATTRS[pair[1]]],_support_crit_base+maxima[8]+bonuses.cri_rate,_support_damage_base+maxima[9]+bonuses.cri_dmg]
	for shape in [[0,1],[0,1,3],[0,1,2,3]]:
		for tilt in [0.5,1.0,2.0]:
			var indices: Array=[]; var weights: Array=[]; var norm:=1.0
			for dimension in shape:
				var scale:=maxf(0.000001,float(roots[dimension]))*(float(tilt) if dimension==0 else (1.0/float(tilt) if dimension==1 else 1.0))
				indices.append([pair[0],pair[1],8,9][dimension]); weights.append(1.0/scale); norm*=scale
			_support_specs.append({"indices":indices,"weights":weights,"norm":norm,"shape":shape})

func _joint_factor(box: Array,bonuses: Dictionary) -> float:
	if _support_specs.is_empty(): return INF
	var pair: Array={"atk":[1,4],"maxHp":[0,3],"def":[2,5]}[_support_source]
	var constants: Array=[_support_base+bonuses[ATTRS[pair[0]]],1.0+bonuses[ATTRS[pair[1]]],_support_crit_base+bonuses.cri_rate,_support_damage_base+bonuses.cri_dmg]
	var attack:=INF; var critical:=INF
	for index in range(_support_specs.size()):
		var spec: Dictionary=_support_specs[index]
		var total:=0.0
		for dimension in range(spec.shape.size()): total+=float(constants[spec.shape[dimension]])*float(spec.weights[dimension])
		for slot in range(5): total+=float(_trees[slot][box[slot]].supports[index])
		var bound:=float(spec.norm)*pow(total/spec.shape.size(),spec.shape.size())
		if spec.shape.size()==2: attack=minf(attack,bound)
		else: critical=minf(critical,bound)
	return attack if _profile.type=="healing" else attack+critical

func _build_tree_step() -> void:
	var tree: Array = _trees[_tree_slot]
	if _tree_item<_choices[_tree_slot].size():
		if _tree_group_keys.is_empty(): _tree_group_keys=_by_set_items[_tree_slot].keys()
		var group: Array=_by_set_items[_tree_slot][_tree_group_keys[_tree_group_index]]
		if _tree_group_item>=group.size(): _tree_group_index+=1; _tree_group_item=0; return
		var item: Dictionary = group[_tree_group_item]
		_tree_group_item+=1
		var sets: Dictionary = {}
		if not str(item.set).is_empty(): sets[item.set]=true
		_tree_level.append(tree.size())
		var supports:=PackedFloat64Array()
		for spec in _support_specs:
			var value:=0.0
			for index in range(spec.indices.size()): value+=item.v[spec.indices[index]]*spec.weights[index]
			supports.append(value)
		tree.append({"v":item.v,"sets":sets,"count":1,"item":item,"supports":supports})
		_tree_item+=1; return
	if _tree_level.size()==1:
		_tree_roots.append(_tree_level[0]); _tree_slot+=1; _tree_item=0; _tree_level=[]; _tree_next=[]; _tree_pair=0; _tree_group_keys=[]; _tree_group_index=0; _tree_group_item=0; return
	if _tree_pair>=_tree_level.size():
		_tree_level=_tree_next; _tree_next=[]; _tree_pair=0; return
	var left_id: int=_tree_level[_tree_pair]
	if _tree_pair+1>=_tree_level.size(): _tree_next.append(left_id); _tree_pair+=1; return
	var right_id: int=_tree_level[_tree_pair+1]
	var left: Dictionary=tree[left_id]; var right: Dictionary=tree[right_id]
	var vector: PackedFloat64Array=left.v.duplicate()
	for index in range(ATTRS.size()): vector[index]=maxf(vector[index],right.v[index])
	var sets: Dictionary=left.sets.duplicate()
	for id in right.sets: sets[id]=true
	_tree_next.append(tree.size())
	var supports: PackedFloat64Array=left.supports.duplicate()
	for index in range(supports.size()): supports[index]=maxf(supports[index],right.supports[index])
	tree.append({"v":vector,"sets":sets,"count":int(left.count)+int(right.count),"left":left_id,"right":right_id,"supports":supports})
	_tree_pair+=2

func _box_upper(box: Array) -> float:
	var box_key:=JSON.stringify(box)
	if _box_cache.has(box_key): return float(_box_cache[box_key])
	var vector:=_zeros()
	var possible: Dictionary={}
	for slot in range(5):
		var node: Dictionary=_trees[slot][box[slot]]
		vector=_add(vector,node.v)
		for id in node.sets: possible[id]=int(possible.get(id,0))+1
	var optimistic:=_optimistic_sets(possible,5)
	var attrs:=_as_dict(vector)
	for key in optimistic.statBonuses: attrs[key]+=optimistic.statBonuses[key]
	var upper:=_fast_upper(_stats(attrs),optimistic.ownerEffects,_joint_factor(box,optimistic.statBonuses),optimistic.profileKey)
	if _box_cache.size()>=32768: _box_cache.clear()
	_box_cache[box_key]=upper
	return upper

func _search_step() -> void:
	if not _branch_work.is_empty(): _branch_step(); return
	if _stack.is_empty(): _phase="done"; return
	var work: Dictionary=_heap_pop(_stack)
	if float(work.upper)+EPS<_score: return
	var box: Array=work.box
	var split_slot:=-1; var largest:=1
	for slot in range(5):
		var node: Dictionary=_trees[slot][box[slot]]
		if int(node.count)>largest: largest=int(node.count); split_slot=slot
	_visited+=1
	if split_slot<0:
		var items: Array=[]
		for slot in range(5):
			var item: Dictionary=_trees[slot][box[slot]].item
			if not item.relic.is_empty(): items.append(item.relic)
		var snapshot:=_snapshot(items)
		if float(snapshot.objective)>_score or (float(snapshot.objective)==_score and _prefer_loadout(snapshot,_best)):
			_best=snapshot; _score=float(snapshot.objective)
		return
	# Strong branching is itself cooperative: one bound per work unit.
	_active_upper=float(work.upper)
	_branch_work={"box":box,"slot":0,"child":0,"options":[],"maximum":0.0,"total":0.0,"bestMax":INF,"bestSum":INF,"bestCount":-1,"bestOptions":[]}

func _branch_step() -> void:
	var work: Dictionary=_branch_work
	if int(work.slot)>=5:
		for child in work.bestOptions:
			if float(child.upper)+EPS>=_score: _heap_push(_stack,child)
		_branch_work={}; _active_upper=-INF; return
	var slot:=int(work.slot)
	var split: Dictionary=_trees[slot][work.box[slot]]
	if int(split.count)<=1: work.slot+=1; return
	var child: int=split.left if int(work.child)==0 else split.right
	var next: Array=work.box.duplicate(); next[slot]=child
	var upper:=_box_upper(next)
	work.options.append({"box":next,"upper":upper,"priority":upper})
	work.maximum=maxf(float(work.maximum),upper); work.total+=upper; work.child+=1
	if int(work.child)<2: return
	if float(work.maximum)<float(work.bestMax) or (work.maximum==work.bestMax and (float(work.total)<float(work.bestSum) or (work.total==work.bestSum and int(split.count)>int(work.bestCount)))):
		work.bestMax=work.maximum; work.bestSum=work.total; work.bestCount=split.count; work.bestOptions=work.options
	work.options=[]; work.maximum=0.0; work.total=0.0; work.child=0; work.slot+=1

func _filled_empty(snapshot: Dictionary) -> int:
	var result:=0
	for item in snapshot.get("relics",[]):
		if not _before.get("relicUids",{}).has(item.slotId) and _useful_attributes(Sets.attribute_bonuses(_catalog,[item])): result+=1
	return result

func _prefer_loadout(a: Dictionary,b: Dictionary) -> bool:
	var filled_a:=_filled_empty(a); var filled_b:=_filled_empty(b)
	if filled_a!=filled_b: return filled_a>filled_b
	var kept_a := 0; var kept_b := 0
	var ids_a := ""; var ids_b := ""
	for slot in SLOTS:
		var current := str(_before.relicUids.get(slot,""))
		var uid_a := str(a.relicUids.get(slot,"")); var uid_b := str(b.relicUids.get(slot,""))
		if not current.is_empty():
			kept_a += int(uid_a == current); kept_b += int(uid_b == current)
		ids_a += uid_a+"\u001f"; ids_b += uid_b+"\u001f"
	return kept_a > kept_b if kept_a != kept_b else ids_a < ids_b

func _as_dict(vector: PackedFloat64Array) -> Dictionary:
	var result: Dictionary = {}
	for index in range(ATTRS.size()): result[ATTRS[index]] = vector[index]
	return result

func _stats(attrs: Dictionary) -> Dictionary:
	# Exact permanent progression order, regression-checked against game_model.
	var data: Dictionary = _catalog.CharacterData[_char_id]
	var level := clampi(int(_saved.level),1,10)
	var multiplier := pow(1.1,level-1)
	var result: Dictionary = {}
	for key in ["hp","atk","def"]:
		var value := floorf(floorf(float(data.baseStats[key])+float(data.growthRate[key])*(level-1))*multiplier)
		var percent := float(_cst[key+"Percent"])+(float(_saved.get("awakening",0))*0.05 if key=="hp" else 0.0)
		result["maxHp" if key=="hp" else key] = maxi(0 if key=="def" else 1,int(floorf((value*(1+percent)+attrs[key+"_flat"])*(1+attrs[key+"_pct"]))))
	result.spd = (floorf(float(data.baseStats.spd)*multiplier)+attrs.spd)*(1+attrs.spd_pct)
	result.cri = minf(1.0,float(data.baseStats.cri)*multiplier+attrs.cri_rate)
	result.criDmg = float(data.baseStats.criDmg)*multiplier+attrs.cri_dmg
	for key in ["normalDmgBonus","skillDmgBonus","ultDmgBonus","skillCdReduce"]: result[key] = _cst[key]
	result.energyRate = attrs.energy_rate; result.hp = result.maxHp; result.critRate = result.cri; result.critDmg = result.criDmg
	return result

func _snapshot(items: Array) -> Dictionary:
	var evaluated := Sets.evaluate(_catalog,items)
	var attrs := Sets.attribute_bonuses(_catalog,items)
	for key in evaluated.statBonuses: attrs[key] += evaluated.statBonuses[key]
	var stats := _stats(attrs)
	var uids: Dictionary = {}
	for item in items: uids[item.slotId] = item.uid
	return {"charId":_char_id,"relics":items.duplicate(true),"relicUids":uids,"stats":stats,"counts":evaluated.counts,"activeBonuses":evaluated.activeBonuses,"statBonuses":evaluated.statBonuses,"ownerEffects":evaluated.ownerEffects,"objective":_evaluate(stats,evaluated.ownerEffects)}

func evaluate_loadout(items: Array) -> Dictionary:
	return _snapshot(items)

func _reference(stats: Dictionary,effects: Array) -> Dictionary:
	var actor: Dictionary = _battle._make_ally({"id":_char_id,"stats":stats,"constellation":int(_saved.constellation),"ownerEffects":effects},0)
	var other_stats := {"maxHp":1000000000,"atk":100,"def":float(_context.enemyDefense),"spd":float(_context.otherSpeed),"cri":0.0,"criDmg":1.5}
	var target: Dictionary = _battle._make_ally({"id":"reference","stats":other_stats,"element":"neutral"},9)
	target.isAlly = false; target.passiveId = ""
	for status in _context.targetStatuses: target.statuses.append({"id":str(status),"duration":99,"value":null,"stacks":1})
	var others: Array = []
	for index in range(int(_context.enemyCount)): others.append(target.duplicate(true))
	_battle.state = {"allies":[actor],"enemies":others,"turn":1,"config":{}}
	if _char_id in ["tiya", "lumi"]:
		# Teammate equipment is fixed throughout this optimizer instance.
		if _wind_team_specs.is_empty():
			for id in _game.state.team:
				if id == null or id == _char_id or not _game.state.ownedCharacters.has(id): continue
				_wind_team_specs.append({"id":id,"stats":_game.computed_stats(id),"constellation":int(_game.state.ownedCharacters[id].constellation),"ownerEffects":Sets.evaluate(_catalog,_game.equipped_relics(id)).ownerEffects})
		for spec in _wind_team_specs: _battle.state.allies.append(_battle._make_ally(spec.duplicate(true),_battle.state.allies.size()))
		if _battle.has_status(target,"wind_armor"):
			var armor := 0.35
			for ally in _battle.state.allies:
				if ally.passiveId == "lumi_passive" and int(ally.constellation)>=6: armor=0.45
			for status in target.statuses:
				if status.id=="wind_armor": status.value=armor
			_wind_reference_buffs(_battle.state.allies)
	return {"actor":actor,"target":target}

func _fast_upper(stats: Dictionary,effects: Array,joint_factor: float = INF,profile_key: String = "") -> float:
	if not _linear_floor_safe or not _normalizer_safe or _profile.type=="survival" or (_char_id in ["gus","kaldi"] and int(_saved.constellation)>=6) or _support_source.is_empty(): return _evaluate(stats,effects,true)
	var source: String=_support_source
	var value:=float(stats.get(source,0.0))
	const NORMALIZER:=1000000000.0
	if value<=0.0 or value>NORMALIZER: return _evaluate(stats,effects,true)
	if profile_key.is_empty(): profile_key=JSON.stringify(effects)
	if not _bound_profiles.has(profile_key):
		var outgoing:=1.7*(1.0+maxf(float(stats.normalDmgBonus),maxf(float(stats.skillDmgBonus),float(stats.ultDmgBonus))))
		var healing:=1.0; var crit_energy: bool=_catalog.CharacterData[_char_id].get("passiveId","")=="gus_passive"
		for effect in effects:
			if effect.get("type","") in ["damageVsStatus","damageWhenFasterThanTarget"]: outgoing*=1.0+absf(float(effect.get("value",0)))
			if effect.get("type","")=="activeSkillHealMult": healing+=maxf(0.0,float(effect.get("value",0)))
			if effect.get("type","")=="energyOnCrit" and float(effect.get("value",0))>0.0: crit_energy=true
		var damage_round:=0.0; var heal_round:=0.0
		for sid in _catalog.CharacterData[_char_id].skills:
			var damage_error:=0.0; var heal_error:=0.0
			for effect in _catalog.SkillData[sid].get("effects",[]):
				var targets:=int(_context.enemyCount) if effect.get("target","") in ["all","all_enemies","chain3"] else (3 if effect.get("target","")=="all_allies" else 1)
				if effect.get("type","")=="damage": damage_error+=targets*(1.0+absf(float(effect.get("multiplier",1.0)))*outgoing)
				if effect.get("type","")=="heal": heal_error+=targets*(1.0+absf(float(effect.get("multiplier",1.0)))*healing)*1.15+targets
			damage_round=maxf(damage_round,damage_error); heal_round=maxf(heal_round,heal_error)
		_bound_profiles[profile_key]={"damageRound":damage_round,"healRound":heal_round,"critEnergy":crit_energy}
	var profile: Dictionary=_bound_profiles[profile_key]
	var coefficient_values: Array=[profile_key,stats.spd,stats.cri if profile.critEnergy else 0]
	for sid in _catalog.CharacterData[_char_id].skills: coefficient_values.append(int(floor(float(_catalog.SkillData[sid].get("energyGain",15))*maxf(0.0,1.0+float(stats.energyRate)))))
	var coefficient_key:=var_to_bytes(coefficient_values).hex_encode()
	var coefficient:=0.0
	if _bound_coefficients.has(coefficient_key):
		coefficient=float(_bound_coefficients[coefficient_key]); _bound_cache_hits+=1
	else:
		var normalized:=stats.duplicate()
		normalized[source]=int(NORMALIZER)
		if source=="maxHp": normalized.hp=int(NORMALIZER)
		if _profile.type=="damage": normalized.criDmg=1.0; normalized.critDmg=1.0
		coefficient=_evaluate(normalized,effects,true)/NORMALIZER
		if _bound_coefficients.size()>=8192: _bound_coefficients.clear()
		_bound_coefficients[coefficient_key]=coefficient
	_fast_bounds+=1
	var critical:=1.0+clampf(float(stats.cri),0.0,1.0)*(maxf(1.0,float(stats.criDmg))-1.0) if _profile.type=="damage" else 1.0
	var rounding:=int(_context.actions)*(value/NORMALIZER)*(critical*float(profile.damageRound)+float(profile.healRound)+1.0)+0.000001
	return coefficient*minf(value*critical,joint_factor)+rounding

func _objective_key(stats: Dictionary,effects: Array,upper: bool) -> String:
	var values: Array = [upper]
	if _profile.type=="survival":
		values.append_array([stats.maxHp,stats.def])
		if _dimensions.has(1): values.append(stats.atk)
	else:
		if _dimensions.has(0): values.append(stats.maxHp)
		if _dimensions.has(1): values.append(stats.atk)
		if _dimensions.has(2): values.append(stats.def)
		var crit_relevant: bool=_catalog.CharacterData[_char_id].get("passiveId","")=="gus_passive"
		for effect in effects:
			if effect.get("type","")=="energyOnCrit" and float(effect.get("value",0.0))>0.0: crit_relevant=true
		values.append_array([stats.cri if crit_relevant or (_profile.type=="damage" and float(stats.criDmg)!=1.0) else 0.0,stats.normalDmgBonus,stats.skillDmgBonus,stats.ultDmgBonus,stats.skillCdReduce])
		if _profile.type=="damage": values.append(stats.criDmg)
		for sid in _catalog.CharacterData[_char_id].skills:
			values.append(int(floor(float(_catalog.SkillData[sid].get("energyGain",15))*maxf(0.0,1.0+float(stats.energyRate)))))
	var kinds: Array = ["damageTakenMult","skillShieldMult"] if _profile.type=="survival" else (["activeSkillHealMult","energyOnCrit","energyOnActiveHeal"] if _profile.type=="healing" else ["damageVsStatus","damageWhenFasterThanTarget","energyOnCrit","energyOnActiveHeal","onBurnDetonation","windPierceOwner","onStatusAppliedPartyFollowUpAmp"])
	var relevant: Array = []
	var speed_relevant: bool = _catalog.CharacterData[_char_id].get("passiveId","")=="zeph_passive"
	for effect in effects:
		if effect.get("type","") in kinds:
			var entry: Dictionary=effect.duplicate(); entry.erase("setId"); entry.erase("pieces"); relevant.append(entry)
			if effect.type=="damageWhenFasterThanTarget": speed_relevant=true
	if speed_relevant: values.append(stats.spd)
	values.append(relevant)
	return var_to_bytes(values).hex_encode()

func _evaluate(stats: Dictionary,effects: Array,upper: bool = false) -> float:
	_evaluation_calls+=1
	var key := _objective_key(stats,effects,upper)
	if _evaluation_cache.has(key):
		_evaluation_hits+=1
		return float(_evaluation_cache[key])
	var reference := _reference(stats,effects)
	var actor: Dictionary = reference.actor
	var target: Dictionary = reference.target
	var result := 0.0
	if _profile.type == "survival":
		var own_shield := 0
		for sid in actor.skills:
			var skill: Dictionary = _catalog.SkillData[sid]
			if skill.get("type","") != "skill": continue
			for effect in skill.effects:
				if effect.get("statusId","")=="shield" and effect.get("target","") in ["self","all_allies"]:
					own_shield += _battle.skill_effect_amount(actor,effect,actor)
		var attacker := target.duplicate(true)
		attacker.stats.atk = int(_context.incomingRawHit); attacker.stats.cri = 0.0; attacker.statuses = []
		actor.c6Used = true # Repeatable full-HP index excludes one-use immunity.
		var incoming: float = _battle.expected_effect_damage(attacker,actor,{"type":"enemy","element":"neutral"},{"type":"damage","multiplier":1.0,"scalingStat":"atk"})
		result = (float(actor.maxHp)+own_shield)*float(_context.incomingRawHit)/maxf(1.0,incoming)
	elif _char_id == "selin":
		result = _evaluate_selin(actor, target, upper)
	elif _char_id in ["tiya", "lumi"]:
		result = _evaluate_wind(actor, target, upper)
	else:
		_prepare_skills(actor,target)
		_policy_optimal = upper or _context.policy=="optimal"
		_memo.clear()
		result = _value(int(_context.actions),int(_context.initialEnergy),0)
		if _profile.type == "healing" and actor.passiveId == "ayla_passive": result += int(_context.actions)*maxi(1,int(actor.stats.atk*0.4))
	if _evaluation_cache.size() >= 2048:
		_evaluation_cache.erase(_cache_keys.pop_front())
	_evaluation_cache[key] = result; _cache_keys.append(key)
	return result

func _prepare_skills(actor: Dictionary,target: Dictionary) -> void:
	_skills = []; _rewards = []; _transitions = []
	var crit := clampf(float(actor.stats.cri),0.0,1.0)
	for sid in actor.skills:
		var skill: Dictionary = _catalog.SkillData[sid]
		var reward := 0.0; var hits := 0; var healing := false
		for effect in skill.get("effects",[]):
			var target_type := str(effect.get("target","single"))
			var count := int(_context.enemyCount) if target_type in ["all","all_enemies","chain3"] else (3 if target_type == "all_allies" else 1)
			if effect.type == "damage":
				var chain := 1.0
				for hit in range(count):
					if _profile.type == "damage":
						reward += _battle.expected_effect_damage(actor,target,skill,effect,chain)
						if actor.id == "gus" and int(actor.constellation)>=6:
							var normal: Dictionary = _catalog.SkillData.gus_normal
							reward += crit*0.4*_battle.predict_effect_damage(actor,target,normal,normal.effects[0],false,true,1.0+float(actor.stats.normalDmgBonus))
						if actor.id == "kaldi" and int(actor.constellation)>=6 and skill.type == "ultimate" and _context.targetStatuses.has("burn"):
							reward += _battle.predict_effect_damage(actor,target,{"type":"follow_up","element":"fire"},{"multiplier":0.8,"rawAtk":true},false,true)
					hits += 1
					chain = maxf(0.3,chain-float(effect.get("chainDecay",0.0)))
			elif effect.type == "heal":
				healing = true
				if _profile.type == "healing":
					var amount: int = _battle.skill_effect_amount(actor,effect,actor)
					reward += count*amount
					if actor.passiveId == "shana_passive":
						reward += (2 if target_type=="all_allies" else (0 if target_type=="self" else 1))*int(amount*0.15)
		var branches: Array = [{"p":1.0,"crits":0}]
		for hit in range(hits if actor.passiveId=="gus_passive" or _battle.owner_effect_sum(actor,"energyOnCrit")>0.0 else 0):
			var next: Dictionary = {}
			for branch in branches:
				for is_crit in [0,1]:
					var chance: float = crit if is_crit else 1.0-crit
					var k: int = int(branch.crits)+int(is_crit)
					next[k] = float(next.get(k,0.0))+float(branch.p)*chance
			branches = []
			for k in next:
				if next[k]>0: branches.append({"p":next[k],"crits":k})
		var transitions: Array = []
		for branch in branches:
			var energy := int(branch.crits)*5 if actor.passiveId=="gus_passive" else 0
			if branch.crits>0: energy += int(_battle.owner_effect_sum(actor,"energyOnCrit"))
			if healing: energy += int(_battle.owner_effect_sum(actor,"energyOnActiveHeal"))
			if actor.id=="ember" and int(actor.constellation)>=6 and skill.type=="normal":
				transitions.append({"p":float(branch.p)*0.4,"energy":energy})
				transitions.append({"p":float(branch.p)*0.6,"energy":energy+10})
			else: transitions.append({"p":branch.p,"energy":energy})
		var merged: Dictionary={}
		for branch in transitions: merged[branch.energy]=float(merged.get(branch.energy,0.0))+float(branch.p)
		transitions=[]
		for energy in merged: transitions.append({"energy":energy,"p":merged[energy]})
		_skills.append({"type":skill.type,"cost":int(skill.get("energyCost",100)),"gain":_battle.action_energy_gain(actor,skill),"cooldown":maxi(1,int(skill.get("cooldown",0))-int(actor.stats.skillCdReduce)) if int(skill.get("cooldown",0))>0 else 0})
		_rewards.append(reward); _transitions.append(transitions)
	_auto_skill_order=[]
	for index in range(_skills.size()):
		if _skills[index].type=="ultimate": _auto_skill_order.append(index)
	for index in range(_skills.size()-1,-1,-1):
		if _skills[index].type=="skill": _auto_skill_order.append(index)
	for index in range(_skills.size()):
		if not _skills[index].type in ["skill","ultimate"]: _auto_skill_order.append(index)

func _value(turns: int,energy: int,cooldown: int) -> float:
	if turns<=0: return 0.0
	var key := turns*10000+energy*20+cooldown
	if _memo.has(key): return float(_memo[key])
	var best := 0.0
	for index in _auto_skill_order:
		var skill: Dictionary = _skills[index]
		if skill.type=="ultimate" and energy<skill.cost: continue
		if skill.type=="skill" and cooldown>0: continue
		var next_energy := 0 if skill.type=="ultimate" else mini(100,energy+int(skill.gain))
		var next_cd := maxi(0,int(skill.cooldown)-1) if skill.type=="skill" else maxi(0,cooldown-1)
		var value := float(_rewards[index])
		for branch in _transitions[index]: value += float(branch.p)*_value(turns-1,mini(100,next_energy+int(branch.energy)),next_cd)
		best = maxf(best,value)
		if not _policy_optimal: break
	_memo[key] = best
	return best

func cancel() -> Dictionary:
	_cancelled = true; _phase = "cancelled"; _stack.clear(); _branch_work={}; _active_upper=-INF; return preview()

func preview() -> Dictionary:
	var upper := _score if _phase=="done" else _root_upper
	if _phase=="search":
		upper = maxf(_score,float(_stack[0].upper)) if not _stack.is_empty() else _score
		upper=maxf(upper,_active_upper)
	var counts: Array = []
	for choices in _choices: counts.append(choices.size())
	var improvement := _score-float(_before.get("objective",0.0))
	var filled:=_filled_empty(_best) if not _before.is_empty() else 0
	var useful:bool=not _before.is_empty() and _best.get("relicUids",{}) != _before.get("relicUids",{})
	var proven := not _cancelled and _phase=="done" and upper<=_score
	var objective := str(_profile.get("type","damage"))
	return {"success":_error.is_empty(),"error":_error,"charId":_char_id,"context":_context.duplicate(true),"fingerprint":_fingerprint,"phase":_phase,"done":_phase in ["done","cancelled","error"],"cancelled":_cancelled,"provenOptimal":proven,"lowerBound":_score,"upperBound":upper,"gap":maxf(0.0,upper-_score)/maxf(absf(_score),EPS),"scanned":_scan,"total":_total,"visited":_visited,"pruned":_removed,"highestRarities":_highest_rarity.duplicate(),"candidateCounts":counts,"evaluationCalls":_evaluation_calls,"evaluationCacheHits":_evaluation_hits,"fastBounds":_fast_bounds,"boundCacheHits":_bound_cache_hits,"frontierNodes":_stack.size(),"costGold":0,"before":_before.duplicate(true),"after":_best.duplicate(true),"roleLabel":str(_profile.get("label","输出")),"objectiveShortLabel":("队伍贡献" if _char_id in ["selin","lumi"] else {"damage":"参考输出","healing":"潜在治疗","survival":"承伤能力"}.get(objective,objective)),"objectiveLabel":("六次行动协同收益" if _char_id in ["selin","lumi"] else {"damage":"参考场景六次行动期望伤害","healing":"参考场景六次行动潜在治疗","survival":"施放自身护盾后的有效承伤"}.get(objective,objective)),"assumptions":_assumptions(),"improvement":improvement,"filledEmptySlots":filled,"usefulChange":useful,"canApply":not _fingerprint.is_empty() and not _cancelled and _error.is_empty() and useful}

func _assumptions() -> Array:
	if _char_id in ["tiya", "lumi"]: return ["%d 次自身行动，按自动优先级与实际充能、冷却计算；目标为 %d 个中性敌人，防御 %.0f。" % [int(_context.actions),int(_context.enemyCount),float(_context.enemyDefense)], "按当前编队、破甲和可触发套装持续覆盖，计入缇娅非暴击贯穿；露弥另计队友每行动的平均技能增益。", "这是固定编队的输出与协同参考；护盾、减伤、生存、行动顺序及状态起手另在实战发挥作用。"]
	if _char_id == "selin": return ["按当前编队统计自身输出、引爆和队友燃烧增益；目标维持6回合燃烧。", "六次行动内计入充能、终结技覆盖与套装首次引爆后的生效时机。"]
	if _profile.get("type","")=="survival": return ["满血施放一次自身战技护盾，以中性基础伤害 %d 的直接攻击计算等效生命。"%int(_context.incomingRawHit),"采用真实防御、减伤及满血格挡期望；一次性无敌、队友护盾、持续回复和实战战术另行发挥作用。","同收益先补齐空槽，再保留已有装备；仅使用未装备和当前角色遗物，等级与金币保持原样。"]
	var result: Array = ["%d 次自身行动，起始能量 %d；按自动战斗优先级（终结技→战技→普攻），速度仅参与条件判定。"%[int(_context.actions),int(_context.initialEnergy)],"%d 个持续存活的中性敌人，防御 %.0f、其他单位速度 %.0f；自身可施加状态的条件潜能：%s（本基准按全程覆盖计算）。"%[int(_context.enemyCount),float(_context.enemyDefense),float(_context.otherSpeed),("、".join(_context.targetStatuses) if not _context.targetStatuses.is_empty() else "无")],"真实技能缩放、暴击封顶、整套阈值、命座及能量触发；固定参考场景的最优性与具体战斗结果分别展示。"]
	if _context.policy=="optimal": result[0] = "%d 次自身行动；显式选择最优合法手动技能策略，速度仅参与条件判定。"%int(_context.actions)
	if _profile.get("type","")=="healing": result.append("三名友方持续有足够缺失生命：统计主动治疗和角色直接治疗被动；满血实际恢复为零，再生与护盾单独发挥作用。")
	else: result.append("统计自身直接伤害与直接追击；队友增益、控制收益及目标自身属性决定的持续伤害单独发挥作用。")
	return result

func _evaluate_selin(actor: Dictionary, target: Dictionary, upper: bool) -> float:
	_selin_upper = upper
	_prepare_skills(actor, target)
	_policy_optimal = upper or _context.policy == "optimal"
	_selin_team_damage = 0.0
	_selin_team_burn_attack = 0.0
	for id in _game.state.team:
		if id == null or id == _char_id or not _game.state.ownedCharacters.has(id): continue
		var friend: Dictionary = _battle._make_ally({"id":id,"stats":_game.computed_stats(id),"constellation":int(_game.state.ownedCharacters[id].constellation),"ownerEffects":Sets.evaluate(_catalog,_game.equipped_relics(id)).ownerEffects},1)
		var average := 0.0
		for sid in friend.skills:
			var skill: Dictionary = _catalog.SkillData[sid]
			for effect in skill.get("effects", []):
				if effect.get("type", "") != "damage": continue
				var targets := int(_context.enemyCount) if effect.get("target", "") in ["all","all_enemies","chain3"] else 1
				# Divide out the existing rare bucket before adding 80 percentage points.
				var innate := 0.2 if friend.passiveId == "kaldi_passive" else (0.7 if int(friend.constellation)>=6 else 0.4) if friend.passiveId == "cinder_passive" and skill.type in ["skill","ultimate"] else 0.0
				average += targets * _battle.expected_effect_damage(friend,target,skill,effect) / (1.0 + innate)
		_selin_team_damage += average / maxf(1.0,float(friend.skills.size()))
		var can_burn: bool = friend.get("passiveId", "") == "ember_passive"
		for sid in friend.skills:
			for effect in _catalog.SkillData[sid].get("effects", []):
				if effect.get("statusId", "") == "burn": can_burn = true
		if can_burn: _selin_team_burn_attack = maxf(_selin_team_burn_attack,float(friend.stats.atk))
	_selin_burn_attack = float(actor.stats.atk)
	_selin_set_amp = 0.0
	var direct_amp := 0.0
	for effect in actor.ownerEffects:
		if effect.get("type", "") == "onBurnDetonation":
			_selin_set_amp = maxf(_selin_set_amp,float(effect.get("partyBurnAmp",0.4)))
			direct_amp = maxf(direct_amp,float(effect.get("ownerDirectAmp",0.25)))
	_selin_rewards = []
	for lit in [false,true]:
		var rewards: Array = []
		actor.statuses = [{"id":"ember_lantern_direct","duration":2,"value":direct_amp}] if lit else []
		for sid in actor.skills:
			var skill: Dictionary = _catalog.SkillData[sid]
			var reward := 0.0
			for effect in skill.get("effects", []):
				if effect.get("type", "") == "damage":
					var count := int(_context.enemyCount) if effect.get("target", "") in ["all","all_enemies","chain3"] else 1
					reward += count * _battle.expected_effect_damage(actor,target,skill,effect)
			if skill.type == "ultimate" and int(actor.constellation) >= 6:
				reward += int(_context.enemyCount) * _battle.predict_effect_damage(actor,target,{"type":"follow_up","element":"fire"},{"multiplier":0.6,"rawAtk":true},false,true)
			# Current active action's detonation sees only the previously active set.
			reward += int(_context.enemyCount) * _selin_burn_attack * 0.156 * (1.0 + (_selin_set_amp if lit else 0.0))
			rewards.append(reward)
		_selin_rewards.append(rewards)
	_memo.clear()
	return _selin_value(int(_context.actions),int(_context.initialEnergy),0,0,false)

func _selin_value(turns: int, energy: int, cooldown: int, aura: int, lit: bool) -> float:
	if turns <= 0: return 0.0
	var key := str([turns,energy,cooldown,aura,lit])
	if _memo.has(key): return float(_memo[key])
	var best := 0.0
	for index in _auto_skill_order:
		var skill: Dictionary = _skills[index]
		if skill.type == "ultimate" and energy < skill.cost: continue
		if skill.type == "skill" and cooldown > 0: continue
		var next_energy := 0 if skill.type == "ultimate" else mini(100,energy+int(skill.gain))
		var next_cd := maxi(0,int(skill.cooldown)-1) if skill.type == "skill" else maxi(0,cooldown-1)
		var active_aura := 2 if skill.type == "ultimate" else aura
		var value := float(_selin_rewards[int(lit)][index])
		value += _selin_team_damage * (0.8 if active_aura > 0 else 0.0)
		var burn_source := maxf(_selin_burn_attack, _selin_team_burn_attack)
		var burn_deepening := 1.8 if _selin_team_burn_attack > _selin_burn_attack and active_aura > 0 else 1.0
		if _selin_upper:
			# Keep a monotone safe bound when the strongest burn source changes owner.
			burn_source = maxf(_selin_burn_attack, _selin_team_burn_attack * (1.8 if active_aura > 0 else 1.0))
			burn_deepening = 1.0
		# Ordinary burn keeps its strongest source; team baseline cancels between loadouts.
		value += int(_context.enemyCount) * burn_source * 0.18 * (1.0 + _selin_set_amp) * burn_deepening
		for branch in _transitions[index]: value += float(branch.p)*_selin_value(turns-1,mini(100,next_energy+int(branch.energy)),next_cd,maxi(0,active_aura-1),true)
		best = maxf(best,value)
		if not _policy_optimal: break
	_memo[key] = best
	return best

# These scores use maintained armor/party buffs, not a hidden battle simulation.
# Teammate actions are averaged equally; the optimized unit retains its legal DP.
func _wind_can_apply_armor(unit: Dictionary) -> bool:
	for sid in unit.skills:
		for effect in _catalog.SkillData[sid].get("effects",[]):
			if effect.get("statusId","")=="wind_armor": return true
	return false

func _wind_reference_buffs(allies: Array) -> void:
	for source in allies:
		if not _wind_can_apply_armor(source): continue
		for effect in source.get("ownerEffects",[]):
			if effect.get("type","")!="onStatusAppliedPartyFollowUpAmp" or effect.get("statusId","")!="wind_armor": continue
			for friend in allies:
				var found := false
				for status in friend.statuses:
					if status.id==effect.get("buffId","wind_oath"):
						status.value=maxf(float(status.value),float(effect.value)); found=true
				if not found: friend.statuses.append({"id":effect.get("buffId","wind_oath"),"duration":99,"value":effect.value,"followUpTag":effect.get("followUpTag","innate_piercing")})

func _wind_skill_targets(skill: Dictionary) -> int:
	var count := 0
	for effect in skill.get("effects",[]):
		if effect.get("type","")=="damage": count=maxi(count,int(_context.enemyCount) if effect.get("target","") in ["all","all_enemies","chain3"] else 1)
	return count

func _wind_innate_reference(unit: Dictionary,target: Dictionary,skill: Dictionary) -> float:
	if unit.passiveId!="tiya_passive" or not _battle.has_status(target,"wind_armor"): return 0.0
	var coefficient: float = (0.66 if int(unit.constellation)>=6 else 0.60)*(1.0+float(_battle._timed_follow_up_amp(unit,"innate_piercing")))
	return _wind_skill_targets(skill)*_battle.predict_effect_damage(unit,target,{"type":"follow_up","element":"wind"},{"multiplier":coefficient,"defPierce":1.0,"rawAtk":true},false,true)

func _wind_average_damage(unit: Dictionary,target: Dictionary) -> float:
	var result := 0.0
	for sid in unit.skills:
		var skill: Dictionary=_catalog.SkillData[sid]
		for effect in skill.get("effects",[]):
			if effect.get("type","")!="damage": continue
			var count := int(_context.enemyCount) if effect.get("target","") in ["all","all_enemies","chain3"] else 1
			var chain := 1.0
			for hit in range(count):
				result+=_battle.expected_effect_damage(unit,target,skill,effect,chain)
				chain=maxf(0.3,chain-float(effect.get("chainDecay",0.0)))
		result+=_wind_innate_reference(unit,target,skill)
	return result/maxf(1.0,float(unit.skills.size()))

func _evaluate_wind(actor: Dictionary,target: Dictionary,upper: bool) -> float:
	_prepare_skills(actor,target)
	for index in range(actor.skills.size()): _rewards[index]+=_wind_innate_reference(actor,target,_catalog.SkillData[actor.skills[index]])
	_policy_optimal=upper or _context.policy=="optimal"
	_memo.clear()
	var result := _value(int(_context.actions),int(_context.initialEnergy),0)
	if actor.passiveId!="lumi_passive" or not _battle.has_status(target,"wind_armor"): return result
	var full_allies: Array=_battle.state.allies
	var full := 0.0
	for friend in full_allies:
		if friend.uid!=actor.uid: full+=_wind_average_damage(friend,target)
	var base_allies: Array=[]
	var other_armor := false
	for friend in full_allies:
		if friend.uid==actor.uid: continue
		var copy: Dictionary=friend.duplicate(true)
		copy.statuses=[]
		base_allies.append(copy)
		other_armor=other_armor or _wind_can_apply_armor(copy)
	var base_target: Dictionary=target.duplicate(true)
	for index in range(base_target.statuses.size()-1,-1,-1):
		if base_target.statuses[index].id=="wind_armor":
			if other_armor: base_target.statuses[index].value=0.35
			else: base_target.statuses.remove_at(index)
	_battle.state.allies=base_allies
	if other_armor: _wind_reference_buffs(base_allies)
	var base := 0.0
	for friend in base_allies: base+=_wind_average_damage(friend,base_target)
	_battle.state.allies=full_allies
	return result+int(_context.actions)*maxf(0.0,full-base)
