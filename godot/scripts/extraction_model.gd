extends RefCounted
## 搜打撤独立状态机；所有变更通过宿主原子存档事务提交。
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
	return {"credits": 0, "stash": [], "loadout": [], "mailbox": [], "collection": [], "unlockedDifficulty": 0, "run": {}, "lastRun": {}, "runs": 0}

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
	return {"uid": _uid("item"), "itemId": id, "x": 0, "y": 0, "rotated": false, "revealed": false}

func start_run(difficulty: int = 0) -> Dictionary:
	if active(): return _fail("当前搜打撤尚未结算")
	if host.abyss_run_active() or not host._issued_config.is_empty(): return _fail("请先结束当前远征或战斗")
	if difficulty < 0 or difficulty > int(state().unlockedDifficulty): return _fail("该危险等级尚未解锁")
	var party: Array = _departure_party()
	if party.is_empty(): return _fail("请先编队")
	var previous: Dictionary = host.state.duplicate(true)
	var generator := RandomNumberGenerator.new()
	generator.seed = host.rng.randi()
	state().run = {"id": host._uid("extraction"), "act": 1, "node": 0, "phase": "route", "difficulty": difficulty, "bag": [], "equipped": [], "party": party.duplicate(true), "containers": [], "routes": [], "activeEncounter": {}, "rngState": str(generator.state), "serial": 0, "roomsCleared": 0, "bossesDefeated": 0, "collectedValue": 0, "room": {}, "startedAt": host._now()}
	for item in state().loadout:
		if not _place(run().bag, item.duplicate(true), dimensions("bag")):
			host.state = previous
			return _fail("携带物品无法放入背包，请减少携带数量")
	state().loadout = []
	_routes()
	return _commit(previous, {"message": "出发，击败每幕首领后可以撤离"})

func _departure_party() -> Array:
	# 保留完整局外成长，出发后仅冻结快照避免局中换装。
	return host.battle_party(false)

func _sync_room() -> void:
	if not active() or not run().has("map"): return
	for room in run().map.rooms:
		if room.id == run().map.currentRoomId:
			room.containers = run().containers.duplicate(true)
			if run().phase in ["room", "boss_exit"]: room.cleared = true

func _generate_map() -> void:
	var map := {"rooms": [], "edges": [], "districts": [], "currentRoomId": "", "bossRoomId": "", "bossUnlocked": false, "explored": 0, "requiredExploration": 4}
	var themes := ["ruins", "forest", "sanctum"]
	var names := ["旧王城遗址", "幽光林地", "星核圣所"]
	var theme_offset := int(_rand() * 3)
	var types := ["battle", "cache", "rest", "event", "elite", "hospital", "workshop", "shrine"]
	var vault_index := 6 + int(_rand() * 6) if _rand() < float(data.get("mapEconomy", {}).get("vaultChance", 0.45)) else -1
	var labels := {"entry":"远征入口", "battle":"巡逻走廊", "cache":"旅人物资站", "rest":"隐蔽营地", "event":"遗迹调查", "elite":"禁卫哨所", "vault":"封存宝库", "hospital":"疗愈药房", "workshop":"符文工坊", "shrine":"星辉神龛", "boss":"封印核心"}
	for district in range(3):
		var theme: String = themes[(district + theme_offset + int(run().act) - 1) % 3]
		var pool: Array = data.get("mapBackgrounds", {}).get(theme, ["res://assets/extraction/rooms/%s_1.webp" % theme, "res://assets/extraction/rooms/%s_2.webp" % theme])
		var bg: String = str(pool[int(_rand() * pool.size()) % pool.size()])
		map.districts.append({"id": "district_%d" % district, "name": names[(district + theme_offset + int(run().act) - 1) % 3], "theme": theme, "background": bg})
		for local in range(4):
			var index := district * 4 + local
			var kind: String = "entry" if index == 0 else str(types[int(_rand() * types.size()) % types.size()])
			# 保底基础补给与营地；高价值宝库稀少且必须击败守卫。
			if index == 1: kind = "cache"
			if index == 2: kind = "rest"
			if index == vault_index: kind = "vault"
			var id := _uid("room")
			map.rooms.append({"id": id, "name": labels[kind], "type": kind, "description": _room_description(kind), "tier": mini(4, district + local + 1), "districtId": "district_%d" % district, "x": 0.12 + district * 0.36 + (_rand() - 0.5) * 0.09, "y": 0.12 + local * 0.24 + (_rand() - 0.5) * 0.07, "visited": index == 0, "cleared": index == 0, "background": str(pool[posmod(hash(str(run().rngState) + str(index)), pool.size())]), "containers": []})
			if index > 0:
				var parent: int = district * 4 + int(_rand() * local) if local > 0 else index - 1
				map.edges.append([map.rooms[parent].id, id])
			if local >= 2 and _rand() < 0.7:
				var extra: String = map.rooms[index - 1].id
				if not _has_edge(map.edges, extra, id): map.edges.append([extra, id])
	# 每个区块至少一个环路，允许绕路而非只有线性树枝。
	for district in range(3):
		var base := district * 4
		for local in range(1, 4):
			if not _has_edge(map.edges, map.rooms[base].id, map.rooms[base + local].id):
				map.edges.append([map.rooms[base].id, map.rooms[base + local].id])
				break
	var boss_id := _uid("room")
	map.rooms.append({"id": boss_id, "name": labels.boss, "type": "boss", "description": "完成四处独立探索后解除封印；击败首领可撤离或深入下一幕。", "tier": 4, "districtId": "district_2", "x": 0.94, "y": 0.92, "visited": false, "cleared": false, "background": map.districts[2].background, "containers": []})
	# 两条独立入口使首领无需清完整张地图即可抵达。
	map.edges.append([map.rooms[6].id, boss_id])
	map.edges.append([map.rooms[11].id, boss_id])
	map.currentRoomId = map.rooms[0].id
	map.bossRoomId = boss_id
	run().map = map
	run().room = map.rooms[0].duplicate(true)
	run().containers = []
	run().selectedContainer = ""

