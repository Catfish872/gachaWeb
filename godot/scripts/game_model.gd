extends RefCounted
## Native, transactional port of the original web v3 game state.
## Empty save_dir selects isolated in-memory operation for deterministic tests.

const ExtractionModel = preload("res://scripts/extraction_model.gd")
const AbyssBalance = preload("res://scripts/abyss_balance.gd")
const RelicSets = preload("res://scripts/relic_sets.gd")
const MAX_LEVEL := 10
const MAX_STAMINA := 100
const STAMINA_OVERFLOW_CAP := 300
const RECOVERY_MS := 360000
const TRAIN_COST := 500
const TRAIN_EXP := 100
const ABYSS_UNLOCK_FLOOR := 20
const ABYSS_FIVE_STAR_FLOOR := 51
const TEAM_PRESET_COUNT := 5
const TEAM_PRESET_NAME_LIMIT := 16

var extraction
var rogue_data: Dictionary = {}

var catalog: Dictionary = {}
var state: Dictionary = {}
var last_error := ""
var active_slot := 1
var save_dir: String
var save_blocked := false
var rng := RandomNumberGenerator.new()
var random_source: Callable
var _memory_slots: Dictionary = {}
var _issued_config: Dictionary = {}
var _uid_counter := 0

func _init(directory: String = "user://saves") -> void:
	save_dir = directory
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/catalog.json"))
	if parsed is Dictionary:
		catalog = parsed
	var rogue_parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/rogue_v2.json"))
	if rogue_parsed is Dictionary:
		rogue_data = rogue_parsed
		for key in ["rewardFloors", "shopFloors", "restFloors"]:
			for index in range(rogue_data[key].size()):
				rogue_data[key][index] = int(rogue_data[key][index])
	rng.randomize()
	extraction = ExtractionModel.new(self)
	state = default_state()
	_load_initial()

func _now() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)

func _uid(prefix: String) -> String:
	_uid_counter += 1
	return "%s_%d_%d_%d" % [prefix, _now(), _uid_counter, rng.randi()]

func random_value() -> float:
	return clampf(float(random_source.call()), 0.0, 0.99999999) if random_source.is_valid() else minf(rng.randf(), 0.99999999)

func _pick(items: Array) -> Variant:
	return items[mini(items.size() - 1, int(random_value() * items.size()))] if not items.is_empty() else null

func default_character() -> Dictionary:
	return {"level": 1, "exp": 0, "shards": 0, "constellation": 0, "awakening": 0, "breakthroughLevel": 0, "equippedRelics": {}}

func default_rogue() -> Dictionary:
	return {"runId": null, "selectedRewards": [], "pendingChoices": [], "nextStep": {"type": "none", "floor": 0}, "characterFocus": {}, "eligibleCharacters": [], "temporaryCurrency": 0, "eventHistory": [], "shopStock": [], "pendingNode": {}, "runTeam": [], "activeEncounter": {}, "metaEarned": 0, "floorsCleared": 0, "difficulty": 0, "targetRelicSetId": "", "relicRewardVersion": 0, "sceneBlocks": {}}

func default_meta() -> Dictionary:
	return {"currency": 0, "totalEarned": 0, "upgrades": {"vitality": 0, "offense": 0, "recovery": 0, "supply": 0}, "runsCompleted": 0, "runsLost": 0, "unlockedDifficulty": 0, "selectedDifficulty": 0, "selectedRelicSetId": "flame_oath"}

func default_team_presets(team: Array) -> Array:
	var presets: Array = []
	for index in range(TEAM_PRESET_COUNT):
		presets.append({"name": "队伍 %d" % (index + 1), "team": team.duplicate() if index == 0 else []})
	return presets

func default_state() -> Dictionary:
	var ember := default_character()
	ember.shards = 3
	var zeph := default_character()
	zeph.shards = 1
	return {"extraction": ExtractionModel.defaults(), "version": 9, "createdAt": _now(), "lastSaved": _now(),
		"resources": {"diamonds": 1600, "gold": 50000, "stamina": 100, "staminaLastUpdate": _now()},
		"ownedCharacters": {"ember": ember, "zeph": zeph}, "relics": [], "team": ["ember", "zeph", null], "stageProgress": {},
		"teamPresets": default_team_presets(["ember", "zeph", null]), "activeTeamPreset": 0,
		"pityCounters": {"standard": {"count": 0, "count4": 0, "guaranteedFeatured": false}, "limited_kaldi": {"count": 0, "count4": 0, "guaranteedFeatured": false}},
		"dailyMissions": {"lastReset": 0, "completed": []}, "stats": {"totalPulls": 0, "totalBattles": 0, "totalVictories": 0, "totalGoldSpent": 0},
		"dialogueSeen": {}, "chapterGiftClaimed": {},
		"abyss": {"currentFloor": 1, "maxFloor": 0, "savedPartyState": null, "lastFreeResetTime": 0, "rogue": default_rogue(), "meta": default_meta(), "lastRun": {}, "daily": {"dayKey": -1, "paid": {}}}}

func _fail(message: String) -> Dictionary:
	last_error = message
	return {"success": false, "error": message}

func _commit(previous: Dictionary, result: Dictionary = {}) -> Dictionary:
	if not save_game():
		state = previous
		return _fail(last_error)
	last_error = ""
	result.success = true
	return result

func _slot_path(slot: int) -> String:
	return save_dir.path_join("slot%d.json" % slot)

func _atomic_write(path: String, value: Dictionary) -> bool:
	if DirAccess.dir_exists_absolute(path) or DirAccess.dir_exists_absolute(path + ".tmp"):
		last_error = "存档文件路径已被目录占用"
		return false
	var parent := path.get_base_dir()
	var cursor := ProjectSettings.globalize_path(parent)
	while not DirAccess.dir_exists_absolute(cursor):
		if FileAccess.file_exists(cursor):
			last_error = "存档路径被现有文件占用，原存档已保留"
			return false
		var ancestor := cursor.get_base_dir()
		if ancestor == cursor or ancestor.is_empty():
			break
		cursor = ancestor
	if not DirAccess.dir_exists_absolute(parent) and DirAccess.make_dir_recursive_absolute(parent) != OK:
		last_error = "无法创建存档目录，请检查存储权限"
		return false
	var temp := path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		last_error = "存档写入失败，请检查存储空间"
		return false
	file.store_string(JSON.stringify(value, "\t"))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		last_error = "存档写入失败，已保留原文件"
		return false
	# Same-directory rename keeps the original file intact until the new one is complete.
	if DirAccess.rename_absolute(temp, path) != OK:
		last_error = "存档替换失败，已保留原文件"
		return false
	return true

func save_game() -> bool:
	if save_blocked:
		last_error = "存档数据异常，原文件已保留。请导入有效存档或重置此槽位"
		return false
	var old_timestamp = state.get("lastSaved", 0)
	state.lastSaved = _now()
	if save_dir.is_empty():
		_memory_slots[active_slot] = state.duplicate(true)
		return true
	if not _atomic_write(_slot_path(active_slot), state):
		state.lastSaved = old_timestamp
		return false
	return true

func _read_slot(slot: int) -> Variant:
	if save_dir.is_empty():
		return _memory_slots.get(slot, null)
	if not FileAccess.file_exists(_slot_path(slot)):
		return null
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(_slot_path(slot))) != OK:
		return {"__corrupt": true}
	return parser.data

func _load_initial() -> void:
	if not save_dir.is_empty():
		var meta_path := save_dir.path_join("active_slot.json")
		if FileAccess.file_exists(meta_path):
			var meta = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
			if meta is Dictionary and int(meta.get("slot", 1)) in [1, 2, 3]:
				active_slot = int(meta.slot)
	var raw = _read_slot(active_slot)
	if raw == null:
		save_game()
	elif valid_save(raw):
		state = _normalize(raw)
		recover_stamina()
	else:
		save_blocked = true
		last_error = "存档数据异常，原文件已保留。请导入有效存档或重置此槽位"

func _set_active_metadata() -> bool:
	return true if save_dir.is_empty() else _atomic_write(save_dir.path_join("active_slot.json"), {"slot": active_slot})

func load_slot(slot: int) -> Dictionary:
	if slot not in [1, 2, 3]:
		return _fail("无效存档槽位")
	if slot == active_slot:
		return {"success": not save_blocked, "slot": slot, "error": last_error if save_blocked else ""}
	var raw = _read_slot(slot)
	if raw != null and not valid_save(raw):
		return _fail("目标存档数据异常，原文件已保留")
	if not save_blocked and not save_game():
		return _fail(last_error)
	var previous := state.duplicate(true)
	var previous_slot := active_slot
	var previous_blocked := save_blocked
	active_slot = slot
	state = default_state() if raw == null else _normalize(raw)
	save_blocked = false
	if not save_game():
		state = previous
		active_slot = previous_slot
		save_blocked = previous_blocked
		return _fail(last_error)
	if not _set_active_metadata():
		state = previous
		active_slot = previous_slot
		save_blocked = previous_blocked
		return _fail(last_error)
	_issued_config.clear()
	extraction.reset_runtime()
	recover_stamina()
	return {"success": true, "slot": slot}

func slot_summaries() -> Array:
	var results: Array = []
	for slot in [1, 2, 3]:
		var raw = state if slot == active_slot and not save_blocked else _read_slot(slot)
		var valid: bool = raw != null and valid_save(raw)
		results.append({"id": "slot%d" % slot, "slot": slot, "name": "存档 %d" % slot, "isActive": slot == active_slot, "hasData": raw != null,
			"corrupt": raw != null and not valid, "createdAt": raw.get("createdAt", 0) if valid else 0, "lastSaved": raw.get("lastSaved", 0) if valid else 0,
			"totalPulls": raw.get("stats", {}).get("totalPulls", 0) if valid else 0, "totalVictories": raw.get("stats", {}).get("totalVictories", 0) if valid else 0,
			"ownedCount": raw.get("ownedCharacters", {}).size() if valid else 0})
	return results

func export_save(path: String, slot: int = -1) -> Dictionary:
	if slot == -1:
		slot = active_slot
	if slot not in [1, 2, 3]:
		return _fail("无效存档槽位")
	if path.is_empty() or (slot == active_slot and save_blocked):
		return _fail("请选择导出路径并确认当前存档有效")
	var data = state if slot == active_slot else _read_slot(slot)
	if data == null or not valid_save(data):
		return _fail("此槽位没有有效存档")
	var payload := {"game": "void-rift-gacha", "schema": 6, "slotId": "slot%d" % slot, "exportedAt": _now(), "data": data.duplicate(true)}
	if path.begins_with("content://"):
		# Android's selected document URI does not support sibling temp files.
		# The local gameplay save remains atomic; this path writes only the
		# separate document explicitly selected by the user in the file picker.
		var document := FileAccess.open(path, FileAccess.WRITE)
		if document == null: return _fail("无法写入所选文档，请重新选择导出位置")
		document.store_string(JSON.stringify(payload, "\t"))
		document.flush()
		var write_error := document.get_error()
		document.close()
		if write_error != OK: return _fail("导出文档写入失败，本地存档保持不变")
		var verification := FileAccess.open(path, FileAccess.READ)
		if verification == null: return _fail("导出后无法读取校验，请重新选择支持读取的文档位置")
		var verified = JSON.parse_string(verification.get_as_text())
		verification.close()
		if not verified is Dictionary or verified != payload: return _fail("导出文档校验失败，请重新导出")
	elif not _atomic_write(path, payload):
		return _fail(last_error)
	return {"success": true, "path": path}

func import_save(path: String, slot: int = -1) -> Dictionary:
	if slot == -1:
		slot = active_slot
	if slot not in [1, 2, 3]:
		return _fail("无效存档槽位")
	if not path.begins_with("content://") and not FileAccess.file_exists(path):
		return _fail("存档文件不存在")
	var source_file := FileAccess.open(path, FileAccess.READ)
	if source_file == null:
		return _fail("存档文件无法读取")
	var source_size := source_file.get_length()
	source_file.close()
	if source_size > 16 * 1024 * 1024:
		return _fail("存档文件超过 16 MB")
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK or not parser.data is Dictionary:
		return _fail("文件格式不正确，原存档已保留")
	var parsed: Dictionary = parser.data
	if parsed.has("game") and parsed.game != "void-rift-gacha":
		return _fail("此文件属于其他游戏")
	var data = parsed.get("data", parsed)
	if not valid_save(data):
		return _fail("存档数据不完整或字段无效，原存档已保留")
	if slot != active_slot:
		var normalized := _normalize(data)
		normalized.lastSaved = _now()
		if save_dir.is_empty():
			_memory_slots[slot] = normalized
		elif not _atomic_write(_slot_path(slot), normalized):
			return _fail(last_error)
		return {"success": true, "slot": slot}
	var previous := state.duplicate(true)
	var old_blocked := save_blocked
	state = _normalize(data)
	save_blocked = false
	var result := _commit(previous, {"slot": active_slot})
	if not result.success:
		save_blocked = old_blocked
	else:
		_issued_config.clear()
		extraction.reset_runtime()
		recover_stamina()
	return result

func reset_slot(slot: int = -1) -> Dictionary:
	if slot == -1:
		slot = active_slot
	if slot not in [1, 2, 3]:
		return _fail("无效存档槽位")
	var replacement := default_state()
	if save_dir.is_empty():
		_memory_slots[slot] = replacement.duplicate(true)
	elif not _atomic_write(_slot_path(slot), replacement):
		return _fail(last_error)
	if slot == active_slot:
		state = replacement
		save_blocked = false
		_issued_config.clear()
		extraction.reset_runtime()
	last_error = ""
	return {"success": true, "slot": slot}

func _number(value: Variant, minimum: float = 0.0, maximum: float = 1.0e15) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum

func valid_save(value: Variant) -> bool:
	if not value is Dictionary or not value.get("resources") is Dictionary or not value.get("ownedCharacters") is Dictionary:
		return false
	if not _number(value.get("version", 3), 2, 9) or int(value.get("version", 3)) not in [2, 3, 4, 5, 6, 7, 8, 9] or value.ownedCharacters.is_empty():
		return false
	for key in ["diamonds", "gold", "stamina"]:
		if not _number(value.resources.get(key), 0):
			return false
	for key in ["createdAt", "lastSaved"]:
		if value.has(key) and not _number(value[key]):
			return false
	if value.resources.has("staminaLastUpdate") and not _number(value.resources.staminaLastUpdate):
		return false
	for key in ["stats", "pityCounters", "stageProgress", "dialogueSeen", "chapterGiftClaimed", "abyss", "dailyMissions"]:
		if value.has(key) and not value[key] is Dictionary:
			return false
	if value.has("extraction") and not extraction.valid(value.extraction):
		return false
	for id in value.ownedCharacters:
		var owned = value.ownedCharacters[id]
		if not catalog.CharacterData.has(id) or not owned is Dictionary:
			return false
		for key in ["level", "exp", "shards", "constellation", "awakening"]:
			if owned.has(key) and not _number(owned[key]):
				return false
		if owned.has("equippedRelics") and not owned.equippedRelics is Dictionary:
			return false
	var team = value.get("team", ["ember", "zeph", null])
	if not team is Array or team.size() > 3:
		return false
	var unique: Array = []
	for id in team:
		if id == null: continue
		if not id is String: return false
		if id.is_empty(): continue
		if not value.ownedCharacters.has(id) or id in unique:
			return false
		unique.append(id)
	if unique.is_empty():
		return false
	if value.has("teamPresets"):
		var presets = value.teamPresets
		if not presets is Array or presets.size() != TEAM_PRESET_COUNT:
			return false
		for preset in presets:
			if not preset is Dictionary or not preset.get("name") is String or not preset.get("team") is Array:
				return false
			if preset.name != _clean_team_preset_name(preset.name) or preset.name.is_empty() or preset.team.size() > 3:
				return false
			var preset_ids: Array = []
			for id in preset.team:
				if id == null: continue
				if not id is String: return false
				if id.is_empty(): continue
				if not value.ownedCharacters.has(id) or id in preset_ids: return false
				preset_ids.append(id)
	if value.has("activeTeamPreset"):
		if not _number(value.activeTeamPreset, -1, TEAM_PRESET_COUNT - 1) or float(value.activeTeamPreset) != int(value.activeTeamPreset):
			return false
	for progress in value.get("stageProgress", {}).values():
		if not progress is Dictionary or not progress.get("cleared", false) is bool:
			return false
		for key in ["stars", "bestTurns"]:
			if progress.has(key) and not _number(progress[key]):
				return false
	for seen in value.get("dialogueSeen", {}).values():
		if not seen is bool:
			return false
	for gift in value.get("chapterGiftClaimed", {}).values():
		if not gift is Dictionary or not gift.get("claimed", false) is bool or not _number(gift.get("date", 0)):
			return false
		if gift.has("charId") and not gift.charId is String:
			return false
	for pity in value.get("pityCounters", {}).values():
		if not pity is Dictionary or not _number(pity.get("count", 0)) or not _number(pity.get("count4", 0)):
			return false
	for stat in value.get("stats", {}).values():
		if not _number(stat):
			return false
	var relics = value.get("relics", [])
	if not relics is Array or relics.size() > 100000:
		return false
	var uids: Dictionary = {}
	for relic in relics:
		if not relic is Dictionary or not relic.get("uid") is String or relic.uid.is_empty() or uids.has(relic.uid):
			return false
		uids[relic.uid] = true
		if not _valid_relic(relic):
			return false

	var abyss: Dictionary = value.get("abyss", {})
	for key in ["currentFloor", "maxFloor", "lastFreeResetTime"]:
		if abyss.has(key) and not _number(abyss[key]):
			return false
	if abyss.get("savedPartyState") != null:
		if not abyss.savedPartyState is Array:
			return false
		for unit in abyss.savedPartyState:
			if not unit is Dictionary or not unit.get("id") is String or not _number(unit.get("currentHp", 0)) or not _number(unit.get("maxHp", 1), 1) or not _number(unit.get("energy", 0)) or not unit.get("cooldowns", {}) is Dictionary:
				return false
			for cooldown in unit.get("cooldowns", {}).values():
				if not _number(cooldown):
					return false
	if abyss.has("rogue"):
		var rogue = abyss.rogue
		if not rogue is Dictionary:
			return false
		if rogue.get("runId") != null and not rogue.runId is String:
			return false
		for key in ["selectedRewards", "pendingChoices", "eligibleCharacters", "eventHistory", "shopStock"]:
			if rogue.has(key) and not rogue[key] is Array:
				return false
		for key in ["nextStep", "characterFocus"]:
			if rogue.has(key) and not rogue[key] is Dictionary:
				return false
		for focus in rogue.get("characterFocus", {}).values():
			if not _number(focus):
				return false
		for char_id in rogue.get("eligibleCharacters", []):
			if not char_id is String or not catalog.CharacterData.has(char_id):
				return false
		var next_step: Dictionary = rogue.get("nextStep", {})
		if next_step.get("type", "none") not in ["none", "reward", "route", "event", "shop", "rest"] or not _number(next_step.get("floor", 0)):
			return false
		for reward in rogue.get("selectedRewards", []) + rogue.get("pendingChoices", []):
			if not reward is Dictionary or not reward.get("id") is String or not reward.get("effects", []) is Array:
				return false
			for key in ["name", "description", "icon", "target", "rarity", "pool", "characterId", "choiceId"]:
				if reward.has(key) and not reward[key] is String:
					return false
			var definition: Dictionary = {}
			for candidate in catalog.AbyssData.rogue.rewards:
				if candidate.id == reward.id:
					definition = candidate
			if definition.is_empty() or reward.effects.size() != definition.effects.size():
				return false
			for index in range(reward.effects.size()):
				if not reward.effects[index] is Dictionary:
					return false
				for key in definition.effects[index]:
					if not reward.effects[index].has(key):
						return false
				if reward.effects[index].get("type") != definition.effects[index].type:
					return false
			for effect in reward.get("effects", []):
				if not effect is Dictionary or not effect.get("type") is String:
					return false
				for key in ["value", "multiplier", "duration", "chance", "count"]:
					if effect.has(key) and not _number(effect[key], -1.0e6, 1.0e6):
						return false
				for key in ["stat", "statusId", "element", "skillType"]:
					if effect.has(key) and not effect[key] is String:
						return false
	return _valid_rogue_v2(value)

