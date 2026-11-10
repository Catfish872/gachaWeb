extends "res://scripts/relic_optimizer.gd"
## Bounded, cooperative recommendation using the exact reference evaluator.
## The scan and a finite diverse quality floor are mandatory; their elapsed
## time counts against the optional refinement deadline.
const QUICK_LANE_LIMITS = [6, 2, 2, 2]
const QUICK_SLOT_LIMIT := 128
const QUICK_START_LIMIT := 4
const QUICK_PASS_LIMIT := 2
const QUICK_LOCAL_FLOOR_STEPS := 80
var _quick_started_usec := 0
var _quick_finished_usec := 0
var _quick_budget_usec := 3000000
var _quick_evaluation_cap := 2048
var _quick_budget_exhausted := false
var _quick_quality_floor_complete := false
var _quick_mandatory_quality_overrun := false
var _quick_quality_overrun_until_usec := 0
var _quick_stop_reason := ""
var _quick_seed_steps := 0
var _quick_seed_total := 0
var _quick_seed_exact_evaluations := 0
var _quick_local_steps := 0
var _quick_local_exact_evaluations := 0
var _quick_initializing := true
var _quick_has_incumbent := false
var _quick_before_eligible := false
var _quick_source_weights: Dictionary = {}
var _quick_base_stats: Dictionary = {}
var _quick_scan_usec := 0
var _quick_ranked_sets: Array = []
var _quick_lanes: Array = [{},{},{},{},{}]
var _quick_global: Array = [[],[],[],[],[]]
var _quick_current: Array = [{},{},{},{},{}]
var _quick_choice_uids: Array = [{},{},{},{},{}]
var _quick_equipped_uids: Dictionary = {}
var _quick_reference_items: Dictionary = {}
var _quick_reference_index := 0
var _quick_prepare_slot := 0
var _quick_prepare_keys: Array = []
var _quick_prepare_key := 0
var _quick_prepare_lane := 0
var _quick_prepare_rank := 0
var _quick_seed_cursor := 0
var _quick_starts: Array = []
var _quick_local_turn := 0
var _quick_snapshot_keys: Dictionary = {}
var _quick_exact_snapshots := 0

func _init(game, char_id: String, context: Dictionary = {}) -> void:
	# Set before the inherited setup, including reference/header preparation.
	_quick_started_usec = Time.get_ticks_usec()
	_quick_budget_usec = maxi(1, int(context.get("quickBudgetMs", 3000))) * 1000
	_quick_evaluation_cap = clampi(int(context.get("quickEvaluationCap", 2048)), 2, 4096)
	super(game, char_id, context)
	_quick_initializing = false
	_before = {}; _best = {}; _score = 0.0
	_groups = [{},{},{},{},{}]
	_choices = [[],[],[],[],[]]
	if not _error.is_empty():
		_quick_finished_usec = Time.get_ticks_usec()
		return
	_quick_base_stats = _stats(Sets.empty_stat_bonuses())
	# Cache skill/source weights once. Item ranking never evaluates a skill or
	# computes a cycle; every compared complete loadout uses the base evaluator.
	var effect_type := "heal" if _profile.type == "healing" else "damage"
	for sid in _catalog.CharacterData[_char_id].skills:
		for effect in _catalog.SkillData[sid].get("effects", []):
			if effect.get("type", "") != effect_type and not (_char_id=="eve" and effect.get("statusId","")=="shield"): continue
			var source := str(effect.get("scalingStat", "atk"))
			if source == "hp": source = "maxHp"
			var count := int(_context.enemyCount) if effect.get("target", "") in ["all", "all_enemies", "chain3"] else 1
			_quick_source_weights[source] = float(_quick_source_weights.get(source, 0.0)) + maxf(0.0, float(effect.get("multiplier", 1.0))) * count
	if _quick_source_weights.is_empty(): _quick_source_weights.atk = 1.0
	for id in _reference_team:
		if id == _char_id: continue
		_quick_reference_items[id] = {}
		for uid in _game.state.ownedCharacters[id].get("equippedRelics", {}).values():
			if uid != null and not str(uid).is_empty(): _quick_equipped_uids[str(uid)] = id

func _has_linear_floor_safety() -> bool:
	# Only needed for exact proof bounds, which this search never builds.
	return false

