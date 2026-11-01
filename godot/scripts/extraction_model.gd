extends RefCounted
## 搜打撤独立状态机；所有变更通过宿主原子存档事务提交。
const ExpeditionEvents = preload("res://scripts/expedition_events.gd")
const STASH_WIDTH := 10
const STASH_HEIGHT := 12
const BAG_WIDTH := 6
const BAG_HEIGHT := 5
const MAX_ACTS := 3
const ROOMS_PER_ACT := 4
var _host_ref: WeakRef
var host:
	get: return _host_ref.get_ref()
var data: Dictionary = {}
var _engine

func _init(owner) -> void:
	_host_ref = weakref(owner)
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/extraction.json"))
	if parsed is Dictionary: data = parsed

static func defaults() -> Dictionary:
	return {"credits": 0, "stash": [], "loadout": [], "mailbox": [], "collection": [], "unlockedDifficulty": 0, "run": {}, "lastRun": {}, "runs": 0, "utility": {"armor": {}, "backpack": {}}, "keyring": []}

func state() -> Dictionary:
	return host.state.extraction

func run() -> Dictionary:
	return state().run

func active() -> bool:
	return not run().is_empty()

func item_def(id: String) -> Dictionary:
	return data.get("items", {}).get(id, {})

func _fail(message: String) -> Dictionary:
	return host._fail(message)

func _commit(previous: Dictionary, result: Dictionary = {}) -> Dictionary:
	_sync_room()
	return host._commit(previous, result)

func _rand() -> float:
	var r := RandomNumberGenerator.new()
	r.state = int(run().rngState)
	var value := r.randf()
	run().rngState = str(r.state)
	return value

func _uid(prefix: String) -> String:
	run().serial += 1
	return "%s_%s_%d" % [run().id, prefix, int(run().serial)]

func _make_item(id: String) -> Dictionary:
	return {"uid": _uid("item"), "itemId": id, "x": 0, "y": 0, "rotated": false, "revealed": false, "appraisalRisk": int(run().difficulty), "originAct":int(run().act)}

func start_run(difficulty: int = 0) -> Dictionary:
	if active(): return _fail("当前搜打撤尚未结算")
	if host.abyss_run_active() or not host._issued_config.is_empty(): return _fail("请先结束当前远征或战斗")
	if difficulty < 0 or difficulty > int(state().unlockedDifficulty): return _fail("该危险等级尚未解锁")
	var party: Array = _departure_party()
	if party.is_empty(): return _fail("请先编队")
	var previous: Dictionary = host.state.duplicate(true)
	var generator := RandomNumberGenerator.new()
	generator.seed = host.rng.randi()
	state().run = {"id": host._uid("extraction"), "act": 1, "node": 0, "phase": "route", "difficulty": difficulty, "bag": [], "equipped": [], "party": party.duplicate(true), "containers": [], "routes": [], "activeEncounter": {}, "rngState": str(generator.state), "serial": 0, "roomsCleared": 0, "bossesDefeated": 0, "collectedValue": 0, "room": {}, "blessings": [], "pendingChoices": [], "characterFocus": {}, "roomActions": [], "growthBattles": 0, "startedAt": host._now()}
	run().baseMaxHp = _base_party_hp(party)
	run().securedValue = 0
	run().securedItems = 0
	for unit in party:
		if int(host.catalog.CharacterData[unit.id].rarity) == 5: run().characterFocus[unit.id] = 1.0
	for item in state().loadout:
		if not _place(run().bag, item.duplicate(true), dimensions("bag")):
			host.state = previous
			return _fail("携带物品无法放入背包，请减少携带数量")
	state().loadout = []
	_routes()
	return _commit(previous, {"message": "出发，击败每幕首领后可以撤离"})

func _departure_party() -> Array:
	# 保留完整局外成长；装备/命座冻结，战斗经验升级从下一战生效。
	var party:Array=host.battle_party(false)
	for unit in party:unit.permanentGrowth=host.growth_snapshot(unit.id)
	return party

func _sync_room() -> void:
	if not active() or not run().has("map"): return
	for room in run().map.rooms:
		if room.id == run().map.currentRoomId:
			room.containers = run().containers.duplicate(true)
			room.actions = run().get("roomActions", []).duplicate(true)
			for flag in ["unlocked", "depositUsed", "name", "description", "eventIcon"]:
				if run().room.has(flag): room[flag] = run().room[flag]
			if run().phase in ["room", "boss_exit"]: room.cleared = true

func _generate_map() -> void:
	var map := {"rooms": [], "edges": [], "districts": [], "currentRoomId": "", "bossRoomId": "", "bossUnlocked": false, "explored": 0, "requiredExploration": 6}
	var themes := ["ruins", "forest", "sanctum"]
	var names := ["旧王城遗址", "幽光林地", "星核圣所"]
	var offset := int(_rand() * 3)
	var types := ["battle", "battle", "cache", "rest", "event", "elite", "hospital", "workshop", "shrine"]
	var labels := {"entry":"远征入口", "battle":"巡逻走廊", "cache":"旅人物资站", "rest":"隐蔽营地", "event":"遗迹调查", "elite":"禁卫哨所", "vault":"封存宝库", "hospital":"疗愈药房", "workshop":"符文工坊", "shrine":"星辉神龛", "boss":"封印核心"}
	var vault := 8 + int(_rand() * 10) if _rand() < float(data.mapEconomy.vaultChance) else -1
	var relay_index := 3 + int(_rand() * 4)
	var key_index := 9 + int(_rand() * 8) if _rand() < 0.45 else -1
	labels.key_vault = "封存密室"
	labels.relay = "远征寄存站"
	for district in range(3):
		var theme: String = themes[(district + offset + int(run().act) - 1) % 3]
		var pool: Array = data.get("mapBackgrounds", {}).get(theme, ["res://assets/extraction/rooms/%s_1.webp" % theme, "res://assets/extraction/rooms/%s_2.webp" % theme])
		map.districts.append({"id":"district_%d" % district, "name":names[(district+offset+int(run().act)-1)%3], "theme":theme, "background":("res://assets/extraction/rooms/%s_act%d.webp" % [theme,int(run().act)]) if int(run().act)>1 else pool[0]})
		for local in range(6):
			var index := district * 6 + local
			var kind: String = str(types[int(_rand() * types.size()) % types.size()])
			if index == 0: kind = "entry"
			elif index == 1: kind = "cache"
			elif index == 2: kind = "rest"
			elif index == vault: kind = "vault"
			elif index == relay_index: kind = "relay"
			elif index == key_index: kind = "key_vault"
			var room_pool: Array = pool.duplicate()
			if int(run().act)>1:
				var act_background:="res://assets/extraction/rooms/%s_act%d.webp" % [theme,int(run().act)]
				if index in [0,1]:room_pool=[act_background]
				else:
					# One existing background roll is retained; weighting changes only art.
					for repeat in range(pool.size()*4):room_pool.append(act_background)
			if kind == "relay": room_pool.append("res://assets/extraction/rooms/courier_waystation.webp")
			elif kind == "key_vault": room_pool.append("res://assets/extraction/rooms/astral_vault.webp")
			var id := _uid("room")
			map.rooms.append({"id":id, "name":labels[kind], "type":kind, "description":_room_description(kind), "tier":mini(4,district+1+int(local/3)), "districtId":"district_%d" % district, "x":0.07+(district*2+local%2)*0.14+(_rand()-0.5)*0.012, "y":0.18+int(local/2)*0.31+(_rand()-0.5)*0.012, "visited":index==0, "cleared":index==0, "background":room_pool[int(_rand()*room_pool.size())%room_pool.size()], "containers":[], "actions":[]})
		# Randomized frontier tree on adjacent lattice cells, plus one local loop.
		var visited: Array = [0]
		var candidates: Array = []
		for local in range(6):
			if local % 2 == 0: candidates.append([local,local+1])
			if local < 4: candidates.append([local,local+2])
		while visited.size() < 6:
			var frontier: Array = []
			for edge in candidates:
				if (edge[0] in visited) != (edge[1] in visited): frontier.append(edge)
			var edge: Array = frontier[int(_rand()*frontier.size())%frontier.size()]
			map.edges.append([map.rooms[district*6+edge[0]].id,map.rooms[district*6+edge[1]].id])
			if edge[0] not in visited: visited.append(edge[0])
			if edge[1] not in visited: visited.append(edge[1])
		var extras: Array = []
		for edge in candidates:
			if not _has_edge(map.edges,map.rooms[district*6+edge[0]].id,map.rooms[district*6+edge[1]].id): extras.append(edge)
		if not extras.is_empty():
			var edge: Array = extras[int(_rand()*extras.size())%extras.size()]
			map.edges.append([map.rooms[district*6+edge[0]].id,map.rooms[district*6+edge[1]].id])
		if district > 0:
			var row := int(_rand()*3)
			map.edges.append([map.rooms[(district-1)*6+row*2+1].id,map.rooms[district*6+row*2].id])
			if _rand() < 0.55:
				var second := (row+1+int(_rand()*2))%3
				map.edges.append([map.rooms[(district-1)*6+second*2+1].id,map.rooms[district*6+second*2].id])
	var boss_id := _uid("room")
	var boss_row := int(_rand()*3)
	map.rooms.append({"id":boss_id, "name":labels.boss, "type":"boss", "description":"击败首领，撤离或深入下一幕", "tier":4, "districtId":"district_2", "x":0.95, "y":0.18+boss_row*0.31, "visited":false, "cleared":false, "background":map.districts[2].background, "containers":[], "actions":[]})
	map.edges.append([map.rooms[12+boss_row*2+1].id,boss_id])
	map.currentRoomId = map.rooms[0].id
	map.bossRoomId = boss_id
	run().map = map
	run().room = map.rooms[0].duplicate(true)
	run().containers = []
	run().selectedContainer = ""
	run().roomActions = []

func _has_edge(edges: Array, a: String, b: String) -> bool:
	for edge in edges:
		if (edge[0] == a and edge[1] == b) or (edge[1] == a and edge[0] == b): return true
	return false

func _routes() -> void:
	if not run().has("map"): _generate_map()
	run().phase = "route"
	run().routes = route_options()

func map_state() -> Dictionary:
	var result: Dictionary = run().get("map", {}).duplicate(true)
	var paths := _travel_paths()
	result.reachableRoomIds = paths.keys()
	result.travelPaths = paths
	return result

func room_scene() -> Dictionary:
	var scene: Dictionary = run().get("room", {}).duplicate(true)
	scene.containers = containers()
	scene.selectedContainer = run().get("selectedContainer", "")
	return scene

func route_options() -> Array:
	if not active() or not run().has("map"): return run().get("routes", []).duplicate(true)
	var result: Array = []
	var paths := _travel_paths()
	for room in run().map.rooms:
		if paths.has(room.id):
			var option: Dictionary = room.duplicate(true)
			option.locked = room.type == "boss" and not run().map.bossUnlocked
			option.path = paths[room.id]
			result.append(option)
	return result

func choose_route(id: String) -> Dictionary:
	return enter_room(id)

func enter_room(id: String) -> Dictionary:
	if not active() or run().phase not in ["route", "room", "boss_exit"]: return _fail("请先结束当前战斗")
	if not run().get("pendingChoices", []).is_empty(): return _fail("先选择一项祝福")
	var previous: Dictionary = host.state.duplicate(true)
	if not run().has("map"):
		_generate_map()
		_routes()
		return _commit(previous, {"message": "旧探索已迁移为随机地图，请选择相邻房间"})
	var target: Dictionary = {}
	for room in run().map.rooms:
		if room.id == id: target = room
	if target.is_empty() or not _travel_paths().has(id): return _fail("道路尚未打通")
	if target.type == "boss" and not run().map.bossUnlocked: return _fail("继续探索，解除首领封印")
	_sync_room()
	run().map.currentRoomId = id
	run().node = int(target.tier)
	run().room = target.duplicate(true)
	run().containers = target.containers.duplicate(true)
	run().roomActions = target.get("actions", []).duplicate(true)
	run().selectedContainer = ""
	run().routes = []
	run().phase = "room"
	if target.visited:
		if target.type == "boss" and target.cleared: run().phase = "boss_exit"
	else:
		target.visited = true
		run().room.visited = true
		if target.type != "boss":
			run().map.explored += 1
			run().roomsCleared += 1
			run().node = int(target.tier)
			run().map.bossUnlocked = run().map.explored >= int(run().map.requiredExploration)
		var kind: String = target.type
		if kind in ["battle", "elite", "boss", "vault"]:
			run().node = int(target.tier)
			_generate_encounter("elite" if kind == "vault" else kind)
		else:
			if kind in ["rest", "event", "hospital", "workshop", "shrine", "key_vault"]: _prepare_room_actions(kind)
			if kind not in ["rest", "event", "key_vault", "relay"]: _populate_room(kind)
	return _commit(previous, {"config": run().activeEncounter.duplicate(true), "message": str(target.name)})