func _merge_defaults(base: Dictionary, src: Dictionary) -> Dictionary:
	var merged := base.duplicate(true)
	for key in src:
		if merged.get(key) is Dictionary and src[key] is Dictionary:
			merged[key] = _merge_defaults(merged[key], src[key])
		else:
			merged[key] = src[key]
	return merged

func _normalize(src: Dictionary) -> Dictionary:
	var result := _merge_defaults(default_state(), src.duplicate(true))
	result.version = 9
	# Legacy saves preserve the live formation and seed only the first preset.
	result.teamPresets = src.teamPresets.duplicate(true) if src.has("teamPresets") else default_team_presets(result.team)
	result.activeTeamPreset = int(src.get("activeTeamPreset", 0)) if src.has("teamPresets") else 0
	if result.activeTeamPreset >= 0 and _team_members(result.team) != _team_members(result.teamPresets[result.activeTeamPreset].team):
		result.activeTeamPreset = -1
	extraction.migrate_state(result, int(src.get("version", 3)))
	# Owned collections replace defaults; preserved extension fields remain round-trippable.
	result.ownedCharacters = src.ownedCharacters.duplicate(true)
	for id in result.ownedCharacters:
		var character := _merge_defaults(default_character(), result.ownedCharacters[id])
		character.level = clampi(int(character.level), 1, MAX_LEVEL)
		character.exp = maxi(0, int(character.exp))
		character.shards = maxi(0, int(character.shards))
		character.constellation = clampi(int(character.constellation), 0, 6)
		character.awakening = clampi(int(character.awakening), 0, 100)
		_normalize_progress(character)
		character.equippedRelics = {}
		result.ownedCharacters[id] = character
	for relic in result.relics:
		relic.level = int(relic.level)
		relic.rarity = int(relic.rarity)
		if int(src.get("version",3))<9 and not relic.has("legacySellValue"):
			relic.legacySellValue=int({3:50,4:200,5:800}.get(relic.rarity,50))+relic.level*20
			relic.legacySellLevel=relic.level
		var owner = relic.get("equippedBy")
		if owner != null and result.ownedCharacters.has(owner):
			var equipped: Dictionary = result.ownedCharacters[owner].equippedRelics
			if equipped.has(relic.slotId):
				relic.equippedBy = null
			else:
				equipped[relic.slotId] = relic.uid
		else:
			relic.equippedBy = null
	for key in result.resources:
		if result.resources[key] is float:
			result.resources[key] = int(result.resources[key])
	for pity in result.pityCounters.values():
		pity.count = int(pity.get("count", 0))
		pity.count4 = int(pity.get("count4", 0))
		pity.guaranteedFeatured = bool(pity.get("guaranteedFeatured", false))
	result.abyss.currentFloor = maxi(1, int(result.abyss.currentFloor))
	result.abyss.maxFloor = maxi(0, int(result.abyss.maxFloor))
	for key in ["selectedRewards", "pendingChoices"]:
		for index in range(result.abyss.rogue[key].size()):
			var saved_reward: Dictionary = result.abyss.rogue[key][index]
			for definition in catalog.AbyssData.rogue.rewards:
				if definition.id == saved_reward.id:
					result.abyss.rogue[key][index] = _merge_defaults(definition, saved_reward)
					result.abyss.rogue[key][index].effects = definition.effects.duplicate(true)
	# Old endless saves keep the record but begin a bounded expedition at floor one.
	if int(src.get("version", 3)) < 4:
		result.abyss.currentFloor = 1
		result.abyss.savedPartyState = null
		result.abyss.rogue = default_rogue()
	if result.abyss.savedPartyState is Array:
		for unit in result.abyss.savedPartyState:
			unit.currentHp = int(unit.currentHp)
			unit.maxHp = int(unit.maxHp)
			unit.energy = int(unit.get("energy", 0))
			unit.cooldowns = unit.get("cooldowns", {}).duplicate(true)
			for key in unit.cooldowns:
				unit.cooldowns[key] = int(unit.cooldowns[key])
	if not result.abyss.rogue.activeEncounter.is_empty():
		var encounter: Dictionary = result.abyss.rogue.activeEncounter
		for key in ["floor", "abyssLayer", "staminaCost", "runLength", "seed", "difficulty", "relicRewardVersion", "abyssGrowthVersion"]:
			if encounter.has(key):
				encounter[key] = int(encounter[key])
		for key in ["gold", "exp", "diamonds"]:
			encounter.rewards[key] = int(encounter.rewards.get(key, 0))
		if encounter.rewards.has("relicDrop"):
			encounter.rewards.relicDrop.rarity = int(encounter.rewards.relicDrop.rarity)
			if encounter.rewards.relicDrop.get("item") is Dictionary:
				encounter.rewards.relicDrop.item.level = int(encounter.rewards.relicDrop.item.level)
				encounter.rewards.relicDrop.item.rarity = int(encounter.rewards.relicDrop.item.rarity)
		if encounter.has("encounterModifier"):
			encounter.encounterModifier = AbyssBalance.modifier(str(encounter.encounterModifier.id))
	_migrate_bounded_abyss(result)
	_migrate_unlimited_blessings(result)
	_migrate_abyss_shop(result)
	return result

func _migrate_bounded_abyss(value: Dictionary) -> void:
	# Previously earned permanent assets and counters stay byte-for-byte intact.
	# Completed legacy floors are summarized once; unplayed encounters issue no reward.
	var abyss: Dictionary = value.abyss
	var rogue: Dictionary = abyss.rogue
	if rogue.runId == null or str(rogue.runId).is_empty() or int(rogue.difficulty) == 3 or int(abyss.currentFloor) <= 50: return
	abyss.lastRun = {"outcome":"legacy_completion", "floorsCleared":int(rogue.floorsCleared), "metaEarned":int(rogue.metaEarned), "blessings":rogue.selectedRewards.size(), "coinsLost":int(rogue.temporaryCurrency), "difficulty":int(rogue.difficulty)}
	abyss.currentFloor = 1
	abyss.savedPartyState = null
	abyss.rogue = default_rogue()

func exp_to_next_level(level: int) -> int:
	if level >= MAX_LEVEL:
		return 0
	return 50 if level <= 1 else mini(5000, int(200 * pow(2, level - 2)))

func _normalize_progress(character: Dictionary) -> void:
	while int(character.level) < MAX_LEVEL and int(character.exp) >= exp_to_next_level(int(character.level)):
		character.exp -= exp_to_next_level(int(character.level))
		character.level += 1
	if int(character.level) >= MAX_LEVEL:
		character.level = MAX_LEVEL
		character.exp = 0

func _grant_exp(char_id: String, amount: int) -> Dictionary:
	var character: Dictionary = state.ownedCharacters[char_id]
	var old_level := int(character.level)
	var old_exp := int(character.exp)
	var gain := maxi(0, amount) if old_level < MAX_LEVEL else 0
	character.exp += gain
	_normalize_progress(character)
	return {"charId": char_id, "gained": gain, "leveledUp": int(character.level) - old_level, "oldLevel": old_level, "newLevel": character.level, "oldExp": old_exp, "newExp": character.exp}

func train_character(char_id: String) -> Dictionary:
	if not state.ownedCharacters.has(char_id):
		return _fail("未拥有该角色")
	if int(state.ownedCharacters[char_id].level) >= MAX_LEVEL:
		return _fail("角色已达最高等级")
	if state.resources.gold < TRAIN_COST:
		return _fail("金币不足，需要 500 金币")
	var previous := state.duplicate(true)
	state.resources.gold -= TRAIN_COST
	state.stats.totalGoldSpent += TRAIN_COST
	var result := _grant_exp(char_id, TRAIN_EXP)
	result.cost = TRAIN_COST
	return _commit(previous, result)

func team_is_locked() -> bool:
	return abyss_run_active() or extraction.active() or not _issued_config.is_empty()

func _team_members(ids: Array) -> Array:
	return ids.filter(func(id): return id is String and not id.is_empty())

func _clean_team_preset_name(value: String) -> String:
	return value.replace("\n", " ").replace("\r", " ").replace("\t", " ").strip_edges().left(TEAM_PRESET_NAME_LIMIT)

func _validate_team(ids: Array) -> Dictionary:
	if ids.size() > 3:
		return _fail("队伍最多容纳三名角色")
	var filtered: Array = []
	for id in ids:
		if id == null: continue
		if not id is String: return _fail("队伍包含无效的角色标识")
		if id.is_empty(): continue
		if not state.ownedCharacters.has(id):
			return _fail("队伍包含未拥有的角色")
		if id in filtered:
			return _fail("同一角色只能上阵一次")
		filtered.append(id)
	if filtered.is_empty():
		return _fail("请至少上阵一名角色")
	while filtered.size() < 3:
		filtered.append(null)
	return {"success": true, "team": filtered}

func set_team(ids: Array) -> Dictionary:
	if team_is_locked():
		return _fail("当前战斗或远征的队伍已锁定，结束后可以重新编队")
	var checked := _validate_team(ids)
	if not checked.success: return checked
	var previous := state.duplicate(true)
	state.team = checked.team
	state.activeTeamPreset = -1
	for index in range(TEAM_PRESET_COUNT):
		if _team_members(state.teamPresets[index].team) == _team_members(state.team):
			state.activeTeamPreset = index
			break
	return _commit(previous)

func save_team_preset(index: int, ids: Array) -> Dictionary:
	if team_is_locked():
		return _fail("当前战斗或远征的队伍已锁定，结束后可以保存阵容")
	if index < 0 or index >= TEAM_PRESET_COUNT: return _fail("请选择有效队伍预设")
	var checked := _validate_team(ids)
	if not checked.success: return checked
	var previous := state.duplicate(true)
	state.teamPresets[index].team = checked.team.duplicate()
	state.team = checked.team.duplicate()
	state.activeTeamPreset = index
	return _commit(previous, {"preset": index})

func switch_team_preset(index: int) -> Dictionary:
	if team_is_locked():
		return _fail("当前战斗或远征的队伍已锁定，结束后可以切换阵容")
	if index < 0 or index >= TEAM_PRESET_COUNT: return _fail("请选择有效队伍预设")
	var checked := _validate_team(state.teamPresets[index].team)
	if not checked.success: return checked
	var previous := state.duplicate(true)
	state.team = checked.team.duplicate()
	state.activeTeamPreset = index
	return _commit(previous, {"preset": index})

func rename_team_preset(index: int, value: String) -> Dictionary:
	if index < 0 or index >= TEAM_PRESET_COUNT: return _fail("请选择有效队伍预设")
	var preset_name := _clean_team_preset_name(value)
	if preset_name.is_empty(): return _fail("请输入队伍名称")
	var previous := state.duplicate(true)
	state.teamPresets[index].name = preset_name
	return _commit(previous, {"preset": index})

func constellation_info(char_id: String) -> Array:
	if not catalog.CharacterData.has(char_id):
		return []
	var rarity := str(int(catalog.CharacterData[char_id].rarity))
	var character: Dictionary = state.ownedCharacters.get(char_id, default_character())
	var result: Array = []
	for index in range(6):
		var entry: Dictionary = catalog.ConstellationGeneric[index].duplicate(true)
		if index == 5:
			entry.merge(catalog.ConstellationC6.get(char_id, {}), true)
		entry.index = index
		entry.level = index + 1
		entry.cost = int(catalog.ConstellationCost[rarity][index])
		entry.unlocked = int(character.constellation) > index
		entry.isNext = int(character.constellation) == index
		entry.canUnlock = state.ownedCharacters.has(char_id) and entry.isNext and int(character.shards) >= entry.cost
		result.append(entry)
	return result

func constellation_bonuses(char_id: String) -> Dictionary:
	var result := {"hpPercent": 0.0, "defPercent": 0.0, "atkPercent": 0.0, "normalDmgBonus": 0.0, "skillDmgBonus": 0.0, "ultDmgBonus": 0.0, "skillCdReduce": 0, "custom": {}}
	for entry in constellation_info(char_id):
		if not entry.unlocked:
			continue
		for key in entry.buff:
			if result.has(key) and key != "custom":
				result[key] += entry.buff[key]
		if entry.buff.has("c6_type"):
			result.custom = entry.buff.duplicate(true)
	return result

func unlock_constellation(char_id: String) -> Dictionary:
	if not state.ownedCharacters.has(char_id):
		return _fail("未拥有该角色")
	var character: Dictionary = state.ownedCharacters[char_id]
	var level := int(character.constellation)
	if level >= 6:
		return _fail("已达最高命座")
	var cost := int(constellation_info(char_id)[level].cost)
	if character.shards < cost:
		return _fail("碎片不足，需要 %d 片" % cost)
	var previous := state.duplicate(true)
	character.shards -= cost
	character.constellation += 1
	return _commit(previous, {"newLevel": character.constellation, "cost": cost})

func equipped_relics(char_id: String) -> Array:
	var result: Array = []
	for uid in state.ownedCharacters.get(char_id, {}).get("equippedRelics", {}).values():
		if uid == null:
			continue
		var relic := get_relic(str(uid))
		if not relic.is_empty() and relic.get("equippedBy") == char_id:
			result.append(relic)
	return RelicSets.unique_relics(catalog, result)

func equipped_bonuses(char_id: String) -> Dictionary:
	return RelicSets.attribute_bonuses(catalog, equipped_relics(char_id))

func computed_stats_for_relic_loadout(char_id: String, relics: Array) -> Dictionary:
	var evaluated := RelicSets.evaluate(catalog, relics)
	return computed_stats(char_id, -1, {"constellation":constellation_bonuses(char_id),"awakening":int(state.ownedCharacters.get(char_id, {}).get("awakening", 0)),"relics":RelicSets.attribute_bonuses(catalog, relics),"relicSetBonuses":evaluated.statBonuses})

func relic_loadout_snapshot(char_id: String, relics: Variant = null) -> Dictionary:
	var items: Array = equipped_relics(char_id) if relics == null else relics
	items = RelicSets.unique_relics(catalog, items)
	var evaluated := RelicSets.evaluate(catalog, items)
	var uids: Dictionary = {}
	for relic in items:
		uids[relic.slotId] = relic.uid
	return {"charId":char_id,"relics":items.duplicate(true),"relicUids":uids,"stats":computed_stats_for_relic_loadout(char_id,items),"counts":evaluated.counts,"activeBonuses":evaluated.activeBonuses,"statBonuses":evaluated.statBonuses,"ownerEffects":evaluated.ownerEffects}

func computed_stats(char_id: String, level_override:int=-1, frozen:Dictionary={}) -> Dictionary:
	if not catalog.CharacterData.has(char_id):
		return {}
	var data: Dictionary = catalog.CharacterData[char_id]
	var saved: Dictionary = state.ownedCharacters.get(char_id, default_character())
	var level := clampi(level_override if level_override>=0 else int(saved.level), 1, MAX_LEVEL)
	var multiplier := pow(1.1, level - 1)
	var base: Dictionary = data.baseStats
	var growth: Dictionary = data.growthRate
	var cst:Dictionary=frozen.constellation if frozen.has("constellation") else constellation_bonuses(char_id)
	var rb:Dictionary=(frozen.relics if frozen.has("relics") else equipped_bonuses(char_id)).duplicate(true)
	var set_bonuses: Dictionary = RelicSets.evaluate(catalog,equipped_relics(char_id)).statBonuses if frozen.is_empty() else frozen.get("relicSetBonuses", {})
	for key in set_bonuses:
		rb[key] = float(rb.get(key,0)) + float(set_bonuses[key])
	var result: Dictionary = {}
	for key in ["hp", "atk", "def"]:
		var value := floorf(floorf(float(base[key]) + float(growth[key]) * (level - 1)) * multiplier)
		var percent := float(cst[key + "Percent"]) + (float(frozen.get("awakening",saved.awakening)) * 0.05 if key == "hp" else 0.0)
		result["maxHp" if key == "hp" else key] = maxi(0 if key == "def" else 1, int(floorf((value * (1 + percent) + rb[key + "_flat"]) * (1 + rb[key + "_pct"]))))
	result.spd = (floorf(float(base.spd) * multiplier) + rb.spd) * (1.0 + float(rb.get("spd_pct", 0)))
	result.cri = minf(1, float(base.cri) * multiplier + rb.cri_rate)
	result.criDmg = float(base.criDmg) * multiplier + rb.cri_dmg
	for key in ["normalDmgBonus", "skillDmgBonus", "ultDmgBonus", "skillCdReduce"]:
		result[key] = cst[key]
	result.energyRate = rb.energy_rate
	result.hp = result.maxHp
	result.critRate = result.cri
	result.critDmg = result.criDmg
	return result

