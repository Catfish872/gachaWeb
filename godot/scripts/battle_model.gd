extends RefCounted
## Deterministic combat simulation. No scene nodes, timers, global state or saves.
## Each accepted act/auto_step produces one bounded batch of animation events.

const AbyssBalance = preload("res://scripts/abyss_balance.gd")

const CONTROL_STATUSES = ["freeze", "stun", "electrify"]
const STATUS_IDS = ["burn", "freeze", "stun", "poison", "electrify", "regen", "atk_up", "def_up", "spd_down", "shield", "invincible", "taunt"]
const ELEMENT_ADVANTAGE = {
	"fire": ["wind", "water"], "water": ["fire", "thunder"],
	"wind": ["thunder", "fire"], "thunder": ["water", "wind"]
}
var catalog: Dictionary
var state: Dictionary = {}
var rng = RandomNumberGenerator.new()
var _effects: Array = []
var _events: Array = []
var _queue: Array = []
var _cursor: int = 0
var _waves: Array = []
var _steps: int = 0
var _max_steps: int = 10000
var _extra_flags: Dictionary = {}
var _is_abyss := false

func _init(data: Dictionary = {}) -> void:
	catalog = data
	rng.seed = 1

func start(config: Dictionary, allies: Array, rogue_effects: Array = []) -> Dictionary:
	if config.has("seed"):
		rng.seed = int(config.seed)
	_events = []
	_is_abyss = bool(config.get("isAbyss", false))
	_effects = rogue_effects.duplicate(true) if _is_abyss else []
	_steps = 0
	_max_steps = clampi(int(config.get("maxSteps", 10000)), 10, 100000)
	state = {"phase": "player_turn", "allies": [], "enemies": [], "turn": 0,
		"wave": 1, "events": [], "log": [], "config": config.duplicate(true),
		"turnOrder": [], "currentActor": "", "steps": 0, "reason": ""}
	_waves = config.get("waves", []).duplicate(true)
	if _waves.is_empty():
		_waves = [{"enemies": config.get("enemies", [])}]
	for i in range(allies.size()):
		if not allies[i] is Dictionary:
			continue
		var unit = _make_ally(allies[i], i)
		if not unit.is_empty():
			state.allies.append(unit)
	_apply_rogue_stats()
	_spawn_wave()
	_apply_battle_start()
	_build_queue()
	_seek_actor()
	_publish()
	return state

func current_actor() -> Dictionary:
	if state.is_empty() or state.phase in ["victory", "defeat"]:
		return {}
	return get_unit(state.get("currentActor", ""))

func get_unit(uid: String) -> Dictionary:
	for unit in state.get("allies", []) + state.get("enemies", []):
		if unit.uid == uid:
			return unit
	return {}

func skill_data(skill_id: String, is_ally: bool = true) -> Dictionary:
	return catalog.get("SkillData" if is_ally else "EnemySkillData", {}).get(skill_id, {})

func available_actions() -> Array:
	var actor = current_actor()
	if actor.is_empty() or _controlled(actor):
		return []
	return _available(actor)

func legal_targets(skill_id: String) -> Array:
	var actor = current_actor()
	if actor.is_empty() or not actor.skills.has(skill_id) and not actor.get("phase2Skills", []).has(skill_id):
		return []
	var skill = skill_data(skill_id, actor.isAlly)
	var result: Array = []
	for effect in skill.get("effects", []):
		var kind = str(effect.get("target", "single"))
		var candidates: Array = []
		match kind:
			"self": candidates = [actor]
			"all_allies", "lowest_hp_ally": candidates = _friends(actor)
			_: candidates = _foes(actor)
		for target in candidates:
			if not result.has(target.uid):
				result.append(target.uid)
	return result

func act(skill_id: String, target_id: String = "") -> Dictionary:
	var actor = current_actor()
	if actor.is_empty():
		return _error("战斗已经结束")
	if not actor.isAlly:
		return _error("请等待敌方行动")
	if not _available(actor).has(skill_id):
		return _error("技能不可用：能量不足、冷却中或不属于当前角色")
	if not target_id.is_empty() and not legal_targets(skill_id).has(target_id):
		return _error("目标无效或已经倒下")
	return _take_action(actor, skill_id, target_id)

func auto_step() -> Dictionary:
	if state.is_empty():
		return _error("尚未开始战斗")
	if state.phase in ["victory", "defeat"]:
		return {"success": true, "events": [], "finished": true}
	var actor = current_actor()
	if actor.is_empty():
		_events = []
		_seek_actor()
		_publish()
		return {"success": true, "events": _events.duplicate(true)}
	var skills = _available(actor)
	if skills.is_empty():
		_events = []
		_emit("skip", actor, actor, 0, actor.name + " 无可用技能")
		_steps += 1
		_cursor += 1
		_seek_actor()
		_publish()
		return {"success": true, "events": _events.duplicate(true)}
	var chosen = str(skills[0])
	if actor.isAlly:
		for sid in skills:
			var data = skill_data(sid)
			if _hold_healing_skill(actor, data): continue
			if data.get("type") == "ultimate":
				chosen = sid
				break
			if data.get("type") == "skill":
				chosen = sid
	else:
		chosen = _enemy_choice(actor, skills)
	return _take_action(actor, chosen, "")