func _populate_room(kind: String) -> void:
	var economy: Dictionary = data.get("mapEconomy", {})
	var counts: Array = economy.get("ordinaryContainers", [1,2])
	var item_counts: Array = economy.get("ordinaryItems", [2,3])
	var count := int(counts[0]) + int(_rand() * (int(counts[1]) - int(counts[0]) + 1))
	if kind == "vault": count = int(economy.get("vaultContainers", 2))
	var quality := int(economy.get("vaultQuality", 1)) if kind == "vault" else int(economy.get("shrineQuality", 0)) if kind == "shrine" else 0
	var room_pools := {"hospital": ["补给", "疗愈用品"], "workshop": ["符文构件", "遗迹装置", "工具", "零件", "装备", "整备"], "shrine": ["古物", "王室遗物", "奇珍", "秘传典籍"], "vault": ["珠宝", "贵金属", "王室遗物", "奇珍", "遗迹珍藏"]}
	var kinds := ["wooden_chest", "old_urn", "herb_basket", "alchemy_cabinet", "iron_reliquary", "bookcase", "crystal_cache", "weapon_rack", "golem_case", "offering_altar"]
	var theme := "ruins"
	for district in run().map.districts:
		if district.id == run().room.districtId: theme = district.theme
	var district_kinds := {"ruins":["wooden_chest", "old_urn", "bookcase"], "forest":["herb_basket", "offering_altar", "old_urn"], "sanctum":["golem_case", "crystal_cache", "alchemy_cabinet"]}
	kinds.append_array(district_kinds.get(theme, []))
	for i in range(count):
		var object_kind: String = kinds[int(_rand() * kinds.size()) % kinds.size()]
		var labels := {"wooden_chest":"封存木箱", "old_urn":"古陶瓮", "herb_basket":"采药篮", "alchemy_cabinet":"炼金药柜", "iron_reliquary":"圣物匣", "bookcase":"遗迹书柜", "crystal_cache":"晶石储匣", "weapon_rack":"古代兵器架", "golem_case":"魔偶机匣", "offering_altar":"供奉祭台"}
		var item_count := int(economy.get("vaultItems", 3)) if kind == "vault" else int(item_counts[0]) + int(_rand() * (int(item_counts[1]) - int(item_counts[0]) + 1))
		_container(labels[object_kind], item_count, quality, room_pools.get(kind, []))
		var container: Dictionary = run().containers.back()
		container.kind = object_kind
		container.sprite = "res://assets/extraction/containers/%s.png" % object_kind
		container.sceneX = 0.18 + i * 0.29 + (_rand() - 0.5) * 0.08
		container.sceneY = 0.55 + _rand() * 0.22

func choose_container(id: String) -> Dictionary:
	if not active() or run().phase not in ["room", "boss_exit"] or _find_container(id).is_empty(): return _fail("当前容器不可搜索")
	var previous: Dictionary = host.state.duplicate(true)
	run().selectedContainer = id
	return _commit(previous)

func _heal(fraction: float) -> void:
	for unit in run().party:
		if unit.currentHp > 0: unit.currentHp = mini(int(unit.maxHp), int(unit.currentHp + unit.maxHp * fraction))

func _generate_encounter(kind: String) -> void:
	var act := int(run().act)
	var pool: Array = ["wolf", "goblin", "fire_imp"] if act == 1 else ["ice_wolf", "thunder_hawk", "fire_imp"]
	var count := 2 if act < 3 else 3
	if kind == "elite":
		pool = ["dark_knight", "stone_golem"]
		count = 1 if act < 3 else 2
	elif kind == "boss":
		pool = host.catalog.AbyssData.pools.boss
		count = 1
	var enemies: Array = []
	for i in range(count): enemies.append(pool[int(_rand() * pool.size()) % pool.size()])
	var rank := int(run().difficulty)
	if kind == "boss" and rank >= 4:
		enemies.append("dark_knight")
		if rank >= 5: enemies.append("thunder_hawk")
	var budgets: Dictionary = data.get("balance", {})
	var n := float((act - 1) * 5 + int(run().node))
	var hp: float = (0.70 + 0.075 * n) * float(budgets.get("rankHp", [1,1.35,1.8,2.4])[rank])
	var atk: float = (0.65 + 0.030 * n) * float(budgets.get("rankAtk", [1,1.5,2.2,3.2])[rank])
	hp *= float(budgets.get("actHp", [1.0, 1.0, 1.0])[act - 1])
	atk *= float(budgets.get("actAtk", [1.0, 1.0, 1.0])[act - 1])
	if kind == "boss": hp *= 0.45; atk *= 0.85
	var mods := {"hpMod": hp, "atkMod": atk, "defMod": (0.80 + 0.014 * n) * float(budgets.get("rankDef", [1,1.1,1.2,1.3])[rank]), "spdMod": 1.0 + 0.008 * n}
	var config := {"id": _uid("encounter"), "token": _uid("battle"), "name": "第 %d 幕 · %s" % [act, "首领" if kind == "boss" else "精英" if kind == "elite" else "巡逻队"], "isExtraction": true, "maxRounds": 40, "isAbyss": false, "isBoss": kind == "boss", "isElite": kind == "elite", "enemies": enemies, "waves": [{"enemies": enemies.duplicate()}], "scaleMult": mods, "seed": int(_rand() * 2147483000), "rewards": {}, "staminaCost": 0, "difficulty": rank, "act": act, "kind": kind, "healingMultiplier": 1.0, "enrageAfterRound": 15 if rank >= 3 else 0, "enragePerRound": 0.05 if rank >= 3 else 0.0, "enrageCap": 0.5 if rank >= 3 else 0.0}
	run().activeEncounter = config
	run().phase = "battle"
	_engine = null

func prepare_battle() -> Dictionary:
	if not active() or run().phase != "battle" or run().activeEncounter.is_empty(): return _fail("当前没有战斗")
	return {"success": true, "config": run().activeEncounter.duplicate(true)}

func battle_party() -> Array:
	return run().get("party", []).duplicate(true)

func effects() -> Array:
	var result: Array = []
	if not active(): return result
	for item in run().equipped:
		for raw in item_def(item.itemId).get("effects", []):
			var effect: Dictionary = raw.duplicate(true)
			effect.rewardId = item.itemId
			effect.rewardInstanceId = item.uid
			effect.rewardName = item_def(item.itemId).name
			result.append(effect)
	for reward in run().get("blessings", []):
		for raw in _growth_definition(str(reward.id)).get("effects", []):
			var effect: Dictionary = raw.duplicate(true)
			effect.rewardId = reward.id
			effect.rewardInstanceId = reward.instanceId
			effect.rewardName = reward.name
			result.append(effect)
	return result

func start_battle(engine) -> Dictionary:
	if _engine != null: return _fail("当前战斗已经开始")
	var prepared := prepare_battle()
	if not prepared.success: return prepared
	_engine = engine
	var armor: Dictionary = equipment_status().armor
	prepared.config.equipmentShields = _equipment_shield_allocations()
	prepared.config.equipmentShieldMax = int(armor.max)
	engine.start(prepared.config, battle_party(), effects())
	return {"success": true, "config": prepared.config}

func settle_battle(config: Dictionary, battle_state: Dictionary) -> Dictionary:
	if not active() or run().phase != "battle" or run().activeEncounter.is_empty(): return _fail("战斗已经结算")
	if _engine == null or _engine.state != battle_state: return _fail("缺少有效战斗结果")
	if str(config.get("token", "")) != str(run().activeEncounter.token) or str(battle_state.get("config", {}).get("token", "")) != str(run().activeEncounter.token): return _fail("战斗凭证不匹配")
	if battle_state.get("phase", "") not in ["victory", "defeat"]: return _fail("战斗尚未结束")
	var previous: Dictionary = host.state.duplicate(true)
	var armor: Dictionary = state().get("utility", {}).get("armor", {})
	var armor_max := int(battle_state.get("config", {}).get("equipmentShieldMax", 0))
	if not armor.is_empty() and armor_max > 0:
		armor.condition = clampf(float(battle_state.get("equipmentShieldRemaining", 0)) / armor_max, 0.0, 1.0)
	var victory: bool = battle_state.phase == "victory"
	var xp:=0
	var progression:Array=[]
	host.state.stats.totalBattles += 1
	if not victory:
		_end("defeat")
	else:
		host.state.stats.totalVictories += 1
		var next_party: Array = []
		for original in run().party:
			var saved: Dictionary = original.duplicate(true)
			for unit in battle_state.allies:
				if unit.id == original.id:
					saved.currentHp = int(unit.currentHp)
					saved.maxHp = int(unit.maxHp)
					saved._abyssSavedMaxHp = int(unit.maxHp)
					saved.energy = int(unit.energy)
					saved.cooldowns = unit.cooldowns.duplicate(true)
			next_party.append(saved)
		run().party = next_party
		var recovery := 0.0
		for effect in effects():
			if effect.get("type") == "victoryHealPct": recovery += float(effect.get("value", 0))
		if recovery > 0: _heal(recovery)
		run().growthBattles = int(run().get("growthBattles", 0)) + 1
		var kind: String = run().activeEncounter.kind
		xp=int(round((35+int(run().act)*10)*(1.5 if kind=="boss" else (1.25 if kind=="elite" else 1.0))))
		for unit in run().party:
			if host.state.ownedCharacters.has(unit.id):
				if not unit.has("permanentGrowth"):unit.permanentGrowth=host.growth_snapshot(unit.id)
				progression.append(host._grant_exp(unit.id,xp))
				unit.level=int(host.state.ownedCharacters[unit.id].level)
				unit.stats=host.computed_stats(unit.id,unit.level,unit.permanentGrowth)
				if not unit.get("saveData") is Dictionary:unit.saveData=host.state.ownedCharacters[unit.id].duplicate(true)
				unit.saveData.level=unit.level
				unit.saveData.exp=int(host.state.ownedCharacters[unit.id].exp)
		run().baseMaxHp=_base_party_hp(run().party)
		run().expEarned=int(run().get("expEarned",0))+xp
		run().activeEncounter = {}
		if kind == "boss":
			run().phase = "boss_exit"
			run().bossesDefeated += 1
			_container("首领保险柜", 4, 2)
		else:
			run().phase = "room"
			if run().room.get("type") == "vault": _populate_room("vault")
			else: _container("精英战利品" if kind == "elite" else "敌人背包", 3 if kind == "elite" else 2, 1 if kind == "elite" else 0)
		if int(run().growthBattles) == 1 or kind in ["elite", "boss"]:
			_offer_growth("gold" if kind == "boss" else "")
	var result := _commit(previous, {"victory": victory, "ended": not victory, "rewards": {"exp":xp}, "progression":progression, "lastRun": state().lastRun.duplicate(true), "message": "首领已击败，出口开放" if victory and active() and run().phase == "boss_exit" else "战斗结束"})
	if result.success: _engine = null
	return result

func _container(title: String, count: int, quality: int, categories: Array = []) -> void:
	var container := {"id": _uid("container"), "name": title, "kind": "safe" if quality == 2 else "supply", "width": 6, "height": 8, "revealed": 0, "items": [], "quality": quality, "sprite": "res://assets/extraction/containers/rune_vault.png" if quality == 2 else "res://assets/extraction/containers/wooden_chest.png", "sceneX": 0.2 + _rand() * 0.6, "sceneY": 0.55 + _rand() * 0.22}
	var weights: Array = data.get("rarityWeightsByAct", [[32,20,32,13,2.8,0.2],[23,15,34,21,6.5,0.5],[15,10,34,28,12,1]])[int(run().act)-1].duplicate()
	var economy: Dictionary = data.get("lootEconomy", {})
	weights[3] = float(weights[3]) + quality * float(economy.get("qualityPurpleWeight", 3)) + float(economy.get("riskPurpleWeight", 2)) * int(run().difficulty)
	weights[4] = float(weights[4]) + quality * float(economy.get("qualityGoldWeight", 2)) + float(economy.get("riskGoldWeight", 1)) * int(run().difficulty)
	weights[5] = float(weights[5]) + quality * float(economy.get("qualityRedWeight", 0.7)) + float(economy.get("riskRedWeight", 0.05)) * int(run().difficulty)
	for i in range(count):
		var total := 0.0
		for w in weights: total += float(w)
		var target := _rand() * total
		var rarity := 0
		for ri in range(weights.size()):
			target -= float(weights[ri])
			if target <= 0: rarity = ri; break
		if quality == 2 and i == count - 1: rarity = maxi(rarity, 4 if int(run().act) == MAX_ACTS else 3)
		var pool: Array = []
		for key in data.items:
			if int(data.items[key].rarity) == rarity: pool.append(key)
		var preferred: Array = []
		for key in pool:
			if data.items[key].get("category", "") in categories: preferred.append(key)
		if not preferred.is_empty(): pool = preferred
		if not pool.is_empty():
			var item_weight:=0.0
			for key in pool:item_weight+=float(data.items[key].get("dropWeight",1.0))
			var item_roll:=_rand()*item_weight
			var picked:String=str(pool.back())
			for key in pool:
				item_roll-=float(data.items[key].get("dropWeight",1.0))
				if item_roll<=0:picked=str(key);break
			container.items.append(_make_item(picked))
	var packed: Array = []
	for item in container.items:
		_place(packed, item, Vector2i(6, 8))
	container.items = packed
	run().containers.append(container)