func _snapshot(items: Array) -> Dictionary:
	# Base construction asks for an empty-loadout score before our cooperative
	# scan can freeze teammate equipment. Defer only that initial request.
	if _quick_initializing: return {"objective":0.0, "relics":[], "relicUids":{}}
	return super._snapshot(items)

func advance(budget_usec: int = 4000) -> Dictionary:
	if not _error.is_empty(): _phase = "error"
	if _phase in ["ready", "error", "cancelled"]: return preview()
	var until := Time.get_ticks_usec() + clampi(budget_usec, 100, 4000)
	while Time.get_ticks_usec() < until and not _phase in ["ready", "error", "cancelled"]:
		if _phase in ["shortlist", "seed", "refine"] and _quick_limit_reached():
			_quick_finish(true)
			break
		var quality_work: bool = _phase in ["shortlist", "seed", "refine"] and not _quick_quality_floor_complete
		match _phase:
			"scan":
				var scan_started := Time.get_ticks_usec()
				_quick_scan_step()
				_quick_scan_usec += Time.get_ticks_usec() - scan_started
			"reference": _quick_reference_step()
			"baseline": _quick_baseline_step()
			"incumbent": _quick_incumbent_step()
			"shortlist": _quick_shortlist_step()
			"seed": _quick_seed_step()
			"refine": _quick_refine_step()
		if quality_work and _quick_wall_expired():
			_quick_mandatory_quality_overrun = true
			_quick_quality_overrun_until_usec = _quick_finished_usec if _quick_finished_usec > 0 else Time.get_ticks_usec()
		if not _error.is_empty():
			_phase = "error"
			_quick_finished_usec = Time.get_ticks_usec()
			break
	return preview()

func _quick_wall_expired() -> bool:
	return Time.get_ticks_usec() - _quick_started_usec >= _quick_budget_usec

func _quick_limit_reached() -> bool:
	# The exact-evaluation cap always wins, including explicit small caps.
	# The wall deadline applies once the finite quality floor is complete.
	return _quick_exact_snapshots >= _quick_evaluation_cap or (_quick_quality_floor_complete and _quick_wall_expired())

func _quick_scan_step() -> void:
	if _game.state.relics.size() != _total:
		_error = "库存已变化，请重新计算"
		return
	if _scan >= _total:
		# Include the actual comparison loadout even when it has lower stars.
		for relic in _current_items:
			var attrs := Sets.attribute_bonuses(_catalog, [relic])
			var slot := SLOTS.find(str(relic.slotId))
			for index in range(ATTRS.size()):
				var value := float(attrs[ATTRS[index]])
				if not is_finite(value):
					_error = "遗物属性无效，请检查存档"
					return
				_raw_slot_max[slot][index] = maxf(_raw_slot_max[slot][index], absf(value))
		# Absolute safety envelopes also cover finite negative flat/percent rolls.
		# One shared overflow check, before any real snapshot or integer stats.
		if not _numeric_domain_safe():
			_error = "遗物数值超出计算范围，请检查存档"
			return
		if _fingerprint_header(_game, _char_id, _context) != _initial_header:
			_error = "角色或队伍已变化，请重新计算"
			return
		_fingerprint = _hash.finish().hex_encode()
		_phase = "reference"
		return
	var relic = _game.state.relics[_scan]
	_hash.update(_relic_fingerprint_bytes(relic))
	_scan += 1
	if not relic is Dictionary: return
	var uid := str(relic.get("uid", ""))
	if uid.is_empty(): return
	if _seen_uids.has(uid):
		_error = "遗物标识重复，请检查存档"
		return
	_seen_uids[uid] = true
	var owner := str(relic.get("equippedBy", "") if relic.get("equippedBy") != null else "")
	if _quick_equipped_uids.has(uid) and owner == str(_quick_equipped_uids[uid]):
		_quick_reference_items[owner][uid] = relic.duplicate(true)
	if not owner.is_empty() and owner != _char_id: return
	var slot := SLOTS.find(str(relic.get("slotId", "")))
	if slot < 0: return
	var is_current := owner == _char_id and uid == str(_saved.get("equippedRelics", {}).get(SLOTS[slot], ""))
	if is_current: _current_items.append(relic.duplicate(true))
	var rarity := int(relic.get("rarity", 0))
	if rarity < int(_highest_rarity[slot]): return
	if rarity > int(_highest_rarity[slot]):
		_highest_rarity[slot] = rarity
		_quick_lanes[slot] = {}
		_quick_global[slot] = []
		_quick_current[slot] = {}
	var item := _quick_candidate(relic, slot)
	if item.is_empty(): return
	if is_current: _quick_current[slot] = item
	var set_key := str(item.set) if _catalog.get("RelicSets", {}).has(item.set) else ""
	if not _quick_lanes[slot].has(set_key): _quick_lanes[slot][set_key] = [[],[],[],[]]
	var lanes: Array = _quick_lanes[slot][set_key]
	for lane in range(4): _quick_rank_insert(lanes[lane], item, lane, int(QUICK_LANE_LIMITS[lane]))
	# Four bounded global lanes put strong off-set pieces first in local search.
	if _quick_global[slot].is_empty(): _quick_global[slot] = [[],[],[],[]]
	for lane in range(4): _quick_rank_insert(_quick_global[slot][lane], item, lane, int(QUICK_LANE_LIMITS[lane]))

