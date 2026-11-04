extends RefCounted
## Long-run automatic action frequencies, independent of damage and combat RNG.
## A renewal ends after an ultimate: its energy reset leaves only event energy
## and the remaining shared skill cooldown. Rewards include the ending ultimate.
const CACHE_LIMIT := 512
const STATE_LIMIT := 32768
const DEPTH_LIMIT := 512
const TOLERANCE := 0.000000001
static var _cache: Dictionary = {}
static var _cache_order: Array = []

## skillAuraWeights[i] is the fraction of ALL actions that use skill i while
## the two-action ultimate aura is active. It includes the ultimate itself.
## Each reachable recurrent class is normalized by its own expected cycle length
## before mixing by entrance probability; mixing lengths first would be biased.
static func weights(skills: Array, transitions: Array, order: Array = [], initial_energy: int = 0) -> Dictionary:
	# Exact raw inputs are sufficient to identify the result. Check them before
	# rebuilding and sorting the normalized model on every warm cache hit.
	var signature := var_to_bytes([skills, transitions, order, clampi(initial_energy,0,100)]).hex_encode()
	if _cache.has(signature):
		var cached: Dictionary = _cache[signature].duplicate(true)
		cached.cacheHit = true
		return cached
	var model := _model(skills, transitions, order)
	if not model.get("error", "").is_empty(): return _failure(model.error)
	var initial := _state(clampi(initial_energy, 0, 100), 0, 0, model.stride)
	var result := _deterministic(model, initial) if model.deterministic else _regenerative(model, initial)
	result.cacheHit = false
	if result.get("success", false):
		if _cache_order.size() >= CACHE_LIMIT: _cache.erase(_cache_order.pop_front())
		_cache[signature] = result.duplicate(true)
		_cache_order.append(signature)
	return result

## Independent finite-horizon expectation for diagnostics; no sampling or RNG.
static func finite_weights(skills: Array, transitions: Array, order: Array = [], actions: int = 6, initial_energy: int = 0) -> Dictionary:
	var model := _model(skills, transitions, order)
	if not model.get("error", "").is_empty(): return _failure(model.error)
	if actions <= 0: return _failure("The finite horizon must contain at least one action.")
	var states: Dictionary = {_state(clampi(initial_energy, 0, 100), 0, 0, model.stride): 1.0}
	var counts := _zeros(skills.size())
	var aura_counts := _zeros(skills.size())
	var visited: Dictionary = {}
	for _turn in range(actions):
		var next: Dictionary = {}
		for key in states:
			visited[key] = true
			var state := _unpack(key, model.stride)
			var index := _choose(model, state[0], state[1])
			if index < 0: return _failure("The automatic order has no legal action.")
			var mass := float(states[key])
			counts[index] += mass
			if model.skills[index].type == "ultimate" or state[2] > 0: aura_counts[index] += mass
			var branches := _next(model, state, index)
			for target in branches: next[target] = float(next.get(target, 0.0)) + mass * float(branches[target])
		states = next
	var result := _result(counts, aura_counts, float(actions), "finite_expectation", visited.size(), 0, 0.0)
	result.actions = actions
	return result

static func clear_cache() -> void:
	_cache.clear()
	_cache_order.clear()