func containers() -> Array:
	return run().get("containers", []).duplicate(true)

func _find_container(id: String) -> Dictionary:
	for container in run().get("containers", []):
		if container.id == id: return container
	return {}

func reveal_next(container_id: String) -> Dictionary:
	if not active() or run().phase not in ["room", "boss_exit"]: return _fail("当前无法搜索")
	var container := _find_container(container_id)
	if container.is_empty(): return _fail("容器不存在")
	for item in container.items:
		if not item.revealed:
			var previous: Dictionary = host.state.duplicate(true)
			item.revealed = true
			container.revealed += 1
			return _commit(previous, {"item": item.duplicate(true), "definition": item_def(item.itemId).duplicate(true)})
	return _fail("容器已经搜索完毕")

func dimensions(scope: String) -> Vector2i:
	return Vector2i(STASH_WIDTH, STASH_HEIGHT) if scope == "stash" else _bag_bounds(state())

func _items(scope: String) -> Array:
	return state().stash if scope == "stash" else run().get("bag", [])

func _size(item: Dictionary) -> Vector2i:
	var definition := item_def(str(item.get("itemId", "")))
	var value := Vector2i(int(definition.get("width", 1)), int(definition.get("height", 1)))
	return Vector2i(value.y, value.x) if item.get("rotated", false) else value

func _fits(items: Array, item: Dictionary, bounds: Vector2i) -> bool:
	var s := _size(item)
	var rect := Rect2i(int(item.x), int(item.y), s.x, s.y)
	if rect.position.x < 0 or rect.position.y < 0 or rect.end.x > bounds.x or rect.end.y > bounds.y: return false
	for other in items:
		if other.uid == item.uid: continue
		var os := _size(other)
		if rect.intersects(Rect2i(int(other.x), int(other.y), os.x, os.y)): return false
	return true

func _place(items: Array, item: Dictionary, bounds: Vector2i) -> bool:
	for rotated in [false, true]:
		item.rotated = rotated
		for y in range(bounds.y):
			for x in range(bounds.x):
				item.x = x; item.y = y
				if _fits(items, item, bounds): items.append(item); return true
	return false

func take_item(container_id: String, item_uid: String) -> Dictionary:
	if not active() or run().phase not in ["room", "boss_exit"]: return _fail("当前无法拾取")
	var container := _find_container(container_id)
	if container.is_empty(): return _fail("容器不存在")
	for i in range(container.items.size()):
		var item: Dictionary = container.items[i]
		if item.uid != item_uid: continue
		if not item.revealed: return _fail("请先搜索该物品")
		var previous: Dictionary = host.state.duplicate(true)
		if not _pickup_fit(item): return _fail("背包已满，物品留在原容器；可继续搜索更小的物品")
		container.items.remove_at(i)
		run().collectedValue += item_value(item)
		return _commit(previous, {"item": item.duplicate(true)})
	return _fail("物品已被取走")

func _pickup_fit(item: Dictionary) -> bool:
	if item_def(item.itemId).get("kind")=="key":
		if state().keyring.size()>=20000:return false
		state().keyring.append(item.duplicate(true))
		return true
	var bag: Array = run().bag.duplicate(true)
	if _place(bag, item.duplicate(true), dimensions("bag")):
		run().bag = bag
		return true
	bag = run().bag.duplicate(true)
	bag.append(item.duplicate(true))
	var packed := _packed_copy(bag,dimensions("bag"))
	if packed.size()!=bag.size(): return false
	run().bag = packed
	return true

func take_all_revealed(container_id: String) -> Dictionary:
	if not active() or run().phase not in ["room", "boss_exit"]: return _fail("当前无法拾取")
	var container := _find_container(container_id)
	if container.is_empty(): return _fail("容器不存在")
	var previous: Dictionary = host.state.duplicate(true)
	var candidates: Array = []
	for item in container.items:
		if item.revealed: candidates.append(item)
	candidates.sort_custom(func(a,b): return float(item_value(a)) / (_size(a).x * _size(a).y) > float(item_value(b)) / (_size(b).x * _size(b).y))
	var taken: Array = []
	var left: Array = []
	for item in candidates:
		if _pickup_fit(item):
			taken.append(item.uid)
			container.items.erase(item)
			run().collectedValue += item_value(item)
		else: left.append(item.uid)
	return _commit(previous, {"taken": taken, "left": left, "message": "拾取 %d 件，空间不足留下 %d 件；未丢弃任何背包物品" % [taken.size(), left.size()]})

func move_item(scope: String, uid: String, x: int, y: int, rotated: bool) -> Dictionary:
	if scope not in ["stash", "bag"] or (scope == "bag" and (not active() or run().phase == "battle")): return _fail("当前无法移动物品")
	for item in _items(scope):
		if item.uid == uid:
			var candidate: Dictionary = item.duplicate(true)
			candidate.x = x; candidate.y = y; candidate.rotated = rotated
			if not _fits(_items(scope), candidate, dimensions(scope)): return _fail("该位置被占用或超出边界")
			var previous: Dictionary = host.state.duplicate(true)
			item.x = x; item.y = y; item.rotated = rotated
			return _commit(previous)
	return _fail("物品不存在")

func sort_grid(scope: String) -> Dictionary:
	if scope not in ["stash", "bag"] or (scope == "bag" and (not active() or run().phase == "battle")): return _fail("当前无法整理")
	var pending: Array = _items(scope).duplicate(true)
	var packed := _packed_copy(pending,dimensions(scope))
	if packed.size()!=pending.size(): return _fail("暂未找到合适布局，原物品保持原位")
	var previous: Dictionary = host.state.duplicate(true)
	if scope == "stash": state().stash = packed
	else: run().bag = packed
	return _commit(previous)

func equip_item(uid: String, replace_uid: String = "") -> Dictionary:
	if not can_prepare_supplies(): return _fail("战斗结束后再整备")
	var selected: Dictionary = {}
	for entry in run().bag:
		if entry.uid == uid: selected=entry;break
	if selected.is_empty(): return _fail("物品不存在")
	var d := item_def(selected.itemId)
	if d.get("kind")=="utility": return set_utility_slot(str(d.slot),uid)
	if d.get("kind")!="equipment": return _fail("这件物品无法装备")
	var old: Dictionary = {}
	for item in run().equipped:
		if item.uid == replace_uid: old=item;break
	if not replace_uid.is_empty() and old.is_empty(): return _fail("替换装备已经改变")
	if run().equipped.size()>=3 and old.is_empty(): return _fail("选择一件装备替换")
	var previous: Dictionary = host.state.duplicate(true)
	run().bag.erase(selected)
	if not old.is_empty():
		run().equipped.erase(old)
		var remaining: Array = run().bag.duplicate(true)
		remaining.append(old.duplicate(true))
		var packed := _packed_copy(remaining,dimensions("bag"))
		if packed.size()!=remaining.size():
			host.state=previous
			return _fail("背包装不下换出的装备")
		run().bag=packed
	run().equipped.append(selected)
	return _commit(previous,{"message":"已装备「%s」" % d.name})

func unequip_item(uid: String) -> Dictionary:
	if not can_prepare_supplies(): return _fail("战斗结束后再整备")
	for i in range(run().equipped.size()):
		var item: Dictionary = run().equipped[i]
		if item.uid != uid: continue
		var previous: Dictionary = host.state.duplicate(true)
		if not _place(run().bag, item.duplicate(true), dimensions("bag")): return _fail("背包空间不足")
		run().equipped.remove_at(i)
		return _commit(previous)
	return _fail("物品不存在")

func use_item(uid: String) -> Dictionary:
	if not can_prepare_supplies(): return _fail("战斗结束后再使用补给")
	for i in range(run().bag.size()):
		var item: Dictionary = run().bag[i]
		if item.uid != uid: continue
		var definition := item_def(item.itemId)
		if definition.kind != "consumable": return _fail("物品无法使用")
		if not can_use_consumable(item.itemId): return _fail("当前无需这份补给")
		var previous: Dictionary = host.state.duplicate(true)
		_apply_consumable(definition)
		run().bag.remove_at(i)
		return _commit(previous)
	return _fail("物品不存在")

func discard_item(uid: String) -> Dictionary:
	if not active() or run().phase == "battle": return _fail("请在战斗外整理")
	for i in range(run().bag.size()):
		if run().bag[i].uid == uid:
			var previous: Dictionary = host.state.duplicate(true)
			run().bag.remove_at(i)
			return _commit(previous)
	return _fail("物品不存在")

func advance_room() -> Dictionary:
	if not active() or run().phase != "room": return _fail("请先完成当前房间")
	if not run().get("pendingChoices", []).is_empty(): return _fail("先选择一项祝福")
	var previous: Dictionary = host.state.duplicate(true)
	_sync_room()
	_routes()
	return _commit(previous, {"config": run().activeEncounter.duplicate(true)})

func continue_act() -> Dictionary:
	if not active() or run().phase != "boss_exit": return _fail("击败首领后才能继续")
	if not run().get("pendingChoices", []).is_empty(): return _fail("先选择一项祝福")
	if int(run().act) >= MAX_ACTS: return _fail("三幕探索已完成，请撤离结算")
	var previous: Dictionary = host.state.duplicate(true)
	run().act += 1; run().node = 0
	_generate_map()
	_routes()
	return _commit(previous)

func _end(outcome: String) -> void:
	var value := 0
	for item in run().bag + run().equipped: value += item_value(item)
	state().lastRun = {"outcome": outcome, "act": int(run().act), "difficulty": int(run().difficulty), "roomsCleared": int(run().roomsCleared), "bossesDefeated": int(run().bossesDefeated), "value": value, "items": run().bag.size() + run().equipped.size(), "durationSeconds": maxi(0, int((host._now() - int(run().startedAt)) / 1000)), "securedValue":int(run().get("securedValue",0)), "securedItems":int(run().get("securedItems",0)), "salvageGold":int(run().get("salvageGold",0)), "expEarned":int(run().get("expEarned",0))}
	state().runs += 1
	state().run = {}

func extract() -> Dictionary:
	if not active() or run().phase != "boss_exit": return _fail("击败本幕首领后才能撤离")
	var previous: Dictionary = host.state.duplicate(true)
	for item in run().bag + run().equipped:
		var copy: Dictionary = item.duplicate(true)
		if not _place(state().stash, copy, dimensions("stash")): state().mailbox.append(item.duplicate(true))
	if int(run().act) == MAX_ACTS: state().unlockedDifficulty = maxi(int(state().unlockedDifficulty), mini(max_difficulty(), int(run().difficulty) + 1))
	_end("extracted")
	return _commit(previous, {"ended": true, "lastRun": state().lastRun.duplicate(true), "message": "撤离成功，战利品已入库；超出空间的物品保存在待领取区"})

func retreat() -> Dictionary:
	if not active(): return _fail("当前没有进行中的搜打撤")
	var previous: Dictionary = host.state.duplicate(true)
	if _engine != null and run().phase == "battle" and str(_engine.state.get("config",{}).get("token","")) == str(run().activeEncounter.get("token","")):
		var maximum := int(_engine.state.config.get("equipmentShieldMax",0))
		if maximum > 0 and not state().utility.armor.is_empty(): state().utility.armor.condition = clampf(float(_engine.state.get("equipmentShieldRemaining",0))/maximum,0.0,1.0)
	_end("retreat")
	var result := _commit(previous, {"ended": true, "victory": false, "rewards": {}, "lastRun": state().lastRun.duplicate(true)})
	if result.success: _engine = null
	return result

func sell_item(uid: String) -> Dictionary:
	if active(): return _fail("请在本局结束后处理仓库")
	for i in range(state().stash.size()):
		var item: Dictionary = state().stash[i]
		if item.uid != uid: continue
		var previous: Dictionary = host.state.duplicate(true)
		var value := item_value(item)
		host.state.resources.gold += value
		state().stash.remove_at(i)
		return _commit(previous, {"value": value})
	return _fail("物品不存在")

func collect_item(uid: String) -> Dictionary:
	if active(): return _fail("请在本局结束后收藏")
	for i in range(state().stash.size()):
		var item: Dictionary = state().stash[i]
		if item.uid != uid: continue
		if int(item_def(item.itemId).rarity)<4:return _fail("图鉴收藏金色与红色物品")
		if item.itemId in state().collection: return _fail("该藏品已经收藏，可以出售重复物品")
		var previous: Dictionary = host.state.duplicate(true)
		state().collection.append(item.itemId)
		state().stash.remove_at(i)
		return _commit(previous)
	return _fail("物品不存在")

func claim_mail() -> Dictionary:
	if active(): return _fail("请在本局结束后领取")
	var previous: Dictionary = host.state.duplicate(true)
	var remaining: Array = []
	var count := 0
	for item in state().mailbox:
		if _place(state().stash, item.duplicate(true), dimensions("stash")): count += 1
		else: remaining.append(item)
	state().mailbox = remaining
	return _commit(previous, {"count": count})