func _quick_candidate(relic: Dictionary, slot: int) -> Dictionary:
	var attrs := Sets.attribute_bonuses(_catalog, [relic])
	for key in attrs:
		if not is_finite(float(attrs[key])):
			_error = "遗物属性无效，请检查存档"
			return {}
	for index in range(ATTRS.size()): _raw_slot_max[slot][index] = maxf(_raw_slot_max[slot][index], absf(float(attrs[ATTRS[index]])))
	# Float-only ranking is an inexpensive heuristic. Integer progression and
	# all combat/cycle calculations happen only in guarded complete snapshots.
	var stats: Dictionary = {}
	for source in ["hp", "atk", "def"]:
		var target: String = "maxHp" if source == "hp" else source
		stats[target] = (float(_quick_base_stats[target]) + float(attrs[source + "_flat"])) * (1.0 + float(attrs[source + "_pct"]))
	stats.cri = minf(1.0, float(_quick_base_stats.cri) + float(attrs.cri_rate))
	stats.criDmg = float(_quick_base_stats.criDmg) + float(attrs.cri_dmg)
	var priority := 0.0
	if _profile.type == "survival":
		priority = float(stats.maxHp) * (100.0 + float(stats.def))
	else:
		for source in _quick_source_weights:
			priority += float(stats.get(source, stats.atk)) * float(_quick_source_weights[source])
		if _profile.type == "damage": priority *= 1.0 + clampf(float(stats.cri), 0.0, 1.0) * (float(stats.criDmg) - 1.0)
	var uid := str(relic.uid)
	return {"relic":relic.duplicate(true), "slot":slot, "set":str(relic.get("setId", "")), "uid":uid, "current":uid == str(_saved.get("equippedRelics", {}).get(SLOTS[slot], "")), "useful":_useful_attributes(attrs), "priority":priority, "ranks":[priority, float(attrs.energy_rate), float(attrs.cri_rate), float(attrs.cri_dmg)]}

func _quick_rank_insert(items: Array, candidate: Dictionary, lane: int, limit: int) -> void:
	var position := 0
	while position < items.size():
		var previous: Dictionary = items[position]
		var left := float(candidate.ranks[lane])
		var right := float(previous.ranks[lane])
		if left > right or (left == right and (float(candidate.priority) > float(previous.priority) or (candidate.priority == previous.priority and _tie_item(candidate, previous)))):
			break
		position += 1
	if position >= limit: return
	items.insert(position, candidate)
	if items.size() > limit: items.pop_back()

func _quick_reference_step() -> void:
	if _quick_reference_index >= _reference_team.size():
		_selin_specs_ready = true
		_thunder_specs_ready = true
		_phase = "baseline"
		return
	var id: String = _reference_team[_quick_reference_index]
	_quick_reference_index += 1
	if id == _char_id: return
	var items: Array = []
	var found: Dictionary = _quick_reference_items[id]
	# Match equipped_relics ordering without any inventory lookup.
	for uid in _game.state.ownedCharacters[id].get("equippedRelics", {}).values():
		if uid != null and found.has(str(uid)): items.append(found[str(uid)])
	items = Sets.unique_relics(_catalog, items)
	var spec := {"id":id, "stats":_game.computed_stats_for_relic_loadout(id, items), "constellation":int(_game.state.ownedCharacters[id].constellation), "ownerEffects":Sets.evaluate(_catalog, items).ownerEffects}
	if _char_id in ["tiya", "lumi"]: _wind_team_specs.append(spec)
	if _char_id == "selin": _selin_team_specs.append(spec)
	if _char_id in ["raisa","vika","eve"]: _thunder_team_specs.append(spec)