func battle_party(is_abyss: bool = false) -> Array:
	var issued: Dictionary = state.abyss.rogue.activeEncounter if is_abyss else _issued_config
	if not issued.is_empty() and bool(issued.get("isAbyss",false)) == is_abyss and issued.get("partySnapshot") is Array:
		return issued.partySnapshot.duplicate(true)
	var result: Array = []
	for id in state.team:
		if id == null or not state.ownedCharacters.has(id) or not catalog.CharacterData.has(id):
			continue
		var data: Dictionary = catalog.CharacterData[id]
		var saved: Dictionary = state.ownedCharacters[id]
		var stats := computed_stats(id)
		var unit := {"id": id, "name": data.name, "element": data.element, "stats": stats, "skills": data.skills.duplicate(), "passiveId": data.get("passiveId", ""),
			"ownerEffects": RelicSets.evaluate(catalog,equipped_relics(id)).ownerEffects,
			"level": saved.level, "constellation": saved.constellation, "saveData": saved.duplicate(true), "maxHp": stats.maxHp, "currentHp": stats.maxHp, "energy": 0, "cooldowns": {}}
		if is_abyss and state.abyss.savedPartyState is Array:
			for persisted in state.abyss.savedPartyState:
				if persisted.id == id:
					unit.currentHp = persisted.currentHp
					unit.energy = persisted.get("energy", 0)
					unit.cooldowns = persisted.get("cooldowns", {}).duplicate(true)
					unit._abyssSavedMaxHp = persisted.get("maxHp", stats.maxHp)
		result.append(unit)
	return result

func pity_info(pool_id: String) -> Dictionary:
	if not catalog.GachaPoolData.pools.has(pool_id):
		return {}
	var pool: Dictionary = catalog.GachaPoolData.pools[pool_id]
	var pity: Dictionary = state.pityCounters.get(pool_id, {"count": 0, "count4": 0, "guaranteedFeatured": false})
	var rate5 := float(pool.rates["5"])
	if int(pity.count) >= int(pool.pity.soft):
		rate5 = minf(1, rate5 + (int(pity.count) - int(pool.pity.soft) + 1) * float(pool.pity.softIncrease))
	return {"count": int(pity.count), "count4": int(pity.count4), "hard": int(pool.pity.hard), "rate5": rate5, "guaranteedFeatured": pity.guaranteedFeatured}

func pull(pool_id: String, count: int) -> Dictionary:
	if not catalog.GachaPoolData.pools.has(pool_id) or count < 1 or count > 1000:
		return _fail("祈愿参数无效")
	var pool: Dictionary = catalog.GachaPoolData.pools[pool_id]
	for rarity in [3, 4, 5]:
		for key in ["pool%d" % rarity, "featured%d" % rarity]:
			for id in pool.get(key, []):
				if not catalog.CharacterData.has(id) or int(catalog.CharacterData[id].rarity) != rarity:
					return _fail("卡池配置异常，已暂停该卡池")
		if pool.get("pool%d" % rarity, []).is_empty():
			return _fail("卡池缺少角色")
	var cost := int(pool.costPerPull) * count
	var currency: String = pool.get("currency", "diamonds")
	if int(state.resources.get(currency, 0)) < cost:
		return _fail("星尘晶不足")
	var previous := state.duplicate(true)
	state.resources[currency] -= cost
	if not state.pityCounters.has(pool_id):
		state.pityCounters[pool_id] = {"count": 0, "count4": 0, "guaranteedFeatured": false}
	var results: Array = []
	for _index in range(count):
		var pity: Dictionary = state.pityCounters[pool_id]
		var rate5 := float(pity_info(pool_id).rate5)
		var rate4 := 1.0 if int(pity.count4) >= 9 else float(pool.rates["4"])
		var hard: bool = int(pity.count) >= int(pool.pity.hard) - 1
		var roll := 0.0 if hard else random_value()
		var rarity := 5 if hard or roll < rate5 else (4 if roll < rate5 + rate4 else 3)
		pity.count = 0 if rarity == 5 else int(pity.count) + 1
		pity.count4 = 0 if rarity >= 4 else int(pity.count4) + 1
		var featured := false
		if rarity == 5:
			if bool(pool.guaranteedFeatured) and bool(pity.guaranteedFeatured):
				featured = true
				pity.guaranteedFeatured = false
			else:
				featured = random_value() < float(pool.get("featuredRate5", 0.5))
				if bool(pool.guaranteedFeatured) and not featured:
					pity.guaranteedFeatured = true
		elif rarity == 4:
			featured = random_value() < float(pool.get("featuredRate4", 0.5))
		var candidates: Array = pool["pool%d" % rarity]
		if featured and not pool.get("featured%d" % rarity, []).is_empty():
			candidates = pool["featured%d" % rarity]
		if rarity == 5 and not featured and bool(pool.get("excludeFeaturedFromOffBanner", false)):
			candidates = candidates.filter(func(candidate): return not pool.get("featured5", []).has(candidate))
		# The source's non-featured branch includes Kaldi. Preserve its exact RNG/pity semantics.
		var id: String = _pick(candidates)
		var is_new: bool = not state.ownedCharacters.has(id)
		var shards := 0
		if is_new:
			state.ownedCharacters[id] = default_character()
		else:
			shards = 25 if rarity == 5 else (5 if rarity == 4 else 1)
			state.ownedCharacters[id].shards += shards
		results.append({"charId": id, "rarity": rarity, "isFeatured": featured, "isNew": is_new, "shards": shards})
	state.stats.totalPulls += count
	state.gachaHistory = results.duplicate(true)
	return _commit(previous, {"results": results, "cost": cost})

func get_relic(uid: String) -> Dictionary:
	for relic in state.relics:
		if relic.uid == uid:
			return relic
	return {}

func _round_stat(value: float, stat: String) -> float:
	return floorf(value + 0.5) if stat in ["spd", "hp_flat", "atk_flat", "def_flat", "energy_rate_flat"] else floorf(value * 1000 + 0.5) / 1000.0

func generate_relic(rarity: int, slot_id: String, set_id: String = "*") -> Dictionary:
	if rarity not in [3, 4, 5] or not catalog.RelicMainStatPool.has(slot_id):
		return {}
	if set_id != "*" and not set_id.is_empty() and not catalog.RelicSets.has(set_id):
		return {}
	var relic := _generate_relic_with_source(rarity, slot_id, "", random_value, "")
	relic.uid = _uid("relic")
	var chosen_set: String = str(_pick(catalog.RelicSets.keys())) if set_id == "*" else set_id
	if not chosen_set.is_empty():relic.setId = chosen_set
	return relic

func _generate_relic_with_source(rarity: int, slot_id: String, set_id: String, source: Callable, uid: String) -> Dictionary:
	var pool: Array = catalog.RelicMainStatPool[slot_id]
	var main: Dictionary = pool[mini(pool.size()-1, int(float(source.call())*pool.size()))]
	var candidates: Array = []
	for entry in catalog.RelicSubStatPool:
		if entry.stat != main.stat:
			candidates.append(entry)
	var chosen: Array = []
	for _i in range(int(catalog.RelicRarityConfig[str(rarity)].initSubStats)):
		var index := mini(candidates.size() - 1, int(float(source.call()) * candidates.size()))
		chosen.append(candidates.pop_at(index))
	var subs: Array = []
	for entry in chosen:
		subs.append({"stat": entry.stat, "name": entry.name, "value": _round_stat(float(entry.range[0]) + float(source.call()) * float(entry.range[1] - entry.range[0]), entry.stat)})
	var relic := {"uid":uid,"slotId":slot_id,"rarity":rarity,"level":0,"mainStat":main.duplicate(true),"subStats":subs,"equippedBy":null}
	if not set_id.is_empty():
		relic.setId = set_id
	return relic

func _valid_relic(relic: Variant) -> bool:
	if not relic is Dictionary or not relic.get("uid") is String or relic.uid.is_empty():return false
	if not catalog.RelicMainStatPool.has(relic.get("slotId", "")) or not _integer(relic.get("rarity", 0),3,5):return false
	if not _integer(relic.get("level", 0),0,25) or not relic.get("mainStat") is Dictionary or not relic.get("subStats") is Array:return false
	if relic.has("setId") and (not relic.setId is String or (not relic.setId.is_empty() and not catalog.RelicSets.has(relic.setId))):return false
	if relic.has("legacySellValue") and not _integer(relic.legacySellValue):return false
	if relic.has("legacySellLevel") and not _integer(relic.legacySellLevel,0,int(relic.level)):return false
	var main: Dictionary = relic.mainStat
	if not main.get("stat") is String or not main.get("name") is String or not _number(main.get("base")) or not _number(main.get("perLevel")):return false
	for sub in relic.subStats:
		if not sub is Dictionary or not sub.get("stat") is String or not sub.get("name") is String or not _number(sub.get("value")):return false
	return true

func add_relic(relic: Dictionary) -> Dictionary:
	if relic.is_empty() or not relic.has("uid") or not get_relic(str(relic.uid)).is_empty():
		return _fail("遗物数据无效或已经存在")
	var previous := state.duplicate(true)
	state.relics.append(relic.duplicate(true))
	if not valid_save(state):
		state = previous
		return _fail("遗物数据无效")
	return _commit(previous, {"relic": relic})

func relic_level_cap(relic: Dictionary) -> int:
	return int({3: 15, 4: 20, 5: 25}.get(int(relic.get("rarity", 5)), 25))

func relic_upgrade_cost(level: int) -> int:
	return 80 + clampi(level, 0, 24) * 20

func relic_upgrade_cost_to_max(uid: String) -> int:
	var relic := get_relic(uid)
	var total := 0
	if not relic.is_empty():
		for level in range(int(relic.level), relic_level_cap(relic)):
			total += relic_upgrade_cost(level)
	return total

func relic_max_cost(uid: String) -> int:
	return relic_upgrade_cost_to_max(uid)

func _upgrade_relic_one(relic: Dictionary) -> String:
	relic.level += 1
	if int(relic.level) % 4 != 0 or relic.subStats.is_empty():
		return ""
	var sub: Dictionary = _pick(relic.subStats)
	for definition in catalog.RelicSubStatPool:
		if definition.stat == sub.stat:
			var boost := _round_stat(float(definition.range[0]) * 0.8 + random_value() * float(definition.range[1] - definition.range[0]) * 0.8, sub.stat)
			sub.value = _round_stat(float(sub.value) + boost, sub.stat)
			return sub.name
	return ""

func upgrade_relic(uid: String) -> Dictionary:
	var relic := get_relic(uid)
	if relic.is_empty():
		return _fail("遗物不存在")
	if int(relic.level) >= relic_level_cap(relic):
		return _fail("已达最高强化等级")
	var cost := relic_upgrade_cost(int(relic.level))
	if state.resources.gold < cost:
		return _fail("金币不足，需要 %d 金币" % cost)
	var previous := state.duplicate(true)
	state.resources.gold -= cost
	state.stats.totalGoldSpent += cost
	var boosted := _upgrade_relic_one(relic)
	return _commit(previous, {"newLevel": relic.level, "boostedStat": boosted, "cost": cost})

func upgrade_relic_to_max(uid: String) -> Dictionary:
	var relic := get_relic(uid)
	if relic.is_empty():
		return _fail("遗物不存在")
	if int(relic.level) >= relic_level_cap(relic):
		return _fail("已达最高强化等级")
	var cost := relic_upgrade_cost_to_max(uid)
	if state.resources.gold < cost:
		return _fail("金币不足，需要 %d 金币" % cost)
	var previous := state.duplicate(true)
	var old_level := int(relic.level)
	state.resources.gold -= cost
	state.stats.totalGoldSpent += cost
	var boosted: Array = []
	while int(relic.level) < relic_level_cap(relic):
		var stat := _upgrade_relic_one(relic)
		if not stat.is_empty():
			boosted.append(stat)
	return _commit(previous, {"newLevel": int(relic.level), "oldLevel": old_level, "totalCost": cost, "boostedStats": boosted})

func equipped_relic_upgrade_preview(char_id: String) -> Dictionary:
	var result := {"success": true, "uids": [], "cost": 0, "equippedCount": 0}
	if not state.ownedCharacters.has(char_id):
		return {"success": false, "error": "未拥有该角色"}
	var equipped: Dictionary = state.ownedCharacters[char_id].equippedRelics
	for slot in catalog.RelicSlots:
		var uid: String = str(equipped.get(slot.id, ""))
		var relic := get_relic(uid)
		if relic.is_empty():continue
		if relic.get("equippedBy") != char_id or relic.slotId != slot.id:
			return {"success": false, "error": "遗物装备已变更，请重试"}
		result.equippedCount += 1
		if int(relic.level) < relic_level_cap(relic):
			result.uids.append(uid)
			result.cost += relic_upgrade_cost_to_max(uid)
	return result

func upgrade_equipped_relics_to_max(char_id: String) -> Dictionary:
	var preview := equipped_relic_upgrade_preview(char_id)
	if not preview.success:return _fail(str(preview.error))
	if preview.uids.is_empty():
		return _fail("已全部满级" if int(preview.equippedCount) > 0 else "请先装备遗物")
	var cost: int = int(preview.cost)
	if state.resources.gold < cost:return _fail("金币不足，需要 %d 金币" % cost)
	var previous := state.duplicate(true)
	var previous_rng: int = rng.state
	state.resources.gold -= cost
	state.stats.totalGoldSpent += cost
	for uid in preview.uids:
		var relic := get_relic(str(uid))
		while int(relic.level) < relic_level_cap(relic):
			_upgrade_relic_one(relic)
	var result := _commit(previous, {"count": preview.uids.size(), "totalCost": cost})
	if not result.success:rng.state = previous_rng
	return result

func upgrade_relic_max(uid: String) -> Dictionary:
	return upgrade_relic_to_max(uid)

func equip_relic(uid: String, char_id: String) -> Dictionary:
	var relic := get_relic(uid)
	if relic.is_empty():
		return _fail("遗物不存在")
	if not state.ownedCharacters.has(char_id):
		return _fail("未拥有该角色")
	var previous := state.duplicate(true)
	var equipped: Dictionary = state.ownedCharacters[char_id].equippedRelics
	var old_uid = equipped.get(relic.slotId)
	if old_uid != null and old_uid != uid:
		var old := get_relic(str(old_uid))
		if not old.is_empty():
			old.equippedBy = null
	var old_owner = relic.get("equippedBy")
	if old_owner != null and old_owner != char_id and state.ownedCharacters.has(old_owner):
		state.ownedCharacters[old_owner].equippedRelics.erase(relic.slotId)
	equipped[relic.slotId] = uid
	relic.equippedBy = char_id
	return _commit(previous)

func unequip_relic(char_id: String, slot_id: String) -> Dictionary:
	if not state.ownedCharacters.has(char_id) or not catalog.RelicMainStatPool.has(slot_id):
		return _fail("角色或遗物部位不存在")
	var previous := state.duplicate(true)
	var equipped: Dictionary = state.ownedCharacters[char_id].equippedRelics
	var uid = equipped.get(slot_id)
	if uid != null:
		var relic := get_relic(str(uid))
		if not relic.is_empty():
			relic.equippedBy = null
	equipped.erase(slot_id)
	return _commit(previous)

func relic_sell_value(relic: Dictionary) -> int:
	if relic.has("legacySellValue"):
		return int(relic.legacySellValue)+maxi(0,int(relic.level)-int(relic.get("legacySellLevel",relic.level)))*12
	return int({3:30,4:120,5:480}.get(int(relic.rarity),30))+int(relic.level)*12

func sell_relic(uid: String) -> Dictionary:
	var relic := get_relic(uid)
	if relic.is_empty():
		return _fail("遗物不存在")
	var previous := state.duplicate(true)
	var owner = relic.get("equippedBy")
	if owner != null and state.ownedCharacters.has(owner):
		state.ownedCharacters[owner].equippedRelics.erase(relic.slotId)
	var gold := relic_sell_value(relic)
	state.relics.erase(relic)
	state.resources.gold += gold
	return _commit(previous, {"gold": gold, "count": 1})

func batch_sell_relics(rarity_or_options: Variant) -> Dictionary:
	if rarity_or_options is Dictionary:
		return batch_sell_relic_options(rarity_or_options)
	if int(rarity_or_options) not in [3, 4, 5]:
		return _fail("请选择遗物稀有度")
	return batch_sell_relic_options({"rarity": int(rarity_or_options)})

func batch_sell_relic_options(options: Dictionary) -> Dictionary:
	var targets: Array = []
	var gold := 0
	for relic in state.relics:
		if relic.get("equippedBy") != null and relic.get("equippedBy") != "":
			continue
		var matches: bool = int(options.get("rarity", 0)) == int(relic.rarity) or (bool(options.get("all3Star", false)) and int(relic.rarity) == 3) or (bool(options.get("all4Star", false)) and int(relic.rarity) == 4) or (bool(options.get("allUnupgraded", false)) and int(relic.level) == 0)
		if matches:
			targets.append(relic)
			gold += relic_sell_value(relic)
	if targets.is_empty():
		return _fail("没有符合条件的未装备遗物")
	var previous := state.duplicate(true)
	for relic in targets:
		state.relics.erase(relic)
	state.resources.gold += gold
	return _commit(previous, {"count": targets.size(), "gold": gold})

