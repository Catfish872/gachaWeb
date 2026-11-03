extends RefCounted
## Deterministic combat simulation. No scene nodes, timers, global state or saves.
## Each accepted act/auto_step produces one bounded batch of animation events.

const AbyssBalance = preload("res://scripts/abyss_balance.gd")

const ENEMY_RECOVERY_SKILL := "enemy_recover"
const CONTROL_STATUSES = ["freeze", "stun", "electrify"]
const STATUS_IDS = ["wind_armor", "wind_oath", "burn", "freeze", "stun", "poison", "electrify", "regen", "atk_up", "def_up", "spd_down", "shield", "invincible", "taunt", "ember_oath", "ember_lantern_burn", "ember_lantern_direct"]
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
var _control_check: Dictionary = {}

func _init(data: Dictionary = {}) -> void:
	catalog = data
	rng.seed = 1

func start(config: Dictionary, allies: Array, rogue_effects: Array = []) -> Dictionary:
	if config.has("seed"):
		rng.seed = int(config.seed)
	_events = []
	_is_abyss = bool(config.get("isAbyss", false)) or bool(config.get("isExtraction", false))
	_effects = rogue_effects.duplicate(true) if _is_abyss else []
	_steps = 0
	_control_check = {}
	_max_steps = clampi(int(config.get("maxSteps", 10000)), 10, 100000)
	state = {"phase": "player_turn", "allies": [], "enemies": [], "turn": 0,
		"wave": 1, "events": [], "log": [], "config": config.duplicate(true),
		"turnOrder": [], "currentActor": "", "steps": 0, "reason": "",
		"controlStats": {"electrify": {
			"ally": {"opportunities":0, "skips":0, "expectedSkips":0.0},
			"boss": {"opportunities":0, "skips":0, "expectedSkips":0.0},
			"enemy": {"opportunities":0, "skips":0, "expectedSkips":0.0}}}}
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
	if config.get("isExtraction", false):
		for unit in state.allies:
			var amount := int(config.get("equipmentShields",{}).get(unit.id,0))
			if amount > 0:
				unit.statuses.append({"id":"shield","duration":1,"value":null,"stacks":1,"shieldHp":amount,"source":"expedition_equipment","persistent":true})
				_sync_shield(unit)
		_sync_equipment_shields()
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
	if not is_ally and skill_id == ENEMY_RECOVERY_SKILL:
		return {"name": "收势调整", "effects": [], "animation": "fireball"}
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
	if _controlled(actor):
		return _error("当前角色受到控制，请等待下一次行动")
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
		_consume_action_statuses(actor)
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
	# Ready ultimates always fire, including full-HP healing and on-heal effects.
	if skill.get("type", "") == "ultimate": return false
	var has_heal := false
	for effect in skill.get("effects", []):
		if effect.get("type", "") == "damage": return false
		if effect.get("type", "") == "heal": has_heal = true
	if not has_heal: return false
	var threshold := 0.90
	for friend in _friends(actor):
		if float(friend.currentHp) / friend.maxHp < threshold: return false
	return true