func _hold_healing_skill(actor: Dictionary, skill: Dictionary) -> bool:
	var has_heal := false
	for effect in skill.get("effects", []):
		if effect.get("type", "") == "damage": return false
		if effect.get("type", "") == "heal": has_heal = true
	if not has_heal: return false
	var threshold := 0.80 if skill.get("type", "") == "ultimate" else 0.90
	for friend in _friends(actor):
		if float(friend.currentHp) / friend.maxHp < threshold: return false
	return true

func _take_action(actor: Dictionary, sid: String, target_id: String) -> Dictionary:
	_events = []
	_extra_flags = {}
	_execute_skill(actor, sid, target_id)
	_steps += 1
	_cursor += 1
	_seek_actor()
	_publish()
	return {"success": true, "events": _events.duplicate(true), "finished": state.phase in ["victory", "defeat"]}

func _make_ally(input: Dictionary, index: int) -> Dictionary:
	var id = str(input.get("id", ""))
	var data = catalog.get("CharacterData", {}).get(id, {})
	if data.is_empty() and not input.has("stats"):
		return {}
	var stats: Dictionary = input.get("stats", data.get("baseStats", {})).duplicate(true)
	_normalize_stats(stats)
	var save_data = input.get("saveData", {})
	var c = int(input.get("constellation", save_data.get("constellation", 0)))
	# Progression computes these; fallback supports caller-supplied raw units too.
	if not stats.has("normalDmgBonus"): stats.normalDmgBonus = 0.15 if c >= 1 else 0.0
	if not stats.has("skillCdReduce"): stats.skillCdReduce = 1 if c >= 2 else 0
	if not stats.has("skillDmgBonus"): stats.skillDmgBonus = 0.2 if c >= 3 else 0.0
	if not stats.has("ultDmgBonus"): stats.ultDmgBonus = 0.3 if c >= 5 else 0.0
	return {"uid": "ally_%d" % index, "id": id, "dataId": id,
		"name": str(input.get("name", data.get("name", id))), "isAlly": true,
		"element": input.get("element", data.get("element", "wind")),
		"role": data.get("role", "dps"), "rarity": data.get("rarity", 3),
		"image": data.get("image"), "color": data.get("color", "#ffffff"),
		"stats": stats, "maxHp": stats.maxHp,
		"currentHp": clampi(int(input.get("currentHp", stats.maxHp)), 0, int(input.get("_abyssSavedMaxHp", input.get("maxHp", stats.maxHp)))),
		"savedMaxHp": input.get("_abyssSavedMaxHp", input.get("maxHp", stats.maxHp)),
		"energy": clampi(int(input.get("energy", 0)), 0, 100), "maxEnergy": 100,
		"skills": input.get("skills", data.get("skills", [])).duplicate(),
		"passiveId": input.get("passiveId", data.get("passiveId", "")), "constellation": c,
		"statuses": [], "shield": 0, "cooldowns": input.get("cooldowns", {}).duplicate(),
		"baseAtk": stats.atk, "isBoss": false, "inPhase2": false,
		"c6Used": false, "deathReported": false}

func _normalize_stats(stats: Dictionary) -> void:
	stats.maxHp = maxi(1, int(stats.get("maxHp", stats.get("hp", 1000))))
	stats.hp = stats.maxHp
	stats.atk = maxi(1, int(stats.get("atk", 100)))
	stats.def = maxi(0, int(stats.get("def", 50)))
	stats.spd = maxf(1.0, float(stats.get("spd", 100)))
	stats.cri = clampf(float(stats.get("cri", stats.get("critRate", 0.1))), 0.0, 1.0)
	stats.criDmg = maxf(1.0, float(stats.get("criDmg", stats.get("critDmg", 1.5))))