static func _model(skills: Array, transitions: Array, order: Array) -> Dictionary:
	var model := {"skills": [], "transitions": [], "order": order.duplicate(), "stride": 1, "deterministic": true, "error": ""}
	if skills.is_empty() or skills.size() != transitions.size():
		model.error = "Skills and transition rows must have equal, positive sizes."
		return model
	for index in range(skills.size()):
		var source: Dictionary = skills[index]
		var skill := {"type": str(source.get("type", "normal")), "cost": int(source.get("cost", 100)), "gain": int(source.get("gain", 0)), "cooldown": int(source.get("cooldown", 0))}
		if skill.gain < 0 or skill.cooldown < 0 or skill.cost < 0:
			model.error = "Energy gains, costs and cooldowns must be nonnegative."
			return model
		# Saturating additions preserve every reachable energy in [0, 100].
		skill.gain = mini(100, skill.gain)
		model.skills.append(skill)
		model.stride = maxi(model.stride, skill.cooldown + 1)
		var merged: Dictionary = {}
		for branch in transitions[index]:
			var probability := float(branch.get("p", 0.0))
			var energy := int(branch.get("energy", 0))
			if not is_finite(probability) or probability < 0.0 or energy < 0:
				model.error = "Transition probabilities and event energy must be finite and nonnegative."
				return model
			if probability > 0.0:
				energy = mini(100, energy)
				merged[energy] = float(merged.get(energy, 0.0)) + probability
		var energies: Array = merged.keys()
		energies.sort()
		var total := 0.0
		for energy in energies: total += float(merged[energy])
		if not is_finite(total) or total <= 0.0 or absf(total - 1.0) > TOLERANCE:
			model.error = "Each transition row must sum to one."
			return model
		var row: Array = []
		for energy in energies: row.append({"energy": energy, "p": float(merged[energy]) / total})
		model.transitions.append(row)
		model.deterministic = model.deterministic and row.size() == 1
	if model.order.is_empty():
		for index in range(skills.size()):
			if model.skills[index].type == "ultimate": model.order.append(index)
		for index in range(skills.size() - 1, -1, -1):
			if model.skills[index].type == "skill": model.order.append(index)
		for index in range(skills.size()):
			if not model.skills[index].type in ["skill", "ultimate"]: model.order.append(index)
	for index in model.order:
		if not index is int or index < 0 or index >= skills.size():
			model.error = "The automatic order contains an invalid skill index."
			return model
	return model

static func _state(energy: int, cooldown: int, aura: int, stride: int) -> int:
	return (energy * stride + cooldown) * 2 + aura

static func _unpack(key: int, stride: int) -> Array:
	var packed := key >> 1
	return [int(packed / stride), packed % stride, key & 1]

static func _choose(model: Dictionary, energy: int, cooldown: int) -> int:
	for index in model.order:
		var skill: Dictionary = model.skills[index]
		if skill.type == "ultimate" and energy < skill.cost: continue
		if skill.type == "skill" and cooldown > 0: continue
		return index
	return -1

static func _next(model: Dictionary, state: Array, index: int) -> Dictionary:
	var skill: Dictionary = model.skills[index]
	var ultimate: bool = skill.type == "ultimate"
	var energy := 0 if ultimate else mini(100, int(state[0]) + int(skill.gain))
	var cooldown := maxi(0, int(skill.cooldown) - 1) if skill.type == "skill" else maxi(0, int(state[1]) - 1)
	var result: Dictionary = {}
	for branch in model.transitions[index]:
		# An ultimate ignores its ordinary gain, then receives its event energy.
		# The aura is renewed before ultimate rewards and expires one action later.
		var key := _state(mini(100, energy + int(branch.energy)), cooldown, 1 if ultimate else 0, model.stride)
		result[key] = float(result.get(key, 0.0)) + float(branch.p)
	return result

static func _deterministic(model: Dictionary, initial: int) -> Dictionary:
	var seen: Dictionary = {}
	var actions: Array = []
	var active: Array = []
	var key := initial
	while not seen.has(key):
		if seen.size() >= STATE_LIMIT: return _failure("The reachable action chain exceeds the supported state budget.")
		seen[key] = actions.size()
		var state := _unpack(key, model.stride)
		var index := _choose(model, state[0], state[1])
		if index < 0: return _failure("The automatic order has no legal action.")
		actions.append(index)
		active.append(model.skills[index].type == "ultimate" or state[2] > 0)
		key = int(_next(model, state, index).keys()[0])
	var start := int(seen[key])
	var counts := _zeros(model.skills.size())
	var aura_counts := _zeros(model.skills.size())
	for action in range(start, actions.size()):
		counts[actions[action]] += 1.0
		if active[action]: aura_counts[actions[action]] += 1.0
	var result := _result(counts, aura_counts, float(actions.size() - start), "deterministic_cycle", seen.size(), 0, 0.0)
	result.transientActions = start
	result.cycleLength = actions.size() - start
	result.closedClasses = 1
	return result