func valid(value: Variant) -> bool:
	if not value is Dictionary: return false
	for key in ["credits", "unlockedDifficulty", "runs"]:
		if not host._integer(value.get(key, 0), 0, max_difficulty() if key == "unlockedDifficulty" else 1000000000): return false
	for key in ["stash", "loadout", "mailbox", "collection"]:
		if not value.get(key, []) is Array or value.get(key, []).size() > 10000: return false
	if not value.get("lastRun", {}) is Dictionary: return false
	var summary: Dictionary = value.get("lastRun", {})
	if not summary.is_empty():
		if summary.get("outcome", "") not in ["extracted", "retreat", "defeat"]: return false
		for key in ["act", "difficulty", "roomsCleared", "bossesDefeated", "value", "items", "durationSeconds"]:
			if not host._integer(summary.get(key, -1)): return false
	var ids: Dictionary = {}
	if not _valid_utility(value.get("utility", {}), ids): return false
	if not value.get("keyring",[]) is Array or not _valid_items(value.get("keyring",[]),ids,Vector2i.ZERO,20000):return false
	for key_item in value.get("keyring",[]):
		if item_def(key_item.itemId).get("kind")!="key":return false
	if not _valid_items(value.get("stash", []), ids, Vector2i(STASH_WIDTH, STASH_HEIGHT)): return false
	if not _valid_items(value.get("mailbox", []), ids): return false
	if value.get("loadout", []).size() > 3 or not _valid_items(value.get("loadout", []), ids): return false
	var collected: Dictionary = {}
	for id in value.get("collection", []):
		if not id is String or item_def(id).is_empty() or collected.has(id): return false
		collected[id] = true
	var r = value.get("run", {})
	if not r is Dictionary: return false
	if r.is_empty(): return true
	for key in ["id", "phase", "rngState"]:
		if not r.get(key) is String: return false
	if r.phase not in ["route", "room", "battle", "boss_exit"] or not r.rngState.is_valid_int(): return false
	if not _valid_growth_state(r): return false
	if r.has("baseMaxHp") and not host._integer(r.baseMaxHp,1,300000000): return false
	for key in ["securedValue","securedItems","salvageGold","expEarned"]:
		if r.has(key) and not host._integer(r[key],0,1000000000): return false
	for key in ["act", "node", "difficulty", "serial", "roomsCleared", "bossesDefeated", "collectedValue", "startedAt"]:
		if not host._integer(r.get(key, -1), 0, 10000000000000000): return false
	if int(r.act) < 1 or int(r.act) > 3 or int(r.node) > 4 or int(r.difficulty) > int(value.get("unlockedDifficulty", 0)): return false
	for key in ["bag", "equipped", "containers", "routes", "party"]:
		if not r.get(key) is Array: return false
	if r.equipped.size() > 3 or r.containers.size() > 10 or r.routes.size() > 19 or r.party.is_empty() or r.party.size() > 3: return false
	if not _valid_items(r.bag, ids, _bag_bounds(value)) or not _valid_items(r.equipped, ids): return false
	for item in r.equipped:
		if item_def(item.itemId).kind != "equipment": return false
	for option in r.routes:
		if not option is Dictionary or not option.get("id") is String or not option.get("name") is String or not option.get("description") is String or option.get("type", "") not in ["entry", "boss", "battle", "cache", "rest", "event", "elite", "vault", "hospital", "workshop", "shrine", "key_vault", "relay"]: return false
	var container_ids: Dictionary = {}
	for container in r.containers:
		if not container is Dictionary or not container.get("id") is String or not container.get("items") is Array: return false
		if container_ids.has(container.id) or not container.get("name") is String or not host._integer(container.get("revealed", 0)): return false
		container_ids[container.id] = true
		if not _valid_scene_container(container): return false
		if not _valid_items(container.items, ids): return false
	if r.has("map") and not _valid_map(r, ids): return false
	var party_ids: Dictionary = {}
	for unit in r.party:
		if not unit is Dictionary or not host.catalog.CharacterData.has(unit.get("id", "")) or not unit.get("stats") is Dictionary: return false
		if not host._integer(unit.get("currentHp", -1)) or not host._integer(unit.get("maxHp", 0), 1) or unit.currentHp > unit.maxHp: return false
		if unit.has("permanentGrowth"):
			var snapshot=unit.permanentGrowth
			if not snapshot is Dictionary or not snapshot.get("constellation") is Dictionary or not snapshot.get("relics") is Dictionary or not host._integer(snapshot.get("awakening",-1),0,100):return false
			for key in ["hpPercent","atkPercent","defPercent","normalDmgBonus","skillDmgBonus","ultDmgBonus","skillCdReduce"]:
				if not host._number(snapshot.constellation.get(key),0,1000000):return false
			for key in ["hp_flat","atk_flat","def_flat","hp_pct","atk_pct","def_pct","spd","cri_rate","cri_dmg","energy_rate"]:
				if not host._number(snapshot.relics.get(key),0,100000000):return false
		if party_ids.has(unit.id): return false
		party_ids[unit.id] = true
		if not unit.get("skills") is Array or not unit.get("cooldowns") is Dictionary: return false
		if not host._integer(unit.get("energy", -1), 0, 100): return false
		for cooldown in unit.cooldowns.values():
			if not host._integer(cooldown, 0, 999): return false
		for skill in unit.skills:
			if not skill is String or not host.catalog.SkillData.has(skill): return false
		for stat in ["maxHp", "atk", "def", "spd", "cri", "criDmg"]:
			if not host._number(unit.stats.get(stat), 0, 100000000): return false
	if not r.get("activeEncounter") is Dictionary or not r.get("room") is Dictionary: return false
	if r.phase == "battle":
		var config: Dictionary = r.activeEncounter
		if int(config.get("maxRounds", 40)) != 40 or not config.get("isExtraction", false) or config.get("isAbyss", false) or not config.get("token") is String or not config.get("enemies") is Array or not config.get("scaleMult") is Dictionary: return false
		if not config.get("id") is String or not config.get("name") is String or config.get("kind", "") not in ["battle", "elite", "boss"] or not host._integer(config.get("seed", -1), 0, 2147483647): return false
		if config.enemies.is_empty() or config.enemies.size() > 3: return false
		for stat in ["hpMod", "atkMod", "defMod", "spdMod"]:
			if not host._number(config.scaleMult.get(stat), 0.01, 1000): return false
		if not config.get("waves") is Array or config.waves.size() != 1 or not config.waves[0] is Dictionary or config.waves[0].get("enemies") != config.enemies or config.waves[0].size() != 1: return false
		for enemy in config.enemies:
			if not host.catalog.EnemyData.has(enemy): return false
	if r.phase != "battle" and not r.activeEncounter.is_empty(): return false
	if r.phase == "route" and r.routes.is_empty(): return false
	if r.phase == "boss_exit" and (int(r.node) != ROOMS_PER_ACT or int(r.bossesDefeated) != int(r.act)): return false
	return true

func _valid_items(items: Array, ids: Dictionary, bounds := Vector2i.ZERO, max_count:int=10000) -> bool:
	if items.size() > max_count: return false
	for item in items:
		if not item is Dictionary or not item.get("uid") is String or item.uid.is_empty() or ids.has(item.uid): return false
		if not item.get("itemId") is String or item_def(item.itemId).is_empty(): return false
		if not host._integer(item.get("x", -1), 0, 100) or not host._integer(item.get("y", -1), 0, 100) or not item.get("rotated") is bool or not item.get("revealed") is bool: return false
		if item.has("legacyValue") and not host._integer(item.legacyValue, 0, 1000000000): return false
		if item.has("appraisalRisk") and not host._integer(item.appraisalRisk, 0, 5): return false
		if item.has("condition") and not host._number(item.condition, 0, 1): return false
		if item.has("originAct") and not host._integer(item.originAct,1,3):return false
		if bounds != Vector2i.ZERO and not _fits(items, item, bounds): return false
		ids[item.uid] = true
	return true

func sort_items(scope: String) -> Dictionary:
	return sort_grid(scope)

func auto_pack(scope: String) -> Dictionary:
	return sort_grid(scope)

func bring_item(uid: String) -> Dictionary:
	if active(): return _fail("请在出发前选择携带物品")
	if state().loadout.size() >= 3: return _fail("最多携带三件物品出发")
	for i in range(state().stash.size()):
		if state().stash[i].uid != uid: continue
		var trial: Array = []
		for staged in state().loadout + [state().stash[i]]:
			if not _place(trial, staged.duplicate(true), dimensions("bag")): return _fail("携带物品无法放入背包")
		var previous: Dictionary = host.state.duplicate(true)
		state().loadout.append(state().stash[i])
		state().stash.remove_at(i)
		return _commit(previous)
	return _fail("物品不存在")

func store_item(uid: String) -> Dictionary:
	if active(): return _fail("请先结束本局")
	for i in range(state().loadout.size()):
		var item: Dictionary = state().loadout[i]
		if item.uid != uid: continue
		var previous: Dictionary = host.state.duplicate(true)
		if not _place(state().stash, item.duplicate(true), dimensions("stash")): return _fail("仓库空间不足")
		state().loadout.remove_at(i)
		return _commit(previous)
	return _fail("物品不存在")

func buy_supply(item_id: String) -> Dictionary:
	if item_def(item_id).get("kind")=="key":return buy_keys(item_id,1)
	if active(): return _fail("请在营地购买补给")
	var definition := item_def(item_id)
	var cost := int(definition.get("buyPrice", 0))
	if cost <= 0: return _fail("该物品无法购买")
	var required_risk := int(definition.get("buyMinRisk", 0))
	if int(state().unlockedDifficulty) < required_risk: return _fail("解锁危险等级 %d 后可购买" % required_risk)
	if int(host.state.resources.gold) < cost: return _fail("金币不足")
	var item := {"uid": host._uid("supply"), "itemId": item_id, "x": 0, "y": 0, "rotated": false, "revealed": true}
	var previous: Dictionary = host.state.duplicate(true)
	if not _place(state().stash, item, dimensions("stash")): return _fail("仓库空间不足")
	host.state.resources.gold -= cost
	return _commit(previous, {"cost": cost})

func departure_party() -> Array:
	return _departure_party()

func max_difficulty() -> int:
	return maxi(0, data.get("balance", {}).get("rankHp", [1.0]).size() - 1)

func _valid_map(r: Dictionary, ids: Dictionary) -> bool:
	if not r.map is Dictionary: return false
	var m: Dictionary = r.map
	if not m.get("rooms") is Array or m.rooms.size() not in [13, 19] or not m.get("edges") is Array or m.edges.size() > 48 or not m.get("districts") is Array or m.districts.size() != 3: return false
	if not host._integer(m.get("explored", -1), 0, m.rooms.size() - 2) or not host._integer(m.get("requiredExploration", -1), 4, 6) or int(m.get("requiredExploration", -1)) not in [4, 6] or not m.get("bossUnlocked") is bool: return false
	if m.bossUnlocked != (int(m.explored) >= int(m.requiredExploration)): return false
	var rooms: Dictionary = {}
	var bosses := 0
	var explored := 0
	var container_ids: Dictionary = {}
	for room in m.rooms:
		if not room is Dictionary or not room.get("id") is String or rooms.has(room.id): return false
		if not room.get("name") is String or not room.get("background") is String or not room.get("districtId") is String: return false
		if room.get("type") not in ["entry", "boss", "battle", "cache", "rest", "event", "elite", "vault", "hospital", "workshop", "shrine", "key_vault", "relay"]: return false
		if not host._number(room.get("x"), 0, 1) or not host._number(room.get("y"), 0, 1) or not host._integer(room.get("tier"), 0, 4): return false
		if not room.get("visited") is bool or not room.get("cleared") is bool or not room.get("containers") is Array or room.containers.size() > 10: return false
		if not _valid_room_actions(room.get("actions", [])): return false
		for flag in ["unlocked", "depositUsed"]:
			if room.has(flag) and not room[flag] is bool: return false
		rooms[room.id] = room
		if room.type == "boss":
			bosses += 1
			if room.id != m.get("bossRoomId"): return false
		elif room.type != "entry" and room.visited: explored += 1
		# 当前房间的物理对象由run.containers验证，其存档镜像不重复计数。
		if room.id == m.get("currentRoomId"): continue
		for container in room.containers:
			if not container is Dictionary or not container.get("id") is String or container_ids.has(container.id) or not container.get("items") is Array or not container.get("name") is String or not host._integer(container.get("revealed", -1)): return false
			container_ids[container.id] = true
			if not _valid_scene_container(container): return false
			if not _valid_items(container.items, ids): return false
	if bosses != 1 or explored != int(m.explored) or not rooms.has(m.get("currentRoomId")): return false
	var reached := {m.currentRoomId: true}
	var unique_edges: Dictionary = {}
	for edge in m.edges:
		if not edge is Array or edge.size() != 2 or not rooms.has(edge[0]) or not rooms.has(edge[1]) or edge[0] == edge[1]: return false
		var edge_key := str(edge[0]) + "|" + str(edge[1])
		var reversed_key := str(edge[1]) + "|" + str(edge[0])
		if unique_edges.has(edge_key) or unique_edges.has(reversed_key): return false
		unique_edges[edge_key] = true
	for _pass in range(m.rooms.size()):
		for edge in m.edges:
			if reached.has(edge[0]): reached[edge[1]] = true
			if reached.has(edge[1]): reached[edge[0]] = true
	return reached.size() == m.rooms.size()