func _has_edge(edges: Array, a: String, b: String) -> bool:
	for edge in edges:
		if (edge[0] == a and edge[1] == b) or (edge[1] == a and edge[0] == b): return true
	return false

func _routes() -> void:
	if not run().has("map"): _generate_map()
	run().phase = "route"
	run().routes = route_options()

func map_state() -> Dictionary:
	return run().get("map", {}).duplicate(true)

func room_scene() -> Dictionary:
	var scene: Dictionary = run().get("room", {}).duplicate(true)
	scene.containers = containers()
	scene.selectedContainer = run().get("selectedContainer", "")
	return scene

func route_options() -> Array:
	if not active() or not run().has("map"): return run().get("routes", []).duplicate(true)
	var result: Array = []
	for room in run().map.rooms:
		if _has_edge(run().map.edges, run().map.currentRoomId, room.id):
			var option: Dictionary = room.duplicate(true)
			option.locked = room.type == "boss" and not run().map.bossUnlocked
			result.append(option)
	return result

func choose_route(id: String) -> Dictionary:
	return enter_room(id)

func enter_room(id: String) -> Dictionary:
	if not active() or run().phase not in ["route", "room", "boss_exit"]: return _fail("请先结束当前战斗")
	var previous: Dictionary = host.state.duplicate(true)
	if not run().has("map"):
		_generate_map()
		_routes()
		return _commit(previous, {"message": "旧探索已迁移为随机地图，请选择相邻房间"})
	var target: Dictionary = {}
	for room in run().map.rooms:
		if room.id == id: target = room
	if target.is_empty() or not _has_edge(run().map.edges, run().map.currentRoomId, id): return _fail("只能进入相邻的连通房间")
	if target.type == "boss" and not run().map.bossUnlocked: return _fail("探索四处不同房间后才能解除首领封印")
	_sync_room()
	run().map.currentRoomId = id
	run().node = int(target.tier)
	run().room = target.duplicate(true)
	run().containers = target.containers.duplicate(true)
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
			run().map.bossUnlocked = run().map.explored >= 4
		var kind: String = target.type
		if kind in ["battle", "elite", "boss", "vault"]:
			run().node = int(target.tier)
			_generate_encounter("elite" if kind == "vault" else kind)
		else:
			if kind == "rest": _heal(0.25)
			elif kind == "event" and _rand() < 0.25:
				for unit in run().party:
					if unit.currentHp > 0: unit.currentHp = maxi(1, int(unit.currentHp * 0.88))
			else: _populate_room(kind)
	return _commit(previous, {"config": run().activeEncounter.duplicate(true), "message": str(target.name)})