func _quick_baseline_step() -> void:
	_before = _quick_evaluate(_current_items)
	_quick_before_eligible = true
	for slot in range(5):
		if not _quick_global[slot].is_empty() and _quick_current[slot].is_empty(): _quick_before_eligible = false
		if not _quick_global[slot].is_empty(): _quick_add_choice(slot, _quick_global[slot][0][0])
		elif not _quick_current[slot].is_empty(): _quick_before_eligible = false
	_phase = "incumbent"

func _quick_incumbent_step() -> void:
	if _quick_before_eligible:
		_best = _before.duplicate(true)
	else:
		_best = _quick_evaluate(_quick_seed_items("", 0))
	_score = float(_best.objective)
	_quick_has_incumbent = true
	_quick_add_start(_best)
	if _quick_limit_reached():
		_quick_finish(true)
		return
	_seed_sets = []
	for set_id in _catalog.get("RelicSets", {}):
		for slot in range(5):
			if _quick_lanes[slot].has(set_id):
				_seed_sets.append(set_id)
				break
	var pair_sets := mini(QUICK_START_LIMIT, _seed_sets.size())
	_quick_seed_total = 4 + _seed_sets.size() * 8 + int(pair_sets * (pair_sets - 1) / 2) * 10
	_phase = "shortlist"

func _quick_add_choice(slot: int, item: Dictionary) -> void:
	if _quick_choice_uids[slot].has(item.uid) or _choices[slot].size() >= QUICK_SLOT_LIMIT: return
	_quick_choice_uids[slot][item.uid] = true
	_choices[slot].append(item)

func _quick_shortlist_step() -> void:
	if _quick_prepare_slot >= 5:
		_phase = "seed"
		return
	var slot := _quick_prepare_slot
	if _quick_prepare_keys.is_empty():
		if not _quick_current[slot].is_empty(): _quick_add_choice(slot, _quick_current[slot])
		_quick_prepare_keys = ["@global"]
		_quick_prepare_keys.append_array(_quick_lanes[slot].keys())
	if _quick_prepare_rank >= 6:
		_quick_prepare_slot += 1
		_quick_prepare_keys = []; _quick_prepare_key = 0; _quick_prepare_lane = 0; _quick_prepare_rank = 0
		return
	var key: String = _quick_prepare_keys[_quick_prepare_key]
	var lanes: Array = _quick_global[slot] if key == "@global" else _quick_lanes[slot][key]
	if not lanes.is_empty() and _quick_prepare_rank < lanes[_quick_prepare_lane].size():
		_quick_add_choice(slot, lanes[_quick_prepare_lane][_quick_prepare_rank])
	_quick_prepare_key += 1
	if _quick_prepare_key >= _quick_prepare_keys.size():
		_quick_prepare_key = 0
		_quick_prepare_lane += 1
		if _quick_prepare_lane >= 4:
			_quick_prepare_lane = 0
			_quick_prepare_rank += 1

func _quick_seed_items(desired: String, lane: int) -> Array:
	var items: Array = []
	for slot in range(5):
		if _quick_global[slot].is_empty(): continue
		var lanes: Array = _quick_global[slot]
		if not desired.is_empty() and _quick_lanes[slot].has(desired): lanes = _quick_lanes[slot][desired]
		var chosen: Dictionary = lanes[lane][0]
		items.append(chosen.relic)
	return items

