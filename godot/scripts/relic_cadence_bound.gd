extends RefCounted
## Cooperative upper envelope for deterministic, automatic three-skill cycles.
## Each pair comes from the same nonnegative energy multiplier q. Closed tier
## intervals deliberately retain both sides of exact boundaries. A failed or
## unsupported model returns INF, so the caller can keep its general LP bound.
const Cycle = preload("res://scripts/relic_cycle.gd")
const MAX_BASE_GAIN := 1000000
const MAX_MODEL_INTEGER := 2147483647
const ROUNDING_MARGIN := 0.00000001
const PREFIX_CACHE_LIMIT := 512

var done := false
var usable := false
var error := ""
var tiers: Array = []
var total_tiers := 0
var _skills: Array = []
var _transitions: Array = []
var _order: Array = []
var _initial_energy := 0
var _normal := -1
var _skill := -1
var _max_normal := 0
var _max_skill := 0
var _pairs: Array = []
var _cursor := 0
var _signature := ""
var _prefix_weights: Dictionary = {}

## Maxima are saturated integer action gains, in [0, 100]. Positive integral
## catalog bases use exact cross-products; other bases leave the LP in charge.
func init(skills: Array, transitions: Array, order: Array, initial_energy,
		base_normal_gain, base_skill_gain, max_normal_gain, max_skill_gain) -> bool:
	done = false
	usable = false
	error = ""
	tiers.clear()
	_pairs.clear()
	_prefix_weights.clear()
	_cursor = 0
	total_tiers = 0
	_signature = ""
	_normal = -1
	_skill = -1
	if not _valid_model(skills, transitions, order, initial_energy):
		return _fail("Cadence bounds require one normal, skill and ultimate with deterministic zero-event transitions.")
	if not _whole_in_range(base_normal_gain, 1, MAX_BASE_GAIN) or not _whole_in_range(base_skill_gain, 1, MAX_BASE_GAIN):
		return _fail("Cadence bounds require positive integral catalog energy gains within the exact arithmetic limit.")
	if not _whole_in_range(max_normal_gain, 0, 100) or not _whole_in_range(max_skill_gain, 0, 100):
		return _fail("Cadence gain maxima must be saturated integers from zero to 100.")
	_skills = skills.duplicate(true)
	_transitions = transitions.duplicate(true)
	_order = order.duplicate()
	_initial_energy = int(initial_energy)
	_max_normal = int(max_normal_gain)
	_max_skill = int(max_skill_gain)
	for index in range(_skills.size()):
		if _skills[index].type == "normal": _normal = index
		if _skills[index].type == "skill": _skill = index
	_signature = _model_signature(_skills, _order, _initial_energy)
	var base_n := int(base_normal_gain)
	var base_s := int(base_skill_gain)
	var first_skill := 0
	# For n < 100 the closed interval is [n / base_n, (n + 1) / base_n].
	# Tier 100 extends to infinity. The same holds for s. Sweep the overlap
	# directly, starting at q = 0 even when all ordinary builds have q >= 1.
	for gain_n in range(_max_normal + 1):
		while first_skill < _max_skill and first_skill < 100 and (first_skill + 1) * base_n < gain_n * base_s:
			first_skill += 1
		for gain_s in range(first_skill, _max_skill + 1):
			if gain_n < 100 and gain_s * base_n > (gain_n + 1) * base_s: break
			if gain_s < 100 and (gain_s + 1) * base_n < gain_n * base_s: continue
			_pairs.append([gain_n, gain_s])
	total_tiers = _pairs.size()
	if _pairs.is_empty(): return _fail("The cadence gain domain is empty.")
	usable = true
	return true

## Computes at most one cycle per call. A single failed tier invalidates the
## entire envelope, including earlier successful tiers.
func advance_one() -> bool:
	if done: return true
	if not usable:
		_fail("The cadence bound has not been initialized.")
		return true
	var pair: Array = _pairs[_cursor]
	var candidate: Array = _skills.duplicate(true)
	candidate[_normal].gain = int(pair[0])
	candidate[_skill].gain = int(pair[1])
	var cycle: Dictionary = Cycle.weights(candidate, _transitions, _order, _initial_energy)
	if not bool(cycle.get("success", false)):
		_fail("Cadence tier (%d, %d): %s" % [pair[0], pair[1], str(cycle.get("error", "Cycle evaluation failed."))])
		return true
	var weights: Array = cycle.get("skillWeights", [])
	if weights.size() != _skills.size():
		_fail("The cadence cycle returned an invalid skill-weight count.")
		return true
	var total := 0.0
	for weight in weights:
		if not _finite_number(weight) or float(weight) < 0.0 or float(weight) > 1.0:
			_fail("The cadence cycle returned invalid skill weights.")
			return true
		total += float(weight)
	if absf(total - 1.0) > Cycle.TOLERANCE:
		_fail("The cadence cycle weights do not sum to one.")
		return true
	tiers.append({"gainN":int(pair[0]), "gainS":int(pair[1]), "weights":weights.duplicate()})
	_cursor += 1
	done = _cursor >= _pairs.size()
	return done