## Positive nonultimate gains make these paths acyclic before the next ultimate.
## A visiting mark rejects unsupported zero-gain loops instead of recursing forever.
static func _segment(key: int, model: Dictionary, memo: Dictionary, visiting: Dictionary) -> Dictionary:
	if memo.has(key): return memo[key]
	if visiting.has(key) or visiting.size() >= DEPTH_LIMIT:
		model.error = "A stochastic nonultimate loop requires a more general renewal model."
		return {}
	if memo.size() >= STATE_LIMIT:
		model.error = "The reachable action chain exceeds the supported state budget."
		return {}
	visiting[key] = true
	var state := _unpack(key, model.stride)
	var index := _choose(model, state[0], state[1])
	if index < 0:
		model.error = "The automatic order has no legal action."
		return {}
	var counts := _zeros(model.skills.size())
	var aura_counts := _zeros(model.skills.size())
	counts[index] = 1.0
	var ultimate: bool = model.skills[index].type == "ultimate"
	if ultimate or state[2] > 0: aura_counts[index] = 1.0
	var result := {"counts": counts, "aura": aura_counts, "length": 1.0, "exits": {}}
	var branches := _next(model, state, index)
	if ultimate:
		result.exits = branches
	else:
		for target in branches:
			var tail := _segment(target, model, memo, visiting)
			if tail.is_empty(): return {}
			var probability := float(branches[target])
			result.length += probability * float(tail.length)
			for skill in range(counts.size()):
				result.counts[skill] += probability * float(tail.counts[skill])
				result.aura[skill] += probability * float(tail.aura[skill])
			for exit_state in tail.exits:
				var exit_probability := probability * float(tail.exits[exit_state])
				if exit_probability > 0.0: result.exits[exit_state] = float(result.exits.get(exit_state, 0.0)) + exit_probability
	visiting.erase(key)
	memo[key] = result
	return result

static func _regenerative(model: Dictionary, initial: int) -> Dictionary:
	var memo: Dictionary = {}
	var entrance := _segment(initial, model, memo, {})
	if entrance.is_empty(): return _failure(model.error)
	var keys: Array = entrance.exits.keys()
	var ids: Dictionary = {}
	for index in range(keys.size()): ids[keys[index]] = index
	var segments: Array = []
	var rows: Array = []
	var cursor := 0
	var residual := absf(_sum_values(entrance.exits) - 1.0)
	while cursor < keys.size():
		var segment := _segment(keys[cursor], model, memo, {})
		if segment.is_empty(): return _failure(model.error)
		var row: Dictionary = {}
		for key in segment.exits:
			if not ids.has(key):
				ids[key] = keys.size()
				keys.append(key)
			row[ids[key]] = float(segment.exits[key])
		residual = maxf(residual, absf(_sum_values(row) - 1.0))
		segments.append(segment)
		rows.append(row)
		cursor += 1
	var components := _components(rows)
	var component_of: Dictionary = {}
	for component in range(components.size()):
		for node in components[component]: component_of[node] = component
	var closed: Array = []
	var transient: Array = []
	for component in range(components.size()):
		var is_closed := true
		for node in components[component]:
			for target in rows[node]:
				if component_of[target] != component: is_closed = false
		if is_closed: closed.append(components[component])
		else: transient.append_array(components[component])
	var entrance_vector := _zeros(keys.size())
	for key in entrance.exits: entrance_vector[ids[key]] = float(entrance.exits[key])
	var absorption := _absorption(rows, transient, closed, entrance_vector)
	if absorption.is_empty(): return _failure("The recurrent-class absorption system is numerically singular.")
	residual = maxf(residual, float(absorption.residual))
	var counts := _zeros(model.skills.size())
	var aura_counts := _zeros(model.skills.size())
	var mean_cycle_length := 0.0
	for component in range(closed.size()):
		var nodes: Array = closed[component]
		var stationary := _stationary(rows, nodes)
		if stationary.is_empty(): return _failure("The recurrent-class stationary system is numerically singular.")
		var distribution: Array = stationary["values"]
		residual = maxf(residual, float(stationary.residual))
		var length := 0.0
		for local in range(nodes.size()): length += float(distribution[local]) * float(segments[nodes[local]].length)
		if length <= 0.0 or not is_finite(length): return _failure("The expected renewal length is invalid.")
		var probability := float(absorption["values"][component])
		mean_cycle_length += probability * length
		for local in range(nodes.size()):
			var mass := probability * float(distribution[local]) / length
			var segment: Dictionary = segments[nodes[local]]
			for skill in range(counts.size()):
				counts[skill] += mass * float(segment.counts[skill])
				aura_counts[skill] += mass * float(segment.aura[skill])
	var result := _result(counts, aura_counts, 1.0, "regenerative_chain", memo.size(), keys.size(), residual)
	result.closedClasses = closed.size()
	result.meanCycleLength = mean_cycle_length
	return result