func _take_action(actor: Dictionary, sid: String, target_id: String) -> Dictionary:
	_events = []
	_execute_skill(actor, sid, target_id)
	_record_enemy_pacing(actor, sid)
	_record_enemy_cycle_action(actor, sid)
	_after_active_action(actor)
	_consume_action_statuses(actor)
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
		# Permanent set stats are already in stats; only wearer-bound triggers travel here.
		"ownerEffects": input.get("ownerEffects", []).duplicate(true),
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
		var web_endless: bool = AbyssBalance.uses_web_endless(state.config)
		var scale = wave.get("scaleMult", state.config.get("scaleMult", 1.0))
		var mods = AbyssBalance.web_endless_scale(int(state.config.get("floor", 1)), id) if web_endless else (abyss_scale(int(state.config.get("floor", 1)), id) if state.config.get("isAbyss", false) else {})
		if not web_endless:
			if scale is Dictionary: mods = scale
			elif mods.is_empty(): mods = {"hpMod": scale, "atkMod": scale, "defMod": scale, "spdMod": 1.0}
		if state.config.get("isAbyss", false):
			if not web_endless: mods = AbyssBalance.apply_difficulty(mods, int(state.config.get("difficulty", 0)))
			mods = AbyssBalance.apply_modifier(mods, state.config.get("encounterModifier", {}))
		# New chapter enemies carry a separate abyss budget; story and expeditions retain their own base.
		var bs: Dictionary = data.get("abyssBaseStats", data.baseStats) if state.config.get("isAbyss", false) and not state.config.get("isExtraction", false) else data.baseStats
		var final_boss := bool(state.config.get("isExtraction", false)) and bool(state.config.get("isBoss", false)) and bool(data.get("isBoss", false)) and int(state.config.get("act", 1)) == int(state.config.get("maxActs", 3)) and is_equal_approx(float(state.config.get("finalBossStatMultiplier", 1.0)), 1.15)
		var boss_factor := 1.15 if final_boss else 1.0
		var stats = {"maxHp": maxi(1, int(bs.hp * mods.get("hpMod", 1) * boss_factor)),
			"atk": maxi(1, int(bs.atk * mods.get("atkMod", 1) * boss_factor)), "def": maxi(0, int(bs.def * mods.get("defMod", 1) * boss_factor)),
			"spd": maxf(1, bs.spd * mods.get("spdMod", 1) * boss_factor), "cri": 0.1, "criDmg": 1.5}
		# Newly issued encounters may allocate a final attack budget per support.
		# Missing/invalid entries preserve the normal scaling and old saved encounters.
		var attack_overrides = state.config.get("enemyAttackOverrides", {})
		if attack_overrides is Dictionary and attack_overrides.has(id):
			var attack_override = attack_overrides[id]
			if (attack_override is int or attack_override is float) and is_finite(float(attack_override)) and float(attack_override) >= 0.0:
				stats.atk = maxi(1, int(attack_override))
		if web_endless: stats.spd = maxf(1.0, floorf(float(stats.spd)))
		if _is_abyss and not web_endless:
			var speed_limit := AbyssBalance.MAX_ENEMY_SPEED
			if state.config.get("isExtraction", false):
				speed_limit = 120.0
				# New final-boss encounters carry the explicit 15% budget marker.
				# Earlier issued encounters and non-boss units keep their original limit.
				if final_boss:
					speed_limit *= 1.15
			stats.spd = minf(speed_limit, stats.spd)
		state.enemies.append({"uid": "enemy_%d_%d" % [state.wave, i], "id": id, "dataId": id,
			"name": data.name, "element": data.element, "isAlly": false,
			"archetype": data.get("type", "normal"),
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
					var source: Dictionary = {} if effect.get("sourcePolicy", "") == "blessing" else _battle_start_source()
					apply_status(pool[index], effect.statusId, int(effect.get("duration", 1)), effect.get("value"), source, -1, {"battleStart":true})
					pool.remove_at(index)

func _battle_start_source() -> Dictionary:
	var strongest: Dictionary = {}
	var attack := -1
	for unit in _alive(state.allies):
		var current := _effective_atk(unit)
		if current > attack:
			strongest = unit
			attack = current
	return strongest

func dot_rule(key: String, fallback: float) -> float:
	return maxf(0.0, float(catalog.get("CombatRules", {}).get(key, fallback)))

func poison_damage_preview(unit: Dictionary) -> Dictionary:
	var attack_sum := 0.0
	var count := 0
	var sources: Dictionary = {}
	for status in unit.get("statuses", []):
		if status.get("id", "") != "poison" or int(status.get("duration", 0)) <= 0 or not status.has("dotAttack"): continue
		var attack := maxf(0.0, float(status.dotAttack))
		attack_sum += attack
		count += 1
		var uid := str(status.get("sourceUid", ""))
		if not sources.has(uid):sources[uid] = {"uid":uid, "name":str(status.get("sourceName", "")), "attackSum":0.0, "stacks":0}
		sources[uid].attackSum += attack
		sources[uid].stacks += 1
	var coefficient := dot_rule("poisonAttackRatio", 0.02)
	var growth := dot_rule("poisonStackGrowth", 0.10)
	var amplified_attack := 0.0
	for entry in sources.values():
		var source := get_unit(str(entry.uid))
		amplified_attack += float(entry.attackSum) * (1.0 + _external_deepening(source, unit))
	var amount := maxi(1, int(amplified_attack * coefficient * (1.0 + growth * maxf(0.0, float(count - 1))))) if count > 0 else 0
	return {"amount":amount, "stacks":count, "sources":sources.values()}

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
	_order_contiguous_allies()
	_cursor = 0
	state.turn += 1
	state.turnOrder = _queue.map(func(unit): return unit.uid)
	_emit("round", {}, {}, state.turn, "第 %d 回合" % state.turn)
	if state.config.get("isAbyss", false) and state.turn in [21, 40]:
		for enemy in _alive(state.enemies):
			if enemy.isBoss:
				_emit("enrage", enemy, enemy, int((boss_enrage_mult(enemy) - 1.0) * 100), enemy.name + (" · 持久战狂暴：每回合攻击 +5%，最多 +100%" if state.turn == 21 else " · 狂暴达到上限：攻击 +100%"))
	if state.config.get("isExtraction", false) and int(state.config.get("difficulty", 0)) >= 3 and state.turn in [16, 25]:
		for enemy in _alive(state.enemies):
			if enemy.isBoss:
				_emit("enrage", enemy, enemy, int((boss_enrage_mult(enemy) - 1.0) * 100), enemy.name + (" · 持久战狂暴：每回合攻击 +5%，最多 +50%" if state.turn == 16 else " · 狂暴达到上限：攻击 +50%"))
	# Zeph's C6 applies before allies act, so its one-round buff can be used.
	for unit in _alive(state.allies):
		if unit.id == "zeph" and _c6(unit) and _above_average_speed(unit):
			var friends = _friends(unit).filter(func(friend): return friend.uid != unit.uid)
			if not friends.is_empty():
				friends.sort_custom(func(a,b): return a.stats.spd * modifiers(a).spdMult < b.stats.spd * modifiers(b).spdMult)
				apply_status(friends[0], "atk_up", 1, 0.3, unit)

func _order_contiguous_allies() -> void:
	# Speed decides enemy boundaries; formation decides order inside each ally run.
	var formation: Dictionary = {}
	for i in range(state.allies.size()):
		formation[state.allies[i].uid] = i
	var start := 0
	while start < _queue.size():
		if not _queue[start].isAlly:
			start += 1
			continue
		var end := start + 1
		while end < _queue.size() and _queue[end].isAlly:
			end += 1
		var allies := _queue.slice(start, end)
		allies.sort_custom(func(a, b): return formation[a.uid] < formation[b.uid])
		for i in range(allies.size()):
			_queue[start + i] = allies[i]
		start = end

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
			if state.config.get("isExtraction", false) and int(state.turn) >= 40:
				_finish("defeat", "战区封锁，行动失败")
				return
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
		_prepare_control_check(actor)
		if _controlled(actor):
			_emit("skip", actor, actor, 0, actor.name + " 因控制效果跳过行动", {"statusId": _control_check.get("reason", "")})
			_consume_action_statuses(actor)
			_cursor += 1
			_steps += 1
			continue
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
		var poison_done := false
		for status in unit.statuses.duplicate():
			if unit.currentHp <= 0: break
			match status.id:
				"burn":
					if status.has("dotAttack"):
						var amount := maxi(1, int(float(status.dotAttack) * dot_rule("burnAttackRatio", 0.18) * burn_damage_multiplier(get_unit(str(status.get("sourceUid", ""))), unit)))
						_status_damage(unit, amount, "burn", {"sourceUid":str(status.get("sourceUid", "")), "sourceName":str(status.get("sourceName", ""))})
				"poison":
					if not poison_done:
						poison_done = true
						var total := poison_damage_preview(unit)
						if int(total.amount) > 0:
							var source_uid := str(total.sources[0].uid) if total.sources.size() == 1 else ""
							_status_damage(unit, int(total.amount), "poison", {"sourceUid":source_uid, "dotSources":total.sources, "poisonStacks":int(total.stacks)})
				"regen": _heal(unit, unit, maxi(1, int(unit.maxHp * 0.08)), "regen", false, "status")
		if unit.currentHp > 0 and unit.passiveId == "tide_passive":
			_heal(unit, unit, maxi(1, int(unit.maxHp * (0.06 if _c6(unit) else 0.03))), "tide_passive", false, "passive")
		for sid in unit.cooldowns: unit.cooldowns[sid] = maxi(0, int(unit.cooldowns[sid]) - 1)

	# Settle every source before expiring buffs: ally ordering must not change DOT amplification.
	for unit in state.allies + state.enemies:
		for status in unit.statuses:
			if not status.id in CONTROL_STATUSES and not status.get("persistent", false): status.duration -= 1
		_cleanup_statuses(unit)

func _available(unit: Dictionary) -> Array:
	var result: Array = []
	var skills = unit.skills.duplicate()
	for cycle_sid in _enemy_action_cycle(unit):
		if not skills.has(cycle_sid): skills.append(cycle_sid)
	if unit.get("inPhase2", false):
		for sid in unit.get("phase2Skills", []):
			if not skills.has(sid): skills.append(sid)
	for sid in skills:
		var data = skill_data(sid, unit.isAlly)
		if data.is_empty(): continue
		if int(unit.cooldowns.get(sid, 0)) > 0: continue
		if unit.isAlly and data.get("type", "") == "ultimate" and unit.energy < int(data.get("energyCost", 100)): continue
		result.append(sid)
	var pacing := _enemy_pacing_config(unit)
	if not pacing.is_empty():
		var fallback := str(pacing.get("fallbackSkill", ""))
		if not fallback.is_empty() and not skill_data(fallback, false).is_empty() and int(unit.cooldowns.get(fallback, 0)) <= 0 and not result.has(fallback):
			result.append(fallback)
		if not result.has(ENEMY_RECOVERY_SKILL): result.append(ENEMY_RECOVERY_SKILL)
	return result

func _enemy_choice(unit: Dictionary, skills: Array) -> String:
	var cycle := _enemy_action_cycle(unit)
	if not cycle.is_empty():
		_sync_enemy_cycle_phase(unit)
		var sid := str(cycle[posmod(int(unit.get("actionCycleCursor", 0)), cycle.size())])
		return sid if skills.has(sid) else ENEMY_RECOVERY_SKILL
	var pacing := _enemy_pacing_config(unit)
	if not pacing.is_empty(): return _paced_enemy_choice(unit, skills, pacing)
	return _legacy_enemy_choice(unit, skills)

# Opt-in, data-defined cycles preserve telegraph/action order in every mode.
# Cursor changes only after an executed cycle skill; control skips leave it intact.
func _enemy_action_cycle(unit: Dictionary) -> Array:
	if unit.get("isAlly", true): return []
	var data: Dictionary = catalog.get("EnemyData", {}).get(str(unit.get("dataId", unit.get("id", ""))), {})
	var cycle = data.get("phase2ActionCycle", []) if unit.get("inPhase2", false) else []
	if not cycle is Array or cycle.is_empty(): cycle = data.get("actionCycle", [])
	return cycle if cycle is Array else []

func _sync_enemy_cycle_phase(unit: Dictionary) -> void:
	var phase2 := bool(unit.get("inPhase2", false))
	if phase2 == bool(unit.get("actionCyclePhase2", false)): return
	var previous := str(unit.get("actionCycleLastSkill", ""))
	var warned := bool(skill_data(previous, false).get("telegraphNext", false))
	unit.actionCycleCursor = 1 if warned and _enemy_action_cycle(unit).size() > 1 else 0
	unit.actionCyclePhase2 = phase2

func _record_enemy_cycle_action(unit: Dictionary, sid: String) -> void:
	var cycle := _enemy_action_cycle(unit)
	if cycle.is_empty(): return
	_sync_enemy_cycle_phase(unit)
	var index := posmod(int(unit.get("actionCycleCursor", 0)), cycle.size())
	if sid != str(cycle[index]): return
	unit.actionCycleLastSkill = sid
	unit.actionCycleCursor = (index + 1) % cycle.size()

func _legacy_enemy_choice(unit: Dictionary, skills: Array) -> String:
	if unit.get("aiPattern", "") in ["telegraphed", "low_hp_charge"] and unit.skills.size() >= 2:
		var warning := str(unit.skills[0])
		var heavy := str(unit.skills[1])
		if unit.get("chargeReady", false) and skills.has(heavy):
			unit.chargeReady = false
			unit.chargeSpent = true
			return heavy
		var can_charge: bool = unit.aiPattern == "telegraphed" or (not unit.get("chargeSpent", false) and float(unit.currentHp) / unit.maxHp < 0.35)
		if can_charge and skills.has(warning):
			unit.chargeReady = true
			return warning
		# The third skill is the ordinary strike above the charge threshold.
		if unit.skills.size() > 2 and skills.has(unit.skills[2]): return str(unit.skills[2])
		if skills.has(warning): return warning
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

# Pacing is opt-in and mode-local. Missing keys on older battle dictionaries are safe.
func _enemy_pacing_config(unit: Dictionary) -> Dictionary:
	if unit.get("isAlly", true) or not _is_abyss: return {}
	var data: Dictionary = catalog.get("EnemyData", {}).get(str(unit.get("dataId", unit.get("id", ""))), {})
	var pacing = data.get("expeditionAI", {})
	return pacing if pacing is Dictionary else {}

func _enemy_skill_is_aoe(sid: String) -> bool:
	# Classify declared hostile targets, even with one survivor or a dead caster.
	# Team shields/buffs target all_allies and do not count as hostile area attacks.
	for effect in skill_data(sid, false).get("effects", []):
		if str(effect.get("target", "single")) not in ["all", "all_enemies", "chain3"]: continue
		if effect.get("type", "") == "damage": return true
		if effect.get("type", "") == "status" and effect.get("statusId", "") in ["burn", "poison", "freeze", "stun", "electrify", "spd_down"]: return true
	return false

func _record_enemy_pacing(unit: Dictionary, sid: String) -> void:
	var pacing := _enemy_pacing_config(unit)
	if pacing.is_empty(): return
	if unit.get("aiPattern", "") == "low_hp_charge" and unit.skills.size() >= 2:
		if sid == str(unit.skills[0]): unit.chargeReady = true
		elif sid == str(unit.skills[1]):
			unit.chargeReady = false
			unit.chargeSpent = true
	if sid == ENEMY_RECOVERY_SKILL:
		unit.pacingRecoveryPending = false
		return
	var requires_recovery := _enemy_skill_is_aoe(sid)
	for effect in skill_data(sid, false).get("effects", []):
		if effect.get("type", "") == "damage" and pacing.get("recoveryAfterDamage", false): requires_recovery = true
	# Only an executed allowed recovery action clears this; phase/control skips retain it.
	if requires_recovery:
		unit.pacingRecoveryPending = true
	elif pacing.get("recoveryPolicy", "idle") == "single" and _enemy_skill_has_single_damage(sid):
		unit.pacingRecoveryPending = false

func _enemy_skill_has_single_damage(sid: String) -> bool:
	if _enemy_skill_is_aoe(sid): return false
	for effect in skill_data(sid, false).get("effects", []):
		if effect.get("type", "") == "damage": return true
	return false

func _paced_enemy_choice(unit: Dictionary, skills: Array, pacing: Dictionary) -> String:
	if unit.get("pacingRecoveryPending", false):
		if pacing.get("recoveryPolicy", "idle") == "single":
			var single_skills: Array = skills.filter(func(sid): return _enemy_skill_has_single_damage(str(sid)))
			if not single_skills.is_empty(): return _legacy_enemy_choice(unit, single_skills)
		return ENEMY_RECOVERY_SKILL
	var candidates: Array = skills.filter(func(sid): return sid != ENEMY_RECOVERY_SKILL)
	# Preserve the puppet's one-time low-HP warning and charge state. A failed
	# intent roll waits without reapplying the warning buff or consuming its charge.
	var low_hp_charge: bool = unit.get("aiPattern", "") == "low_hp_charge" and unit.skills.size() >= 2
	if low_hp_charge:
		var warning := str(unit.skills[0])
		var heavy := str(unit.skills[1])
		if unit.get("chargeSpent", false) or (not unit.get("chargeReady", false) and float(unit.currentHp) / unit.maxHp >= 0.35):
			candidates.erase(warning)
			candidates.erase(heavy)
		elif not unit.get("chargeReady", false):
			if candidates.has(warning): return warning
			return ENEMY_RECOVERY_SKILL
		else:
			candidates = [heavy] if candidates.has(heavy) else []
	elif unit.get("aiPattern", "") == "boss" and unit.get("inPhase2", false):
		var phase_skills: Array = candidates.filter(func(sid): return unit.get("phase2Skills", []).has(sid))
		if not phase_skills.is_empty(): candidates = phase_skills
	var area: Array = candidates.filter(func(sid): return _enemy_skill_is_aoe(str(sid)))
	var ordinary: Array = candidates.filter(func(sid): return not _enemy_skill_is_aoe(str(sid)))
	# Exactly one probability gate per actual selection; availability/UI never draws RNG.
	var area_chance := clampf(float(pacing.get("aoeChance", 0.25)), 0.0, 1.0) if not area.is_empty() else 0.0
	var idle_chance := clampf(float(pacing.get("idleChance", 0.0)), 0.0, 1.0 - area_chance)
	var intent_roll := rng.randf() if area_chance + idle_chance > 0.0 else 1.0
	if intent_roll < area_chance:
		var chosen := str(area[0]) if area.size() == 1 else str(area[rng.randi_range(0, area.size() - 1)])
		return chosen
	if intent_roll < area_chance + idle_chance or ordinary.is_empty(): return ENEMY_RECOVERY_SKILL
	if low_hp_charge: return str(ordinary[0])
	return _legacy_enemy_choice(unit, ordinary)

func _targets(kind: String, caster: Dictionary, selected: String, cache: Dictionary) -> Array:
	var friends = _friends(caster)
	var foes = _foes(caster)
	var manual = get_unit(selected)
	match kind:
		"self": return [caster] if caster.currentHp > 0 else []
		"all_allies": return friends
		"boss_ally":
			for friend in friends:
				if bool(friend.get("isBoss", false)): return [friend]
			return []
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
	_extra_flags = {}
	var skill = skill_data(sid, caster.isAlly)
	var kind = str(skill.get("type", "enemy"))
	_emit("skill", caster, {}, 0, caster.name + " · " + str(skill.get("name", sid)), {"skill_id": sid, "skill_type": kind, "animation": skill.get("animation", "slash")})
	if caster.isAlly:
		if kind == "ultimate": caster.energy = 0
		else:
			_gain_energy(caster, action_energy_gain(caster, skill))
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
					var amount = skill_effect_amount(caster, effect, target)
					_heal(caster, target, amount, sid, true, kind)
					had_heal = true
				"status":
					if rng.randf() < float(effect.get("chance", 1.0)):
						var shield_amount := skill_effect_amount(caster, effect, target) if effect.get("statusId", "") == "shield" else -1
						apply_status(target, str(effect.statusId), int(effect.get("duration", 1)), effect.get("value"), caster, shield_amount, {"refreshDuration":bool(effect.get("refreshDuration",false))})
	if had_heal: _gain_owner_action_energy(caster, "energyOnActiveHeal")
	if caster.id == "ayla" and _c6(caster) and had_heal:
		for friend in _friends(caster): apply_status(friend, "regen", 1, null, caster)

	if caster.get("id", "") == "selin" and kind == "ultimate":
		# Native hits and C6 resolve before refreshing the team aura.
		if _c6(caster):
			for foe in _foes(caster): _extra_damage(caster, foe, 0.6, "fire", "selin_ult_c6")
		for friend in _friends(caster):
			if friend.uid != caster.uid: _refresh_combat_buff(friend, "ember_oath", 0.8, 2, caster)

func action_energy_gain(caster: Dictionary, skill: Dictionary) -> int:
	if not caster.get("isAlly", false) or skill.get("type", "") == "ultimate": return 0
	var energy_bonus = float(caster.stats.get("energyRate", 0.0)) + _effect_sum("energyGainMult")
	return int(floor(float(skill.get("energyGain", 15)) * maxf(0, 1 + energy_bonus)))

func owner_effect_sum(unit: Dictionary, type: String) -> float:
	var total := 0.0
	for effect in unit.get("ownerEffects", []):
		if effect.get("type", "") == type: total += float(effect.get("value", 0.0))
	return total

func _gain_owner_action_energy(caster: Dictionary, type: String) -> void:
	if not caster.get("isAlly", false): return
	var amount := owner_effect_sum(caster, type)
	var flag := "owner:%s:%s" % [str(caster.uid), type]
	if amount <= 0.0 or _extra_flags.has(flag): return
	_extra_flags[flag] = true
	_gain_energy(caster, amount)

func effective_speed(unit: Dictionary) -> float:
	return float(unit.stats.spd) * float(modifiers(unit).spdMult)

func effect_source_value(caster: Dictionary, effect: Dictionary, target: Dictionary = {}, raw: bool = false) -> int:
	# scalingStat is optional. Legacy shields use the recipient's maximum HP;
	# declaring a source makes damage/healing/shields use the caster's stated stat.
	if effect.get("statusId", "") == "shield" and not effect.has("scalingStat"):
		return int(target.get("maxHp", caster.get("maxHp", 1)))
	match str(effect.get("scalingStat", "atk")):
		"maxHp", "hp": return int(caster.maxHp)
		"def": return maxi(0, int(caster.stats.def * (1.0 if raw else float(modifiers(caster).defMult))))
		_: return int(caster.stats.atk) if raw or effect.get("rawAtk", false) else _effective_atk(caster)

func skill_effect_amount(caster: Dictionary, effect: Dictionary, target: Dictionary = {}) -> int:
	# Shared by live skills and loadout evaluation. Passive/regen/utility calls
	# keep their original paths and never receive active-skill set modifiers.
	var source := effect_source_value(caster, effect, target)
	if effect.get("statusId", "") == "shield":
		var value := float(effect.value) if effect.get("value") != null else 0.3
		var coefficient := float(effect.get("multiplier", value)) if effect.has("scalingStat") else value
		return maxi(0, int(source * coefficient * maxf(0.0, 1.0 + owner_effect_sum(caster, "skillShieldMult"))))
	var heal_mult := float(effect.get("multiplier", 1.0)) * (maxf(0, 1 + _effect_sum("healMult")) if caster.isAlly else 1.0)
	heal_mult *= maxf(0.0, 1.0 + owner_effect_sum(caster, "activeSkillHealMult"))
	return maxi(1, int(source * heal_mult))

func _effective_atk(unit: Dictionary) -> int:
	var mult = modifiers(unit).atkMult
	if unit.passiveId == "zeph_passive" and _above_average_speed(unit): mult *= 1.15
	mult *= boss_enrage_mult(unit)
	return maxi(1, int(unit.stats.atk * mult))

func boss_enrage_mult(unit: Dictionary) -> float:
	if not _is_abyss or unit.isAlly or not unit.isBoss: return 1.0
	if state.config.get("isExtraction", false):
		return 1.0 + clampf(float(int(state.get("turn", 1)) - 15) * 0.05, 0.0, 0.5) if int(state.config.get("difficulty", 0)) >= 3 else 1.0
	return 1.0 + clampf(float(int(state.get("turn", 1)) - 20) * 0.05, 0.0, 1.0)

func _above_average_speed(unit: Dictionary) -> bool:
	var all = _alive(state.allies + state.enemies)
	var sum = 0.0
	for other in all: sum += other.stats.spd * modifiers(other).spdMult
	return unit.stats.spd * modifiers(unit).spdMult > sum / maxi(1, all.size())

func _raw_effect_damage(caster: Dictionary, target: Dictionary, skill: Dictionary, effect: Dictionary, mult: float, critical: bool) -> float:
	var source := effect_source_value(caster, effect, target)
	var mods := modifiers(target)
	var raw := source * mult * (100.0 / (100.0 + maxf(0, target.stats.def * mods.defMult * (1.0 - float(effect.get("defPierce", 0.0))))))
	var element := str(skill.get("element", effect.get("element", caster.element)))
	raw *= element_mult(element, target.element) * (float(caster.stats.criDmg) if critical else 1.0)
	if effect.get("trueDamage", false): raw = effect_source_value(caster, effect, target, true) * mult
	return raw

func predict_effect_damage(caster: Dictionary, target: Dictionary, skill: Dictionary, effect: Dictionary, critical: bool = false, follow_up: bool = false, chain: float = 1.0, blocked: bool = false) -> int:
	# Exact direct-hit formula before shield absorption. Pure: no RNG or state writes.
	if int(target.get("currentHp", 0)) <= 0 or has_status(target, "invincible"): return 0
	var mult := float(effect.get("multiplier", 1.0)) * chain
	if not follow_up: mult *= _damage_multiplier(caster, target, str(skill.get("type", "enemy")), false)
	else: mult *= _owner_follow_up_multiplier(caster, target)
	var raw := _raw_effect_damage(caster, target, skill, effect, mult, critical and not follow_up)
	var taken := _damage_taken_multiplier(target, caster)
	var preliminary := maxi(1, int(raw * taken))
	if target.get("id", "") == "lorin" and _c6(target) and not target.get("c6Used", false) and target.get("shield", 0) > 0 and preliminary > target.maxHp * 0.3: return 0
	if blocked and target.get("passiveId", "") == "lorin_passive" and target.currentHp > target.maxHp * 0.5: taken *= 0.5
	return maxi(1, int(raw * maxf(0.1, taken * maxf(0.0, 1.0 - float(modifiers(target).damageReduction)))))

func expected_effect_damage(caster: Dictionary, target: Dictionary, skill: Dictionary, effect: Dictionary, chain: float = 1.0) -> float:
	var chance := clampf(float(caster.stats.cri), 0.0, 1.0)
	var block_chance := 0.3 if target.get("passiveId", "") == "lorin_passive" and target.currentHp > target.maxHp * 0.5 else 0.0
	var result := 0.0
	for critical in [false, true]:
		var critical_weight := chance if critical else 1.0 - chance
		if critical_weight <= 0.0: continue
		var damage := float(predict_effect_damage(caster, target, skill, effect, critical, false, chain, false))
		if block_chance > 0.0:
			damage = (1.0 - block_chance) * damage + block_chance * predict_effect_damage(caster, target, skill, effect, critical, false, chain, true)
		result += critical_weight * damage
	return result

func _damage(caster: Dictionary, target: Dictionary, skill: Dictionary, sid: String, effect: Dictionary, mult: float, follow_up: bool = false) -> int:
	if int(target.get("currentHp", 0)) <= 0: return 0
	if has_status(target, "invincible"):
		_emit("miss", caster, target, 0, target.name + " 无敌", {"skill_id": sid})
		return 0
	var skill_type = str(skill.get("type", "enemy"))
	if not follow_up:
		mult *= _damage_multiplier(caster, target, skill_type, false)
	else:
		mult *= _owner_follow_up_multiplier(caster, target)
	var element = str(skill.get("element", effect.get("element", caster.element)))
	var mods = modifiers(target)
	var crit_chance = float(caster.stats.cri) if not follow_up else 0.0
	var crit = rng.randf() < crit_chance
	var element_bonus = element_mult(element, target.element)
	var raw := _raw_effect_damage(caster, target, skill, effect, mult, crit)
	var taken_mult := _damage_taken_multiplier(target, caster)
	var damage = maxi(1, int(raw * taken_mult))
	if target.id == "lorin" and _c6(target) and not target.c6Used and target.shield > 0 and damage > target.maxHp * 0.3:
		target.c6Used = true
		apply_status(target, "invincible", 1, null, target)
		_emit("miss", caster, target, 0, "绝对防壁阻挡了致命攻击", {"skill_id": sid})
		return 0
	if target.passiveId == "lorin_passive" and target.currentHp > target.maxHp * 0.5 and rng.randf() < 0.3:
		taken_mult *= 0.5
		_emit("block", target, target, 0, "格挡 · 伤害降低 50%")
	# Ordinary reductions share one 90% ceiling; shields absorb afterwards.
	damage = maxi(1, int(raw * maxf(0.1, taken_mult * maxf(0.0, 1.0 - mods.damageReduction))))
	damage = _absorb(target, damage)
	var hp_before := int(target.currentHp)
	target.currentHp = maxi(0, int(target.currentHp) - damage)
	_emit("damage", caster, target, damage, "%s → %s  -%d" % [caster.name, target.name, damage], {"skill_id": sid, "isCrit": crit, "element": element, "elementMult": element_bonus, "follow_up": follow_up, "effectiveHpDamage":mini(damage,hp_before), "hpBefore":hp_before, "defPierce":float(effect.get("defPierce",0.0)), "followUpTag":str(effect.get("followUpTag", ""))})
	if crit and not follow_up: _gain_owner_action_energy(caster, "energyOnCrit")
	if damage <= 0: return damage
	if caster.isAlly:
		var drain := maxf(0.0, _effect_sum("lifesteal"))
		if drain > 0.0: _heal(caster, caster, maxi(1, int(mini(damage, hp_before) * drain)), "rogue_lifesteal", false, "status")
		if target.currentHp <= 0: _gain_energy(caster, maxf(0.0, _effect_sum("energyOnKill")))
	if follow_up: return damage
	if caster.isAlly:
		var key := "wind_hits_" + str(target.uid)
		_extra_flags[key] = int(_extra_flags.get(key, 0)) + 1
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

func _owner_follow_up_multiplier(caster: Dictionary, target: Dictionary) -> float:
	# Direct set damage bonuses also cover follow-up hits. Trigger processing still
	# returns at the existing follow_up boundary, so these hits start no proc chains.
	var status := _timed_status_value(caster, "ember_lantern_direct") if has_status(target, "burn") else 0.0
	var speed := 0.0
	for effect in caster.get("ownerEffects", []):
		if effect.get("type", "") == "damageVsStatus" and has_status(target, str(effect.get("statusId", ""))): status += float(effect.get("value", 0.0))
		elif effect.get("type", "") == "damageWhenFasterThanTarget" and effective_speed(caster) > effective_speed(target): speed += float(effect.get("value", 0.0))
		elif effect.get("type", "") == "windPierceOwner" and has_status(target, "wind_armor"): status += float(effect.get("value", 0.0))
	return maxf(0.1, 1.0 + status) * maxf(0.1, 1.0 + speed) * (1.0 + _external_deepening(caster, target))

func _damage_multiplier(caster: Dictionary, target: Dictionary, kind: String, include_taken: bool = true) -> float:
	var result = 1.0
	if caster.isAlly:
		var key = {"normal": "normalDmgBonus", "skill": "skillDmgBonus", "ultimate": "ultDmgBonus"}.get(kind, "")
		result *= 1.0 + float(caster.stats.get(key, 0.0))
		var deepening := _external_deepening(caster, target)
		if caster.passiveId == "kaldi_passive" and has_status(target, "burn"): deepening += 0.2
		if caster.passiveId == "cinder_passive" and kind in ["skill", "ultimate"] and has_status(target, "burn"): deepening += 0.7 if _c6(caster) else 0.4
		if caster.id == "bolt" and _c6(caster) and has_status(target, "electrify"): deepening += 0.35
		result *= 1.0 + deepening
	var buckets = {"status": _timed_status_value(caster, "ember_lantern_direct") if has_status(target, "burn") else 0.0, "type": 0.0, "typeStatus": 0.0, "shield": 0.0, "execute": 0.0, "speed": 0.0}
	for effect in _effects + caster.get("ownerEffects", []):
		var value = float(effect.get("value", 0))
		match effect.get("type", ""):
			"damageWhileShielded":
				if caster.isAlly and caster.shield > 0: buckets.shield += value
			"damageVsLowHp":
				if caster.isAlly and float(target.currentHp) / target.maxHp <= clampf(float(effect.get("threshold", 0.35)), 0.0, 1.0): buckets.execute += value
			"damageVsStatus":
				if caster.isAlly and has_status(target, effect.statusId): buckets.status += value
			"windNativeDamage":
				if caster.isAlly and kind in ["normal", "skill", "ultimate"]: buckets.type += value
			"skillTypeDamage":
				if caster.isAlly and kind == effect.skillType: buckets.type += value
			"skillTypeDamageVsStatus":
				if caster.isAlly and kind == effect.skillType and has_status(target, effect.statusId): buckets.typeStatus += value
			"damageWhenFasterThanTarget":
				if caster.isAlly and effective_speed(caster) > effective_speed(target): buckets.speed += value
	for key in ["status", "type", "typeStatus", "shield", "execute", "speed"]: result *= maxf(0.1, 1.0 + buckets[key])
	return result * _damage_taken_multiplier(target, caster) if include_taken else result

func _damage_taken_multiplier(target: Dictionary, source: Dictionary = {}) -> float:
	if not target.isAlly: return 1.0
	var taken := 0.0
	var taken_status := 0.0
	for effect in _effects + target.get("ownerEffects", []):
		if effect.get("type", "") == "damageTakenMult": taken += float(effect.get("value", 0.0))
		elif effect.get("type", "") == "damageTakenWhileStatus" and has_status(target, str(effect.get("statusId", ""))): taken_status += float(effect.get("value", 0.0))
	# Match the Web buckets: additive within each source, multiplicative across sources.
	var source_factor := 1.0
	if not source.is_empty() and has_status(source, "wind_armor"):
		source_factor = maxf(0.0, 1.0 - (0.20 if _lumi_alive() else 0.0) - _effect_sum("windArmoredGuard"))
	return maxf(0.1, maxf(0.0, 1.0 + taken) * maxf(0.0, 1.0 + taken_status) * source_factor)

func _after_rogue_damage(caster: Dictionary, target: Dictionary, skill: Dictionary, sid: String, element: String) -> void:
	if not caster.isAlly: return
	for i in range(_effects.size()):
		var effect = _effects[i]
		if skill.get("onHitPerActionTarget", false) and effect.get("type", "") in ["applyStatusAfterDamage", "energyOnHitStatus"]:
			var key := "wind_once_%d_%s" % [i, target.uid]
			if _extra_flags.has(key): continue
			_extra_flags[key] = true
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

func apply_status(unit: Dictionary, status_id: String, duration: int, value = null, caster: Dictionary = {}, shield_amount: int = -1, options: Dictionary = {}) -> bool:
	if status_id == "wind_armor":
		if unit.get("currentHp", 0) <= 0 or duration <= 0: return false
		duration += int(_effect_sum("windArmorDuration"))
		var reduction := float(value) if value != null else 0.35
		if not options.get("battleStart", false) and caster.get("passiveId", "") == "lumi_passive" and _c6(caster): reduction = maxf(reduction, 0.45)
		var old: Dictionary = {}
		for st in unit.statuses:
			if st.id == "wind_armor" and int(st.duration) > 0: old = st; break
		if old.is_empty(): unit.statuses.append({"id":"wind_armor","duration":duration,"value":reduction,"stacks":1})
		else:
			old.duration = maxi(old.duration, duration)
			old.value = maxf(float(old.value), reduction)
		if not options.get("battleStart", false): _apply_owner_status_effects(caster, status_id)
		_emit("status", caster, unit, duration, unit.name + " · 破甲", {"status":"wind_armor", "statusId":"wind_armor", "duration":duration, "value":reduction})
		return true
	if not STATUS_IDS.has(status_id) or duration <= 0 or unit.get("currentHp", 0) <= 0: return false
	# Statuses are battle-local; snapshots never fall back to the victim's stats.
	if status_id in ["burn", "poison"] and (caster.is_empty() or not caster.has("stats")):return false
	if status_id == "burn" and caster.get("isAlly", false):
		duration += int(_effect_sum("burnDurationAdd"))
		if caster.get("id", "") == "selin" and _c6(caster): duration += 1
	var dot_attack := _effective_atk(caster) if status_id in ["burn", "poison"] else 0
	var existing: Dictionary = {}
	var refresh := bool(options.get("refreshDuration", false))
	var refresh_source := str(caster.get("uid", ""))
	if status_id != "poison":
		for status in unit.statuses:
			if status.id != status_id or int(status.duration) <= 0 or status.get("source", "") == "expedition_equipment": continue
			if refresh and status.get("refreshSourceUid", "") != refresh_source: continue
			existing = status
			break
	if existing.is_empty():
		existing = {"id": status_id, "duration": duration, "value": value, "stacks": 1}
		if status_id == "shield": existing.shieldHp = shield_amount if shield_amount >= 0 else maxi(0, int(unit.maxHp * (float(value) if value != null else 0.3)))
		unit.statuses.append(existing)
	else:
		existing.duration = duration if refresh else int(existing.duration) + duration
		if value != null: existing.value = value
		if status_id == "shield":
			var added := shield_amount if shield_amount >= 0 else maxi(0, int(unit.maxHp * (float(value) if value != null else 0.3)))
			existing.shieldHp = maxi(int(existing.get("shieldHp", 0)), added) if refresh else int(existing.get("shieldHp", 0)) + added
	if refresh: existing.refreshSourceUid = refresh_source
	if status_id == "burn" and dot_attack >= int(existing.get("dotAttack", 0)):
		existing.dotAttack = dot_attack
		existing.sourceUid = str(caster.get("uid", ""))
		existing.sourceName = str(caster.get("name", ""))
	if status_id == "poison":
		existing.dotAttack = dot_attack
		existing.sourceUid = str(caster.get("uid", ""))
		existing.sourceName = str(caster.get("name", ""))
		existing.duration = 1
		existing.persistent = true
	if status_id == "electrify":
		var chance_bonus := _electrify_source_bonus(caster)
		existing.electrifySkipChanceBonus = maxf(float(existing.get("electrifySkipChanceBonus", chance_bonus)), chance_bonus)
	_sync_shield(unit)
	if not options.get("battleStart", false): _apply_owner_status_effects(caster, status_id)
	_emit("status", caster, unit, duration, unit.name + " · " + status_id, {"status": status_id, "statusId": status_id, "duration": int(existing.duration), "value": value, "persistent":bool(existing.get("persistent",false))})
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
			"wind_armor": mods.defMult *= maxf(0.01, 1.0 - value)
			"invincible": mods.damageReduction = 1.0
	return mods

static func electrify_chance_for_status(data: Dictionary, status: Dictionary = {}) -> float:
	var base := float(data.get("CombatRules", {}).get("electrifySkipChance", 0.35))
	return clampf(base + float(status.get("electrifySkipChanceBonus", 0.0)), 0.0, 1.0)

func electrify_skip_chance(unit: Dictionary) -> float:
	for status in unit.get("statuses", []):
		if status.id == "electrify" and int(status.duration) > 0: return electrify_chance_for_status(catalog, status)
	return electrify_chance_for_status(catalog)

func _electrify_source_bonus(caster: Dictionary) -> float:
	if caster.is_empty(): return 0.0
	var definition: Dictionary = catalog.get("CharacterData" if caster.get("isAlly", false) else "EnemyData", {}).get(str(caster.get("dataId", caster.get("id", ""))), {})
	var bonus := float(definition.get("combatModifiers", {}).get("electrifySkipChanceBonus", 0.0)) + float(caster.get("stats", {}).get("electrifySkipChanceBonus", 0.0))
	if caster.get("isAlly", false):
		for effect in _effects:
			if effect.get("type", "") == "electrifySkipChanceBonus" and (not effect.has("characterId") or effect.characterId == caster.get("id", "")):
				bonus += float(effect.get("value", 0.0))
	return bonus

func _control_token(unit: Dictionary) -> String:
	return "%d:%d:%d:%d:%s" % [int(state.get("wave", 0)), int(state.get("turn", 0)), _cursor, _steps, str(unit.get("uid", ""))]

func control_decision(unit: Dictionary) -> Dictionary:
	# Pure inspection: UI and telemetry never advance combat RNG.
	if unit.get("currentHp", 0) <= 0 or _control_check.get("token", "") != _control_token(unit): return {}
	return _control_check.duplicate(true)

func _prepare_control_check(unit: Dictionary) -> void:
	if unit.get("currentHp", 0) <= 0:
		if _control_check.get("uid", "") == unit.get("uid", ""): _control_check = {}
		return
	var token := _control_token(unit)
	if _control_check.get("token", "") != token:
		_control_check = {"token":token, "uid":unit.uid, "electrifyChecked":false, "electrifySkip":false, "chance":0.0, "reason":""}
	# Deterministic controls take precedence without drawing an unnecessary shock roll.
	for id in ["freeze", "stun"]:
		if has_status(unit, id):
			_control_check.reason = id
			return
	if not has_status(unit, "electrify"): return
	if not _control_check.electrifyChecked:
		var chance := electrify_skip_chance(unit)
		_control_check.chance = chance
		_control_check.electrifySkip = chance >= 1.0 or (chance > 0.0 and rng.randf() < chance)
		_control_check.electrifyChecked = true
		var group := "ally" if unit.isAlly else ("boss" if unit.isBoss else "enemy")
		var counts: Dictionary = state.controlStats.electrify[group]
		counts.opportunities += 1
		counts.expectedSkips += chance
		if _control_check.electrifySkip: counts.skips += 1
	_control_check.reason = "electrify" if _control_check.electrifySkip else ""

func _controlled(unit: Dictionary) -> bool:
	if unit.get("currentHp", 0) <= 0: return false
	for id in ["freeze", "stun"]:
		if has_status(unit, id): return true
	return has_status(unit, "electrify") and _control_check.get("token", "") == _control_token(unit) and bool(_control_check.get("electrifySkip", false))

func _consume_action_statuses(unit: Dictionary) -> void:
	# Each attempted action consumes one turn, whether electrify hits or misses.
	for status in unit.statuses:
		if status.id in CONTROL_STATUSES: status.duration -= 1
	_cleanup_statuses(unit)

func _cleanup_statuses(unit: Dictionary) -> void:
	unit.statuses = unit.statuses.filter(func(status): return status.duration > 0)
	_sync_shield(unit)

func _sync_shield(unit: Dictionary) -> void:
	unit.shield = 0
	for status in unit.statuses:
		if status.id == "shield" and status.duration > 0: unit.shield += int(status.get("shieldHp", 0))

func _absorb(unit: Dictionary, amount: int) -> int:
	var remaining = amount
	var shields: Array = unit.statuses.duplicate()
	shields.sort_custom(func(a,b): return int(a.get("source","")=="expedition_equipment") < int(b.get("source","")=="expedition_equipment"))
	for status in shields:
		if status.id == "shield" and status.duration > 0:
			var absorbed = mini(remaining, int(status.get("shieldHp", 0)))
			status.shieldHp -= absorbed
			remaining -= absorbed
			if absorbed > 0: _emit("shield", unit, unit, absorbed, "护盾吸收 %d" % absorbed, {"source":status.get("source","skill")})
			if status.shieldHp <= 0: status.duration = 0
	_cleanup_statuses(unit)
	_sync_equipment_shields()
	return remaining

# Poison combines sources into one tick; weight source-dependent guard by each
# source's stored attack so an unarmored caster does not inherit another's debuff.
func _status_taken_multiplier(unit: Dictionary, details: Dictionary) -> float:
	var sources: Array = details.get("dotSources", [])
	if sources.size() <= 1: return _damage_taken_multiplier(unit, get_unit(str(details.get("sourceUid", ""))))
	var total := 0.0
	var weighted := 0.0
	for entry in sources:
		var weight := maxf(0.0, float(entry.get("attackSum", 0.0)))
		total += weight
		weighted += weight * _damage_taken_multiplier(unit, get_unit(str(entry.get("uid", ""))))
	return weighted / total if total > 0.0 else _damage_taken_multiplier(unit)

func _status_damage(unit: Dictionary, amount: int, source: String, details: Dictionary = {}) -> void:
	if int(unit.get("currentHp", 0)) <= 0 or amount <= 0: return
	if has_status(unit, "invincible"):
		_emit("miss", {}, unit, 0, unit.name + " 无敌", {"status": source})
		return
	if unit.get("isAlly", false):
		# Player DOT uses the same effective defense and ordinary reduction ceiling
		# as direct hits, then the shared skill/equipment shield ledger. Keep this
		# snapshot-based: ticks remain valid after their caster disappears.
		# A still-present armored source also grants the wind team its source reduction.
		var mods := modifiers(unit)
		var raw := float(amount) * (100.0 / (100.0 + maxf(0.0, float(unit.stats.def) * float(mods.defMult))))
		amount = maxi(1, int(raw * maxf(0.1, _status_taken_multiplier(unit, details) * maxf(0.0, 1.0 - float(mods.damageReduction)))))
		amount = _absorb(unit, amount)
	var hp_before := int(unit.currentHp)
	unit.currentHp = maxi(0, int(unit.currentHp) - amount)
	var extra := details.duplicate(true)
	extra.effectiveHpDamage = mini(amount, hp_before)
	extra.hpBefore = hp_before
	extra.status = source
	extra.damageSource = source
	extra.isCrit = false
	var actor := get_unit(str(details.get("sourceUid", "")))
	_emit("damage", actor, unit, amount, unit.name + " · " + source + " -%d" % amount, extra)

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
		if unit.currentHp <= 0 and _control_check.get("uid", "") == unit.uid: _control_check = {}
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

func _sync_equipment_shields() -> void:
	if not state.get("config",{}).get("isExtraction",false): return
	var total := 0
	for unit in state.allies:
		for status in unit.statuses:
			if status.get("source","") == "expedition_equipment" and status.duration > 0: total += int(status.get("shieldHp",0))
	state.equipmentShieldRemaining = total

# These named buffs refresh; blessing copies remain additive in _effects.
func _refresh_combat_buff(unit: Dictionary, id: String, value: float, duration: int, source: Dictionary) -> void:
	for status in unit.statuses:
		if status.id == id:
			status.duration = duration
			status.value = value
			status.sourceUid = source.uid
			return
	unit.statuses.append({"id":id,"duration":duration,"value":value,"stacks":1,"sourceUid":source.uid})
	_emit("status", source, unit, duration, unit.name + " · " + {"ember_oath":"烬灯誓约","ember_lantern_burn":"织焰","ember_lantern_direct":"引火","wind_oath":"风誓"}.get(id,id), {"status":id,"statusId":id,"duration":duration,"value":value})

func _apply_owner_status_effects(caster: Dictionary, status_id: String) -> void:
	if caster.is_empty() or int(caster.get("currentHp", 0)) <= 0: return
	for effect in caster.get("ownerEffects", []):
		if effect.get("type", "") != "onStatusAppliedPartyFollowUpAmp" or effect.get("statusId", "") != status_id: continue
		var buff_id := str(effect.get("buffId", "wind_oath"))
		var tag := str(effect.get("followUpTag", "innate_piercing"))
		for friend in _friends(caster):
			_refresh_combat_buff(friend, buff_id, float(effect.get("value", 0.4)), int(effect.get("duration", 2)), caster)
			for status in friend.statuses:
				if status.id == buff_id: status.followUpTag = tag

func _timed_follow_up_amp(unit: Dictionary, tag: String) -> float:
	var amount := 0.0
	for status in unit.get("statuses", []):
		if int(status.get("duration", 0)) > 0 and status.get("followUpTag", "") == tag:
			amount += float(status.get("value", 0.0))
	return amount

func _timed_status_value(unit: Dictionary, id: String) -> float:
	var result := 0.0
	for status in unit.get("statuses", []):
		if status.get("id", "") == id and int(status.get("duration", 0)) > 0: result = maxf(result, float(status.get("value", 0)))
	return result

func _external_deepening(caster: Dictionary, target: Dictionary) -> float:
	if caster.is_empty() or not caster.get("isAlly", false): return 0.0
	var value := _timed_status_value(caster, "ember_oath") if has_status(target, "burn") else 0.0
	if has_status(target, "wind_armor") and _lumi_alive(): value += float(catalog.get("CharacterData", {}).get("lumi", {}).get("windArmorDamageDeepening", 0.20))
	return value

func _lumi_alive() -> bool:
	for ally in state.get("allies", []):
		if ally.get("passiveId", "") == "lumi_passive" and int(ally.get("currentHp", 0)) > 0: return true
	return false

func _wind_piercing_hit(caster: Dictionary, target: Dictionary, coefficient: float, primary: bool) -> void:
	if target.currentHp <= 0: return
	var amount := coefficient
	if primary: amount *= maxf(0.0, 1.0 + _timed_follow_up_amp(caster, "innate_piercing") + _effect_sum("windPrimaryAmp"))
	_damage(caster, target, {"type":"follow_up", "element":"wind"}, "wind_primary" if primary else "wind_gold", {"defPierce":1.0, "rawAtk":true, "followUpTag":"innate_piercing" if primary else "blessing_piercing"}, amount, true)


func burn_damage_multiplier(caster: Dictionary, target: Dictionary) -> float:
	if caster.is_empty() or not caster.get("isAlly", false): return 1.0
	var amp := _effect_sum("burnDamageAmp") + _timed_status_value(caster, "ember_lantern_burn")
	return maxf(0.0, 1.0 + amp) * (1.0 + _external_deepening(caster, target))

func burn_remaining_turns(target: Dictionary) -> int:
	var turns := 0
	for status in target.get("statuses", []):
		if status.get("id", "") == "burn": turns = maxi(turns, int(status.get("duration", 0)))
	return turns

func _after_active_action(caster: Dictionary) -> void:
	if caster.get("isAlly", false) and caster.get("currentHp", 0) > 0:
		if caster.get("passiveId", "") == "tiya_passive":
			for target in _foes(caster):
				if has_status(target, "wind_armor") and int(_extra_flags.get("wind_hits_" + str(target.uid), 0)) > 0:
					_wind_piercing_hit(caster, target, 0.66 if _c6(caster) else 0.60, true)
		for effect in _effects:
			if effect.get("type", "") != "windGoldPierce": continue
			for target in _foes(caster):
				if has_status(target, "wind_armor") and int(_extra_flags.get("wind_hits_" + str(target.uid), 0)) >= 2:
					_wind_piercing_hit(caster, target, float(effect.get("multiplier", .36)), false)
	if caster.get("passiveId", "") != "selin_passive" or int(caster.get("currentHp", 0)) <= 0: return
	var detonated := false
	for target in _foes(caster):
		var turns := burn_remaining_turns(target)
		if turns <= 0: continue
		detonated = true
		var amount := maxi(1, int(_effective_atk(caster) * (0.15 + 0.001 * turns) * burn_damage_multiplier(caster, target)))
		# Status damage bypasses defence, crit and every on-hit/energy/lifesteal chain.
		_status_damage(target, amount, "burn", {"sourceUid":caster.uid,"sourceName":caster.name,"skill_id":"selin_passive","detonation":true,"follow_up":true,"element":"fire"})
	if detonated:
		for effect in caster.get("ownerEffects", []):
			if effect.get("type", "") != "onBurnDetonation": continue
			for friend in _friends(caster): _refresh_combat_buff(friend, "ember_lantern_burn", float(effect.get("partyBurnAmp", 0.4)), 2, caster)
			_refresh_combat_buff(caster, "ember_lantern_direct", float(effect.get("ownerDirectAmp", 0.25)), 2, caster)