func _quick_seed_step() -> void:
	# Start with complete sets, then explicit four-piece and 2+2 layouts.
	# Pair seeds use the four strongest measured sets, keeping this work bounded.
	var full_count := 4 + _seed_sets.size() * 3
	var four_count := _seed_sets.size() * 5
	var pair_count := int(_quick_ranked_sets.size() * (_quick_ranked_sets.size() - 1) / 2) * 10
	if _quick_seed_cursor >= full_count + four_count + pair_count:
		for start in _quick_starts:
			start.cursor = 0; start.passes = 0; start.changed = false; start.active = true
		_phase = "refine"
		return
	var items: Array = []
	var desired := ""
	var lane := 0
	if _quick_seed_cursor < full_count:
		lane = _quick_seed_cursor
		if _quick_seed_cursor >= 4:
			var offset := _quick_seed_cursor - 4
			desired = str(_seed_sets[offset % _seed_sets.size()])
			lane = int(offset / _seed_sets.size())
		items = _quick_seed_items(desired, lane)
	elif _quick_seed_cursor < full_count + four_count:
		var offset := _quick_seed_cursor - full_count
		desired = str(_seed_sets[int(offset / 5)])
		items = _quick_pattern_items(desired, "", offset % 5, false)
	else:
		var offset := _quick_seed_cursor - full_count - four_count
		var pair := int(offset / 10)
		var left := 0
		var right := 1
		while pair > 0:
			right += 1
			if right >= _quick_ranked_sets.size():
				left += 1; right = left + 1
			pair -= 1
		items = _quick_pattern_items(str(_quick_ranked_sets[left].id), str(_quick_ranked_sets[right].id), offset % 5, offset % 10 >= 5)
	var primary_set := _quick_seed_cursor >= 4 and _quick_seed_cursor < 4 + _seed_sets.size()
	_quick_seed_cursor += 1
	_quick_seed_steps += 1
	var before_evaluations := _quick_exact_snapshots
	var snapshot := _quick_evaluate(items)
	_quick_seed_exact_evaluations += _quick_exact_snapshots - before_evaluations
	_quick_consider(snapshot)
	_quick_add_start(snapshot)
	if primary_set: _quick_rank_set(desired, snapshot)

func _quick_pattern_items(first: String, second: String, rotation: int, crossed: bool) -> Array:
	var items: Array = []
	for slot in range(5):
		if _quick_global[slot].is_empty(): continue
		var position := (slot + 5 - rotation) % 5
		var desired := first
		if position == 4:
			desired = ""
		elif not second.is_empty():
			var use_second: bool = position % 2 == 1 if crossed else position >= 2
			if use_second: desired = second
		var lanes: Array = _quick_global[slot]
		if not desired.is_empty() and _quick_lanes[slot].has(desired): lanes = _quick_lanes[slot][desired]
		items.append(lanes[0][0].relic)
	return items

func _quick_rank_set(id: String, snapshot: Dictionary) -> void:
	var entry := {"id":id, "score":float(snapshot.objective)}
	var position := 0
	while position < _quick_ranked_sets.size() and float(_quick_ranked_sets[position].score) >= float(entry.score): position += 1
	if position >= QUICK_START_LIMIT: return
	_quick_ranked_sets.insert(position, entry)
	if _quick_ranked_sets.size() > QUICK_START_LIMIT: _quick_ranked_sets.pop_back()

func _quick_evaluate(items: Array) -> Dictionary:
	var key := _quick_loadout_key(items)
	if _quick_snapshot_keys.has(key): return _quick_snapshot_keys[key]
	_quick_exact_snapshots += 1
	_visited += 1
	var snapshot := _snapshot(items)
	_quick_snapshot_keys[key] = snapshot
	if not is_finite(float(snapshot.objective)): _error = "装备评分无效，请重新计算"
	return snapshot

func _quick_loadout_key(items: Array) -> String:
	var ids: Array = ["", "", "", "", ""]
	for item in items:
		var slot := SLOTS.find(str(item.slotId))
		if slot >= 0: ids[slot] = str(item.uid)
	return var_to_bytes(ids).hex_encode()

func _quick_consider(snapshot: Dictionary) -> void:
	var value := float(snapshot.objective)
	if value > _score or (value == _score and _prefer_loadout(snapshot, _best)):
		_best = snapshot
		_score = value

func _quick_add_start(snapshot: Dictionary) -> void:
	var signature := var_to_bytes(_canonical_variant(snapshot.counts)).hex_encode()
	var entry := {"snapshot":snapshot, "signature":signature}
	for index in range(_quick_starts.size()):
		var previous: Dictionary = _quick_starts[index]
		if previous.signature != signature: continue
		if float(snapshot.objective) > float(previous.snapshot.objective) or (snapshot.objective == previous.snapshot.objective and _prefer_loadout(snapshot, previous.snapshot)):
			_quick_starts.remove_at(index)
			break
		return
	var position := 0
	while position < _quick_starts.size():
		var previous: Dictionary = _quick_starts[position].snapshot
		if float(snapshot.objective) > float(previous.objective) or (snapshot.objective == previous.objective and _prefer_loadout(snapshot, previous)): break
		position += 1
	if position >= QUICK_START_LIMIT: return
	_quick_starts.insert(position, entry)
	if _quick_starts.size() > QUICK_START_LIMIT: _quick_starts.pop_back()