func _spawn_wave() -> void:
	state.enemies = []
	var wave: Dictionary = _waves[int(state.wave) - 1]
	var enemies = wave.get("enemies", [])
	for i in range(enemies.size()):
		var id = str(enemies[i])
		var data: Dictionary = catalog.get("EnemyData", {}).get(id, {})
		if data.is_empty():
			state.reason = "未知敌人：" + id
			continue
		var scale = wave.get("scaleMult", state.config.get("scaleMult", 1.0))
		var mods = abyss_scale(int(state.config.get("floor", 1)), id) if state.config.get("isAbyss", false) else {}
		if scale is Dictionary: mods = scale
		elif mods.is_empty(): mods = {"hpMod": scale, "atkMod": scale, "defMod": scale, "spdMod": 1.0}
		if _is_abyss:
			mods = AbyssBalance.apply_difficulty(mods, int(state.config.get("difficulty", 0)))
			mods = AbyssBalance.apply_modifier(mods, state.config.get("encounterModifier", {}))
		var bs = data.baseStats
		var stats = {"maxHp": maxi(1, int(bs.hp * mods.get("hpMod", 1))),
			"atk": maxi(1, int(bs.atk * mods.get("atkMod", 1))), "def": maxi(0, int(bs.def * mods.get("defMod", 1))),
			"spd": maxf(1, bs.spd * mods.get("spdMod", 1)), "cri": 0.1, "criDmg": 1.5}
		if _is_abyss: stats.spd = minf(AbyssBalance.MAX_ENEMY_SPEED, stats.spd)
		state.enemies.append({"uid": "enemy_%d_%d" % [state.wave, i], "id": id, "dataId": id,
			"name": data.name, "element": data.element, "isAlly": false,
			"archetype": data.get("type", "normal"), "controlGuard": 0, "controlSkips": 0,
			"isBoss": data.get("isBoss", false), "icon": data.get("icon", ""), "color": data.get("color", "#ffffff"),
			"stats": stats, "maxHp": stats.maxHp, "currentHp": stats.maxHp,
			"skills": data.skills.duplicate(), "aiPattern": data.get("aiPattern", "random"),
			"phaseThreshold": data.get("phaseThreshold", 0.5), "phase2Skills": data.get("phase2Skills", []).duplicate(),
			"energy": 0, "maxEnergy": 100, "cooldowns": {}, "statuses": [], "shield": 0,
			"baseAtk": stats.atk, "inPhase2": false, "passiveId": "", "constellation": 0,
			"c6Used": false, "deathReported": false})
	_emit("wave", {}, {}, state.wave, "第 %d 波" % state.wave)

func abyss_scale(floor_number: int, enemy_id: String) -> Dictionary:
	return AbyssBalance.scale(floor_number, catalog.get("EnemyData", {}).get(enemy_id, {}))

func _apply_rogue_stats() -> void:
	var buckets: Dictionary = {}
	for effect in _effects:
		if effect.get("type") == "stat":
			var key = str(effect.get("stat", ""))
			buckets[key] = buckets.get(key, 0.0) + float(effect.get("value", 0.0))
	for unit in state.allies:
		var ratio = float(unit.currentHp) / maxf(1.0, float(unit.savedMaxHp))
		for pair in [["atk", "atkMult"], ["def", "defMult"], ["maxHp", "maxHpMult"], ["spd", "spdMult"]]:
			var changed = unit.stats[pair[0]] * maxf(0.1, 1.0 + buckets.get(pair[1], 0.0))
			unit.stats[pair[0]] = changed if pair[0] == "spd" else int(changed)
		unit.stats.cri = clampf(unit.stats.cri + buckets.get("criAdd", 0.0), 0, 1)
		unit.stats.criDmg += buckets.get("criDmgAdd", 0.0)
		unit.maxHp = unit.stats.maxHp
		unit.stats.hp = unit.maxHp
		unit.currentHp = clampi(int(unit.maxHp * ratio), 1 if ratio > 0 else 0, unit.maxHp)
		unit.baseAtk = unit.stats.atk

func _apply_battle_start() -> void:
	for effect in _effects:
		match effect.get("type", ""):
			"battleStartEnergy":
				for unit in _alive(state.allies): _gain_energy(unit, float(effect.get("value", 0)))
			"battleStartStatus":
				for unit in _alive(state.allies): apply_status(unit, effect.statusId, int(effect.get("duration", 1)), effect.get("value"))
			"enemyBattleStartStatus":
				var pool = _alive(state.enemies)
				var count = clampi(int(effect.get("count", pool.size())), 0, pool.size())
				for i in range(count):
					var index = rng.randi_range(0, pool.size() - 1)
					apply_status(pool[index], effect.statusId, int(effect.get("duration", 1)), effect.get("value"))
					pool.remove_at(index)

func _alive(units: Array) -> Array:
	return units.filter(func(unit): return unit.currentHp > 0)

func _friends(unit: Dictionary) -> Array:
	return _alive(state.allies if unit.isAlly else state.enemies)

func _foes(unit: Dictionary) -> Array:
	return _alive(state.enemies if unit.isAlly else state.allies)

func _build_queue() -> void:
	_queue = _alive(state.allies + state.enemies)
	_queue.sort_custom(func(a, b):
		var av = a.stats.spd * modifiers(a).spdMult
		var bv = b.stats.spd * modifiers(b).spdMult
		if av == bv: return a.isAlly and not b.isAlly
		return av > bv)
	_cursor = 0
	state.turn += 1
	state.turnOrder = _queue.map(func(unit): return unit.uid)
	_emit("round", {}, {}, state.turn, "第 %d 回合" % state.turn)
	if _is_abyss and state.turn in [21, 40]:
		for enemy in _alive(state.enemies):
			if enemy.isBoss:
				_emit("enrage", enemy, enemy, int((boss_enrage_mult(enemy) - 1.0) * 100), enemy.name + (" · 持久战狂暴：每回合攻击 +5%，最多 +100%" if state.turn == 21 else " · 狂暴达到上限：攻击 +100%"))
	# Zeph's C6 applies before allies act, so its one-round buff can be used.
	for unit in _alive(state.allies):
		if unit.id == "zeph" and _c6(unit) and _above_average_speed(unit):
			var friends = _friends(unit).filter(func(friend): return friend.uid != unit.uid)
			if not friends.is_empty():
				friends.sort_custom(func(a,b): return a.stats.spd * modifiers(a).spdMult < b.stats.spd * modifiers(b).spdMult)
				apply_status(friends[0], "atk_up", 1, 0.3, unit)