func _valid_scene_container(container: Dictionary) -> bool:
	for key in ["sceneX", "sceneY"]:
		if container.has(key) and not host._number(container[key], 0, 1): return false
	if container.has("quality") and not host._integer(container.quality, 0, 2): return false
	return true

func view_current_room() -> Dictionary:
	if not active() or run().phase != "route" or not run().has("map"): return _fail("当前无法返回房间")
	var previous: Dictionary = host.state.duplicate(true)
	run().phase = "boss_exit" if run().room.get("type") == "boss" and int(run().bossesDefeated) == int(run().act) else "room"
	return _commit(previous)

func _room_description(kind: String) -> String:
	return {"entry":"星纹路标指向遗迹深处。", "cache":"旅人遗留的物资，偶有意外珍藏。", "rest":"营火旁可包扎、冥想或搜寻补给。", "battle":"巡逻警戒，战胜后可搜索。", "elite":"精英守卫驻守，战利品品质更高。", "vault":"精英守卫封锁宝库，战胜后开放两处珍藏。", "hospital":"残存药柜内可能留有疗愈用品。", "workshop":"旧工坊散落着符文构件与装备。", "shrine":"星辉之下，古物与秘典静候来者。", "event":"调查遗迹，选择收获与代价。", "key_vault":"携带对应区域钥匙，开启封存珍藏。", "relay":"将四格珍藏提前送回仓库。"}.get(kind, "封印深处传来回声。")

func plan_smart_loot(container_id: String) -> Dictionary:
	if not active() or run().phase not in ["room", "boss_exit"]: return _fail("当前无法整理战利品")
	var container := _find_container(container_id)
	if container.is_empty(): return _fail("容器不存在")
	var protected: Array = []
	var candidates: Array = []
	var original_ids: Dictionary = {}
	var previous_value := 0
	for item in run().bag:
		original_ids[item.uid] = true
		previous_value += item_value(item)
		if item_def(item.itemId).kind in ["equipment", "consumable"]: protected.append(item.duplicate(true))
		else: candidates.append(item.duplicate(true))
	for item in container.items:
		# Keys have their own inventory; automatic bag optimization never moves them into cells.
		if item.revealed and item_def(item.itemId).get("kind")!="key": candidates.append(item.duplicate(true))
	protected.sort_custom(func(a,b): return _size(a).x * _size(a).y > _size(b).x * _size(b).y)
	var packed: Array = []
	for item in protected:
		if not _place(packed, item, dimensions("bag")): return _fail("受保护的装备与补给占满背包，暂无更优换装方案")
	candidates.sort_custom(func(a,b):
		var av := float(item_value(a)) / (_size(a).x * _size(a).y)
		var bv := float(item_value(b)) / (_size(b).x * _size(b).y)
		return av > bv if not is_equal_approx(av, bv) else str(a.uid) < str(b.uid))
	for item in candidates: _place(packed, item, dimensions("bag"))
	var selected: Dictionary = {}
	var total := 0
	var added: Array = []
	for item in packed:
		selected[item.uid] = true
		total += item_value(item)
		if not original_ids.has(item.uid): added.append(item.duplicate(true))
	var removed: Array = []
	var names: Array = []
	for item in run().bag:
		if not selected.has(item.uid):
			removed.append(item.duplicate(true))
			names.append(str(item_def(item.itemId).name))
	if total <= previous_value or added.is_empty(): return _fail("暂无提高背包总价值的方案；装备与补给不会被换出")
	var fingerprint := JSON.stringify([run().id, run().phase, run().get("room", {}).get("id", ""), run().bag, container, packed]).sha256_text()
	return {"success": true, "removed": removed, "removedNames": names, "added": added, "gain": total - previous_value, "planHash": fingerprint, "packed": packed, "message": "换入 %d 件，价值 +%d；换出物品留在原容器" % [added.size(), total - previous_value]}

func apply_smart_loot(container_id: String, expected_hash: String) -> Dictionary:
	var plan := plan_smart_loot(container_id)
	if not plan.success: return plan
	if expected_hash.is_empty() or plan.planHash != expected_hash: return _fail("物品已变化，请重新预览换入方案")
	var previous: Dictionary = host.state.duplicate(true)
	var container := _find_container(container_id)
	var added_ids: Dictionary = {}
	for item in plan.added: added_ids[item.uid] = true
	var remaining: Array = []
	for item in container.items:
		if not added_ids.has(item.uid): remaining.append(item.duplicate(true))
	for item in plan.removed: remaining.append(item.duplicate(true))
	var height := 8
	for item in remaining: height += _size(item).y
	var placed: Array = []
	for item in remaining:
		if not _place(placed, item, Vector2i(6, height)):
			host.state = previous
			return _fail("容器整理失败，所有物品保持原样")
	var used_height := 8
	for item in placed: used_height = maxi(used_height, int(item.y) + _size(item).y)
	container.items = placed
	container.width = 6
	container.height = used_height
	container.revealed = 0
	for item in placed:
		if item.revealed: container.revealed += 1
	run().bag = plan.packed.duplicate(true)
	return _commit(previous, {"added": plan.added, "removed": plan.removed, "gain": plan.gain, "message": plan.message})

# Version 6: one permanent gold wallet. Existing physical assets keep their old
# appraisal so migration never removes value earned under the previous economy.
func migrate_state(value: Dictionary, source_version: int) -> void:
	var ex: Dictionary = value.extraction
	if source_version < 6:
		value.resources.gold = int(value.resources.gold) + int(ex.get("credits", 0))
		ex.credits = 0
		for scope in ["stash", "loadout", "mailbox"]: _preserve_legacy_values(ex.get(scope, []))
		var old_run: Dictionary = ex.get("run", {})
		for scope in ["bag", "equipped"]: _preserve_legacy_values(old_run.get(scope, []))
		for container in old_run.get("containers", []): _preserve_legacy_values(container.items)
		for room in old_run.get("map", {}).get("rooms", []):
			for container in room.get("containers", []): _preserve_legacy_values(container.items)
	if not ex.has("utility"): ex.utility = {"armor":{}, "backpack":{}}
	if source_version < 7:
		for scope in ["stash", "loadout", "mailbox"]: _preserve_v6_values(ex.get(scope, []))
		for scope in ["bag", "equipped"]: _preserve_v6_values(ex.run.get(scope, []))
		for container in ex.run.get("containers", []): _preserve_v6_values(container.items)
		for room in ex.run.get("map", {}).get("rooms", []):
			for container in room.get("containers", []): _preserve_v6_values(container.items)
	if not ex.has("keyring"):ex.keyring=[]
	if source_version<8:
		for scope in ["stash","loadout","mailbox"]:_preserve_v7_values(ex.get(scope,[]))
		for scope in ["bag","equipped"]:_preserve_v7_values(ex.run.get(scope,[]))
		for slot in ["armor","backpack"]:
			var entry:Dictionary=ex.get("utility",{}).get(slot,{})
			if not entry.is_empty():_preserve_v7_values([entry])
		for container in ex.run.get("containers",[]):_preserve_v7_values(container.items)
		for saved_room in ex.run.get("map",{}).get("rooms",[]):
			for container in saved_room.get("containers",[]):_preserve_v7_values(container.items)
		for scope in ["stash","loadout","mailbox"]:_move_owned_keys(ex[scope],ex.keyring)
		_move_owned_keys(ex.run.get("bag",[]),ex.keyring)
	if not ex.run.is_empty():
		if not ex.run.has("baseMaxHp"): ex.run.baseMaxHp = _base_party_hp(ex.run.party)
		if not ex.run.has("securedValue"): ex.run.securedValue = 0
		if not ex.run.has("securedItems"): ex.run.securedItems = 0
		for key in ["blessings", "pendingChoices", "roomActions"]:
			if not ex.run.has(key): ex.run[key] = []
		if not ex.run.has("characterFocus"):
			ex.run.characterFocus = {}
			for unit in ex.run.party:
				if int(host.catalog.CharacterData[unit.id].rarity) == 5: ex.run.characterFocus[unit.id] = 1.0
		if not ex.run.has("growthBattles"): ex.run.growthBattles = 0

func _preserve_legacy_values(items: Array) -> void:
	for item in items: item.legacyValue = int(item_def(item.itemId).get("legacyValue", item_def(item.itemId).value))

func item_value(item: Dictionary) -> int:
	if item.has("legacyValue"): return int(item.legacyValue)
	var base := int(item_def(str(item.get("itemId", ""))).get("value", 0))
	var risk := clampi(int(item.get("appraisalRisk", 0)), 0, 5)
	var multiplier := float(data.get("lootEconomy", {}).get("riskAppraisalMultiplier", [1.0, 1.25, 1.6, 2.1, 2.9, 4.0])[risk])
	if item_def(str(item.get("itemId",""))).get("kind")=="loot":
		multiplier*=float(data.get("lootEconomy",{}).get("saleMultiplier",1.0))
		multiplier*=float(data.get("lootEconomy",{}).get("actAppraisalMultiplier",[1.0,1.0,1.0])[clampi(int(item.get("originAct",1)),1,3)-1])
	return int(round(base*multiplier))

func _growth_definition(id: String) -> Dictionary:
	for reward in host.catalog.AbyssData.rogue.rewards:
		if reward.id == id: return reward
	return {}

func _growth_count(id: String) -> int:
	var count := 0
	for reward in run().get("blessings", []):
		if reward.id == id: count += 1
	return count

func _growth_pool(rarity: String = "") -> Array:
	var result: Array = []
	for reward in host.catalog.AbyssData.rogue.rewards:
		if _growth_count(reward.id) >= 3: continue
		if reward.pool == "character" and not run().get("characterFocus", {}).has(reward.get("characterId", "")): continue
		if not rarity.is_empty() and reward.rarity != rarity: continue
		result.append(reward)
	return result

func _offer_growth(rarity: String = "") -> void:
	if not run().get("pendingChoices", []).is_empty(): return
	var options: Array = []
	var pool := _growth_pool(rarity)
	for index in range(mini(3, pool.size())):
		var weights: Array = []
		var total := 0.0
		for reward in pool:
			var weight := float({"white": 6.0, "blue": 3.0, "gold": 1.0}.get(reward.rarity, 1.0))
			if reward.pool == "character": weight *= float(run().characterFocus.get(reward.characterId, 1.0))
			if index == 0 and rarity.is_empty() and reward.pool == "common": weight *= 2.0
			weights.append(weight); total += weight
		var roll := _rand() * total
		var chosen := pool.size() - 1
		for i in range(pool.size()):
			roll -= float(weights[i])
			if roll <= 0: chosen = i; break
		var reward: Dictionary = pool[chosen].duplicate(true)
		reward.choiceId = _uid("growth")
		reward.description = str(reward.description).replace("深渊", "探索")
		options.append(reward)
		pool.remove_at(chosen)
	run().pendingChoices = options

func growth_choices() -> Array:
	return run().get("pendingChoices", []).duplicate(true)

func growth_summary() -> Array:
	var result: Array = []
	for reward in run().get("blessings", []):
		var found := false
		for entry in result:
			if entry.id == reward.id: entry.stacks += 1; found = true; break
		if not found:
			var entry: Dictionary = _growth_definition(reward.id).duplicate(true)
			entry.stacks = 1
			entry.description = str(entry.description).replace("深渊", "探索")
			result.append(entry)
	return result

func choose_growth(choice_id: String) -> Dictionary:
	if not active() or run().phase == "battle": return _fail("当前无法选择祝福")
	var choice: Dictionary = {}
	for option in run().get("pendingChoices", []):
		if option.choiceId == choice_id: choice = option
	if choice.is_empty() or _growth_count(str(choice.get("id", ""))) >= 3: return _fail("祝福已经选取")
	var previous: Dictionary = host.state.duplicate(true)
	var reward := _growth_definition(choice.id).duplicate(true)
	reward.instanceId = _uid("blessing")
	reward.pickedAtAct = int(run().act)
	run().blessings.append(reward)
	var character_id := str(reward.get("characterId", ""))
	if not character_id.is_empty(): run().characterFocus[character_id] = minf(3.0, float(run().characterFocus.get(character_id, 1.0)) + 0.35)
	run().pendingChoices = []
	return _commit(previous, {"reward": reward.duplicate(true), "message": "获得「%s」" % reward.name})