## Iterative Kosaraju decomposition also handles periodic and reducible chains.
static func _components(rows: Array) -> Array:
	var reverse: Array = []
	for _index in range(rows.size()): reverse.append([])
	for node in range(rows.size()):
		for target in rows[node]: reverse[target].append(node)
	var seen: Dictionary = {}
	var finish: Array = []
	for node in range(rows.size()):
		if seen.has(node): continue
		var stack: Array = [[node, false]]
		while not stack.is_empty():
			var entry: Array = stack.pop_back()
			var current := int(entry[0])
			if entry[1]:
				finish.append(current)
				continue
			if seen.has(current): continue
			seen[current] = true
			stack.append([current, true])
			for target in rows[current]:
				if not seen.has(target): stack.append([target, false])
	seen.clear()
	var result: Array = []
	while not finish.is_empty():
		var node := int(finish.pop_back())
		if seen.has(node): continue
		var component: Array = []
		var stack: Array = [node]
		seen[node] = true
		while not stack.is_empty():
			var current := int(stack.pop_back())
			component.append(current)
			for target in reverse[current]:
				if not seen.has(target):
					seen[target] = true
					stack.append(target)
		result.append(component)
	return result

static func _stationary(rows: Array, nodes: Array) -> Dictionary:
	var count := nodes.size()
	if count == 1: return {"values": [1.0], "residual": 0.0}
	var matrix: Array = []
	var rhs: Array = []
	for equation in range(count):
		var row := _zeros(count)
		for variable in range(count):
			if equation == count - 1: row[variable] = 1.0
			elif equation == variable: row[variable] = _leaving(rows[nodes[variable]], nodes[variable])
			else: row[variable] = -float(rows[nodes[variable]].get(nodes[equation], 0.0))
		matrix.append(row)
		rhs.append([1.0 if equation == count - 1 else 0.0])
	var solved := _solve(matrix, rhs)
	if solved.is_empty(): return {}
	var values := _zeros(count)
	var total := 0.0
	for index in range(count):
		var value := float(solved[index][0])
		if not is_finite(value) or value < -TOLERANCE: return {}
		values[index] = maxf(0.0, value)
		total += values[index]
	if total <= 0.0: return {}
	for index in range(count): values[index] /= total
	var residual := absf(total - 1.0)
	for target in range(count):
		var incoming := 0.0
		for source in range(count): incoming += float(values[source]) * float(rows[nodes[source]].get(nodes[target], 0.0))
		residual = maxf(residual, absf(incoming - float(values[target])))
	return {"values": values, "residual": residual}