func recover_stamina(now_ms: int = -1) -> Dictionary:
	if now_ms < 0:
		now_ms = _now()
	var last := int(state.resources.staminaLastUpdate)
	var current := int(state.resources.stamina)
	if now_ms < last:
		# A backwards wall clock must never create free stamina or a long recovery lockout.
		var before := state.duplicate(true)
		state.resources.staminaLastUpdate = now_ms
		return _commit(before, {"recovered": 0})
	var ticks := int((now_ms - last) / RECOVERY_MS)
	if current >= MAX_STAMINA:
		if ticks <= 0:
			return {"success": true, "recovered": 0}
		var before := state.duplicate(true)
		state.resources.staminaLastUpdate = now_ms
		return _commit(before, {"recovered": 0})
	if ticks <= 0:
		return {"success": true, "recovered": 0}
	var previous := state.duplicate(true)
	state.resources.stamina = mini(MAX_STAMINA, current + ticks)
	state.resources.staminaLastUpdate = now_ms if int(state.resources.stamina) >= MAX_STAMINA else last + ticks * RECOVERY_MS
	return _commit(previous, {"recovered": int(state.resources.stamina) - current})

func stamina_time_remaining(now_ms: int = -1) -> int:
	if int(state.resources.stamina) >= MAX_STAMINA:
		return 0
	if now_ms < 0:
		now_ms = _now()
	return RECOVERY_MS - maxi(0, now_ms - int(state.resources.staminaLastUpdate)) % RECOVERY_MS

func purchase(shop_kind: String, item_id: String) -> Dictionary:
	var key := "rechargeItems" if shop_kind == "recharge" else "itemShop"
	if shop_kind not in ["recharge", "item"]:
		return _fail("该商店尚未开放")
	var item: Dictionary = {}
	for entry in catalog.ShopData[key]:
		if entry.id == item_id:
			item = entry
	if item.is_empty():
		return _fail("商品不存在")
	var price := 0 if shop_kind == "recharge" else int(item.price)
	if int(state.resources.gold) < price:
		return _fail("金币不足")
	var previous := state.duplicate(true)
	state.resources.gold -= price
	state.stats.totalGoldSpent += price
	for reward in item.rewards:
		if reward.type in ["gold", "diamonds", "stamina"]:
			if reward.type == "stamina":
				state.resources.stamina = maxi(int(state.resources.stamina), mini(STAMINA_OVERFLOW_CAP, int(state.resources.stamina) + int(reward.amount)))
			else:
				state.resources[reward.type] += int(reward.amount)
	return _commit(previous, {"item": item.duplicate(true), "rewards": item.rewards.duplicate(true), "simulated": shop_kind == "recharge", "cost": price})

func stage_list() -> Array:
	var result: Array = []
	var previous_cleared := true
	for chapter in catalog.StageData.chapters:
		var chapter_unlocked: bool = bool(chapter.get("unlocked", false)) or bool(state.stageProgress.get(chapter.get("unlockCondition", ""), {}).get("cleared", false))
		for entry in chapter.stages:
			var stage: Dictionary = entry.duplicate(true)
			stage.chapterId = chapter.id
			stage.chapterName = chapter.name
			stage.completed = bool(state.stageProgress.get(stage.id, {}).get("cleared", false))
			stage.unlocked = stage.completed or (chapter_unlocked and previous_cleared)
			stage.cleared = stage.completed
			stage.progress = state.stageProgress.get(stage.id, {}).duplicate(true)
			stage.starTurnTarget = 12
			result.append(stage)
			previous_cleared = stage.completed
	return result

func get_stage(stage_id: String) -> Dictionary:
	for stage in stage_list():
		if stage.id == stage_id:
			return stage
	return {}

func prepare_stage(stage_id: String) -> Dictionary:
	if extraction.active(): return _fail("请先结束搜打撤探索")
	if not _issued_config.is_empty() or not state.abyss.rogue.activeEncounter.is_empty():
		return _fail("请先完成或撤离当前战斗")
	var config := get_stage(stage_id)
	if config.is_empty():
		return _fail("关卡不存在")
	if not config.unlocked:
		return _fail("请先通关前一章节")
	if battle_party().is_empty():
		return _fail("队伍为空，请先编队")
	var recovered := recover_stamina()
	if not recovered.success:
		return recovered
	var cost := int(config.get("staminaCost", 6))
	if state.resources.stamina < cost:
		return _fail("体力不足，请等待恢复或前往商店补充")
	var previous := state.duplicate(true)
	if int(state.resources.stamina) >= MAX_STAMINA:
		state.resources.staminaLastUpdate = _now()
	state.resources.stamina -= cost
	config.enemies = config.waves[0].enemies.duplicate()
	config.scaleMult = 1.0
	config.isAbyss = false
	config.token = _uid("battle")
	config._team = state.team.duplicate()
	config.partySnapshot = JSON.parse_string(JSON.stringify(battle_party(false)))
	var result := _commit(previous, {"config": config.duplicate(true)})
	if result.success:
		_issued_config = config
	return result

func prepare_selin_trial() -> Dictionary:
	if extraction.active() or abyss_run_active() or not _issued_config.is_empty():
		return _fail("请先结束当前探索")
	var party: Array = []
	var zero_cst := {"hpPercent":0.0,"atkPercent":0.0,"defPercent":0.0,"normalDmgBonus":0.0,"skillDmgBonus":0.0,"ultDmgBonus":0.0,"skillCdReduce":0,"custom":{}}
	for id in ["selin", "kaldi", "ayla"]:
		var data: Dictionary = catalog.CharacterData[id]
		var gear: Array = []
		var set_id := "ember_lantern" if id == "selin" else "flame_oath" if id == "kaldi" else "aurora_prayer"
		if not catalog.RelicSets.has(set_id):set_id = "ember_lantern"
		for slot in catalog.RelicSlots:
			var relic := _generate_relic_with_source(5, str(slot.id), set_id, func():return 0.35, "trial_" + id + "_" + str(slot.id))
			relic.level = 8
			gear.append(relic)
		var evaluated := RelicSets.evaluate(catalog, gear)
		var stats := computed_stats(id, 5, {"constellation":zero_cst,"awakening":0,"relics":RelicSets.attribute_bonuses(catalog, gear),"relicSetBonuses":evaluated.statBonuses})
		party.append({"id":id,"name":data.name,"element":data.element,"stats":stats,"skills":data.skills.duplicate(),"passiveId":data.get("passiveId",""),"ownerEffects":evaluated.ownerEffects,"level":5,"constellation":0,"saveData":default_character(),"maxHp":stats.maxHp,"currentHp":stats.maxHp,"energy":100,"cooldowns":{},"trialRelics":gear})
	var config := {"id":"trial_selin","name":"借火同行 · 瑟琳试用","isTrial":true,"isAbyss":false,"isBoss":false,"background":"res://assets/content_v270/backgrounds/unlit_town.png","waves":[{"enemies":["furnace_guard","lamp_wraith"]},{"enemies":["lamp_overseer","furnace_lamp"]}],"enemies":["furnace_guard","lamp_wraith"],"scaleMult":1.0,"rewards":{"gold":[0,0],"exp":0,"diamonds":0},"firstClearRewards":{"diamonds":160},"token":_uid("trial"),"_team":[],"partySnapshot":party}
	_issued_config = config
	return {"success":true,"config":config.duplicate(true)}

func wind_trial_info(kind: String) -> Dictionary:
	var entries := {
		"tiya": {"title":"巡路试锋 · 缇娅试用", "party":["tiya", "zeph", "ayla"], "background":"wind_outpost", "guide":"缇娅的战技在两段攻击后施加破甲，终结技先施加破甲再攻击。行动结束时，她会对本次受到自身技能伤害的破甲目标追加贯穿追击。轮到缇娅时，尝试终结技，观察技能伤害与贯穿伤害。"},
		"lumi": {"title":"弦响护行 · 露弥试用", "party":["lumi", "zeph", "ayla"], "background":"rope_bridge", "guide":"露弥先施加破甲，再进行两段攻击。她存活时，全队攻击破甲目标获得伤害加深，破甲敌人造成的伤害降低；战技还会为生命比例最低的队友施加护盾。轮到露弥时，用战技铺开破甲，再由泽菲接续攻击。"},
		"duo": {"title":"双风同行 · 联合演示", "party":["lumi", "tiya", "ayla"], "background":"wind_outpost", "guide":"先让露弥施加群体破甲，再由缇娅接续多段攻击与贯穿追击。两人的专属遗物随试用队伍提供，艾拉负责治疗。可手动比较破甲、支援和追击的协同效果。"}}
	if not entries.has(kind): return {}
	var info: Dictionary = entries[kind].duplicate(true)
	info.id = "trial_wind_duo" if kind == "duo" else "trial_" + kind
	info.reward = 0 if kind == "duo" else 160
	return info

func prepare_wind_trial(kind: String) -> Dictionary:
	if team_is_locked(): return _fail("请先结束当前战斗或远征")
	var info := wind_trial_info(kind)
	if info.is_empty(): return _fail("请选择有效角色试用")
	var party: Array = []
	var zero_cst := {"hpPercent":0.0,"atkPercent":0.0,"defPercent":0.0,"normalDmgBonus":0.0,"skillDmgBonus":0.0,"ultDmgBonus":0.0,"skillCdReduce":0,"custom":{}}
	for id in info.party:
		if not catalog.CharacterData.has(id): return _fail("角色试用资料尚未就绪")
		var data: Dictionary = catalog.CharacterData[id]
		var set_id: String = {"tiya":"wind_blades", "lumi":"wind_strings", "zeph":"wind_voyager", "ayla":"aurora_prayer"}[id]
		if not catalog.RelicSets.has(set_id): return _fail("角色试用装备尚未就绪")
		var gear: Array = []
		for slot in catalog.RelicSlots:
			var relic := _generate_relic_with_source(5, str(slot.id), set_id, func(): return 0.35, "trial_" + id + "_" + str(slot.id))
			relic.level = 8
			gear.append(relic)
		var evaluated := RelicSets.evaluate(catalog, gear)
		var stats := computed_stats(id, 5, {"constellation":zero_cst,"awakening":0,"relics":RelicSets.attribute_bonuses(catalog, gear),"relicSetBonuses":evaluated.statBonuses})
		party.append({"id":id,"name":data.name,"element":data.element,"stats":stats,"skills":data.skills.duplicate(),"passiveId":data.get("passiveId",""),"ownerEffects":evaluated.ownerEffects,"level":5,"constellation":0,"saveData":default_character(),"maxHp":stats.maxHp,"currentHp":stats.maxHp,"energy":100,"cooldowns":{},"trialRelics":gear})
	var background: String = "res://assets/content_v280/backgrounds/%s.png" % info.background
	if not ResourceLoader.exists(background): background = "res://assets/backgrounds/camp.png"
	var waves := [{"enemies":["thunder_hawk", "stone_golem"]}, {"enemies":["dark_knight", "thunder_hawk"]}]
	var config := {"id":info.id,"name":info.title,"isTrial":true,"trialKind":"wind","trialCharacter":kind,"trialGuide":info.guide,"isAbyss":false,"isBoss":false,"background":background,"waves":waves,"enemies":waves[0].enemies.duplicate(),"scaleMult":{"hpMod":4.5,"atkMod":1.15,"defMod":1.0,"spdMod":0.8},"rewards":{"gold":[0,0],"exp":0,"diamonds":0},"firstClearRewards":{"diamonds":info.reward},"token":_uid("trial"),"seed":28001,"_team":[],"partySnapshot":party}
	_issued_config = config
	return {"success":true,"config":config.duplicate(true)}

func _finish_wind_trial(issued: Dictionary, battle_state: Dictionary) -> Dictionary:
	var victory: bool = battle_state.phase == "victory"
	var first_clear: bool = victory and issued.get("trialCharacter", "") != "duo" and not bool(state.stageProgress.get(issued.id, {}).get("cleared", false))
	var award := 160 if first_clear else 0
	var result := {"success":true,"victory":victory,"rewards":{"gold":0,"exp":0,"diamonds":award},"gift":{},"relic":{},"progression":[],"firstClear":first_clear,"ended":false}
	if first_clear:
		var previous := state.duplicate(true)
		state.resources.diamonds += award
		state.stageProgress[issued.id] = {"cleared":true,"stars":1,"bestTurns":maxi(1, int(battle_state.get("turn", 1)))}
		result = _commit(previous, result)
	if result.success: _issued_config.clear()
	return result

func _stage_rewards(config: Dictionary, first_clear: bool) -> Dictionary:
	var source: Dictionary = config.get("rewards", {})
	if bool(config.get("isAbyss", false)):
		return source.duplicate(true)
	var gold_range: Array = source.get("gold", [30, 60])
	var gold := int(float(gold_range[0]) + random_value() * float(gold_range[1] - gold_range[0]))
	var slot: Dictionary = _pick(catalog.RelicSlots)
	var roll := random_value()
	var rarity := 5 if roll < 0.05 else (4 if roll < 0.4 else 3)
	var rewards := {"gold": gold, "exp": int(source.get("exp", 20)), "diamonds": int(source.get("diamonds", 0)), "relicDrop": {"slotId": slot.id, "rarity": rarity}}
	if bool(config.get("isTrial", false)):
		rewards.erase("relicDrop")
	if first_clear and config.has("firstClearRelic"):
		rewards.relicDrop = config.firstClearRelic.duplicate(true)
	if first_clear:
		for key in config.get("firstClearRewards", {}):
			if key in ["gold", "exp", "diamonds"]:
				rewards[key] += int(config.firstClearRewards[key])
	return rewards

func _chapter_gift(stage_id: String) -> Dictionary:
	var mapping := {"ch1_4": {"chapterId": "ch1", "charId": "kaldi"}, "ch2_4": {"chapterId": "ch2", "charId": "ayla"}}
	if not mapping.has(stage_id):
		return {}
	var config: Dictionary = mapping[stage_id]
	if state.chapterGiftClaimed.get(config.chapterId, {}).get("claimed", false):
		return {}
	var id: String = config.charId
	var is_new: bool = not state.ownedCharacters.has(id)
	if is_new:
		state.ownedCharacters[id] = default_character()
	else:
		state.ownedCharacters[id].shards += 25
	state.chapterGiftClaimed[config.chapterId] = {"claimed": true, "charId": id, "date": _now()}
	return {"chapterId": config.chapterId, "charId": id, "charName": catalog.CharacterData[id].name, "isNew": is_new, "shardsGained": 0 if is_new else 25}

func finish_battle(config: Dictionary, battle_state: Dictionary) -> Dictionary:
	if config.get("isExtraction", false):
		return extraction.settle_battle(config, battle_state)
	if _issued_config.is_empty() or config.get("token", "") != _issued_config.get("token", ""):
		return _fail("战斗已经结算或战斗凭证已失效")
	if battle_state.has("config"):
		var actual = battle_state.config
		if not actual is Dictionary or actual.get("token", "") != _issued_config.get("token", "") or actual.get("id", "") != _issued_config.get("id", ""):
			return _fail("战斗结果与当前战斗凭证不匹配")
	var phase: String = battle_state.get("phase", "")
	if phase not in ["victory", "defeat"]:
		return _fail("战斗尚未结束")
	# Settlement uses the issued config, never caller-modified reward/cost fields.
	var issued := _issued_config.duplicate(true)
	if issued.get("isTrial", false) and issued.get("trialKind", "") == "wind":
		return _finish_wind_trial(issued, battle_state)
	var previous := state.duplicate(true)
	var abyss := bool(issued.get("isAbyss", false))
	if abyss and abyss_floor_cap(int(issued.get("difficulty",0))) > 0 and int(issued.floor) > abyss_floor_cap(int(issued.get("difficulty",0))):
		_migrate_bounded_abyss(state)
		var migrated := _commit(previous, {"victory":true,"ended":true,"rewards":{},"lastRun":state.abyss.lastRun.duplicate(true)})
		if migrated.success: _issued_config.clear()
		return migrated
	state.stats.totalBattles += 1
	if phase == "defeat":
		if abyss:
			_end_abyss_run("defeat")
		var result := _commit(previous, {"victory": false, "rewards": {}, "gift": {}, "ended": abyss, "lastRun": state.abyss.lastRun.duplicate(true) if abyss else {}})
		if result.success:
			_issued_config.clear()
		return result
	state.stats.totalVictories += 1
	var first_clear: bool = not bool(state.stageProgress.get(issued.id, {}).get("cleared", false)) and not abyss
	var rewards := _stage_rewards(issued, first_clear)
	var daily_award:Dictionary={}
	if abyss:
		rewards.gold=0
		daily_award=_award_abyss_daily(int(issued.floor),int(issued.get("difficulty",0)))
		rewards.diamonds=int(daily_award.get("amount",0))
	for key in ["gold", "diamonds"]:
		state.resources[key] += int(rewards.get(key, 0))
	var progression: Array = []
	for id in issued._team:
		if id != null and state.ownedCharacters.has(id):
			progression.append(_grant_exp(id, int(rewards.get("exp", 0))))
	var relic: Dictionary = {}
	if rewards.has("relicDrop"):
		if rewards.relicDrop.get("item") is Dictionary:
			relic = rewards.relicDrop.item.duplicate(true)
		else:
			# Pre-2.5 issued encounters keep their original loose-piece rewards.
			relic = generate_relic(int(rewards.relicDrop.rarity), str(rewards.relicDrop.slotId), str(rewards.relicDrop.get("setId", "" if abyss else "*")))
		if not relic.is_empty():
			state.relics.append(relic)
	var gift: Dictionary = {}
	if abyss:
		var gains := _process_abyss_victory(issued, battle_state)
		rewards.runCoins = gains.runCoins
		rewards.meta = gains.meta
	else:
		var old_best := int(state.stageProgress.get(issued.id, {}).get("bestTurns", 2147483647))
		var all_alive: bool = not battle_state.get("allies", []).is_empty()
		for unit in battle_state.get("allies", []):
			if int(unit.get("currentHp", 0)) <= 0:
				all_alive = false
		var stars := 1 + (1 if all_alive else 0) + (1 if int(battle_state.get("turn", 1)) <= int(issued.get("starTurnTarget", 12)) else 0)
		state.stageProgress[issued.id] = {"cleared": true, "stars": maxi(stars, int(state.stageProgress.get(issued.id, {}).get("stars", 0))), "bestTurns": mini(old_best, maxi(1, int(battle_state.get("turn", 1))))}
		gift = _chapter_gift(issued.id)
	var result := _commit(previous, {"victory": true, "rewards": rewards, "dailyAward":daily_award, "relic": relic, "gift": gift, "progression": progression, "firstClear": first_clear,
		"nextStep": state.abyss.rogue.nextStep.duplicate(true) if abyss else {}, "pendingChoices": state.abyss.rogue.pendingChoices.duplicate(true) if abyss else [], "ended": abyss and not abyss_run_active(), "lastRun": state.abyss.lastRun.duplicate(true) if abyss and not abyss_run_active() else {}})
	if result.success:
		_issued_config.clear()
	return result