func _prepare_room_actions(kind: String, event_override: int = -1) -> void:
	var choices: Array = []
	if kind == "key_vault":
		choices = [{"id":"unlock", "label":"打开密室", "description":"使用本区域钥匙", "effect":{"unlock":true}}]
	elif kind in ["rest", "hospital"]:
		choices = [{"id":"recover", "label":"包扎休整", "description":"全队恢复35%，倒下角色复苏", "effect":{"heal":0.35,"revive":true}}, {"id":"meditate", "label":"冥想蓄能", "description":"恢复10%，获得40能量，清空冷却", "effect":{"heal":0.1,"energy":40,"cooldown":99}}, {"id":"scavenge", "label":"寻找补给", "description":"搜寻营地留下的物资", "effect":{"cache":true}}]
	elif kind == "shrine":
		choices = [{"id":"insight", "label":"聆听神谕", "description":"选择一项祝福", "effect":{"blessing":""}}, {"id":"sacrifice", "label":"献血祈愿", "description":"消耗20%生命，选择蓝色祝福", "effect":{"hpCost":0.2,"blessing":"blue"}}, {"id":"leave", "label":"收集余光", "description":"获得30能量", "effect":{"energy":30}}]
	elif kind == "workshop":
		choices = [{"id":"forge", "label":"刻印符文", "description":"选择蓝色祝福", "cost":90, "effect":{"blessing":"blue"}}, {"id":"overload", "label":"共鸣锻造", "description":"消耗20%生命，选择金色祝福", "cost":160, "effect":{"hpCost":0.2,"blessing":"gold"}}, {"id":"study", "label":"研读铭文", "description":"选择一项祝福", "effect":{"blessing":""}}]
	else:
		var event_index := event_override if event_override >= 0 else int(_rand() * 6)
		if event_index >= 3:
			var event_data := ExpeditionEvents.event_data(event_index-3)
			choices = event_data.choices
			run().room.name = event_data.name
			run().room.description = event_data.description
			run().room.eventIcon = event_data.icon
		elif event_index == 0:
			choices = [{"id":"rescue", "label":"救助旅人", "description":"消耗15%生命，选择蓝色祝福", "effect":{"hpCost":0.15,"blessing":"blue"}}, {"id":"share", "label":"交换补给", "description":"恢复全队20%生命", "effect":{"heal":0.2}}, {"id":"search", "label":"调查车队", "description":"寻找遗落的货箱", "effect":{"cache":true}}]
		elif event_index == 1:
			choices = [{"id":"listen", "label":"倾听回声", "description":"获得35能量，冷却减少1", "effect":{"energy":35,"cooldown":1}}, {"id":"study", "label":"解读石碑", "description":"选择一项祝福", "effect":{"blessing":""}}, {"id":"rest", "label":"泉边休息", "description":"全队恢复25%生命", "effect":{"heal":0.25}}]
		else:
			choices = [{"id":"open", "label":"打开秘匣", "description":"消耗12%生命，找到精良物资", "effect":{"hpCost":0.12,"cache":true,"quality":1}}, {"id":"trace", "label":"追寻星光", "description":"选择一项祝福", "effect":{"blessing":""}}, {"id":"shelter", "label":"借光疗愈", "description":"恢复20%，倒下角色复苏", "effect":{"heal":0.2,"revive":true}}]
	for choice in choices:
		choice.cost = int(choice.get("cost", 0))
		choice.used = false
		choice.selected = false
		if choice.effect.has("battle"):
			var old_phase: String = run().phase
			var old_encounter: Dictionary = run().activeEncounter.duplicate(true)
			_generate_encounter(str(choice.effect.battle))
			choice.encounter = run().activeEncounter.duplicate(true)
			run().activeEncounter = old_encounter
			run().phase = old_phase
	run().roomActions = choices

func room_actions() -> Array:
	if not active(): return []
	var result: Array = run().get("roomActions", []).duplicate(true)
	for choice in result:
		var reason := ""
		if bool(choice.get("used", false)): reason = "已经完成整备"
		elif run().phase == "battle" or not run().get("pendingChoices", []).is_empty(): reason = "先完成当前选择"
		elif int(host.state.resources.gold) < int(choice.get("cost", 0)): reason = "金币不足"
		var effect: Dictionary = choice.get("effect", {})
		var shield: Dictionary = equipment_status().armor
		if reason.is_empty() and effect.has("repair") and (shield.item.is_empty() or float(shield.percent)>=1.0): reason = "装备护盾无需修复"
		if reason.is_empty() and effect.has("shieldCost") and (shield.item.is_empty() or float(shield.percent)<float(effect.shieldCost)): reason = "装备护盾余量不足"
		if choice.has("encounter"): choice.encounterPreview = choice.encounter.duplicate(true)
		if reason.is_empty() and effect.get("unlock", false) and _room_key_uid().is_empty(): reason = "需要对应区域钥匙"
		if reason.is_empty() and effect.has("hpCost"):
			for unit in run().party:
				if int(unit.currentHp) <= maxi(1, int(ceil(unit.maxHp * float(effect.hpCost)))): reason = "生命不足"
		if reason.is_empty() and effect.has("blessing") and _growth_pool(str(effect.blessing)).is_empty(): reason = "祝福已集齐"
		choice.enabled = reason.is_empty()
		choice.disabledReason = reason
		choice.erase("effect")
	return result

func choose_room_action(action_id: String) -> Dictionary:
	if not active() or run().phase not in ["room", "boss_exit"]: return _fail("请进入房间后操作")
	var allowed := false
	for option in room_actions():
		if option.id == action_id and option.enabled: allowed = true
	if not allowed: return _fail("此选项暂不可用")
	var previous: Dictionary = host.state.duplicate(true)
	var chosen: Dictionary = {}
	for option in run().roomActions:
		if option.id == action_id: chosen = option
		option.used = true
		option.selected = option.id == action_id
	var effect: Dictionary = chosen.effect
	host.state.resources.gold -= int(chosen.cost)
	for unit in run().party:
		if effect.has("hpCost"): unit.currentHp -= maxi(1, int(ceil(unit.maxHp * float(effect.hpCost))))
		if effect.has("heal") and (unit.currentHp > 0 or effect.get("revive", false)): unit.currentHp = mini(int(unit.maxHp), int(unit.currentHp) + maxi(1, int(unit.maxHp * float(effect.heal))))
		if unit.currentHp <= 0: continue
		unit.energy = mini(100, int(unit.energy) + int(effect.get("energy", 0)))
		for key in unit.cooldowns: unit.cooldowns[key] = maxi(0, int(unit.cooldowns[key]) - int(effect.get("cooldown", 0)))
	if effect.has("repair"): state().utility.armor.condition = minf(1.0,float(state().utility.armor.get("condition",1.0))+float(effect.repair))
	if effect.has("shieldCost"): state().utility.armor.condition = maxf(0.0,float(state().utility.armor.get("condition",1.0))-float(effect.shieldCost))
	if effect.get("key",false):
		_container("遗契密钥",0,0)
		run().containers.back().items = [_make_item(_room_key_id())]
	if effect.has("battle"):
		run().activeEncounter = chosen.encounter.duplicate(true)
		run().phase = "battle"
		_engine = null
	if effect.get("unlock", false):
		var key_uid := _room_key_uid()
		for entry in state().keyring.duplicate():
			if entry.uid==key_uid:state().keyring.erase(entry);break
		for entry in run().bag.duplicate():
			if entry.uid == key_uid: run().bag.erase(entry); break
		run().room.unlocked = true
		_populate_room("vault")
	if effect.has("blessing"): _offer_growth(str(effect.blessing))
	if effect.get("cache", false): _container("遗留物资", 3, int(effect.get("quality", 0)))
	return _commit(previous, {"message": str(chosen.label), "choices": growth_choices(), "config":run().activeEncounter.duplicate(true)})

func use_container_item(container_id: String, uid: String) -> Dictionary:
	if not active() or run().phase not in ["room", "boss_exit"]: return _fail("请在战斗外使用")
	var container := _find_container(container_id)
	if container.is_empty(): return _fail("容器不存在")
	for index in range(container.items.size()):
		var item: Dictionary = container.items[index]
		if item.uid != uid: continue
		if not item.revealed: return _fail("先完成搜索")
		var definition := item_def(item.itemId)
		if definition.kind != "consumable": return _fail("这件物品无法使用")
		if not can_use_consumable(item.itemId): return _fail("当前无需这份补给")
		var previous: Dictionary = host.state.duplicate(true)
		_apply_consumable(definition)
		container.items.remove_at(index)
		return _commit(previous, {"message":"已使用「%s」" % definition.name})
	return _fail("物品已经取走")

func equip_container_item(container_id: String, uid: String, replace_uid: String = "") -> Dictionary:
	if not active() or run().phase not in ["room", "boss_exit"]: return _fail("请在战斗外装备")
	var container := _find_container(container_id)
	if container.is_empty(): return _fail("容器不存在")
	var index := -1
	for i in range(container.items.size()):
		if container.items[i].uid == uid: index = i
	if index < 0: return _fail("物品已经取走")
	var item: Dictionary = container.items[index]
	if not item.revealed: return _fail("先完成搜索")
	if item_def(item.itemId).kind == "utility": return _equip_utility(str(item_def(item.itemId).slot), uid, container.items, Vector2i(int(container.width), int(container.height)))
	if item_def(item.itemId).kind != "equipment": return _fail("这件物品无法装备")
	var replace_index := -1
	for i in range(run().equipped.size()):
		if run().equipped[i].uid == replace_uid: replace_index = i
	if not replace_uid.is_empty() and replace_index < 0: return _fail("替换装备已经改变")
	if run().equipped.size() >= 3 and replace_index < 0: return _fail("选择一件装备替换")
	var previous: Dictionary = host.state.duplicate(true)
	container.items.remove_at(index)
	if replace_index >= 0:
		var old: Dictionary = run().equipped[replace_index]
		run().equipped.remove_at(replace_index)
		# Repack only the container; never destroy displaced equipment.
		var packed: Array = []
		var remaining: Array = container.items.duplicate(true)
		remaining.append(old.duplicate(true))
		remaining.sort_custom(func(a,b): return _size(a).x * _size(a).y > _size(b).x * _size(b).y)
		for entry in remaining:
			if not _place(packed, entry, Vector2i(int(container.width), int(container.height))):
				host.state = previous
				return _fail("原容器放不下换出的装备")
		container.items = packed
	run().equipped.append(item)
	return _commit(previous, {"message":"已装备「%s」" % item_def(item.itemId).name})

func sell_items(uids: Array) -> Dictionary:
	if active(): return _fail("本局结束后出售")
	var targets: Array = []
	var seen := {}
	for uid in uids:
		if not uid is String or seen.has(uid): continue
		seen[uid] = true
		for item in state().stash:
			if item.uid == uid: targets.append(item)
	if targets.size() != seen.size() or targets.is_empty(): return _fail("选择的物品已改变")
	var previous: Dictionary = host.state.duplicate(true)
	var total := 0
	for item in targets:
		total += item_value(item)
		state().stash.erase(item)
	host.state.resources.gold += total
	return _commit(previous, {"count":targets.size(), "value":total, "message":"出售 %d 件，获得 %d 金币" % [targets.size(),total]})

func collect_items(uids: Array) -> Dictionary:
	if active(): return _fail("本局结束后收藏")
	var targets: Array = []
	var seen := {}
	var definitions: Array = state().collection.duplicate()
	for uid in uids:
		if not uid is String or seen.has(uid): continue
		seen[uid] = true
		var found := false
		for item in state().stash:
			if item.uid != uid: continue
			found = true
			if int(item_def(item.itemId).rarity)>=4 and item.itemId not in definitions: targets.append(item); definitions.append(item.itemId)
		if not found: return _fail("选择的物品已改变")
	if targets.is_empty(): return _fail("请选择尚未收藏的金色或红色物品")
	var previous: Dictionary = host.state.duplicate(true)
	for item in targets:
		state().collection.append(item.itemId)
		state().stash.erase(item)
	return _commit(previous, {"count":targets.size(), "message":"收藏 %d 种物品" % targets.size()})

func _valid_growth_state(r: Dictionary) -> bool:
	for key in ["blessings", "pendingChoices", "roomActions"]:
		if not r.get(key, []) is Array: return false
	if r.get("blessings", []).size() > 78 or r.get("pendingChoices", []).size() > 3 or r.get("roomActions", []).size() > 3: return false
	if not r.get("characterFocus", {}) is Dictionary or not host._integer(r.get("growthBattles", 0), 0, 10000): return false
	for id in r.get("characterFocus", {}):
		if not host.catalog.CharacterData.has(id) or not host._number(r.characterFocus[id], 0, 3): return false
	var counts := {}
	var instances := {}
	for reward in r.get("blessings", []):
		if not reward is Dictionary or not reward.get("id") is String or _growth_definition(reward.id).is_empty(): return false
		if not reward.get("instanceId") is String or instances.has(reward.instanceId): return false
		instances[reward.instanceId] = true
		counts[reward.id] = int(counts.get(reward.id, 0)) + 1
		if counts[reward.id] > 3: return false
	var choices := {}
	for reward in r.get("pendingChoices", []):
		if not reward is Dictionary or not reward.get("id") is String or _growth_definition(reward.id).is_empty(): return false
		if not reward.get("choiceId") is String or choices.has(reward.choiceId): return false
		choices[reward.choiceId] = true
	return _valid_room_actions(r.get("roomActions", []))