static func _absorption(rows: Array, transient: Array, closed: Array, entrance: Array) -> Dictionary:
	var values := _zeros(closed.size())
	var closed_of: Dictionary = {}
	for component in range(closed.size()):
		for node in closed[component]:
			closed_of[node] = component
			values[component] += float(entrance[node])
	var residual := 0.0
	if not transient.is_empty():
		var matrix: Array = []
		var rhs: Array = []
		for source in transient:
			var row := _zeros(transient.size())
			for column in range(transient.size()): row[column] = _leaving(rows[source], source) if source == transient[column] else -float(rows[source].get(transient[column], 0.0))
			var exits := _zeros(closed.size())
			for target in rows[source]:
				if closed_of.has(target): exits[closed_of[target]] += float(rows[source][target])
			matrix.append(row)
			rhs.append(exits)
		var solved := _solve(matrix, rhs)
		if solved.is_empty(): return {}
		for source in range(transient.size()):
			var total := 0.0
			for component in range(closed.size()):
				var probability := float(solved[source][component])
				var equation := 0.0
				for column in range(transient.size()): equation += float(matrix[source][column]) * float(solved[column][component])
				residual = maxf(residual, absf(equation - float(rhs[source][component])))
				if not is_finite(probability) or probability < -TOLERANCE or probability > 1.0 + TOLERANCE: return {}
				probability = clampf(probability, 0.0, 1.0)
				values[component] += float(entrance[transient[source]]) * probability
				total += probability
			residual = maxf(residual, absf(total - 1.0))
	var total := 0.0
	for value in values: total += float(value)
	if total <= 0.0: return {}
	residual = maxf(residual, absf(total - 1.0))
	for component in range(values.size()): values[component] /= total
	return {"values": values, "residual": residual}

## Form 1-P_ii as the sum of off-diagonal probabilities to preserve rare exits.
static func _leaving(row: Dictionary, node: int) -> float:
	var result := 0.0
	for target in row:
		if target != node: result += float(row[target])
	return result

## Scaled, pivoted elimination supports several absorption right-hand sides.
static func _solve(matrix: Array, rhs: Array) -> Array:
	var count := matrix.size()
	var width: int = rhs[0].size()
	var work: Array = []
	for row in range(count):
		var scale := 0.0
		for value in matrix[row]: scale = maxf(scale, absf(float(value)))
		if scale == 0.0: return []
		var values: Array = []
		for value in matrix[row]: values.append(float(value) / scale)
		for value in rhs[row]: values.append(float(value) / scale)
		work.append(values)
	for column in range(count):
		var pivot := column
		for row in range(column + 1, count):
			if absf(float(work[row][column])) > absf(float(work[pivot][column])): pivot = row
		var divisor := float(work[pivot][column])
		if divisor == 0.0 or not is_finite(divisor): return []
		if pivot != column:
			var swap: Array = work[column]
			work[column] = work[pivot]
			work[pivot] = swap
		for cell in range(column, count + width): work[column][cell] /= divisor
		for row in range(count):
			if row == column: continue
			var factor := float(work[row][column])
			if factor == 0.0: continue
			work[row][column] = 0.0
			for cell in range(column + 1, count + width): work[row][cell] -= factor * float(work[column][cell])
	var result: Array = []
	for row in work: result.append(row.slice(count))
	return result

static func _result(counts: Array, aura_counts: Array, length: float, method: String, state_count: int, regeneration_states: int, residual: float) -> Dictionary:
	var weights_result := _zeros(counts.size())
	var aura_weights := _zeros(counts.size())
	var total := 0.0
	var aura_uptime := 0.0
	for index in range(counts.size()):
		weights_result[index] = float(counts[index]) / length
		aura_weights[index] = float(aura_counts[index]) / length
		total += weights_result[index]
		aura_uptime += aura_weights[index]
	residual = maxf(residual, absf(total - 1.0))
	if not is_finite(residual) or residual > TOLERANCE: return _failure("The cycle probability residual exceeds tolerance.")
	return {"success": true, "skillWeights": weights_result, "skillAuraWeights": aura_weights, "auraSkillWeights": aura_weights.duplicate(), "auraUptime": aura_uptime, "method": method, "stateCount": state_count, "regenerationStates": regeneration_states, "residual": residual, "cacheHit": false}

static func _zeros(count: int) -> Array:
	var result: Array = []
	result.resize(count)
	result.fill(0.0)
	return result

static func _sum_values(values: Dictionary) -> float:
	var result := 0.0
	for value in values.values(): result += float(value)
	return result

static func _failure(message: String) -> Dictionary:
	return {"success": false, "error": message, "skillWeights": [], "skillAuraWeights": [], "auraSkillWeights": [], "auraUptime": 0.0, "method": "unsupported", "stateCount": 0, "regenerationStates": 0, "residual": INF, "cacheHit": false}