func _populate_room(kind: String) -> void:
	var economy: Dictionary = data.get("mapEconomy", {})
	var counts: Array = economy.get("ordinaryContainers", [1,2])
	var item_counts: Array = economy.get("ordinaryItems", [2,3])
	var count := int(counts[0]) + int(_rand() * (int(counts[1]) - int(counts[0]) + 1))
	if kind == "vault": count = int(economy.get("vaultContainers", 2))
	var quality := int(economy.get("vaultQuality", 1)) if kind == "vault" else int(economy.get("shrineQuality", 0)) if kind == "shrine" else 0
	var room_pools := {"hospital": ["补给", "疗愈用品"], "workshop": ["符文构件", "遗迹装置", "工具", "零件", "装备"], "shrine": ["古物", "王室遗物", "奇珍", "秘传典籍"], "vault": ["珠宝", "贵金属", "王室遗物", "奇珍", "遗迹珍藏"]}
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
	var budgets: Dictionary = data.get("balance", {})
	var n := float((act - 1) * 5 + int(run().node))
	var hp: float = (0.70 + 0.075 * n) * float(budgets.get("rankHp", [1,1.35,1.8,2.4])[rank])
	var atk: float = (0.65 + 0.030 * n) * float(budgets.get("rankAtk", [1,1.5,2.2,3.2])[rank])
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
	return result

func start_battle(engine) -> Dictionary:
	var prepared := prepare_battle()
	if not prepared.success: return prepared
	_engine = engine
	engine.start(prepared.config, battle_party(), effects())
	return {"success": true, "config": prepared.config}

func settle_battle(config: Dictionary, battle_state: Dictionary) -> Dictionary:
	if not active() or run().phase != "battle" or run().activeEncounter.is_empty(): return _fail("战斗已经结算")
	if _engine == null or _engine.state != battle_state: return _fail("缺少有效战斗结果")
	if str(config.get("token", "")) != str(run().activeEncounter.token) or str(battle_state.get("config", {}).get("token", "")) != str(run().activeEncounter.token): return _fail("战斗凭证不匹配")
	if battle_state.get("phase", "") not in ["victory", "defeat"]: return _fail("战斗尚未结束")
	var previous: Dictionary = host.state.duplicate(true)
	var victory: bool = battle_state.phase == "victory"
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
		var kind: String = run().activeEncounter.kind
		run().activeEncounter = {}
		if kind == "boss":
			run().phase = "boss_exit"
			run().bossesDefeated += 1
			_container("首领保险柜", 4, 2)
		else:
			run().phase = "room"
			if run().room.get("type") == "vault": _populate_room("vault")
			else: _container("精英战利品" if kind == "elite" else "敌人背包", 3 if kind == "elite" else 2, 1 if kind == "elite" else 0)
	var result := _commit(previous, {"victory": victory, "ended": not victory, "rewards": {}, "lastRun": state().lastRun.duplicate(true), "message": "首领已击败，出口开放" if victory and active() and run().phase == "boss_exit" else "战斗结束"})
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
		if not pool.is_empty(): container.items.append(_make_item(str(pool[int(_rand() * pool.size()) % pool.size()])))
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
	return Vector2i(STASH_WIDTH, STASH_HEIGHT) if scope == "stash" else Vector2i(BAG_WIDTH, BAG_HEIGHT)

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
		run().collectedValue += int(item_def(item.itemId).value)
		return _commit(previous, {"item": item.duplicate(true)})
	return _fail("物品已被取走")

func _pickup_fit(item: Dictionary) -> bool:
	var bag: Array = run().bag.duplicate(true)
	if _place(bag, item.duplicate(true), dimensions("bag")):
		run().bag = bag
		return true
	bag = run().bag.duplicate(true)
	bag.append(item.duplicate(true))
	bag.sort_custom(func(a,b): return _size(a).x * _size(a).y > _size(b).x * _size(b).y)
	var packed: Array = []
	for entry in bag:
		if not _place(packed, entry, dimensions("bag")): return false
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
	candidates.sort_custom(func(a,b): return float(item_def(a.itemId).value) / (_size(a).x * _size(a).y) > float(item_def(b.itemId).value) / (_size(b).x * _size(b).y))
	var taken: Array = []
	var left: Array = []
	for item in candidates:
		if _pickup_fit(item):
			taken.append(item.uid)
			container.items.erase(item)
			run().collectedValue += int(item_def(item.itemId).value)
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
	pending.sort_custom(func(a,b): return _size(a).x * _size(a).y > _size(b).x * _size(b).y)
	var packed: Array = []
	for item in pending:
		if not _place(packed, item, dimensions(scope)): return _fail("自动整理未找到更好的布局，原布局已保留")
	var previous: Dictionary = host.state.duplicate(true)
	if scope == "stash": state().stash = packed
	else: run().bag = packed
	return _commit(previous)