func abandon_battle(config: Dictionary, battle_state: Dictionary = {}) -> Dictionary:
	if config.get("isExtraction", false):
		return extraction.retreat()
	var defeated := battle_state.duplicate(true)
	defeated.phase = "defeat"
	return finish_battle(config, defeated)

func mark_dialogue_seen(key: String) -> void:
	if not catalog.DialogueData.has(key) or state.dialogueSeen.get(key, false):
		return
	var previous := state.duplicate(true)
	state.dialogueSeen[key] = true
	_commit(previous)

func _init_rogue_run() -> void:
	var rogue: Dictionary = state.abyss.rogue
	if rogue.runId != null and rogue.runId != "":
		return
	rogue = default_rogue()
	rogue.runId = _uid("abyss")
	rogue.runTeam = state.team.duplicate()
	rogue.difficulty = int(state.abyss.meta.selectedDifficulty)
	rogue.targetRelicSetId = str(state.abyss.meta.selectedRelicSetId)
	rogue.relicRewardVersion = 1
	rogue.temporaryCurrency = 30 + 15 * int(state.abyss.meta.upgrades.supply)
	for id in state.team:
		if id != null and int(catalog.CharacterData.get(id, {}).get("rarity", 0)) == 5:
			rogue.eligibleCharacters.append(id)
	for id in rogue.eligibleCharacters:
		rogue.characterFocus[id] = 1.0 / rogue.eligibleCharacters.size()
	state.abyss.rogue = rogue

func _abyss_scene_start(floor_number: int) -> int:
	return 1 + int((maxi(1, floor_number) - 1) / 10) * 10

func abyss_scene_options() -> Array:
	# Each district is one small map, regardless of its number of art variants.
	var options: Array = []
	for theme in extraction.data.get("environmentThemes", {}):
		var backgrounds: Array = extraction.data.environmentThemes[theme].get("backgrounds", [])
		for depth in range(backgrounds.size()):
			if not backgrounds[depth].is_empty(): options.append({"theme": theme, "depth": depth})
	return options

func abyss_scene_from_roll(floor_number: int, roll: float, background_roll: float = 0.0) -> Dictionary:
	var scene := {"startFloor": _abyss_scene_start(floor_number), "theme": "", "depth": -1, "background": "res://assets/backgrounds/abyss.png"}
	if floor_number <= 10 or roll < 0.25: return scene
	var options := abyss_scene_options()
	if options.is_empty(): return scene
	var index := mini(options.size() - 1, int(clampf((roll - 0.25) / 0.75, 0.0, 1.0) * options.size()))
	scene.merge(options[index], true)
	var backgrounds: Array = extraction.data.environmentThemes[scene.theme].backgrounds[int(scene.depth)]
	scene.background = backgrounds[mini(backgrounds.size() - 1, int(clampf(background_roll, 0.0, 1.0) * backgrounds.size()))]
	return scene

func abyss_scene(floor_number: int = -1) -> Dictionary:
	if floor_number < 0: floor_number = int(state.abyss.currentFloor)
	return state.abyss.rogue.get("sceneBlocks", {}).get(str(_abyss_scene_start(floor_number)), abyss_scene_from_roll(floor_number, 0.0)).duplicate(true)

func _ensure_abyss_scene(floor_number: int) -> Dictionary:
	var rogue: Dictionary = state.abyss.rogue
	if not rogue.has("sceneBlocks"): rogue.sceneBlocks = {}
	var key := str(_abyss_scene_start(floor_number))
	if not rogue.sceneBlocks.has(key):
		var roll := random_value() if floor_number > 10 else 0.0
		rogue.sceneBlocks[key] = abyss_scene_from_roll(floor_number, roll, random_value() if roll >= 0.25 else 0.0)
	return rogue.sceneBlocks[key].duplicate(true)

func abyss_background_path() -> String:
	var encounter: Dictionary = state.abyss.rogue.get("activeEncounter", {})
	if not encounter.is_empty() and encounter.has("background"): return str(encounter.background)
	return str(abyss_scene().background)

func abyss_music_track(scene: Dictionary = {}) -> String:
	if scene.is_empty(): scene = abyss_scene()
	var theme := str(scene.get("theme", ""))
	if theme.is_empty(): return "dungeon_mystic" if int(scene.startFloor) > 10 else "sunset_walk"
	return extraction.theme_music_track(theme, int(scene.depth))

func abyss_boss_music_track(scene: Dictionary) -> String:
	# Preserve the 2.8.3 expedition boss mapping, including the wind road score.
	return {"lantern": "lantern_core", "windpass": "windpass_road"}.get(str(scene.get("theme", "")), "determined_pursuit")

func abyss_scene_enemy_pool(floor_number: int, scene: Dictionary = {}) -> Array:
	if scene.is_empty(): scene = abyss_scene(floor_number)
	var kind := "boss" if floor_number % 10 == 0 else "elite" if floor_number % 5 == 0 else "battle"
	var theme := str(scene.get("theme", ""))
	# Older expedition themes share their existing act-based pools. Taking their
	# union uses only enemies actually found there, without importing act scaling.
	var candidates: Array = []
	for act in [1, 2, 3]:
		for id in extraction.environment_enemy_pool(kind, theme, act):
			if id not in candidates and catalog.EnemyData.has(id) and floor_number >= int(catalog.EnemyData[id].get("abyssMinFloor", 1)):
				candidates.append(id)
	return candidates

func _valid_abyss_scene(scene: Variant, start_floor: int) -> bool:
	if not scene is Dictionary or not _integer(scene.get("startFloor"), 1, 1000000000) or int(scene.startFloor) != start_floor: return false
	if not scene.get("theme") is String or not _integer(scene.get("depth"), -1, 100) or not scene.get("background") is String: return false
	if scene.theme.is_empty(): return int(scene.depth) == -1 and scene.background == "res://assets/backgrounds/abyss.png"
	if start_floor <= 10: return false
	var backgrounds: Array = extraction.data.get("environmentThemes", {}).get(scene.theme, {}).get("backgrounds", [])
	return int(scene.depth) >= 0 and int(scene.depth) < backgrounds.size() and scene.background in backgrounds[int(scene.depth)]

func abyss_enemy_pool(floor_number: int) -> Array:
	return abyss_scene_enemy_pool(floor_number)

func abyss_encounter_background(enemies: Array, encounter_seed: int) -> String:
	# New encounters freeze their habitat when issued; this helper never rolls RNG.
	if enemies.has("boss_highland_roc"):
		return "res://assets/content_v280/backgrounds/cloud_nest.png"
	var habitats: Array = []
	for id in enemies:
		for path in catalog.EnemyData.get(id, {}).get("abyssBackgrounds", []):
			if path not in habitats: habitats.append(path)
	if not habitats.is_empty(): return str(habitats[posmod(encounter_seed, habitats.size())])
	if enemies.has("boss_hedor"):
		return "res://assets/content_v270/backgrounds/furnace_core.png"
	var has_lantern := false
	for id in enemies:
		if id in ["ash_moth","lamp_wraith","furnace_guard","furnace_cantor","cracked_puppet","lamp_overseer","furnace_lamp"]:has_lantern = true
	if not has_lantern:return "res://assets/backgrounds/abyss.png"
	var scenes := ["snow_inn", "ash_bridge", "unlit_town", "copper_gallery", "inverted_well", "furnace_core"]
	return "res://assets/content_v270/backgrounds/%s.png" % scenes[posmod(encounter_seed, scenes.size())]

func prepare_abyss() -> Dictionary:
	if extraction.active(): return _fail("请先结束搜打撤探索")
	if abyss_run_active() and abyss_floor_cap() > 0 and int(state.abyss.currentFloor) > abyss_floor_cap():
		var legacy_previous := state.duplicate(true)
		_migrate_bounded_abyss(state)
		var migrated := _commit(legacy_previous, {"ended":true,"lastRun":state.abyss.lastRun.duplicate(true),"message":"旧远征已完成结算，已获得资源完整保留"})
		if migrated.success and bool(_issued_config.get("isAbyss",false)): _issued_config.clear()
		return migrated
	if not state.abyss.rogue.activeEncounter.is_empty():
		_issued_config = state.abyss.rogue.activeEncounter.duplicate(true)
		return {"success": true, "config": _issued_config.duplicate(true), "resumed": true}
	if not _issued_config.is_empty():
		return _fail("请先完成或撤离当前战斗")
	if battle_party(true).is_empty():
		return _fail("队伍为空，请先编队")
	if not state.abyss.rogue.pendingChoices.is_empty() or state.abyss.rogue.nextStep.get("type", "none") != "none" or not state.abyss.rogue.pendingNode.is_empty():
		return _fail("请先完成当前层间选择")
	var previous := state.duplicate(true)
	_init_rogue_run()
	var floor_number := int(state.abyss.currentFloor)
	var boss: bool = floor_number % 10 == 0
	var elite: bool = floor_number % 5 == 0 and not boss
	var scene := _ensure_abyss_scene(floor_number)
	var enemy_pool: Array = abyss_scene_enemy_pool(floor_number, scene)
	var count := 2
	if floor_number >= 7:count += int(random_value() * 2)
	if boss:count = 1
	elif elite:count = 1 if floor_number == 5 else 2
	var enemies: Array = []
	for _index in range(count):
		enemies.append(_pick(enemy_pool))
	var slot: Dictionary = _pick(catalog.RelicSlots)
	var config := {"id": "abyss_floor_%d" % floor_number, "name": "深渊 第 %d 层" % floor_number, "isAbyss": true, "floor": floor_number, "abyssLayer": floor_number,
		"staminaCost": 0, "isBoss": boss, "isElite": elite, "enemies": enemies, "waves": [{"enemies": enemies.duplicate()}], "scaleMult": 1.0,
		"encounterTier": "boss" if boss else ("elite" if elite else "normal"), "endless":abyss_is_endless(), "runLength":abyss_floor_cap(), "difficulty": int(state.abyss.rogue.difficulty),
		"rewards": {"gold": 0, "exp": mini(1000000,35 + floor_number * 5), "diamonds": 0},
		"seed": int(rng.randi()), "token": _uid("battle"), "_team": state.team.duplicate()}
	config.abyssScene = scene
	config.background = scene.background
	config.abyssMusic = abyss_music_track(scene)
	config.abyssBossMusic = abyss_boss_music_track(scene)
	if int(config.difficulty) == 3:config.abyssGrowthVersion = 3
	if floor_number >= 6 and not boss and random_value() < 0.45:
		config.encounterModifier = AbyssBalance.modifier(str(_pick(["bulwark", "frenzy", "swift"])))
	if int(state.abyss.rogue.get("relicRewardVersion",0)) >= 1:
		config.targetRelicSetId = str(state.abyss.rogue.targetRelicSetId)
		config.relicRewardVersion = 1
		var drop := _abyss_relic_drop(floor_number, int(config.difficulty), config.targetRelicSetId, int(config.seed), str(config.token))
		if not drop.is_empty():config.rewards.relicDrop = drop
	elif elite or boss:
		config.rewards.relicDrop = {"slotId": slot.id, "rarity": 5 if boss or floor_number >= ABYSS_FIVE_STAR_FLOOR else 4}
	config.partySnapshot = JSON.parse_string(JSON.stringify(battle_party(true)))
	state.abyss.rogue.activeEncounter = config.duplicate(true)
	var result := _commit(previous, {"config": config.duplicate(true)})
	if result.success:
		_issued_config = config
	return result

func _weighted_pick(items: Array, weights: Array) -> Variant:
	if items.is_empty():
		return null
	var total := 0.0
	for weight in weights:
		total += maxf(0, float(weight))
	if total <= 0:
		return items[0]
	var roll := random_value() * total
	for index in range(items.size()):
		roll -= maxf(0, float(weights[index]))
		if roll <= 0:
			return items[index]
	return items.back()

func reward_eligible_for_characters(reward: Dictionary, eligible: Array) -> bool:
	if reward.get("pool", "common") != "character": return true
	for id in reward.get("eligibleCharacters", [reward.get("characterId", "")]):
		if id in eligible: return true
	return false

func reward_character_weight(reward: Dictionary, focus: Dictionary, _eligible: Array) -> float:
	if reward.get("pool", "common") == "common": return 1.0
	# A shared reward is one ticket. Two owners never add their focus together.
	if not str(reward.get("sharedPoolId", "")).is_empty(): return 1.0
	return maxf(0.01, float(focus.get(reward.get("characterId", ""), 0.25)))

func _available_abyss_rewards(rogue: Dictionary = {}) -> Array:
	if rogue.is_empty(): rogue = state.abyss.rogue
	var result: Array = []
	var seen: Dictionary = {}
	for reward in catalog.AbyssData.rogue.rewards:
		if not seen.has(reward.id) and reward_eligible_for_characters(reward, rogue.eligibleCharacters):
			seen[reward.id] = true
			result.append(reward)
	return result

func _draw_abyss_reward(preferred_pool: String, excluded: Array, forced_rarity: String = "") -> Dictionary:
	var rarity := forced_rarity
	if rarity.is_empty():
		var weights: Dictionary = catalog.AbyssData.rogue.rarityWeights
		rarity = str(_weighted_pick(weights.keys(), weights.values()))
	var all: Array = []
	var filtered: Array = []
	var rarity_pool: Array = []
	for reward in _available_abyss_rewards():
		if reward.id in excluded:
			continue
		all.append(reward)
		if preferred_pool.is_empty() or reward.pool == preferred_pool:
			filtered.append(reward)
			if reward.rarity == rarity:
				rarity_pool.append(reward)
	var candidates: Array = rarity_pool if not rarity_pool.is_empty() else (filtered if not filtered.is_empty() else all)
	var weights: Array = []
	for reward in candidates:
		weights.append(reward_character_weight(reward, state.abyss.rogue.characterFocus, state.abyss.rogue.eligibleCharacters))
	var chosen = _weighted_pick(candidates, weights)
	return {} if chosen == null else chosen.duplicate(true)

func generate_abyss_choices(floor_number: int, force_rarity: String = "") -> Array:
	var result: Array = []
	var used: Array = []
	if force_rarity != "gold":
		var common := _draw_abyss_reward("common", used)
		if not common.is_empty():
			result.append(common)
			used.append(common.id)
	while result.size() < 3:
		var reward := _draw_abyss_reward("", used, force_rarity)
		if reward.is_empty():
			break
		result.append(reward)
		used.append(reward.id)
	for index in range(result.size()):
		result[index].choiceId = "%d_%d_%s" % [floor_number, index, result[index].id]
	return result

func _update_abyss_focus(reward: Dictionary) -> void:
	if not str(reward.get("sharedPoolId", "")).is_empty(): return
	var id: String = reward.get("characterId", "")
	var rogue: Dictionary = state.abyss.rogue
	var ids: Array = rogue.eligibleCharacters
	if id.is_empty() or id not in ids:
		return
	var config: Dictionary = catalog.AbyssData.rogue
	var minimum := float(config.get("focusMin", 0.15))
	var maximum := maxf(1.0 / maxi(1, ids.size()), float(config.get("focusMax", 0.45)))
	if ids.size() == 1:
		rogue.characterFocus = {id: 1.0}
		return
	var gain := float(config.get("focusGainOnPick", 0.10))
	var focus: Dictionary = rogue.characterFocus.duplicate()
	for char_id in ids:
		if not focus.has(char_id):
			focus[char_id] = 1.0 / ids.size()
	focus[id] = minf(maximum, float(focus[id]) + gain)
	var remaining := maxf(0, 1 - float(focus[id]))
	var total := 0.0
	for char_id in ids:
		if char_id != id:
			total += maxf(minimum, float(focus[char_id]))
	for char_id in ids:
		if char_id != id:
			var ratio := maxf(minimum, float(focus[char_id])) / total if total > 0 else 1.0 / maxi(1, ids.size() - 1)
			focus[char_id] = clampf(remaining * ratio, minimum, maximum)
	var sum := 0.0
	for char_id in ids:
		sum += float(focus[char_id])
	for char_id in ids:
		focus[char_id] = clampf(float(focus[char_id]) / maxf(0.00001, sum), minimum, maximum)
	rogue.characterFocus = focus

func choose_abyss_reward(choice_id: String) -> Dictionary:
	var rogue: Dictionary = state.abyss.rogue
	if rogue.nextStep.get("type", "none") != "reward":
		return _fail("当前没有待选祝福")
	var choice: Dictionary = {}
	for reward in rogue.pendingChoices:
		if reward.get("choiceId", "") == choice_id or reward.id == choice_id:
			choice = reward.duplicate(true)
	if choice.is_empty():
		return _fail("祝福选项不存在或已经过期")
	var previous := state.duplicate(true)
	choice.erase("choiceId")
	choice.pickedAtFloor = int(rogue.nextStep.floor)
	rogue.selectedRewards.append(choice)
	rogue.pendingChoices = []
	rogue.nextStep = {"type": "none", "floor": choice.pickedAtFloor}
	_update_abyss_focus(choice)
	return _commit(previous, {"reward": choice, "nextStep": rogue.nextStep.duplicate(true)})