func _quick_refine_step() -> void:
	if _quick_starts.is_empty():
		_quick_quality_floor_complete = true
		_quick_finish(false)
		return
	var active := false
	for start in _quick_starts: active = active or bool(start.active)
	if not active:
		_quick_quality_floor_complete = true
		_quick_finish(false)
		return
	var entry: Dictionary = _quick_starts[_quick_local_turn % _quick_starts.size()]
	_quick_local_turn += 1
	if not bool(entry.active): return
	var width := 1
	for choices in _choices: width = maxi(width, choices.size())
	if int(entry.cursor) >= width * 5:
		entry.passes += 1
		if not bool(entry.changed) or int(entry.passes) >= QUICK_PASS_LIMIT:
			entry.active = false
			return
		entry.cursor = 0; entry.changed = false
	var slot := int(entry.cursor) % 5
	var index := int(int(entry.cursor) / 5)
	entry.cursor += 1
	_quick_local_steps += 1
	if _quick_local_steps >= QUICK_LOCAL_FLOOR_STEPS: _quick_quality_floor_complete = true
	if index >= _choices[slot].size(): return
	var candidate: Dictionary = _choices[slot][index]
	var current: Dictionary = entry.snapshot
	if str(current.relicUids.get(SLOTS[slot], "")) == str(candidate.uid): return
	var items: Array = []
	for relic in current.relics:
		if relic.slotId != SLOTS[slot]: items.append(relic)
	items.append(candidate.relic)
	# Reuse exact snapshots across starts while retaining useful local moves.
	var before_evaluations := _quick_exact_snapshots
	var snapshot := _quick_evaluate(items)
	_quick_local_exact_evaluations += _quick_exact_snapshots - before_evaluations
	if float(snapshot.objective) > float(current.objective) or (snapshot.objective == current.objective and _prefer_loadout(snapshot, current)):
		entry.snapshot = snapshot
		entry.changed = true
	_quick_consider(snapshot)

func _quick_finish(exhausted: bool) -> void:
	_quick_budget_exhausted = exhausted or _quick_wall_expired()
	_quick_stop_reason = "evaluation_cap" if _quick_exact_snapshots >= _quick_evaluation_cap else ("time_budget" if exhausted else "search_complete")
	_quick_finished_usec = Time.get_ticks_usec()
	_phase = "ready"

func cancel() -> Dictionary:
	_cancelled = true
	_phase = "cancelled"
	_quick_stop_reason = "cancelled"
	_quick_finished_usec = Time.get_ticks_usec()
	return preview()

func preview() -> Dictionary:
	var result := super.preview()
	var finished := _quick_finished_usec if _quick_finished_usec > 0 else Time.get_ticks_usec()
	result.phase = _phase
	result.done = _phase in ["ready", "cancelled", "error"]
	result.provenOptimal = false
	result.budgetExhausted = _quick_budget_exhausted or finished - _quick_started_usec >= _quick_budget_usec
	result.elapsedMs = maxf(0.0, float(finished - _quick_started_usec) / 1000.0)
	result.searchBudgetMs = float(_quick_budget_usec) / 1000.0
	result.evaluationCap = _quick_evaluation_cap
	result.exactSnapshots = _quick_exact_snapshots
	result.beforeEligible = _quick_before_eligible
	result.searchMode = "bounded"
	result.scanUsec = _quick_scan_usec
	result.seedSteps = _quick_seed_steps
	result.seedTotal = _quick_seed_total
	result.seedExactEvaluations = _quick_seed_exact_evaluations
	result.localSteps = _quick_local_steps
	result.localExactEvaluations = _quick_local_exact_evaluations
	result.qualityFloorComplete = _quick_quality_floor_complete
	result.stopReason = "error" if not _error.is_empty() else _quick_stop_reason
	result.mandatoryQualityOverrun = _quick_mandatory_quality_overrun
	result.mandatoryQualityOverrunUsec = maxi(0, _quick_quality_overrun_until_usec - _quick_started_usec - _quick_budget_usec) if _quick_mandatory_quality_overrun else 0
	result.mandatoryQualityOverrunMs = float(result.mandatoryQualityOverrunUsec) / 1000.0
	result.canApply = _phase == "ready" and _quick_has_incumbent and not _fingerprint.is_empty() and not _cancelled and _error.is_empty() and bool(result.usefulChange)
	return result