func equip_item(uid: String) -> Dictionary:
	if not active() or run().phase == "battle": return _fail("请在战斗外装备")
	if run().equipped.size() >= 3: return _fail("三处装备位已满")
	for i in range(run().bag.size()):
		var item: Dictionary = run().bag[i]
		if item.uid != uid: continue
		if item_def(item.itemId).kind != "equipment": return _fail("这件物品无法装备")
		var previous: Dictionary = host.state.duplicate(true)
		run().equipped.append(item)
		run().bag.remove_at(i)
		return _commit(previous)
	return _fail("物品不存在")

func unequip_item(uid: String) -> Dictionary:
	if not active() or run().phase == "battle": return _fail("请在战斗外卸下装备")
	for i in range(run().equipped.size()):
		var item: Dictionary = run().equipped[i]
		if item.uid != uid: continue
		var previous: Dictionary = host.state.duplicate(true)
		if not _place(run().bag, item.duplicate(true), dimensions("bag")): return _fail("背包空间不足")
		run().equipped.remove_at(i)
		return _commit(previous)
	return _fail("物品不存在")

func use_item(uid: String) -> Dictionary:
	if not active() or run().phase == "battle": return _fail("请在战斗外使用补给")
	for i in range(run().bag.size()):
		var item: Dictionary = run().bag[i]
		if item.uid != uid: continue
		var definition := item_def(item.itemId)
		if definition.kind != "consumable": return _fail("物品无法使用")
		var previous: Dictionary = host.state.duplicate(true)
		_heal(float(definition.get("heal", 0.25)))
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
	var previous: Dictionary = host.state.duplicate(true)
	_sync_room()
	_routes()
	return _commit(previous, {"config": run().activeEncounter.duplicate(true)})

func continue_act() -> Dictionary:
	if not active() or run().phase != "boss_exit": return _fail("击败首领后才能继续")
	if int(run().act) >= MAX_ACTS: return _fail("三幕探索已完成，请撤离结算")
	var previous: Dictionary = host.state.duplicate(true)
	run().act += 1; run().node = 0
	_generate_map()
	_routes()
	return _commit(previous)

func _end(outcome: String) -> void:
	var value := 0
	for item in run().bag + run().equipped: value += int(item_def(item.itemId).value)
	state().lastRun = {"outcome": outcome, "act": int(run().act), "difficulty": int(run().difficulty), "roomsCleared": int(run().roomsCleared), "bossesDefeated": int(run().bossesDefeated), "value": value, "items": run().bag.size() + run().equipped.size(), "durationSeconds": maxi(0, int((host._now() - int(run().startedAt)) / 1000))}
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
		var value := int(item_def(item.itemId).value)
		state().credits += value
		state().stash.remove_at(i)
		return _commit(previous, {"value": value})
	return _fail("物品不存在")

func collect_item(uid: String) -> Dictionary:
	if active(): return _fail("请在本局结束后收藏")
	for i in range(state().stash.size()):
		var item: Dictionary = state().stash[i]
		if item.uid != uid: continue
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
	for key in ["act", "node", "difficulty", "serial", "roomsCleared", "bossesDefeated", "collectedValue", "startedAt"]:
		if not host._integer(r.get(key, -1), 0, 10000000000000000): return false
	if int(r.act) < 1 or int(r.act) > 3 or int(r.node) > 4 or int(r.difficulty) > int(value.get("unlockedDifficulty", 0)): return false
	for key in ["bag", "equipped", "containers", "routes", "party"]:
		if not r.get(key) is Array: return false
	if r.equipped.size() > 3 or r.containers.size() > 10 or r.routes.size() > 13 or r.party.is_empty() or r.party.size() > 3: return false
	if not _valid_items(r.bag, ids, Vector2i(BAG_WIDTH, BAG_HEIGHT)) or not _valid_items(r.equipped, ids): return false
	for item in r.equipped:
		if item_def(item.itemId).kind != "equipment": return false
	for option in r.routes:
		if not option is Dictionary or not option.get("id") is String or not option.get("name") is String or not option.get("description") is String or option.get("type", "") not in ["entry", "boss", "battle", "cache", "rest", "event", "elite", "vault", "hospital", "workshop", "shrine"]: return false
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
		if not config.get("id") is String or not config.get("name") is String or config.get("kind", "") not in ["battle", "elite", "boss"] or not host._integer(config.get("seed", -1)): return false
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