func rogue_effects() -> Array:
	var result: Array = []
	var upgrades: Dictionary = state.abyss.meta.upgrades
	for key in ["vitality", "offense", "recovery"]:
		var level := int(upgrades[key])
		if level <= 0:
			continue
		var effect := {"type": "victoryHealPct", "value": level * 0.015} if key == "recovery" else {"type": "stat", "stat": "maxHpMult" if key == "vitality" else "atkMult", "value": level * (0.04 if key == "vitality" else 0.03)}
		effect.rewardId = "meta_" + key
		effect.rewardInstanceId = "meta_" + key
		effect.rewardName = "远征传承"
		result.append(effect)
	var selected: Array = state.abyss.rogue.selectedRewards
	for index in range(selected.size()):
		var reward: Dictionary = selected[index]
		for effect in reward.get("effects", []):
			var item: Dictionary = effect.duplicate(true)
			item.rewardId = reward.id
			item.rewardInstanceId = "%s_%d" % [reward.id, index]
			item.rewardName = reward.get("name", reward.id)
			result.append(item)
	return result

func _process_abyss_victory(config: Dictionary, battle_state: Dictionary) -> Dictionary:
	var recovery := 0.0
	for effect in rogue_effects():
		if effect.type == "victoryHealPct":
			recovery += float(effect.get("value", 0))
	var party: Array = []
	for unit in battle_state.get("allies", []):
		var maximum := maxi(1, int(unit.get("maxHp", unit.get("stats", {}).get("maxHp", 1))))
		var hp := clampi(int(unit.get("currentHp", 0)), 0, maximum)
		if hp > 0 and recovery > 0:
			hp = mini(maximum, int(hp + maximum * recovery))
		party.append({"id": unit.id, "currentHp": hp, "maxHp": maximum, "energy": clampi(int(unit.get("energy", 0)), 0, 100), "cooldowns": unit.get("cooldowns", {}).duplicate(true)})
	state.abyss.savedPartyState = party
	var cleared_floor := int(config.floor)
	var coins := 25 + cleared_floor * 2 + (40 if bool(config.isBoss) else (15 if bool(config.isElite) else 0))
	var fragments := 3 + int(cleared_floor / 5) + (8 if bool(config.isBoss) else (3 if bool(config.isElite) else 0))
	state.abyss.rogue.temporaryCurrency += coins
	fragments = _bank_meta(fragments)
	state.abyss.rogue.floorsCleared = cleared_floor
	state.abyss.rogue.activeEncounter = {}
	state.abyss.currentFloor = cleared_floor + 1
	state.abyss.maxFloor = maxi(cleared_floor, int(state.abyss.maxFloor))
	if cleared_floor == ABYSS_UNLOCK_FLOOR:
		fragments += _bank_meta(25)
		state.abyss.meta.unlockedDifficulty=maxi(int(state.abyss.meta.unlockedDifficulty),mini(3,int(state.abyss.rogue.difficulty)+1))
	if abyss_floor_cap() > 0 and cleared_floor >= abyss_floor_cap():
		_end_abyss_run("victory")
	else:
		_ensure_abyss_scene(cleared_floor + 1)
		_set_after_floor(cleared_floor)
	return {"runCoins": coins, "meta": fragments}

func can_free_abyss_reset(_now_ms: int = -1) -> bool:
	return true

func reset_abyss(_use_diamonds: bool = false, _now_ms: int = -1) -> Dictionary:
	var previous := state.duplicate(true)
	if abyss_run_active():
		_end_abyss_run("retreat")
	else:
		state.abyss.currentFloor = 1
		state.abyss.savedPartyState = null
		state.abyss.rogue = default_rogue()
	var result := _commit(previous, {"cost": 0, "ended": true, "lastRun": state.abyss.lastRun.duplicate(true)})
	if result.success and bool(_issued_config.get("isAbyss", false)):
		_issued_config.clear()
	return result

func _abyss_cycle_floor(floor_number:int)->int:
	return floor_number if floor_number<=20 else 11+(floor_number-21)%10

func _is_abyss_reward_floor(floor_number: int) -> bool:
	return _abyss_cycle_floor(floor_number) in rogue_data.rewardFloors or floor_number%10==0

func abyss_run_active() -> bool:
	return state.abyss.rogue.runId != null and str(state.abyss.rogue.runId) != ""

func abyss_floor_cap(rank: int = -1) -> int:
	if rank < 0: rank = int(state.abyss.rogue.difficulty) if abyss_run_active() else int(state.abyss.meta.selectedDifficulty)
	return int(rogue_data.get("floorCapsByDifficulty", [50,50,50,0])[clampi(rank,0,3)])

func abyss_is_endless(rank: int = -1) -> bool:
	return abyss_floor_cap(rank) == 0

func abyss_route_preview() -> Array:
	var result:Array=[]
	var cap := abyss_floor_cap()
	var start:=maxi(1,int(state.abyss.currentFloor)-2)
	if cap > 0: start = mini(start, maxi(1, cap - 9))
	for floor_number in range(start,mini(start+10,cap+1) if cap > 0 else start+10):
		var cycle:=_abyss_cycle_floor(floor_number)
		var after:="reward" if _is_abyss_reward_floor(floor_number) else ("shop" if cycle in rogue_data.shopFloors else ("rest" if cycle in rogue_data.restFloors else "route"))
		if cap > 0 and floor_number == cap: after = "finish"
		result.append({"floor":floor_number,"tier":"boss" if floor_number%10==0 else ("elite" if floor_number%5==0 else "normal"),"after":after})
	return result

func meta_upgrade_list() -> Array:
	var result: Array = []
	for definition in rogue_data.metaUpgrades:
		var item: Dictionary = definition.duplicate(true)
		item.level = int(state.abyss.meta.upgrades[item.id])
		item.cost = int(item.costs[item.level]) if item.level < int(item.maxLevel) else 0
		item.enabled = not abyss_run_active() and item.level < int(item.maxLevel) and int(state.abyss.meta.currency) >= item.cost
		result.append(item)
	return result

func purchase_meta_upgrade(upgrade_id: String) -> Dictionary:
	if abyss_run_active():
		return _fail("请在远征结束后升级传承")
	for item in meta_upgrade_list():
		if item.id != upgrade_id:
			continue
		if int(item.level) >= int(item.maxLevel):
			return _fail("此传承已经达到上限")
		if int(state.abyss.meta.currency) < int(item.cost):
			return _fail("记忆碎片不足，需要 %d" % int(item.cost))
		var previous := state.duplicate(true)
		state.abyss.meta.currency -= int(item.cost)
		state.abyss.meta.upgrades[upgrade_id] += 1
		return _commit(previous, {"upgrade": upgrade_id, "level": int(item.level) + 1, "cost": int(item.cost), "message": "%s提升至 %d 级" % [item.name, int(item.level) + 1]})
	return _fail("传承升级不存在")

func _bank_meta(amount: int) -> int:
	var actual := maxi(0, int(float(amount) * (1.0 + 0.25 * int(state.abyss.rogue.difficulty))))
	state.abyss.meta.currency += actual
	state.abyss.meta.totalEarned += actual
	state.abyss.rogue.metaEarned += actual
	return actual

func _end_abyss_run(outcome: String) -> void:
	var rogue: Dictionary = state.abyss.rogue
	state.abyss.lastRun = {"outcome": outcome, "floorsCleared": int(rogue.floorsCleared), "metaEarned": int(rogue.metaEarned), "blessings": rogue.selectedRewards.size(), "coinsLost": int(rogue.temporaryCurrency), "difficulty": int(rogue.difficulty)}
	if outcome == "victory":
		state.abyss.meta.runsCompleted += 1
		state.abyss.meta.unlockedDifficulty = maxi(int(state.abyss.meta.unlockedDifficulty), mini(3, int(rogue.difficulty) + 1))
	elif outcome == "defeat":
		state.abyss.meta.runsLost += 1
	state.abyss.currentFloor = 1
	state.abyss.savedPartyState = null
	state.abyss.rogue = default_rogue()

func _set_after_floor(floor_number: int) -> void:
	var rogue: Dictionary = state.abyss.rogue
	rogue.pendingChoices = []
	rogue.pendingNode = {}
	rogue.shopStock = []
	var kind := "route"
	if _is_abyss_reward_floor(floor_number):
		rogue.pendingChoices = generate_abyss_choices(floor_number, "gold" if floor_number % 10 == 0 else "")
		kind = "reward" if not rogue.pendingChoices.is_empty() else "rest"
	elif _abyss_cycle_floor(floor_number) in rogue_data.shopFloors:
		kind = "shop"
	elif _abyss_cycle_floor(floor_number) in rogue_data.restFloors:
		kind = "rest"
	rogue.nextStep = {"type": kind, "floor": floor_number}
	if kind == "reward":
		return
	rogue.pendingNode = {"id": "%s_%d" % [kind, floor_number], "type": kind}
	if kind=="rest" and _is_abyss_reward_floor(floor_number) and _available_abyss_rewards().is_empty():rogue.pendingNode.poolUnavailable=true
	if kind == "route":
		var recent_events: Array = []
		for index in range(rogue.eventHistory.size() - 1, -1, -1):
			var history: Dictionary = rogue.eventHistory[index]
			if history.get("type", "") == "event" and history.has("eventId"):
				recent_events.append(history.eventId)
				if recent_events.size() == 2:
					break
		var events: Array = []
		for event in rogue_data.events:
			if event.id not in recent_events:
				events.append(event)
		var selected_event: Dictionary = _pick(events)
		rogue.pendingNode.eventId = str(selected_event.id)
		rogue.pendingNode.eventOptionIds = _sample_abyss_option_ids(selected_event.options)
		rogue.pendingNode.routeOptions = ["event", "rest" if floor_number % 2 == 0 else "shop"]
		if "rest" in rogue.pendingNode.routeOptions:
			rogue.pendingNode.restOptionIds = _sample_abyss_option_ids(rogue_data.restOptions, "recover")
	elif kind == "rest":
		rogue.pendingNode.restOptionIds = _sample_abyss_option_ids(rogue_data.restOptions, "recover")
	elif kind == "shop":
		_generate_abyss_shop()

func _sample_abyss_option_ids(options: Array, fixed_id: String = "") -> Array:
	var pool: Array = []
	var selected: Array = []
	for option in options:
		if option.id == fixed_id:
			selected.append(option.id)
		else:
			pool.append(option.id)
	while selected.size() < 3:
		var option_id: String = str(_pick(pool))
		selected.append(option_id)
		pool.erase(option_id)
	return selected

func _abyss_node_option_pool(options: Array, key: String) -> Array:
	var ids: Array = state.abyss.rogue.pendingNode.get(key, [])
	# Keep the original three choices for nodes saved before option sampling.
	if ids.is_empty():
		return options.slice(0, 3).duplicate(true)
	var selected: Array = []
	for id in ids:
		for option in options:
			if option.id == id:
				selected.append(option.duplicate(true))
	return selected

func _event_definition(event_id: String) -> Dictionary:
	for event in rogue_data.events:
		if event.id == event_id:
			return event
	return {}

func _can_pay_hp(fraction: float) -> bool:
	if not state.abyss.savedPartyState is Array or state.abyss.savedPartyState.is_empty():
		return false
	for unit in state.abyss.savedPartyState:
		var cost := maxi(1, int(ceil(float(unit.maxHp) * fraction)))
		if int(unit.currentHp) <= cost:
			return false
	return true

func _option_disabled_reason(option: Dictionary) -> String:
	if int(state.abyss.rogue.temporaryCurrency) < int(option.get("cost", 0)):
		return "裂隙币不足"
	var effect: Dictionary = option.get("effect", {})
	if effect.has("hpCost") and not _can_pay_hp(float(effect.hpCost)):
		return "全队每人须保留至少 1 点生命，倒下角色需要先复苏"
	if effect.has("blessing") and _rewards_of_rarity(str(effect.blessing)).is_empty():
		return "当前队伍暂无可用的此稀有度祝福"
	return ""

func _option_enabled(option: Dictionary) -> bool:
	return _option_disabled_reason(option).is_empty()

func node_options() -> Dictionary:
	var node: Dictionary = state.abyss.rogue.pendingNode.duplicate(true)
	if node.is_empty():
		return {}
	var kind: String = state.abyss.rogue.nextStep.type
	var options: Array = []
	if kind == "route":
		node.title = "选择下一处落脚点"
		node.description = "每次只能进入一条路线，完成后继续下一层战斗。"
		var event := _event_definition(str(node.get("eventId", "")))
		for route in node.get("routeOptions", []):
			var label := str(event.get("title", "未知事件")) if route == "event" else ("休整营地" if route == "rest" else "裂隙商店")
			var description := str(event.get("description", "")) if route == "event" else ("在营火旁包扎伤口，或利用现有物资整备队伍。" if route == "rest" else "使用本局裂隙币购买有限库存的补给与祝福。")
			options.append({"id": route, "label": label, "description": description, "cost": 0, "currency": "runCoins", "risk": "进入后再选择具体代价" if route == "event" else "", "reward": "", "enabled": true})
	elif kind == "event":
		var event := _event_definition(str(node.get("eventId", "")))
		node.title = event.get("title", "遗迹事件")
		node.description = event.get("description", "")
		options = _abyss_node_option_pool(event.get("options", []), "eventOptionIds")
	elif kind == "rest":
		node.title = "休整营地"
		node.description = "营火驱散了寒意，同行的旅人正在整理行装。"
		options = _abyss_rest_options()
		if node.get("poolUnavailable",false):node.title="临时补给";node.description="当前暂无可用祝福，带上补给继续深入。"
	elif kind == "shop":
		node.title = "裂隙商店"
		node.description = "每件商品限购一次。裂隙币与购买的祝福仅在本次远征中有效。"
	for option in options:
		if option.get("effect", {}).has("meta"):
			var base_meta := int(option.effect.meta)
			var actual_meta := maxi(0, int(base_meta * (1.0 + 0.25 * int(state.abyss.rogue.difficulty))))
			option.description = str(option.description).replace("%d 记忆碎片" % base_meta, "%d 记忆碎片" % actual_meta)
			option.reward = "%d 永久记忆碎片" % actual_meta
		option.disabledReason = _option_disabled_reason(option)
		option.enabled = str(option.disabledReason).is_empty()
		option.presentationEffect = option.get("effect", {}).duplicate(true)
		option.erase("effect")
	node.options = options
	return node

func _complete_abyss_node(message: String, details: Dictionary = {}) -> void:
	var rogue: Dictionary = state.abyss.rogue
	rogue.eventHistory.append({"floor": int(rogue.nextStep.floor), "type": str(rogue.nextStep.type), "nodeId": str(rogue.pendingNode.get("id", "")), "eventId": str(rogue.pendingNode.get("eventId", "")), "message": message, "details": details.duplicate(true)})
	while rogue.eventHistory.size()>100:rogue.eventHistory.pop_front()
	rogue.nextStep = {"type": "none", "floor": int(rogue.nextStep.floor)}
	rogue.pendingNode = {}
	rogue.shopStock = []

func choose_abyss_node(option_id: String) -> Dictionary:
	var rogue: Dictionary = state.abyss.rogue
	var kind: String = rogue.nextStep.type
	if kind not in ["route", "event", "rest"] or rogue.pendingNode.is_empty():
		return _fail("当前没有可处理的事件或营地")
	var previous := state.duplicate(true)
	if kind == "route":
		if option_id not in rogue.pendingNode.get("routeOptions", []):
			return _fail("路线选项已经失效")
		rogue.nextStep.type = option_id
		rogue.pendingNode.type = option_id
		rogue.pendingNode.id = "%s_%d" % [option_id, int(rogue.nextStep.floor)]
		rogue.pendingNode.erase("routeOptions")
		if option_id != "event":
			rogue.pendingNode.erase("eventId")
		if option_id == "shop":
			_generate_abyss_shop()
		return _commit(previous, {"message": "已抵达" + str(node_options().get("title", "落脚点")), "nextStep": rogue.nextStep.duplicate(true)})
	var choices: Array = _abyss_rest_options() if kind == "rest" else _abyss_node_option_pool(_event_definition(str(rogue.pendingNode.get("eventId", ""))).get("options", []), "eventOptionIds")
	var choice: Dictionary = {}
	for option in choices:
		if option.id == option_id:
			choice = option
	if choice.is_empty():
		return _fail("选项已经失效")
	if not _option_enabled(choice):
		return _fail("当前货币、生命或祝福库存无法支付此选项，请选择其他方案")
	rogue.temporaryCurrency -= int(choice.get("cost", 0))
	var outcome := _apply_node_effect(choice.effect)
	var message := str(choice.label) + "：" + str(outcome.message)
	_complete_abyss_node(message, outcome)
	return _commit(previous, {"message": message, "outcome": outcome, "nextStep": rogue.nextStep.duplicate(true)})

func _rewards_of_rarity(rarity: String) -> Array:
	var result: Array = []
	for reward in _available_abyss_rewards():
		if reward.rarity == rarity:
			result.append(reward)
	return result

func _apply_node_effect(effect: Dictionary) -> Dictionary:
	var result := {"message": "", "coins": 0, "meta": 0}
	var parts: Array[String] = []
	if effect.has("hpCost"):
		for unit in state.abyss.savedPartyState:
			unit.currentHp -= maxi(1, int(ceil(float(unit.maxHp) * float(effect.hpCost))))
		parts.append("支付 %d%% 最大生命" % int(float(effect.hpCost) * 100))
	if effect.has("coins"):
		result.coins = int(effect.coins)
	if bool(effect.get("gamble", false)):
		result.coins = 95 if random_value() < 0.6 else 10
	if int(result.coins) > 0:
		state.abyss.rogue.temporaryCurrency += int(result.coins)
		parts.append("获得 %d 裂隙币" % int(result.coins))
	if effect.has("meta"):
		result.meta = _bank_meta(int(effect.meta))
		parts.append("保留 %d 记忆碎片" % int(result.meta))
	if effect.has("heal") or effect.has("energy") or effect.has("cooldown"):
		for unit in state.abyss.savedPartyState:
			if effect.has("heal") and (int(unit.currentHp) > 0 or bool(effect.get("revive", false))):
				unit.currentHp = mini(int(unit.maxHp), int(unit.currentHp) + maxi(1, int(float(unit.maxHp) * float(effect.heal))))
			if int(unit.currentHp) <= 0:
				continue
			unit.energy = mini(100, int(unit.energy) + int(effect.get("energy", 0)))
			for key in unit.cooldowns:
				unit.cooldowns[key] = maxi(0, int(unit.cooldowns[key]) - int(effect.get("cooldown", 0)))
		if effect.has("heal"):
			parts.append("恢复 %d%% 最大生命%s" % [int(float(effect.heal) * 100), "，倒下角色复苏" if bool(effect.get("revive", false)) else ""])
		if effect.has("energy"):
			parts.append("获得 %d 能量" % int(effect.energy))
		if effect.has("cooldown"):
			parts.append("技能冷却缩短")
	if effect.has("blessing"):
		var reward: Dictionary = _pick(_rewards_of_rarity(str(effect.blessing)))
		reward = reward.duplicate(true)
		reward.pickedAtFloor = int(state.abyss.rogue.nextStep.floor)
		state.abyss.rogue.selectedRewards.append(reward)
		_update_abyss_focus(reward)
		result.reward = reward.duplicate(true)
		parts.append("获得祝福「%s」" % reward.name)
	result.message = "；".join(parts)
	return result