## All topology, action priority and initial energy must match initialization.
## Ordinary gains vary with q; the ultimate ignores its ordinary gain.
func matches(skills: Array, transitions: Array, order: Array, initial_energy) -> bool:
	return usable and _valid_model(skills, transitions, order, initial_energy) and _model_signature(skills, order, int(initial_energy)) == _signature

## Query only within the fully constructed domain. The scalar product uses the
## original skill order and a small outward allowance for floating arithmetic.
func upper(rewards: Array, max_normal_gain, max_skill_gain) -> float:
	if not done or not usable or rewards.size() != _skills.size(): return INF
	if not _whole_in_range(max_normal_gain, 0, _max_normal) or not _whole_in_range(max_skill_gain, 0, _max_skill): return INF
	var magnitude := 1.0
	for reward in rewards:
		if not _finite_number(reward): return INF
		magnitude = maxf(magnitude, absf(float(reward)))
	var prefix := int(max_normal_gain) * 101 + int(max_skill_gain)
	var rows: Array = []
	if _prefix_weights.has(prefix):
		rows = _prefix_weights[prefix]
	else:
		var seen: Dictionary = {}
		for tier in tiers:
			if int(tier.gainN) > int(max_normal_gain) or int(tier.gainS) > int(max_skill_gain): continue
			var weights: Array = tier.weights
			# Retain every bit-distinct row. Equal scalar products alone never
			# remove a row, since later queries can have different rewards.
			var key := var_to_bytes(weights).hex_encode()
			if seen.has(key): continue
			seen[key] = true
			rows.append(weights)
		if _prefix_weights.size() >= PREFIX_CACHE_LIMIT: _prefix_weights.clear()
		_prefix_weights[prefix] = rows
	var best := -INF
	for weights in rows:
		var value := 0.0
		for index in range(rewards.size()): value += float(rewards[index]) * float(weights[index])
		if not is_finite(value): return INF
		best = maxf(best, value)
	if not is_finite(best): return INF
	return best + ROUNDING_MARGIN * magnitude

func _fail(message: String) -> bool:
	error = message
	usable = false
	done = true
	tiers.clear()
	_prefix_weights.clear()
	return false

static func _finite_number(value) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _whole_in_range(value, minimum: int, maximum: int) -> bool:
	return _finite_number(value) and float(value) >= minimum and float(value) <= maximum and float(value) == floor(float(value))

static func _valid_model(skills: Array, transitions: Array, order: Array, initial_energy) -> bool:
	if skills.size() != 3 or transitions.size() != 3 or not _whole_in_range(initial_energy, 0, 100): return false
	var types: Dictionary = {}
	for index in range(skills.size()):
		if not skills[index] is Dictionary: return false
		var source: Dictionary = skills[index]
		var type = source.get("type", "")
		if not type is String or not type in ["normal", "skill", "ultimate"] or types.has(type): return false
		types[type] = true
		for key in ["cost", "gain", "cooldown"]:
			if not _whole_in_range(source.get(key, null), 0, MAX_MODEL_INTEGER): return false
		if not transitions[index] is Array or transitions[index].is_empty(): return false
		var total := 0.0
		for branch in transitions[index]:
			if not branch is Dictionary: return false
			var probability = branch.get("p", null)
			var energy = branch.get("energy", null)
			if not _finite_number(probability) or float(probability) < 0.0 or not _whole_in_range(energy, 0, MAX_MODEL_INTEGER): return false
			if float(probability) > 0.0 and int(energy) != 0: return false
			total += float(probability)
		if not is_finite(total) or absf(total - 1.0) > Cycle.TOLERANCE: return false
	for index in order:
		if not index is int or index < 0 or index >= skills.size(): return false
	return true

static func _model_signature(skills: Array, order: Array, initial_energy: int) -> String:
	var topology: Array = []
	for skill in skills: topology.append([skill.type, int(skill.cost), int(skill.cooldown)])
	return var_to_bytes([topology, order, initial_energy]).hex_encode()