func _valid_room_actions(actions: Variant) -> bool:
	if not actions is Array or actions.size() > 3: return false
	for action in actions:
		if not action is Dictionary or not action.get("id") is String or not action.get("label") is String or not action.get("description") is String: return false
		if action.has("selected") and not action.selected is bool: return false
		if not action.get("used") is bool or not host._integer(action.get("cost", -1), 0, 10000) or not action.get("effect") is Dictionary: return false
		if action.effect.has("battle"):
			var config = action.get("encounter")
			if not config is Dictionary or not config.get("isExtraction",false) or config.get("isAbyss",false) or config.get("kind")!="elite": return false
			if not config.get("id") is String or not config.get("name") is String or int(config.get("maxRounds",40))!=40: return false
			if not config.get("token") is String or not host._integer(config.get("seed",-1),0,2147483647): return false
			if not config.get("enemies") is Array or config.enemies.is_empty() or config.enemies.size()>3 or not config.get("scaleMult") is Dictionary: return false
			for enemy in config.enemies:
				if not host.catalog.EnemyData.has(enemy): return false
			for stat in ["hpMod","atkMod","defMod","spdMod"]:
				if not host._number(config.scaleMult.get(stat),0.01,1000): return false
			if not config.get("waves") is Array or config.waves.size()!=1 or not config.waves[0] is Dictionary or config.waves[0].get("enemies")!=config.enemies or config.waves[0].size()!=1: return false
		for key in action.effect:
			var v = action.effect[key]
			match key:
				"heal", "hpCost", "repair", "shieldCost":
					if not host._number(v, 0, 1): return false
				"energy", "cooldown":
					if not host._integer(v, 0, 100): return false
				"quality":
					if not host._integer(v, 0, 2): return false
				"battle":
					if v != "elite": return false
				"blessing":
					if v not in ["", "white", "blue", "gold"]: return false
				"cache", "revive", "unlock", "key":
					if not v is bool: return false
				_: return false
	return true

func can_use_consumable(item_id: String) -> bool:
	if not can_prepare_supplies() or item_def(item_id).get("kind") != "consumable": return false
	var d := item_def(item_id)
	if float(d.get("repair",0)) > 0 and float(equipment_status().armor.percent) < 1.0 and not equipment_status().armor.item.is_empty(): return true
	for unit in run().party:
		if unit.currentHp <= 0:
			if float(d.get("revive",0)) > 0: return true
			continue
		if float(d.get("heal",0)) > 0 and unit.currentHp < unit.maxHp: return true
		if int(d.get("energy",0)) > 0 and int(unit.energy) < 100: return true
		if int(d.get("cooldown",0)) > 0:
			for v in unit.cooldowns.values():
				if int(v) > 0: return true
	return false

# Persistent expedition equipment. These instances have one owner in utility;
# the active run freezes only the HP denominator, never duplicates the item.
func _base_party_hp(party: Array) -> int:
	var total := 0
	for unit in party: total += int(unit.get("stats", {}).get("maxHp", unit.get("maxHp", 1)))
	return maxi(1,total)

func _bag_bounds(ex: Dictionary) -> Vector2i:
	var pack: Dictionary = ex.get("utility", {}).get("backpack", {})
	return Vector2i(6, int(item_def(str(pack.get("itemId", ""))).get("bagHeight", 5)))

func bag_dimensions() -> Vector2i:
	return dimensions("bag")

func equipment_status() -> Dictionary:
	var utility: Dictionary = state().get("utility", {})
	var armor: Dictionary = utility.get("armor", {})
	var pack: Dictionary = utility.get("backpack", {})
	var maximum := 0
	for capacity in _equipment_shield_capacities().values(): maximum += int(capacity)
	var condition := float(armor.get("condition",1.0)) if not armor.is_empty() else 0.0
	var bounds := dimensions("bag")
	var cost := int(ceil(float(item_def(str(armor.get("itemId", ""))).get("repairPrice",0)) * (1.0-condition)))
	return {"armor":{"item":armor.duplicate(true),"max":maximum,"current":int(round(maximum*condition)),"percent":condition,"repairCost":cost}, "backpack":{"item":pack.duplicate(true),"width":bounds.x,"height":bounds.y,"cells":bounds.x*bounds.y},"tactical":run().get("equipped",[]).duplicate(true)}

func supply_preview(id: String) -> Dictionary:
	var d := item_def(id).duplicate(true)
	d.slot = str(d.get("slot", "tactical" if d.get("kind") == "equipment" else ""))
	d.buyPrice = int(d.get("buyPrice",0))
	return d

func set_utility_slot(slot: String, uid: String) -> Dictionary:
	if active() and not can_prepare_supplies(): return _fail("战斗结束后再整备")
	return _equip_utility(slot, uid, run().bag if active() else state().stash, dimensions("bag" if active() else "stash"))

func _equip_utility(slot: String, uid: String, source: Array, source_bounds: Vector2i) -> Dictionary:
	if slot not in ["armor","backpack"]: return _fail("装备位置无效")
	var selected: Dictionary = {}
	for item in source:
		if item.uid == uid: selected = item
	if selected.is_empty() or not selected.get("revealed",false) or item_def(selected.itemId).get("slot","") != slot: return _fail("请选择对应装备")
	var previous: Dictionary = host.state.duplicate(true)
	var old: Dictionary = state().utility[slot]
	var source_is_bag: bool = active() and is_same(source,run().bag)
	source.erase(selected)
	state().utility[slot] = selected
	if slot == "armor" and not selected.has("condition"): selected.condition = 1.0
	if not old.is_empty(): source.append(old)
	var bounds: Vector2i = dimensions("bag") if source_is_bag else source_bounds
	var packed := _packed_copy(source,bounds)
	if packed.size() != source.size():
		host.state = previous
		return _fail("空间不足，请先整理物品")
	source.assign(packed)
	if active() and not source_is_bag:
		var bag_packed := _packed_copy(run().bag,dimensions("bag"))
		if bag_packed.size() != run().bag.size():
			host.state = previous
			return _fail("小背包装不下当前物品")
		run().bag = bag_packed
	return _commit(previous,{"message":"已装备「%s」" % item_def(selected.itemId).name,"slot":slot})

func remove_utility_slot(slot: String) -> Dictionary:
	if slot not in ["armor","backpack"] or (active() and not can_prepare_supplies()): return _fail("当前无法卸下")
	var item: Dictionary = state().utility[slot]
	if item.is_empty(): return _fail("此处尚未装备")
	var previous: Dictionary = host.state.duplicate(true)
	state().utility[slot] = {}
	var scope := "bag" if active() else "stash"
	var all: Array = _items(scope).duplicate(true)
	all.append(item)
	var packed := _packed_copy(all,dimensions(scope))
	if packed.size() != all.size():
		host.state = previous
		return _fail("空间不足，请先整理物品")
	if active(): run().bag = packed
	else: state().stash = packed
	return _commit(previous,{"message":"装备已收回"})

func _packed_copy(items: Array, bounds: Vector2i) -> Array:
	if items.is_empty(): return []
	var area:=0
	for item in items: area+=_size(item).x*_size(item).y
	if area>bounds.x*bounds.y:return []
	var pending := items.duplicate(true)
	pending.sort_custom(func(a,b):
		var sa:=_size(a);var sb:=_size(b)
		return sa.x*sa.y>sb.x*sb.y if sa.x*sa.y!=sb.x*sb.y else maxi(sa.x,sa.y)>maxi(sb.x,sb.y))
	var packed: Array = []
	var complete:=true
	for item in pending:
		if not _place(packed,item,bounds):complete=false;break
	if complete:return packed
	# Bounded exact search fixes legal layouts rejected by area-first greed.
	# Row bitmasks support both 60-cell bags and the 120-cell warehouse.
	var board:Array=[]
	board.resize(bounds.y);board.fill(0)
	var search:={"nodes":0,"limit":12000,"memo":{}}
	packed=[]
	if _pack_search(pending,0,bounds,board,packed,0,search):return packed
	return []

func _pack_search(items:Array,index:int,bounds:Vector2i,board:Array,packed:Array,minimum:int,search:Dictionary)->bool:
	search.nodes+=1
	if search.nodes>search.limit:return false
	if index>=items.size():return true
	var item:Dictionary=items[index]
	var original:=Vector2i(int(item_def(item.itemId).width),int(item_def(item.itemId).height))
	var small:=mini(original.x,original.y);var large:=maxi(original.x,original.y)
	if small==1 and large==1:
		for remaining in items.slice(index):
			if not _place(packed,remaining.duplicate(true),bounds):return false
		return true
	var memo_key:=str(index)+":"+str(minimum)+":"+str(board)
	if search.memo.has(memo_key):return false
	var shapes:Array=[Vector2i(small,large)]
	if small!=large:shapes.append(Vector2i(large,small))
	for y in range(bounds.y):
		for x in range(bounds.x):
			for orientation in range(shapes.size()):
				var code:=(y*bounds.x+x)*2+orientation
				if code<minimum:continue
				var size:Vector2i=shapes[orientation]
				if x+size.x>bounds.x or y+size.y>bounds.y:continue
				var mask:=((1<<size.x)-1)<<x
				var free:=true
				for row in range(y,y+size.y):
					if int(board[row])&mask:free=false;break
				if not free:continue
				for row in range(y,y+size.y):board[row]=int(board[row])|mask
				var placed:Dictionary=item.duplicate(true)
				placed.x=x;placed.y=y;placed.rotated=size.x!=original.x
				packed.append(placed)
				var next_min:=0
				if index+1<items.size():
					var next_size:=_size(items[index+1])
					if mini(next_size.x,next_size.y)==small and maxi(next_size.x,next_size.y)==large:next_min=code+1
				if _pack_search(items,index+1,bounds,board,packed,next_min,search):return true
				packed.pop_back()
				for row in range(y,y+size.y):board[row]=int(board[row])&~mask
	search.memo[memo_key]=true
	return false

func repair_quote() -> Dictionary:
	var a: Dictionary = equipment_status().armor
	return {"cost":a.repairCost,"missing":int(a.max)-int(a.current),"enabled":not active() and not a.item.is_empty() and a.percent < 1.0 and int(host.state.resources.gold) >= int(a.repairCost)}

func repair_equipment() -> Dictionary:
	var quote := repair_quote()
	if not quote.enabled: return _fail("当前无需维修或金币不足")
	var previous: Dictionary = host.state.duplicate(true)
	host.state.resources.gold -= int(quote.cost)
	state().utility.armor.condition = 1.0
	return _commit(previous,{"cost":quote.cost,"message":"护甲已修复"})

func _apply_consumable(d: Dictionary) -> void:
	var repair := float(d.get("repair",0))
	if repair > 0 and not state().utility.armor.is_empty(): state().utility.armor.condition = minf(1.0,float(state().utility.armor.get("condition",1.0))+repair)
	for unit in run().party:
		if unit.currentHp <= 0:
			if float(d.get("revive",0)) > 0: unit.currentHp = maxi(1,int(unit.maxHp*float(d.revive)))
			else: continue
		else: unit.currentHp = mini(int(unit.maxHp),int(unit.currentHp)+int(unit.maxHp*float(d.get("heal",0))))
		unit.energy = mini(100,int(unit.energy)+int(d.get("energy",0)))
		for key in unit.cooldowns: unit.cooldowns[key] = maxi(0,int(unit.cooldowns[key])-int(d.get("cooldown",0)))

func _valid_utility(utility: Variant, ids: Dictionary) -> bool:
	if not utility is Dictionary: return false
	for slot in ["armor","backpack"]:
		var item = utility.get(slot,{})
		if not item is Dictionary: return false
		if item.is_empty(): continue
		if not _valid_items([item],ids) or item_def(item.itemId).get("slot","") != slot: return false
	return true

func _preserve_v6_values(items: Array) -> void:
	for item in items:
		if item.has("legacyValue"): continue
		var price := int(item_def(item.itemId).get("v6Value", item_def(item.itemId).value))
		var risk := clampi(int(item.get("appraisalRisk",0)),0,5)
		item.legacyValue = int(round(price * [1.0,1.25,1.6,2.1,2.9,4.0][risk]))

func _travel_paths() -> Dictionary:
	if not active() or not run().has("map") or run().phase == "battle" or not run().get("pendingChoices",[]).is_empty(): return {}
	var m: Dictionary = run().map
	var result := {}
	var current := str(m.currentRoomId)
	var queue: Array = [current]
	var paths := {current:[current]}
	var rooms := {}
	for room in m.rooms: rooms[room.id] = room
	while not queue.is_empty():
		var from: String = queue.pop_front()
		for edge in m.edges:
			var target := str(edge[1]) if edge[0] == from else (str(edge[0]) if edge[1] == from else "")
			if target.is_empty() or paths.has(target): continue
			var room: Dictionary = rooms[target]
			if room.type == "boss" and not m.bossUnlocked: continue
			var path: Array = paths[from].duplicate()
			path.append(target)
			paths[target] = path
			result[target] = path
			var safe: bool = room.visited and (room.type not in ["battle","elite","vault","boss"] or room.cleared)
			if safe: queue.append(target)
	return result

func _room_key_id() -> String:
	for district in run().get("map",{}).get("districts",[]):
		if district.id == run().room.get("districtId",""): return "key_"+str(district.theme)
	return "key_ruins"