func _migrate_unlimited_blessings(value: Dictionary) -> void:
	var rogue: Dictionary=value.abyss.rogue
	var node: Dictionary=rogue.pendingNode
	if rogue.nextStep.get("type", "none")!="rest" or node.get("type", "")!="rest":return
	if not node.get("exhausted",false) and not node.get("poolUnavailable",false):return
	var eligible:=_available_abyss_rewards(rogue)
	node.erase("exhausted")
	if eligible.is_empty():node.poolUnavailable=true;return
	# A historical cap-exhaustion fallback becomes its owed ordinary choice.
	# Existing stacks, currencies and past decisions stay intact; no reward is granted.
	var floor_number:=int(rogue.nextStep.floor)
	var salt:=str(rogue.runId)+"|"+str(floor_number)+"|unlimited-blessings|"
	eligible.sort_custom(func(a,b):return (salt+str(a.id)).sha256_text() < (salt+str(b.id)).sha256_text())
	var candidates: Array=[]
	if floor_number%10==0:
		for reward in eligible:
			if reward.rarity=="gold":candidates.append(reward)
	for reward in eligible:
		if reward not in candidates:candidates.append(reward)
	rogue.pendingChoices=[]
	for index in range(mini(3,candidates.size())):
		var reward: Dictionary=candidates[index].duplicate(true)
		reward.choiceId="%d_%d_%s"%[floor_number,index,reward.id]
		rogue.pendingChoices.append(reward)
	rogue.nextStep.type="reward"
	rogue.pendingNode={}

func _migrate_abyss_shop(value: Dictionary) -> void:
	var rogue: Dictionary = value.abyss.rogue
	if rogue.nextStep.get("type", "none") != "shop": return
	var used: Array = []
	var stock_ids: Array = []
	for item in rogue.shopStock:
		stock_ids.append(item.id)
		if item.kind == "blessing": used.append(item.rewardId)
	var wanted := int(rogue_data.get("shopBlessingCount",3))
	if used.size() >= wanted: return
	var candidates: Array = []
	for reward in _available_abyss_rewards(rogue):
		if reward.id not in used: candidates.append(reward)
	# A stable, run-local order adds stock once without rerolling purchases or
	# consuming the live encounter RNG when a historical shop is loaded again.
	var salt := str(rogue.runId)+"|"+str(int(rogue.nextStep.floor))+"|shop-v241|"
	candidates.sort_custom(func(a,b):return (salt+str(a.id)).sha256_text() < (salt+str(b.id)).sha256_text())
	for reward in candidates:
		if used.size()>=wanted or rogue.shopStock.size()>=wanted+2: break
		var index := used.size()
		while "blessing_%d"%index in stock_ids:index+=1
		var id := "blessing_%d"%index
		rogue.shopStock.append({"id":id,"kind":"blessing","rewardId":str(reward.id),"sold":false})
		stock_ids.append(id);used.append(reward.id)

func _generate_abyss_shop() -> void:
	var stock: Array = [{"id": "heal", "kind": "heal", "sold": false}, {"id": "energy", "kind": "energy", "sold": false}]
	var used: Array = []
	for index in range(int(rogue_data.get("shopBlessingCount",3))):
		var rarity := "blue" if index == 0 else (("gold" if int(state.abyss.currentFloor) >= 10 else "white") if index == 1 else "")
		var reward := _draw_abyss_reward("", used, rarity)
		if not reward.is_empty():
			stock.append({"id": "blessing_%d" % index, "kind": "blessing", "rewardId": str(reward.id), "sold": false})
			used.append(reward.id)
	state.abyss.rogue.shopStock = stock

func _reward_definition(reward_id: String) -> Dictionary:
	for reward in catalog.AbyssData.rogue.rewards:
		if reward.id == reward_id:
			return reward
	return {}

func abyss_shop_items() -> Array:
	if state.abyss.rogue.nextStep.type != "shop":
		return []
	var result: Array = []
	for raw in state.abyss.rogue.shopStock:
		var item: Dictionary = raw.duplicate(true)
		var available := true
		if item.kind == "heal":
			item.name = "全队急救"
			item.description = "全队恢复 40% 最大生命；倒下角色以 40% 生命复苏。"
			item.cost = 35
		elif item.kind == "energy":
			item.name = "充能药剂"
			item.description = "存活角色获得 45 能量，并清空技能冷却。"
			item.cost = 30
		else:
			var reward := _reward_definition(str(item.rewardId))
			item.name = str(reward.get("name", "祝福"))
			item.description = str(reward.get("description", ""))
			item.cost = int({"white": 55, "blue": 85, "gold": 140}.get(reward.get("rarity", "white"), 55))
			item.rarity = reward.get("rarity", "white")
			available = reward in _available_abyss_rewards()
		item.cost *= int(rogue_data.get("shopPriceMultiplier",2))
		item.disabledReason = "已售罄" if bool(item.sold) else ("当前队伍无法使用此祝福" if not available else ("裂隙币不足" if int(state.abyss.rogue.temporaryCurrency) < int(item.cost) else ""))
		item.enabled = str(item.disabledReason).is_empty()
		result.append(item)
	return result

func purchase_abyss_item(item_id: String) -> Dictionary:
	if state.abyss.rogue.nextStep.type != "shop":
		return _fail("当前没有开放的裂隙商店")
	var item: Dictionary = {}
	for candidate in abyss_shop_items():
		if candidate.id == item_id:
			item = candidate
	if item.is_empty():
		return _fail("商品不存在")
	if not bool(item.enabled):
		return _fail("商品已经售罄、当前队伍无法使用或裂隙币不足")
	var previous := state.duplicate(true)
	state.abyss.rogue.temporaryCurrency -= int(item.cost)
	for raw in state.abyss.rogue.shopStock:
		if raw.id == item_id:
			raw.sold = true
	var outcome: Dictionary = {}
	if item.kind == "heal":
		outcome = _apply_node_effect({"heal": 0.4, "revive": true})
	elif item.kind == "energy":
		outcome = _apply_node_effect({"energy": 45, "cooldown": 99})
	else:
		var reward := _reward_definition(str(item.rewardId)).duplicate(true)
		reward.pickedAtFloor = int(state.abyss.rogue.nextStep.floor)
		state.abyss.rogue.selectedRewards.append(reward)
		_update_abyss_focus(reward)
		outcome = {"message": "获得祝福「%s」" % reward.name, "reward": reward}
	return _commit(previous, {"message": outcome.message, "cost": item.cost, "outcome": outcome})

func leave_abyss_shop() -> Dictionary:
	if state.abyss.rogue.nextStep.type != "shop":
		return _fail("当前没有开放的裂隙商店")
	var previous := state.duplicate(true)
	_complete_abyss_node("离开裂隙商店")
	return _commit(previous, {"message": "补给完成，继续深入", "nextStep": state.abyss.rogue.nextStep.duplicate(true)})

func _integer(value: Variant, minimum: int = 0, maximum: int = 1000000000) -> bool:
	return _number(value, minimum, maximum) and float(value) == floorf(float(value))

func _valid_rogue_v2(value: Dictionary) -> bool:
	var abyss: Dictionary = value.get("abyss", {})
	var daily=abyss.get("daily",{"dayKey":-1,"paid":{}})
	if not daily is Dictionary or not _integer(daily.get("dayKey",-1),-1,1000000000) or not daily.get("paid",{}) is Dictionary:return false
	for milestone in daily.get("paid",{}):
		if not milestone is String or not milestone.is_valid_int() or str(int(milestone))!=milestone or int(milestone)<=0 or int(milestone)%10!=0 or not _integer(daily.paid[milestone]):return false
	var meta = abyss.get("meta", {})
	if not meta is Dictionary:
		return false
	if meta.has("selectedRelicSetId") and (not meta.selectedRelicSetId is String or not catalog.RelicSets.has(meta.selectedRelicSetId)):
		return false
	for key in ["currency", "totalEarned", "runsCompleted", "runsLost"]:
		if meta.has(key) and not _integer(meta[key]):
			return false
	for key in ["unlockedDifficulty", "selectedDifficulty"]:
		if meta.has(key) and not _integer(meta[key], 0, 3):
			return false
	if int(meta.get("selectedDifficulty", 0)) > int(meta.get("unlockedDifficulty", 0)):
		return false
	var upgrades = meta.get("upgrades", {})
	if not upgrades is Dictionary:
		return false
	var limits := {"vitality": 5, "offense": 5, "recovery": 4, "supply": 3}
	for key in upgrades:
		if not limits.has(key) or not _integer(upgrades[key], 0, int(limits[key])):
			return false
	var summary = abyss.get("lastRun", {})
	if not summary is Dictionary:
		return false
	if not summary.is_empty():
		if summary.get("outcome", "") not in ["defeat", "victory", "retreat", "legacy_completion"]:
			return false
		for key in ["floorsCleared", "metaEarned", "blessings", "coinsLost"]:
			if not _integer(summary.get(key, -1)):
				return false
		if not _integer(summary.get("difficulty", 0), 0, 3):
			return false
	if abyss.get("savedPartyState") is Array:
		var ids: Array = []
		if abyss.savedPartyState.size() > 3:
			return false
		for unit in abyss.savedPartyState:
			if not value.ownedCharacters.has(unit.id) or unit.id in ids or not _integer(unit.get("currentHp", -1)) or not _integer(unit.get("maxHp", -1), 1) or float(unit.get("currentHp", -1)) > float(unit.get("maxHp", -1)) or not _integer(unit.get("energy", 0), 0, 100):
				return false
			ids.append(unit.id)
			for cooldown in unit.get("cooldowns", {}).values():
				if not _integer(cooldown, 0, 999):
					return false
	var rogue: Dictionary = abyss.get("rogue", {})
	var scene_blocks = rogue.get("sceneBlocks", {})
	if not scene_blocks is Dictionary: return false
	for key in scene_blocks:
		if not key is String or not key.is_valid_int() or str(int(key)) != key or int(key) < 1 or (int(key) - 1) % 10 != 0 or int(key) > int(abyss.get("currentFloor", 1)): return false
		if not _valid_abyss_scene(scene_blocks[key], int(key)): return false
	if not _integer(rogue.get("relicRewardVersion",0),0,1):return false
	if rogue.has("targetRelicSetId") and (not rogue.targetRelicSetId is String or (not rogue.targetRelicSetId.is_empty() and not catalog.RelicSets.has(rogue.targetRelicSetId))):return false
	if int(rogue.get("relicRewardVersion",0)) == 1 and not catalog.RelicSets.has(rogue.get("targetRelicSetId","")):return false
	if not _integer(rogue.get("difficulty", 0), 0, 3) or int(rogue.get("difficulty", 0)) > int(meta.get("unlockedDifficulty", 0)):
		return false
	for key in ["temporaryCurrency", "metaEarned", "floorsCleared"]:
		if rogue.has(key) and not _integer(rogue[key], 0, 1000000000):
			return false
	if rogue.get("pendingChoices", []).size() > 3 or rogue.get("eventHistory", []).size() > 100 or rogue.get("shopStock", []).size() > 5:
		return false
	var run_team = rogue.get("runTeam", [])
	if not run_team is Array or run_team.size() > 3:
		return false
	var unique_team: Array = []
	for id in run_team:
		if id == null:
			continue
		if not id is String or not value.ownedCharacters.has(id) or id in unique_team:
			return false
		unique_team.append(id)
	for history in rogue.get("eventHistory", []):
		if not history is Dictionary:
			return false
		for key in ["type", "nodeId", "message"]:
			if history.has(key) and not history[key] is String:
				return false
		if history.has("floor") and not _integer(history.floor, 0, 1000000000):
			return false
	var node = rogue.get("pendingNode", {})
	if not node is Dictionary:
		return false
	var next: Dictionary = rogue.get("nextStep", {})
	var kind: String = next.get("type", "none")
	if not node.is_empty():
		if not node.get("id") is String or node.get("type", "") not in ["route", "event", "shop", "rest"] or node.type != kind:
			return false
		if node.type in ["route", "event"] and (not node.get("eventId") is String or _event_definition(node.eventId).is_empty()):
			return false
		if node.type == "route":
			if not node.get("routeOptions") is Array or node.routeOptions.size() != 2 or node.routeOptions[0] != "event" or node.routeOptions[1] not in ["shop", "rest"]:
				return false
	if kind in ["route", "event", "shop", "rest"] and node.is_empty():
		return false
	var stock_ids: Array = []
	for item in rogue.get("shopStock", []):
		if not item is Dictionary or not item.get("id") is String or not item.get("sold") is bool or item.get("kind", "") not in ["heal", "energy", "blessing"] or item.id in stock_ids:
			return false
		stock_ids.append(item.id)
		if item.kind == "blessing" and (not item.get("rewardId") is String or _reward_definition(item.rewardId).is_empty()):
			return false
	var encounter = rogue.get("activeEncounter", {})
	if not encounter is Dictionary:
		return false
	if not encounter.is_empty() and not _valid_abyss_encounter(encounter, value):
		return false
	if not encounter.is_empty() and int(encounter.get("relicRewardVersion",0)) != int(rogue.get("relicRewardVersion",0)):
		return false
	if int(value.get("version", 3)) >= 4:
		if not _integer(abyss.get("currentFloor", 1), 1, 1000000000):
			return false
		var active: bool = rogue.get("runId") != null and str(rogue.get("runId", "")) != ""
		var choice_ids: Array = []
		for reward in rogue.get("pendingChoices", []):
			if reward.id in choice_ids:
				return false
			choice_ids.append(reward.id)
		if (kind == "reward") != (not choice_ids.is_empty()):
			return false
		if kind != "shop" and not rogue.get("shopStock", []).is_empty():
			return false
		if active and int(rogue.get("floorsCleared", 0)) > 0:
			if not abyss.get("savedPartyState") is Array:
				return false
			var carried_ids: Array = []
			for unit in abyss.savedPartyState:
				carried_ids.append(unit.id)
			if carried_ids.size() != unique_team.size():
				return false
			for id in unique_team:
				if id not in carried_ids:
					return false
		if active and int(abyss.get("currentFloor", 1)) != int(rogue.get("floorsCleared", 0)) + 1:
			return false
		if kind != "none" and int(next.get("floor", 0)) != int(rogue.get("floorsCleared", 0)):
			return false
		if active and (unique_team.is_empty() or run_team != value.get("team", [])):
			return false
		if not active and (not encounter.is_empty() or not node.is_empty() or kind != "none" or not rogue.get("pendingChoices", []).is_empty()):
			return false
		if not encounter.is_empty() and (kind != "none" or int(encounter.floor) != int(abyss.get("currentFloor", 1)) or encounter._team != run_team or int(encounter.get("difficulty", 0)) != int(rogue.get("difficulty", 0))):
			return false
	return true