func _seek_actor() -> void:
	# Even an invalid/control-only party can never recurse or block the UI.
	for safety in range(300):
		_report_deaths()
		if _resolve_outcome(): return
		if _steps >= _max_steps:
			_finish("defeat", "战斗达到安全行动上限")
			return
		if _cursor >= _queue.size():
			_end_round()
			_report_deaths()
			if _resolve_outcome(): return
			_build_queue()
		if _queue.is_empty():
			_finish("defeat", "没有可行动单位")
			return
		var actor = _queue[_cursor]
		if actor.currentHp <= 0:
			_cursor += 1
			continue
		if actor.isBoss and not actor.inPhase2 and float(actor.currentHp) / actor.maxHp < actor.phaseThreshold:
			actor.inPhase2 = true
			_emit("phase_change", actor, actor, 2, actor.name + " 进入第二阶段")
		if _is_abyss and not actor.isAlly and int(actor.get("controlGuard", 0)) > 0:
			actor.controlGuard -= 1
		if _controlled(actor):
			_emit("skip", actor, actor, 0, actor.name + " 因控制效果跳过行动")
			for status in actor.statuses:
				if status.id in CONTROL_STATUSES: status.duration -= 1
			if _is_abyss and not actor.isAlly:
				actor.controlSkips = int(actor.get("controlSkips", 0)) + 1
				if actor.controlSkips >= (1 if actor.isBoss else 2):
					actor.controlGuard = 1
					for status in actor.statuses:
						if status.id in CONTROL_STATUSES: status.duration = 0
			_cleanup_statuses(actor)
			_cursor += 1
			_steps += 1
			continue
		if _is_abyss and not actor.isAlly: actor.controlSkips = 0
		state.currentActor = actor.uid
		state.phase = "player_turn" if actor.isAlly else "enemy_turn"
		state.steps = _steps
		return
	_finish("defeat", "状态结算达到安全上限")

func _resolve_outcome() -> bool:
	if _alive(state.allies).is_empty():
		_finish("defeat", "队伍全员倒下")
		return true
	if _alive(state.enemies).is_empty():
		if int(state.wave) < _waves.size():
			state.wave += 1
			_spawn_wave()
			_build_queue()
			return false
		_finish("victory", "战斗胜利")
		return true
	return false

func _finish(phase: String, reason: String) -> void:
	state.phase = phase
	state.reason = reason
	state.currentActor = ""
	state.steps = _steps
	_emit("win" if phase == "victory" else "defeat", {}, {}, 0, reason)

func _end_round() -> void:
	for unit in state.allies + state.enemies:
		if unit.currentHp <= 0: continue
		if unit.passiveId == "ayla_passive":
			var friends = _friends(unit)
			if not friends.is_empty(): _heal(unit, _lowest_hp(friends), maxi(1, int(unit.stats.atk * 0.4)), "ayla_passive", false, "passive")
		for status in unit.statuses.duplicate():
			if unit.currentHp <= 0: break
			match status.id:
				"burn": _status_damage(unit, maxi(1, int(unit.baseAtk * 0.18)), "burn")
				"poison": _status_damage(unit, maxi(1, int(unit.maxHp * (0.015 if _is_abyss and unit.isBoss else 0.05))), "poison")
				"regen": _heal(unit, unit, maxi(1, int(unit.maxHp * 0.08)), "regen", false, "status")
			if not status.id in CONTROL_STATUSES: status.duration -= 1
		_cleanup_statuses(unit)
		if unit.currentHp > 0 and unit.passiveId == "tide_passive":
			_heal(unit, unit, maxi(1, int(unit.maxHp * (0.06 if _c6(unit) else 0.03))), "tide_passive", false, "passive")
		for sid in unit.cooldowns: unit.cooldowns[sid] = maxi(0, int(unit.cooldowns[sid]) - 1)

func _available(unit: Dictionary) -> Array:
	var result: Array = []
	var skills = unit.skills.duplicate()
	if unit.get("inPhase2", false):
		for sid in unit.get("phase2Skills", []):
			if not skills.has(sid): skills.append(sid)
	for sid in skills:
		var data = skill_data(sid, unit.isAlly)
		if data.is_empty(): continue
		if int(unit.cooldowns.get(sid, 0)) > 0: continue
		if unit.isAlly and data.get("type", "") == "ultimate" and unit.energy < int(data.get("energyCost", 100)): continue
		result.append(sid)
	return result