func _room_key_uid() -> String:
	var key_id := _room_key_id()
	for item in state().get("keyring",[])+run().get("bag",[]):
		if item.itemId == key_id: return str(item.uid)
	return ""

# Exact 2x2 packing DP: maximize total sale value, not price per cell.
func preview_deposit(selected_uids: Array = []) -> Dictionary:
	if not active() or run().phase != "room" or run().room.get("type") != "relay": return _fail("请前往寄存站")
	if run().room.get("depositUsed",false): return _fail("本站已经寄存")
	if not run().get("pendingChoices",[]).is_empty(): return _fail("先选择祝福")
	var candidates: Array = []
	var selected := {}
	for uid in selected_uids:
		if not uid is String or selected.has(uid): return _fail("寄存选择已改变")
		selected[uid] = true
	for item in run().bag:
		if selected.is_empty() or selected.has(item.uid): candidates.append(item)
	if not selected.is_empty() and candidates.size() != selected.size(): return _fail("寄存物品已改变")
	var states := {0:{"value":0,"items":[]}}
	for original in candidates:
		var previous_states: Dictionary = states.duplicate(true)
		for mask in previous_states:
			for rotated in [false,true]:
				var candidate: Dictionary = original.duplicate(true)
				candidate.rotated = rotated
				var size := _size(candidate)
				for y in range(3-size.y):
					for x in range(3-size.x):
						var bits := 0
						for dy in range(size.y):
							for dx in range(size.x): bits |= 1 << ((y+dy)*2+x+dx)
						if int(mask)&bits: continue
						var combined := int(mask)|bits
						var value := int(previous_states[mask].value)+item_value(candidate)
						if states.has(combined) and int(states[combined].value) >= value: continue
						candidate.x=x;candidate.y=y
						var items: Array = previous_states[mask].items.duplicate(true)
						items.append(candidate.duplicate(true))
						states[combined] = {"value":value,"items":items}
	var best: Dictionary = states[0]
	for plan in states.values():
		if int(plan.value)>int(best.value): best=plan
	if not selected.is_empty() and best.items.size() != selected.size(): return _fail("所选物品超出寄存格，请减少选择")
	var uids: Array = []
	for item in best.items: uids.append(item.uid)
	var fee := int(data.get("utilityEconomy",{}).get("relayFee",50))
	var hash := JSON.stringify([run().id,run().room.id,best.items,best.value,fee]).sha256_text()
	return {"success":true,"items":best.items,"uids":uids,"value":best.value,"width":2,"height":2,"fee":fee,"planHash":hash,"enabled":not uids.is_empty() and int(host.state.resources.gold)>=fee}

func deposit_items(plan_hash: String, selected_uids: Array = []) -> Dictionary:
	var plan := preview_deposit(selected_uids)
	if not plan.get("success",false) or not plan.get("enabled",false): return _fail("暂时无法寄存")
	if plan.planHash != plan_hash: return _fail("物品已改变，请重新确认")
	var previous: Dictionary = host.state.duplicate(true)
	for item in run().bag.duplicate():
		if item.uid not in plan.uids: continue
		run().bag.erase(item)
		if not _place(state().stash,item.duplicate(true),dimensions("stash")): state().mailbox.append(item.duplicate(true))
	host.state.resources.gold -= int(plan.fee)
	run().room.depositUsed = true
	run().securedValue = int(run().get("securedValue",0))+int(plan.value)
	run().securedItems = int(run().get("securedItems",0))+plan.uids.size()
	return _commit(previous,{"message":"寄存完成","value":plan.value,"fee":plan.fee,"count":plan.uids.size()})

func _equipment_shield_allocations() -> Dictionary:
	var result := {}
	var armor: Dictionary = state().utility.armor
	var capacities := _equipment_shield_capacities()
	var condition := float(armor.get("condition",1.0))
	var total_capacity := 0
	var allocated := 0
	for unit in run().party:
		var capacity := int(capacities[unit.id])
		total_capacity += capacity
		result[unit.id] = int(floor(capacity*condition))
		allocated += int(result[unit.id])
	var remainder := int(round(total_capacity*condition))-allocated
	for unit in run().party:
		if remainder <= 0: break
		if int(result[unit.id]) < int(capacities[unit.id]): result[unit.id] += 1; remainder -= 1
	return result

func can_prepare_supplies() -> bool:
	return active() and (run().phase != "battle" or _engine == null)

func _equipment_shield_capacities() -> Dictionary:
	var armor: Dictionary = state().get("utility",{}).get("armor",{})
	var pct := float(item_def(str(armor.get("itemId", ""))).get("armorPct",0))
	var hp_bonus := 0.0
	for effect in effects():
		if effect.get("type")=="stat" and effect.get("stat")=="maxHpMult": hp_bonus += float(effect.get("value",0))
	var result := {}
	for unit in (run().party if active() else _departure_party()):
		var projected_hp := int(int(unit.stats.maxHp)*maxf(0.1,1.0+hp_bonus))
		result[unit.id] = int(projected_hp*pct)
	return result

func reset_runtime() -> void:
	_engine = null

func take_item_at(container_id:String,uid:String,x:int,y:int,rotated:bool=false)->Dictionary:
	if not active() or run().phase not in ["room","boss_exit"]:return _fail("当前无法拾取")
	var container:=_find_container(container_id)
	if container.is_empty():return _fail("容器不存在")
	var original:Dictionary={}
	for item in container.items:
		if item.uid==uid:original=item;break
	if original.is_empty() or not original.get("revealed",false):return _fail("先完成搜索")
	if item_def(original.itemId).get("kind")=="key":return take_item(container_id,uid)
	var candidate:Dictionary=original.duplicate(true)
	candidate.x=x;candidate.y=y;candidate.rotated=rotated
	if not _fits(run().bag,candidate,dimensions("bag")):return _fail("该位置放不下物品")
	var previous:Dictionary=host.state.duplicate(true)
	run().bag.append(candidate)
	container.items.erase(original)
	run().collectedValue+=item_value(original)
	return _commit(previous,{"item":candidate.duplicate(true),"message":"已收入背包"})

func preview_exchange(container_id:String,uid:String,outgoing_uids:Array)->Dictionary:
	if not active() or run().phase not in ["room","boss_exit"]:return _fail("当前无法交换")
	var container:=_find_container(container_id)
	if container.is_empty():return _fail("容器不存在")
	var incoming:Dictionary={}
	for item in container.items:
		if item.uid==uid:incoming=item;break
	if incoming.is_empty() or not incoming.get("revealed",false):return _fail("先完成搜索")
	if item_def(incoming.itemId).get("kind")=="key":return _fail("钥匙可直接收入钥匙串")
	var requested:Dictionary={}
	for id in outgoing_uids:
		if not id is String or requested.has(id):return _fail("交换选择已改变")
		requested[id]=true
	var remaining:Array=[]
	var removed:Array=[]
	var removed_value:=0
	for item in run().bag:
		if requested.has(item.uid):removed.append(item.duplicate(true));removed_value+=item_value(item)
		else:remaining.append(item.duplicate(true))
	if removed.size()!=requested.size():return _fail("换出物品已改变")
	remaining.append(incoming.duplicate(true))
	var packed:=_packed_copy(remaining,dimensions("bag"))
	if packed.size()!=remaining.size():return _fail("所选物品换出后仍放不下，请增加换出或调整位置")
	var leftovers:Array=[]
	for item in container.items:
		if item.uid!=uid:leftovers.append(item.duplicate(true))
	leftovers.append_array(removed.duplicate(true))
	var height:=8
	for item in leftovers:height+=_size(item).y
	var stored:=_packed_copy(leftovers,Vector2i(6,height))
	if stored.size()!=leftovers.size():return _fail("原容器暂时放不下换出物品")
	var used_height:=8
	for item in stored:used_height=maxi(used_height,int(item.y)+_size(item).y)
	var fingerprint:=JSON.stringify([run().id,run().room.get("id",""),run().bag,container,uid,outgoing_uids,packed]).sha256_text()
	return {"success":true,"added":[incoming.duplicate(true)],"removed":removed,"gain":item_value(incoming)-removed_value,"planHash":fingerprint,"packed":packed,"containerItems":stored,"containerHeight":used_height}

func exchange_items(container_id:String,uid:String,outgoing_uids:Array,plan_hash:String)->Dictionary:
	var plan:=preview_exchange(container_id,uid,outgoing_uids)
	if not plan.success:return plan
	if plan_hash.is_empty() or plan.planHash!=plan_hash:return _fail("物品已变化，请重新确认")
	var previous:Dictionary=host.state.duplicate(true)
	var container:=_find_container(container_id)
	container.items=plan.containerItems.duplicate(true)
	container.width=6;container.height=plan.containerHeight;container.revealed=0
	for item in container.items:
		if item.revealed:container.revealed+=1
	run().bag=plan.packed.duplicate(true)
	run().collectedValue+=item_value(plan.added[0])
	return _commit(previous,{"added":plan.added,"removed":plan.removed,"gain":plan.gain,"message":"交换完成，换出物品留在原容器"})

func _preserve_v7_values(items:Array)->void:
	for item in items:
		if item.has("legacyValue"):continue
		var base:=int(item_def(item.itemId).get("v7Value",item_def(item.itemId).value))
		item.legacyValue=int(round(base*[1.0,1.15,1.3,1.5,1.7,1.9][clampi(int(item.get("appraisalRisk",0)),0,5)]))

func _move_owned_keys(items:Array,ring:Array)->void:
	for item in items.duplicate():
		if item_def(item.itemId).get("kind")=="key":
			items.erase(item)
			ring.append(item)

func keyring()->Array:
	var result:Array=[]
	for id in ["key_ruins","key_forest","key_sanctum"]:
		var d:=item_def(id)
		var count:=0;var value:=0
		for item in state().get("keyring",[]):
			if item.itemId==id:count+=1;value+=item_value(item)
		result.append({"itemId":id,"name":d.name,"icon":d.icon,"count":count,"buyPrice":int(d.buyPrice),"value":value})
	return result

func buy_keys(id:String,count:int=1)->Dictionary:
	if active() and not can_salvage():return _fail("请在工坊、寄存站或撤离点购买")
	var d:=item_def(id)
	if d.get("kind")!="key" or count<1 or count>999 or state().keyring.size()+count>20000:return _fail("钥匙数量无效")
	var cost:=int(d.buyPrice)*count
	if int(host.state.resources.gold)<cost:return _fail("金币不足")
	var previous:Dictionary=host.state.duplicate(true)
	for n in range(count):state().keyring.append({"uid":host._uid("key"),"itemId":id,"x":0,"y":0,"rotated":false,"revealed":true})
	host.state.resources.gold-=cost
	return _commit(previous,{"count":count,"cost":cost,"message":"钥匙已收入钥匙串"})

func sell_keys(id:String,count:int=1)->Dictionary:
	if active() and not can_salvage():return _fail("请在工坊、寄存站或撤离点出售")
	if item_def(id).get("kind")!="key" or count<1 or count>999:return _fail("钥匙数量无效")
	var selected:Array=[]
	for item in state().keyring:
		if item.itemId==id and selected.size()<count:selected.append(item)
	if selected.size()!=count:return _fail("钥匙数量不足")
	var previous:Dictionary=host.state.duplicate(true)
	var value:=0
	for item in selected:value+=item_value(item);state().keyring.erase(item)
	host.state.resources.gold+=value
	return _commit(previous,{"count":count,"value":value,"message":"钥匙已出售"})

func can_salvage()->bool:
	return active() and (run().phase=="boss_exit" or (run().phase=="room" and run().room.get("type","") in ["workshop","relay"]))

func salvage_quote(uids:Array)->Dictionary:
	if not can_salvage():return _fail("工坊、寄存站和首领出口可回收物资")
	var selected:Dictionary={}
	for uid in uids:
		if not uid is String or selected.has(uid):return _fail("回收选择已改变")
		selected[uid]=true
	var items:Array=[];var gross:=0
	for item in run().bag:
		if selected.has(item.uid):items.append(item.duplicate(true));gross+=item_value(item)
	if items.size()!=selected.size() or items.is_empty():return _fail("请选择背包物资")
	var rate:=float(data.get("utilityEconomy",{}).get("salvageRate",0.6))
	var value:=int(floor(gross*rate))
	var fingerprint:=JSON.stringify([run().id,run().room.get("id",""),run().phase,items,rate,value]).sha256_text()
	return {"success":true,"enabled":true,"items":items,"grossValue":gross,"value":value,"rate":rate,"planHash":fingerprint}

func salvage_items(uids:Array,plan_hash:String)->Dictionary:
	var quote:=salvage_quote(uids)
	if not quote.success:return quote
	if plan_hash.is_empty() or quote.planHash!=plan_hash:return _fail("物资已变化，请重新确认")
	var previous:Dictionary=host.state.duplicate(true)
	for selected in quote.items:
		for item in run().bag.duplicate():
			if item.uid==selected.uid:run().bag.erase(item);break
	host.state.resources.gold+=int(quote.value)
	run().salvageGold=int(run().get("salvageGold",0))+int(quote.value)
	return _commit(previous,{"count":quote.items.size(),"value":quote.value,"message":"回收完成，金币已入账"})