func _valid_items(items: Array, ids: Dictionary, bounds := Vector2i.ZERO) -> bool:
	if items.size() > 10000: return false
	for item in items:
		if not item is Dictionary or not item.get("uid") is String or item.uid.is_empty() or ids.has(item.uid): return false
		if not item.get("itemId") is String or item_def(item.itemId).is_empty(): return false
		if not host._integer(item.get("x", -1), 0, 100) or not host._integer(item.get("y", -1), 0, 100) or not item.get("rotated") is bool or not item.get("revealed") is bool: return false
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
	if active(): return _fail("请在营地购买补给")
	var definition := item_def(item_id)
	var cost := int(definition.get("buyPrice", 0))
	if cost <= 0: return _fail("该物品无法购买")
	var required_risk := int(definition.get("buyMinRisk", 0))
	if int(state().unlockedDifficulty) < required_risk: return _fail("解锁危险等级 %d 后可购买" % required_risk)
	if int(state().credits) < cost: return _fail("交易币不足")
	var item := {"uid": host._uid("supply"), "itemId": item_id, "x": 0, "y": 0, "rotated": false, "revealed": true}
	var previous: Dictionary = host.state.duplicate(true)
	if not _place(state().stash, item, dimensions("stash")): return _fail("仓库空间不足")
	state().credits -= cost
	return _commit(previous, {"cost": cost})

func departure_party() -> Array:
	return _departure_party()

func max_difficulty() -> int:
	return maxi(0, data.get("balance", {}).get("rankHp", [1.0]).size() - 1)

func _valid_map(r: Dictionary, ids: Dictionary) -> bool:
	if not r.map is Dictionary: return false
	var m: Dictionary = r.map
	if not m.get("rooms") is Array or m.rooms.size() != 13 or not m.get("edges") is Array or m.edges.size() > 40 or not m.get("districts") is Array or m.districts.size() != 3: return false
	if not host._integer(m.get("explored", -1), 0, 11) or m.get("requiredExploration") != 4 or not m.get("bossUnlocked") is bool: return false
	if m.bossUnlocked != (int(m.explored) >= 4): return false
	var rooms: Dictionary = {}
	var bosses := 0
	var explored := 0
	var container_ids: Dictionary = {}
	for room in m.rooms:
		if not room is Dictionary or not room.get("id") is String or rooms.has(room.id): return false
		if not room.get("name") is String or not room.get("background") is String or not room.get("districtId") is String: return false
		if room.get("type") not in ["entry", "boss", "battle", "cache", "rest", "event", "elite", "vault", "hospital", "workshop", "shrine"]: return false
		if not host._number(room.get("x"), 0, 1) or not host._number(room.get("y"), 0, 1) or not host._integer(room.get("tier"), 0, 4): return false
		if not room.get("visited") is bool or not room.get("cleared") is bool or not room.get("containers") is Array or room.containers.size() > 10: return false
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
	for _pass in range(13):
		for edge in m.edges:
			if reached.has(edge[0]): reached[edge[1]] = true
			if reached.has(edge[1]): reached[edge[0]] = true
	return reached.size() == 13

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
	return {"entry":"星纹路标指向遗迹深处。", "cache":"旅人遗留的物资，偶有意外珍藏。", "rest":"隐蔽营地，首次停留恢复25%生命。", "battle":"巡逻警戒，战胜后可搜索。", "elite":"精英守卫驻守，战利品品质更高。", "vault":"精英守卫封锁宝库，战胜后开放两处珍藏。", "hospital":"残存药柜内可能留有疗愈用品。", "workshop":"旧工坊散落着符文构件与装备。", "shrine":"星辉之下，古物与秘典静候来者。", "event":"机关与遗物并存，调查可能受伤。"}.get(kind, "封印深处传来回声。")

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
		previous_value += int(item_def(item.itemId).value)
		if item_def(item.itemId).kind in ["equipment", "consumable"]: protected.append(item.duplicate(true))
		else: candidates.append(item.duplicate(true))
	for item in container.items:
		if item.revealed: candidates.append(item.duplicate(true))
	protected.sort_custom(func(a,b): return _size(a).x * _size(a).y > _size(b).x * _size(b).y)
	var packed: Array = []
	for item in protected:
		if not _place(packed, item, dimensions("bag")): return _fail("受保护的装备与补给占满背包，暂无更优换装方案")
	candidates.sort_custom(func(a,b):
		var av := float(item_def(a.itemId).value) / (_size(a).x * _size(a).y)
		var bv := float(item_def(b.itemId).value) / (_size(b).x * _size(b).y)
		return av > bv if not is_equal_approx(av, bv) else str(a.uid) < str(b.uid))
	for item in candidates: _place(packed, item, dimensions("bag"))
	var selected: Dictionary = {}
	var total := 0
	var added: Array = []
	for item in packed:
		selected[item.uid] = true
		total += int(item_def(item.itemId).value)
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