func _enemy_choice(unit: Dictionary, skills: Array) -> String:
	# Expedition enemies use their damaging cooldowns; story AI is preserved.
	if _is_abyss and unit.aiPattern == "aggressive":
		var best := ""
		var best_score := -1.0
		for sid in skills:
			var score := 0.0
			for effect in skill_data(sid, false).get("effects", []):
				if effect.type == "damage":
					var targets := _foes(unit).size() if str(effect.get("target", "single")) in ["all", "all_enemies", "chain3"] else 1
					score += float(effect.get("multiplier", 1.0)) * targets
				elif effect.get("statusId", "") in CONTROL_STATUSES: score += 0.5
			if score > best_score:
				best = sid
				best_score = score
		if not best.is_empty(): return best
	if unit.aiPattern == "aggressive":
		for sid in skills:
			for effect in skill_data(sid, false).get("effects", []):
				if effect.type == "damage": return sid
	if unit.aiPattern == "defensive" and float(unit.currentHp) / unit.maxHp < 0.5:
		for sid in skills:
			for effect in skill_data(sid, false).get("effects", []):
				if effect.type == "status" and effect.get("statusId", "") in ["shield", "def_up"]: return sid
	if unit.aiPattern == "boss" and unit.inPhase2:
		var p2 = skills.filter(func(sid): return unit.phase2Skills.has(sid))
		if not p2.is_empty(): return p2[rng.randi_range(0, p2.size() - 1)]
	return skills[rng.randi_range(0, skills.size() - 1)]

func _targets(kind: String, caster: Dictionary, selected: String, cache: Dictionary) -> Array:
	var friends = _friends(caster)
	var foes = _foes(caster)
	var manual = get_unit(selected)
	match kind:
		"self": return [caster] if caster.currentHp > 0 else []
		"all_allies": return friends
		"lowest_hp_ally":
			if cache.has("lowest"): return [cache.lowest] if cache.lowest.currentHp > 0 else []
			if not manual.is_empty() and friends.has(manual): cache.lowest = manual
			elif not friends.is_empty(): cache.lowest = _lowest_hp(friends)
			return [cache.lowest] if cache.has("lowest") else []
		"all", "all_enemies": return foes
		"chain3":
			if not manual.is_empty() and foes.has(manual):
				foes.erase(manual)
				foes.push_front(manual)
			return foes.slice(0, 3)
		"random", "random_enemy": return [foes[rng.randi_range(0, foes.size() - 1)]] if not foes.is_empty() else []
		"single", "single_enemy":
			if cache.has("single"): return [cache.single] if cache.single.currentHp > 0 else []
			var taunted = foes.filter(func(target): return has_status(target, "taunt"))
			if not taunted.is_empty(): cache.single = taunted[0]
			elif not manual.is_empty() and foes.has(manual): cache.single = manual
			elif not foes.is_empty(): cache.single = foes[0] if caster.isAlly else foes[rng.randi_range(0, foes.size() - 1)]
			return [cache.single] if cache.has("single") else []
	return []

func _lowest_hp(units: Array) -> Dictionary:
	var lowest = units[0]
	for unit in units:
		if float(unit.currentHp) / unit.maxHp < float(lowest.currentHp) / lowest.maxHp: lowest = unit
	return lowest

func _execute_skill(caster: Dictionary, sid: String, selected: String = "") -> void:
	var skill = skill_data(sid, caster.isAlly)
	var kind = str(skill.get("type", "enemy"))
	_emit("skill", caster, {}, 0, caster.name + " · " + str(skill.get("name", sid)), {"skill_id": sid, "skill_type": kind, "animation": skill.get("animation", "slash")})
	if caster.isAlly:
		if kind == "ultimate": caster.energy = 0
		else:
			var energy_bonus = float(caster.stats.get("energyRate", 0.0)) + _effect_sum("energyGainMult")
			_gain_energy(caster, floor(float(skill.get("energyGain", 15)) * maxf(0, 1 + energy_bonus)))
	if int(skill.get("cooldown", 0)) > 0:
		caster.cooldowns[sid] = maxi(1, int(skill.cooldown) - (int(caster.stats.get("skillCdReduce", 0)) if caster.isAlly and kind == "skill" else 0))
	var cache: Dictionary = {}
	var had_heal = false
	for effect in skill.get("effects", []):
		var target_type = str(effect.get("target", "single"))
		# Correct the original wolf howl data's reversed viewpoint.
		if sid == "wolf_howl" and effect.type == "status": target_type = "all_allies"
		var targets = _targets(target_type, caster, selected, cache)
		var chain = 1.0
		for target in targets:
			if target.currentHp <= 0: continue
			match effect.type:
				"damage":
					_damage(caster, target, skill, sid, effect, float(effect.get("multiplier", 1.0)) * chain)
					chain = maxf(0.3, chain - float(effect.get("chainDecay", 0.0)))
				"heal":
					var heal_mult = float(effect.get("multiplier", 1.0)) * (maxf(0, 1 + _effect_sum("healMult")) if caster.isAlly else 1.0)
					var amount = maxi(1, int(_effective_atk(caster) * heal_mult))
					_heal(caster, target, amount, sid, true, kind)
					had_heal = true
				"status":
					if rng.randf() < float(effect.get("chance", 1.0)):
						apply_status(target, str(effect.statusId), int(effect.get("duration", 1)), effect.get("value"), caster)
	if caster.id == "ayla" and _c6(caster) and had_heal:
		for friend in _friends(caster): apply_status(friend, "regen", 1, null, caster)