func _valid_abyss_encounter(config: Dictionary, value: Dictionary) -> bool:
	for key in ["id", "name", "token", "encounterTier"]:
		if not config.get(key) is String or str(config[key]).is_empty():
			return false
	if config.encounterTier not in ["normal", "elite", "boss"]:
		return false
	for key in ["isAbyss", "isBoss", "isElite"]:
		if not config.get(key) is bool:
			return false
	if not _integer(config.get("difficulty", 0), 0, 3):
		return false
	if config.has("abyssGrowthVersion") and (not _integer(config.abyssGrowthVersion,3,3) or int(config.difficulty) != 3):return false
	if not _integer(config.get("relicRewardVersion",0),0,1):return false
	if int(config.get("relicRewardVersion",0)) == 1:
		if not config.get("targetRelicSetId") is String or not catalog.RelicSets.has(config.targetRelicSetId):return false
		if config.targetRelicSetId != value.get("abyss",{}).get("rogue",{}).get("targetRelicSetId",""):return false
	elif config.has("targetRelicSetId") and config.targetRelicSetId != "":return false
	if not bool(config.isAbyss) or not _integer(config.get("floor"), 1, 1000000000) or not _integer(config.get("seed"), 0, 4294967295):
		return false
	if config.has("abyssScene"):
		var start_floor := _abyss_scene_start(int(config.floor))
		if not _valid_abyss_scene(config.abyssScene, start_floor): return false
		if config.abyssScene != value.get("abyss", {}).get("rogue", {}).get("sceneBlocks", {}).get(str(start_floor), {}): return false
		if config.get("background") != config.abyssScene.background or not config.get("abyssMusic") is String or not config.get("abyssBossMusic") is String: return false
		var expected_music: String = extraction.theme_music_track(str(config.abyssScene.theme), int(config.abyssScene.depth)) if not str(config.abyssScene.theme).is_empty() else "dungeon_mystic" if int(config.floor) > 10 else "sunset_walk"
		if config.abyssMusic != expected_music or config.abyssBossMusic != abyss_boss_music_track(config.abyssScene): return false
	elif config.has("abyssMusic") or config.has("abyssBossMusic"): return false
	if not config.get("enemies") is Array or config.enemies.is_empty() or config.enemies.size() > 3:
		return false
	for enemy in config.enemies:
		if not enemy is String or not catalog.EnemyData.has(enemy):
			return false
		if config.has("abyssScene") and enemy not in abyss_scene_enemy_pool(int(config.floor), config.abyssScene): return false
	if not config.get("waves") is Array or config.waves.size() != 1 or not config.waves[0] is Dictionary or config.waves[0].get("enemies") != config.enemies:
		return false
	if not config.get("_team") is Array or config._team.size() > 3:
		return false
	for id in config._team:
		if id != null and (not id is String or not value.ownedCharacters.has(id)):
			return false
	if config.has("partySnapshot"):
		if not config.partySnapshot is Array or config.partySnapshot.is_empty() or config.partySnapshot.size()>3:return false
		var party_ids: Array = []
		for unit in config.partySnapshot:
			if not unit is Dictionary or not unit.get("id") is String or not unit.id in config._team or unit.id in party_ids:return false
			party_ids.append(unit.id)
			if not unit.get("stats") is Dictionary or not unit.get("skills") is Array or not unit.get("cooldowns") is Dictionary:return false
			if not _integer(unit.get("maxHp"),1) or not _integer(unit.get("currentHp")) or not _integer(unit.get("_abyssSavedMaxHp",unit.maxHp),1) or int(unit.currentHp)>int(unit.get("_abyssSavedMaxHp",unit.maxHp)) or not _integer(unit.get("energy"),0,100):return false
			for key in ["maxHp","atk","def","spd","cri","criDmg","energyRate"]:
				if not _number(unit.stats.get(key),0,1000000000):return false
			if not valid_relic_growth_snapshot({"ownerEffects":unit.get("ownerEffects",[])}):return false
		for char_id in config._team:
			if char_id != null and char_id not in party_ids:return false
	var rewards = config.get("rewards")
	if not rewards is Dictionary:
		return false
	for key in ["gold", "exp", "diamonds"]:
		if not _integer(rewards.get(key, 0), 0, 1000000):
			return false
	if rewards.has("relicDrop"):
		if not rewards.relicDrop is Dictionary or not catalog.RelicMainStatPool.has(rewards.relicDrop.get("slotId", "")) or not _integer(rewards.relicDrop.get("rarity"), 3, 5):
			return false
		var drop: Dictionary = rewards.relicDrop
		if int(config.get("relicRewardVersion",0)) == 1:
			if drop.get("setId", "") != config.targetRelicSetId or not _valid_relic(drop.get("item")):return false
			if drop.item.get("setId", "") != drop.setId or drop.item.slotId != drop.slotId or int(drop.item.rarity) != int(drop.rarity) or drop.item.get("equippedBy") != null or int(drop.item.level) != 0:return false
			if drop.item.uid != "abyss_relic_" + str(config.token):return false
			for relic in value.get("relics",[]):
				if relic.uid == drop.item.uid:return false
		elif drop.has("setId") or drop.has("item"):return false
	if not _number(config.get("scaleMult", 1.0), 0.1, 1000000000.0):
		return false
	if config.has("encounterModifier"):
		var modifier = config.encounterModifier
		if not modifier is Dictionary or modifier.get("id", "") not in ["bulwark", "frenzy", "swift"]:
			return false
	return true

func abyss_difficulty_options() -> Array:
	var result: Array = []
	var names := ["初探", "险境", "绝境", "无尽"]
	for rank in range(4):
		var unlocked := rank <= int(state.abyss.meta.unlockedDifficulty)
		var modifiers := AbyssBalance.apply_difficulty({"hpMod": 1.0, "atkMod": 1.0, "defMod": 1.0}, rank)
		var hp_percent := int(round((float(modifiers.hpMod) - 1.0) * 100.0))
		var atk_percent := int(round((float(modifiers.atkMod) - 1.0) * 100.0))
		var def_percent := int(round((float(modifiers.defMod) - 1.0) * 100.0))
		result.append({"id": rank, "name": names[rank], "floorCap":abyss_floor_cap(rank), "endless":abyss_is_endless(rank), "description": "每层指数成长7%；记忆碎片收益 +75%。" if rank == 3 else ("基础敌人强度，记忆碎片收益 100%。" if rank == 0 else "敌人生命 +%d%%、攻击 +%d%%、防御 +%d%%；记忆碎片收益 +%d%%。" % [hp_percent, atk_percent, def_percent, rank * 25]), "unlocked": unlocked, "selected": rank == int(state.abyss.meta.selectedDifficulty), "enabled": unlocked and not abyss_run_active()})
	return result

func set_abyss_difficulty(rank: int) -> Dictionary:
	if abyss_run_active():
		return _fail("请在远征结束后选择难度")
	if rank < 0 or rank > 3 or rank > int(state.abyss.meta.unlockedDifficulty):
		return _fail("通关前一难度的 20 层后可解锁此难度")
	var previous := state.duplicate(true)
	state.abyss.meta.selectedDifficulty = rank
	return _commit(previous, {"difficulty": rank, "message": "远征难度已设为「%s」" % abyss_difficulty_options()[rank].name})

func _abyss_rest_options()->Array:
	if state.abyss.rogue.pendingNode.get("poolUnavailable",false):
		return [{"id":"echo_supply","label":"带上补给","description":"获得50裂隙币","effect":{"coins":50}},{"id":"echo_continue","label":"继续深入","description":"前往下一层","effect":{}}]
	return _abyss_node_option_pool(rogue_data.restOptions, "restOptionIds")

func _abyss_day_key()->int:
	# UTC+8 06:00 is UTC 22:00. Never roll the persisted claim day backwards.
	return maxi(int(floor(float(_now())/86400000.0+2.0/24.0)),int(state.abyss.daily.dayKey))

func _abyss_daily_view()->Dictionary:
	var day:=_abyss_day_key()
	return state.abyss.daily.duplicate(true) if day==int(state.abyss.daily.dayKey) else {"dayKey":day,"paid":{}}

func abyss_daily_status()->Dictionary:
	var daily:=_abyss_daily_view()
	var current:=int(state.abyss.currentFloor)
	var next:=int((current+9)/10)*10
	var rank:=int(state.abyss.rogue.difficulty) if abyss_run_active() else int(state.abyss.meta.selectedDifficulty)
	var rates:Array=rogue_data.get("dailyDiamondsPer10",[900,1350,1800,2200]).duplicate()
	var total:=0
	for amount in daily.paid.values():total+=int(amount)
	var paid:=int(daily.paid.get(str(next),0))
	return {"dayKey":daily.dayKey,"resetAt":(int(daily.dayKey)+1)*86400000-7200000,"currentFloor":current,"nextMilestone":next,"paidToday":total,"per10ByDifficulty":rates,"difficulty":rank,"reward":int(rates[rank]),"paid":paid,"remaining":maxi(0,int(rates[rank])-paid),"endless":abyss_is_endless(rank),"floorCap":abyss_floor_cap(rank)}

func _award_abyss_daily(floor_number:int,rank:int)->Dictionary:
	if floor_number%10!=0:return {}
	var daily:=_abyss_daily_view()
	var rates:Array=rogue_data.get("dailyDiamondsPer10",[900,1350,1800,2200])
	var previous:=int(daily.paid.get(str(floor_number),0))
	var entitlement:=int(rates[clampi(rank,0,3)])
	var amount:=maxi(0,entitlement-previous)
	daily.paid[str(floor_number)]=maxi(previous,entitlement)
	state.abyss.daily=daily
	return {"floor":floor_number,"amount":amount,"difficulty":rank,"dayKey":daily.dayKey,"alreadyClaimed":amount==0,"previousPaid":previous,"totalPaid":maxi(previous,entitlement)}

func memory_exchange_status()->Dictionary:
	var complete:=true
	for definition in rogue_data.metaUpgrades:
		if int(state.abyss.meta.upgrades.get(definition.id,0))<int(definition.maxLevel):complete=false
	var outside:bool=not abyss_run_active() and not extraction.active() and _issued_config.is_empty()
	return {"enabled":complete and outside and int(state.abyss.meta.currency)>0,"available":int(state.abyss.meta.currency),"rate":1,"maxed":complete,"reason":"传承全部升满后开放" if not complete else ("请先结束探索" if not outside else ("记忆不足" if int(state.abyss.meta.currency)<=0 else ""))}

func exchange_memory(amount:int)->Dictionary:
	var status:=memory_exchange_status()
	if not status.enabled:return _fail(status.reason)
	if amount<=0 or amount>int(status.available):return _fail("兑换数量无效")
	var previous:=state.duplicate(true)
	state.abyss.meta.currency-=amount
	state.resources.diamonds+=amount
	return _commit(previous,{"amount":amount,"diamonds":amount,"message":"已兑换星尘晶"})

func growth_snapshot(char_id:String)->Dictionary:
	var sets := RelicSets.evaluate(catalog,equipped_relics(char_id))
	return {"constellation":constellation_bonuses(char_id),"relics":equipped_bonuses(char_id),"awakening":int(state.ownedCharacters[char_id].awakening),"relicSetBonuses":sets.statBonuses,"ownerEffects":sets.ownerEffects,"relicSets":sets.activeBonuses}


func relic_set_options() -> Array:
	var result: Array = []
	var active := abyss_run_active()
	var selected: String = str(state.abyss.rogue.get("targetRelicSetId", "")) if active else str(state.abyss.meta.selectedRelicSetId)
	for set_id in catalog.RelicSets:
		var entry: Dictionary = catalog.RelicSets[set_id].duplicate(true)
		entry.selected = set_id == selected
		entry.enabled = not active
		entry.locked = active
		result.append(entry)
	return result

func set_abyss_relic_set(set_id: String) -> Dictionary:
	if abyss_run_active():return _fail("请在远征结束后选择目标套装")
	if not catalog.RelicSets.has(set_id):return _fail("目标套装无效")
	var previous := state.duplicate(true)
	state.abyss.meta.selectedRelicSetId = set_id
	return _commit(previous,{"setId":set_id,"message":"本次远征目标已设为「%s」" % catalog.RelicSets[set_id].name})

func abyss_relic_drop_info(rank: int = -1) -> Dictionary:
	if rank < 0:rank = int(state.abyss.rogue.difficulty) if abyss_run_active() else int(state.abyss.meta.selectedDifficulty)
	rank = clampi(rank,0,3)
	var rule: Dictionary = rogue_data.relicDrops
	var chance := float(rule.normalChanceByDifficulty[rank])
	var four_chance := float(rule.extraRarity4Chance)
	var legacy: bool = abyss_run_active() and int(state.abyss.rogue.get("relicRewardVersion",0)) == 0
	if legacy:chance = 0.0
	return {"difficulty":rank,"normalChance":chance,"extraRarity4Chance":four_chance,"extraRarity5Chance":1.0-four_chance,"expectedPer50":10.0+40.0*chance,"expectedFourStarPer50":5.0+40.0*chance*four_chance,"expectedFiveStarPer50":5.0+40.0*chance*(1.0-four_chance),"expectedSellGoldPer50":3000.0+40.0*chance*(120.0*four_chance+480.0*(1.0-four_chance)),"targetSetId":str(state.abyss.rogue.get("targetRelicSetId","")) if abyss_run_active() else str(state.abyss.meta.selectedRelicSetId),"locked":abyss_run_active(),"legacy":legacy,"milestoneEvery":int(rule.milestoneEvery),"fiveStarEvery":int(rule.fiveStarEvery),"fiveStarFromFloor":ABYSS_FIVE_STAR_FLOOR}

func _abyss_relic_drop(floor_number: int, rank: int, target_set: String, seed_value: int, token: String) -> Dictionary:
	# Independent persisted reward stream: equipment rolls do not perturb enemies,
	# events, blessings or the host RNG. The entire item is signed at preparation.
	var reward_rng := RandomNumberGenerator.new()
	reward_rng.seed = seed_value ^ 0x51E7C0DE
	var rule: Dictionary = rogue_data.relicDrops
	var rarity := 0
	if floor_number % int(rule.fiveStarEvery) == 0:
		rarity = 5
	elif floor_number % int(rule.milestoneEvery) == 0:
		rarity = 4
	elif reward_rng.randf() < float(rule.normalChanceByDifficulty[clampi(rank,0,3)]):
		rarity = 4 if reward_rng.randf() < float(rule.extraRarity4Chance) else 5
	if rarity == 0:return {}
	if floor_number >= ABYSS_FIVE_STAR_FLOOR:rarity = 5
	var slot: String = str(catalog.RelicSlots[mini(catalog.RelicSlots.size()-1,int(reward_rng.randf()*catalog.RelicSlots.size()))].id)
	var item := _generate_relic_with_source(rarity,slot,target_set,reward_rng.randf,"abyss_relic_"+token)
	return {"slotId":slot,"rarity":rarity,"setId":target_set,"item":item}

func valid_relic_growth_snapshot(snapshot: Dictionary) -> bool:
	if snapshot.has("relicSetBonuses"):
		if not snapshot.relicSetBonuses is Dictionary:return false
		var allowed := RelicSets.empty_stat_bonuses()
		for key in snapshot.relicSetBonuses:
			if not allowed.has(key) or not _number(snapshot.relicSetBonuses[key],0,100000000):return false
	if snapshot.has("ownerEffects"):
		if not snapshot.ownerEffects is Array or snapshot.ownerEffects.size()>10:return false
		var seen: Dictionary = {}
		for effect in snapshot.ownerEffects:
			if not effect is Dictionary or not effect.get("type") is String or not _number(effect.get("value"),-1,100000000):return false
			var set_id: String = str(effect.get("setId",""))
			var effect_key: String = "%s:%d:%s" % [set_id,int(effect.get("pieces",0)),str(effect.type)]
			if seen.has(effect_key):return false
			seen[effect_key] = true
			if not catalog.RelicSets.has(set_id):return false
			var found := false
			for bonus in catalog.RelicSets[set_id].bonuses:
				if int(bonus.pieces) != int(effect.get("pieces",0)):continue
				for definition in bonus.effects:
					if definition.type == "stat":continue
					var expected: Dictionary = definition.duplicate(true)
					expected.setId = set_id
					expected.pieces = int(bonus.pieces)
					if JSON.parse_string(JSON.stringify(expected)) == JSON.parse_string(JSON.stringify(effect)):found = true
			if not found:return false
	return true

func begin_best_relic_loadout(char_id: String, context: Dictionary = {}):
	var script_path: String="res://scripts/relic_quick_optimizer.gd" if context.get("searchMode","")=="bounded" else "res://scripts/relic_optimizer.gd"
	var optimizer_script = load(script_path)
	return optimizer_script.new(self,char_id,context)

func preview_best_relic_loadout(char_id: String, context: Dictionary = {}) -> Dictionary:
	# Synchronous convenience for tests and small callers. UI uses begin/advance.
	var search = begin_best_relic_loadout(char_id,context)
	var preview: Dictionary = search.preview()
	while not bool(preview.get("done",false)):
		preview = search.advance(4000)
	return preview

func apply_relic_loadout(plan: Dictionary, allow_unproven: bool = false) -> Dictionary:
	var char_id: String = str(plan.get("charId",""))
	if not state.ownedCharacters.has(char_id):return _fail("未拥有该角色")
	if not plan.get("context") is Dictionary:return _fail("装备方案缺少评价条件，请重新计算")
	if bool(plan.context.get("includeEquippedByOthers",false)):return _fail("请先解除其他角色装备后重新计算")
	if not bool(plan.get("canApply",false)) or bool(plan.get("cancelled",false)):return _fail("请等待装备计算完成")
	if not bool(plan.get("provenOptimal",false)) and not allow_unproven:return _fail("请等待最优方案确认完成，或明确采用当前推荐")
	var optimizer_script = load("res://scripts/relic_optimizer.gd")
	if str(plan.get("fingerprint","")) != optimizer_script.plan_fingerprint(self,char_id,plan.context):return _fail("装备或角色状态已变化，请重新计算")
	if not plan.get("before") is Dictionary or not plan.get("after") is Dictionary or not plan.after.get("relicUids") is Dictionary:return _fail("装备方案无效，请重新计算")
	if plan.before.get("relicUids",{}) != relic_loadout_snapshot(char_id).relicUids:return _fail("当前装备已变化，请重新计算")
	var proposed: Dictionary = plan.after.relicUids
	var items: Array = []
	var uids: Dictionary = {}
	for slot in proposed:
		if not catalog.RelicMainStatPool.has(slot) or not proposed[slot] is String or uids.has(proposed[slot]):return _fail("装备部位或物品无效")
		var relic := get_relic(proposed[slot])
		if relic.is_empty() or relic.slotId != slot:return _fail("装备库存已变化，请重新计算")
		if relic.get("equippedBy") != null and relic.get("equippedBy") != "" and relic.equippedBy != char_id:return _fail("方案包含其他角色装备，请重新计算")
		uids[relic.uid] = true
		items.append(relic)
	if computed_stats_for_relic_loadout(char_id,items) != plan.after.get("stats",{}):return _fail("装备属性已变化，请重新计算")
	var previous := state.duplicate(true)
	for relic in state.relics:
		if relic.get("equippedBy") == char_id:relic.equippedBy = null
	state.ownedCharacters[char_id].equippedRelics = proposed.duplicate(true)
	for relic in items:relic.equippedBy = char_id
	return _commit(previous,{"charId":char_id,"costGold":0,"before":plan.before.duplicate(true),"after":relic_loadout_snapshot(char_id),"message":"已应用整套装备，金币消耗为 0"})

func relic_set_recommendations(char_id: String) -> Array:
	# Collection advice is skill-based and available before ownership. The exact
	# inventory optimum remains the separate loadout search for owned characters.
	var character: Dictionary = catalog.get("CharacterData",{}).get(char_id,{})
	if character.is_empty():return []
	var result: Array = []
	var seen: Dictionary = {}
	var profile: Dictionary = character.get("relicObjective",{})
	for recommendation in profile.get("recommendedSets",[]):
		if not recommendation is Dictionary:continue
		var set_id: String = str(recommendation.get("setId",""))
		if seen.has(set_id) or not catalog.get("RelicSets",{}).has(set_id):continue
		seen[set_id] = true
		var entry: Dictionary = catalog.RelicSets[set_id].duplicate(true)
		entry.setId = set_id
		entry.reason = str(recommendation.get("reason",""))
		entry.owned = state.ownedCharacters.has(char_id)
		entry.equipEnabled = entry.owned
		entry.advisory = true
		result.append(entry)
	return result