func _effective_atk(unit: Dictionary) -> int:
	var mult = modifiers(unit).atkMult
	if unit.passiveId == "zeph_passive" and _above_average_speed(unit): mult *= 1.15
	mult *= boss_enrage_mult(unit)
	return maxi(1, int(unit.stats.atk * mult))

func boss_enrage_mult(unit: Dictionary) -> float:
	if not _is_abyss or unit.isAlly or not unit.isBoss: return 1.0
	return 1.0 + clampf(float(int(state.get("turn", 1)) - 20) * 0.05, 0.0, 1.0)

func _above_average_speed(unit: Dictionary) -> bool:
	var all = _alive(state.allies + state.enemies)
	var sum = 0.0
	for other in all: sum += other.stats.spd * modifiers(other).spdMult
	return unit.stats.spd * modifiers(unit).spdMult > sum / maxi(1, all.size())

func _damage(caster: Dictionary, target: Dictionary, skill: Dictionary, sid: String, effect: Dictionary, mult: float, follow_up: bool = false) -> int:
	if int(target.get("currentHp", 0)) <= 0: return 0
	if has_status(target, "invincible"):
		_emit("miss", caster, target, 0, target.name + " 无敌", {"skill_id": sid})
		return 0
	var skill_type = str(skill.get("type", "enemy"))
	if not follow_up:
		mult *= _damage_multiplier(caster, target, skill_type)
	var element = str(skill.get("element", effect.get("element", caster.element)))
	var mods = modifiers(target)
	var crit_chance = float(caster.stats.cri) if not follow_up else 0.0
	var crit = rng.randf() < crit_chance
	var attack = int(caster.stats.atk) if effect.get("rawAtk", false) else _effective_atk(caster)
	var raw = attack * mult * (100.0 / (100.0 + maxf(0, target.stats.def * mods.defMult * (1.0 - float(effect.get("defPierce", 0.0))))))
	var element_bonus = element_mult(element, target.element)
	raw *= element_bonus * (float(caster.stats.criDmg) if crit else 1.0)
	if effect.get("trueDamage", false): raw = caster.stats.atk * mult
	var damage = maxi(1, int(raw))
	if target.id == "lorin" and _c6(target) and not target.c6Used and target.shield > 0 and damage > target.maxHp * 0.3:
		target.c6Used = true
		apply_status(target, "invincible", 1, null, target)
		_emit("miss", caster, target, 0, "绝对防壁阻挡了致命攻击", {"skill_id": sid})
		return 0
	if target.passiveId == "lorin_passive" and target.currentHp > target.maxHp * 0.5 and rng.randf() < 0.3:
		damage = maxi(1, int(damage * 0.5))
		_emit("block", target, target, 0, "格挡 · 伤害降低 50%")
	damage = maxi(1, int(damage * maxf(0.1, 1.0 - mods.damageReduction)))
	damage = _absorb(target, damage)
	var hp_before := int(target.currentHp)
	target.currentHp = maxi(0, int(target.currentHp) - damage)
	_emit("damage", caster, target, damage, "%s → %s  -%d" % [caster.name, target.name, damage], {"skill_id": sid, "isCrit": crit, "element": element, "elementMult": element_bonus, "follow_up": follow_up})
	if damage <= 0: return damage
	if caster.isAlly:
		var drain := clampf(_effect_sum("lifesteal"), 0.0, 0.35)
		if drain > 0.0: _heal(caster, caster, maxi(1, int(mini(damage, hp_before) * drain)), "rogue_lifesteal", false, "status")
		if target.currentHp <= 0: _gain_energy(caster, clampf(_effect_sum("energyOnKill"), 0.0, 60.0))
	if follow_up: return damage
	if caster.passiveId == "gus_passive" and crit: _gain_energy(caster, 5)
	if target.currentHp > 0:
		if caster.passiveId == "bolt_passive" and crit: apply_status(target, "electrify", 1, null, caster)
		if caster.passiveId == "ember_passive" and skill_type == "normal" and rng.randf() < (0.6 if _c6(caster) else 0.25):
			apply_status(target, "burn", 2, null, caster)
			if _c6(caster): _gain_energy(caster, 10)
		_after_rogue_damage(caster, target, skill, sid, element)
		if target.currentHp > 0 and caster.id == "kaldi" and _c6(caster) and skill_type == "ultimate" and has_status(target, "burn"):
			_extra_damage(caster, target, 0.8, "fire", sid + "_c6")
		if target.currentHp > 0 and caster.id == "gus" and _c6(caster) and crit and rng.randf() < 0.4:
			var normal = skill_data("gus_normal")
			_damage(caster, target, normal, "gus_c6", normal.effects[0], float(normal.effects[0].multiplier) * (1.0 + float(caster.stats.get("normalDmgBonus", 0.0))), true)
	return damage

func _damage_multiplier(caster: Dictionary, target: Dictionary, kind: String) -> float:
	var result = 1.0
	if caster.isAlly:
		var key = {"normal": "normalDmgBonus", "skill": "skillDmgBonus", "ultimate": "ultDmgBonus"}.get(kind, "")
		result *= 1.0 + float(caster.stats.get(key, 0.0))
		if caster.passiveId == "kaldi_passive" and has_status(target, "burn"): result *= 1.2
		if caster.passiveId == "cinder_passive" and kind in ["skill", "ultimate"] and has_status(target, "burn"): result *= 1.7 if _c6(caster) else 1.4
		if caster.id == "bolt" and _c6(caster) and has_status(target, "electrify"): result *= 1.35
	var buckets = {"status": 0.0, "type": 0.0, "typeStatus": 0.0, "taken": 0.0, "takenStatus": 0.0, "shield": 0.0, "execute": 0.0}
	for effect in _effects:
		var value = float(effect.get("value", 0))
		match effect.get("type", ""):
			"damageWhileShielded":
				if caster.isAlly and caster.shield > 0: buckets.shield += value
			"damageVsLowHp":
				if caster.isAlly and float(target.currentHp) / target.maxHp <= clampf(float(effect.get("threshold", 0.35)), 0.0, 1.0): buckets.execute += value
			"damageVsStatus":
				if caster.isAlly and has_status(target, effect.statusId): buckets.status += value
			"skillTypeDamage":
				if caster.isAlly and kind == effect.skillType: buckets.type += value
			"skillTypeDamageVsStatus":
				if caster.isAlly and kind == effect.skillType and has_status(target, effect.statusId): buckets.typeStatus += value
			"damageTakenMult":
				if target.isAlly: buckets.taken += value
			"damageTakenWhileStatus":
				if target.isAlly and has_status(target, effect.statusId): buckets.takenStatus += value
	for key in ["status", "type", "typeStatus", "shield", "execute"]: result *= maxf(0.1, 1.0 + buckets[key])
	var taken = maxf(0.1, 1.0 + buckets.taken) * maxf(0.1, 1.0 + buckets.takenStatus)
	return minf(result, 8.0) * maxf(0.1, taken) if _is_abyss else result * maxf(0.1, taken)

func _after_rogue_damage(caster: Dictionary, target: Dictionary, skill: Dictionary, sid: String, element: String) -> void:
	if not caster.isAlly: return
	for i in range(_effects.size()):
		var effect = _effects[i]
		match effect.get("type", ""):
			"applyStatusAfterDamage":
				if (not effect.has("element") or effect.element == element) and rng.randf() < float(effect.get("chance", 1)):
					apply_status(target, effect.statusId, int(effect.get("duration", 1)), effect.get("value"), caster)
			"energyOnHitStatus":
				if has_status(target, effect.statusId): _gain_energy(caster, float(effect.get("value", 0)))
			"extraDamageVsStatus":
				var flag = "%d_%s_%s" % [i, sid, target.uid]
				if target.currentHp > 0 and has_status(target, effect.statusId) and not _extra_flags.has(flag):
					_extra_flags[flag] = true
					_extra_damage(caster, target, float(effect.get("multiplier", 0.3)), str(effect.get("element", caster.element)), sid + "_rogue", bool(effect.get("trueDamage", false)))

func _extra_damage(caster: Dictionary, target: Dictionary, multiplier: float, element: String, source: String, true_damage: bool = false) -> void:
	_damage(caster, target, {"type": "follow_up", "element": element}, source, {"defPierce": 0, "trueDamage": true_damage, "rawAtk": true}, multiplier, true)

func _heal(caster: Dictionary, target: Dictionary, amount: int, source: String, skill_heal: bool, skill_type: String) -> void:
	if target.currentHp <= 0: return
	var before = int(target.currentHp)
	var overflow = maxi(0, before + amount - int(target.maxHp))
	target.currentHp = mini(int(target.maxHp), before + amount)
	var actual = int(target.currentHp) - before
	_emit("heal", caster, target, actual, "%s +%d" % [target.name, actual], {"skill_id": source, "overheal": overflow, "requestedAmount": amount})
	if caster.isAlly and amount > 0 and skill_type != "status" and (skill_heal or actual > 0):
		for effect in _effects:
			if effect.get("type") == "statusAfterHeal": apply_status(target, effect.statusId, int(effect.get("duration", 1)), effect.get("value"), caster)
	if skill_heal and caster.passiveId == "shana_passive" and target.uid != caster.uid:
		_heal(caster, caster, int(amount * 0.15), "shana_passive", false, "passive")
	if caster.id == "shana" and _c6(caster) and skill_type in ["skill", "ultimate"] and overflow > 0:
		apply_status(target, "shield", 1, float(overflow) / target.maxHp, caster)

func apply_status(unit: Dictionary, status_id: String, duration: int, value = null, caster: Dictionary = {}) -> bool:
	if not STATUS_IDS.has(status_id) or duration <= 0 or unit.get("currentHp", 0) <= 0: return false
	if _is_abyss and not unit.isAlly and status_id in CONTROL_STATUSES:
		if int(unit.get("controlGuard", 0)) > 0:
			_emit("resist", caster, unit, 0, unit.name + " · 控制抗性", {"statusId": status_id})
			return false
		duration = mini(duration, 1 if unit.isBoss else 2)
	if _is_abyss and status_id == "poison":
		var stacks: Array = unit.statuses.filter(func(status): return status.id == "poison")
		if stacks.size() >= 5:
			stacks.sort_custom(func(a, b): return a.duration < b.duration)
			stacks[0].duration = maxi(stacks[0].duration, duration)
			_emit("status", caster, unit, duration, unit.name + " · poison", {"statusId": "poison", "duration": duration})
			return true
	var existing: Dictionary = {}
	if status_id != "poison":
		for status in unit.statuses:
			if status.id == status_id and status.duration > 0: existing = status; break
	if existing.is_empty():
		existing = {"id": status_id, "duration": duration, "value": value, "stacks": 1}
		if status_id == "shield": existing.shieldHp = maxi(0, int(unit.maxHp * (float(value) if value != null else 0.3)))
		unit.statuses.append(existing)
	else:
		if _is_abyss and not unit.isAlly and status_id in CONTROL_STATUSES:
			existing.duration = maxi(existing.duration, duration)
		else:
			existing.duration += duration
		if value != null: existing.value = value
		if status_id == "shield": existing.shieldHp += maxi(0, int(unit.maxHp * (float(value) if value != null else 0.3)))
	_sync_shield(unit)
	_emit("status", caster, unit, duration, unit.name + " · " + status_id, {"status": status_id, "statusId": status_id, "duration": duration, "value": value})
	return true

func has_status(unit: Dictionary, status_id: String) -> bool:
	for status in unit.get("statuses", []):
		if status.id == status_id and int(status.duration) > 0: return true
	return false

func modifiers(unit: Dictionary) -> Dictionary:
	var mods = {"atkMult": 1.0, "defMult": 1.0, "spdMult": 1.0, "damageReduction": 0.0}
	for status in unit.get("statuses", []):
		if status.duration <= 0: continue
		var value = float(status.value) if status.get("value") != null else 0.3
		match status.id:
			"atk_up": mods.atkMult *= 1 + value
			"def_up": mods.defMult *= 1 + value
			"spd_down": mods.spdMult *= maxf(0.01, 1 - value)
			"stun": mods.defMult *= 0.7
			"invincible": mods.damageReduction = 1.0
	return mods

func _controlled(unit: Dictionary) -> bool:
	for id in CONTROL_STATUSES:
		if has_status(unit, id): return true
	return false

func _cleanup_statuses(unit: Dictionary) -> void:
	unit.statuses = unit.statuses.filter(func(status): return status.duration > 0)
	_sync_shield(unit)

func _sync_shield(unit: Dictionary) -> void:
	unit.shield = 0
	for status in unit.statuses:
		if status.id == "shield" and status.duration > 0: unit.shield += int(status.get("shieldHp", 0))

func _absorb(unit: Dictionary, amount: int) -> int:
	var remaining = amount
	for status in unit.statuses:
		if status.id == "shield" and status.duration > 0:
			var absorbed = mini(remaining, int(status.get("shieldHp", 0)))
			status.shieldHp -= absorbed
			remaining -= absorbed
			if absorbed > 0: _emit("shield", unit, unit, absorbed, "护盾吸收 %d" % absorbed)
			if status.shieldHp <= 0: status.duration = 0
	_cleanup_statuses(unit)
	return remaining

func _status_damage(unit: Dictionary, amount: int, source: String) -> void:
	if has_status(unit, "invincible"):
		_emit("miss", {}, unit, 0, unit.name + " 无敌", {"status": source})
		return
	unit.currentHp = maxi(0, int(unit.currentHp) - amount)
	_emit("damage", {}, unit, amount, unit.name + " · " + source + " -%d" % amount, {"status": source, "isCrit": false})

func element_mult(attacker: String, defender: String) -> float:
	if not ELEMENT_ADVANTAGE.has(attacker): return 1.0
	if ELEMENT_ADVANTAGE[attacker][0] == defender: return 1.5
	if ELEMENT_ADVANTAGE[attacker][1] == defender: return 0.75
	return 1.0

func _effect_sum(type: String) -> float:
	var sum = 0.0
	for effect in _effects:
		if effect.get("type") == type: sum += float(effect.get("value", 0))
	return sum

func _gain_energy(unit: Dictionary, amount: float) -> void:
	unit.energy = clampi(int(unit.energy + amount), 0, 100)

func _c6(unit: Dictionary) -> bool:
	return bool(unit.get("isAlly", false)) and int(unit.get("constellation", 0)) >= 6

func _report_deaths() -> void:
	for unit in state.allies + state.enemies:
		if unit.currentHp <= 0 and not unit.deathReported:
			unit.deathReported = true
			_emit("death", {}, unit, 0, unit.name + " 倒下了")

func _emit(type: String, actor: Dictionary, target: Dictionary, amount: int, text: String, extra: Dictionary = {}) -> void:
	var event = {"type": type, "actor": actor.get("uid", ""), "target": target.get("uid", ""), "amount": amount, "text": text}
	event.merge(extra, true)
	_events.append(event)

func _publish() -> void:
	state.events = _events.duplicate(true)
	state.steps = _steps
	state.log.append_array(_events.duplicate(true))
	if state.log.size() > 300: state.log = state.log.slice(state.log.size() - 300)

func _error(message: String) -> Dictionary:
	return {"success": false, "error": message, "events": []}
