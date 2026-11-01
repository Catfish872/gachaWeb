extends SceneTree
const Game = preload("res://scripts/game_model.gd")
const Battle = preload("res://scripts/battle_model.gd")
var checks := 0
var failures := 0
func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok: failures += 1; print("FAIL ", text)
func _init() -> void:
	var game = Game.new("")
	game.rng.seed = 271828
	var ex = game.extraction
	check(game.valid_save(game.state), "default save valid")
	check(ex.start_run(0).success, "start")
	check(game.valid_save(game.state), "run valid")
	check(not ex.start_run().success, "double start blocked")
	check(not game.set_team(["ember"]).success, "team locked")
	check(not game.prepare_abyss().success, "abyss blocked")
	check(not ex.route_options().is_empty(), "route choice")
	var original_gold = game.state.resources.gold
	var room = ex.route_options()[0]
	for candidate in ex.route_options():
		if candidate.type in ["battle", "elite"]: room = candidate; break
	check(ex.choose_route(room.id).success, "choose route")
	check(not ex.choose_route(room.id).success, "duplicate route blocked")
	check(not ex.extract().success, "cannot extract before boss")
	if ex.run().phase == "battle":
		var config = ex.prepare_battle().config
		check(not ex.settle_battle(config, {"phase":"victory"}).success, "fake result blocked")
		var battle = Battle.new(game.catalog)
		check(ex.start_battle(battle).success, "battle start")
		while battle.state.phase not in ["victory","defeat"]: battle.auto_step()
		check(game.finish_battle(config,battle.state).success, "real settlement")
		check(not game.finish_battle(config,battle.state).success, "double settlement blocked")
	check(game.state.resources.gold == original_gold, "no permanent gold from run")
	if ex.active(): check(ex.retreat().success, "retreat")
	check(game.valid_save(game.state), "settled save valid")
	# Deterministic saved room and physical grid rules.
	game = Game.new("")
	ex = game.extraction
	check(ex.start_run().success, "new run")
	ex.run().phase = "room"
	ex._container("测试箱", 5, 2)
	check(game.valid_save(game.state), "container save valid")
	var cid = ex.containers()[0].id
	var item = ex.containers()[0].items[0]
	check(not ex.take_item(cid,item.uid).success, "unrevealed cannot take")
	var before = ex.containers().duplicate(true)
	var saved = game.state.duplicate(true)
	game.state = game._normalize(saved)
	check(ex.containers() == before, "restart same loot")
	check(ex.reveal_next(cid).success, "reveal")
	check(ex.take_item(cid,item.uid).success, "take")
	check(not ex.take_item(cid,item.uid).success, "double take blocked")
	check(not ex.move_item("bag",item.uid,-1,0,false).success, "out of bounds")
	check(ex.sort_grid("bag").success, "sort")
	check(game.valid_save(game.state), "grid save valid")
	var malformed = game.state.duplicate(true)
	malformed.extraction.run.bag.append(malformed.extraction.run.bag[0].duplicate(true))
	check(not game.valid_save(malformed), "duplicate item rejected")
	malformed = game.state.duplicate(true)
	malformed.extraction.run.bag[0].itemId = "missing"
	check(not game.valid_save(malformed), "unknown item rejected")
	malformed = game.state.duplicate(true)
	malformed.extraction.run.bag[0].x = 100
	check(not game.valid_save(malformed), "invalid placement rejected")
	ex.run().phase = "boss_exit"
	ex.run().bossesDefeated = 1
	check(ex.extract().success, "extract")
	check(not ex.extract().success, "double extraction blocked")
	check(ex.state().stash.size() == 1, "one physical item banked")
	check(ex.bring_item(item.uid).success, "bring item")
	check(ex.state().stash.is_empty(), "staged item removed stash")
	check(ex.store_item(item.uid).success, "return item")
	var expected = ex.item_def(item.itemId).value
	check(ex.sell_item(item.uid).success, "sell")
	check(ex.state().credits == expected, "price authoritative")
	check(not ex.sell_item(item.uid).success, "double sale blocked")
	ex.state().credits = 10000
	check(ex.buy_supply("bandage").success, "purchase sink")
	var supply = ex.state().stash[0]
	check(ex.bring_item(supply.uid).success, "carry supply")
	check(ex.start_run().success, "start carried")
	check(ex.state().loadout.is_empty() and ex.run().bag.size() == 1, "carry moved once")
	check(ex.use_item(supply.uid).success, "use supply")
	check(not ex.use_item(supply.uid).success, "double consumption blocked")
	check(ex.retreat().success, "end")
	var old = game.state.duplicate(true)
	old.version = 4
	old.erase("extraction")
	check(game.valid_save(old), "v4 accepted")
	var migrated = game._normalize(old)
	check(migrated.version == 5 and migrated.extraction.stash.is_empty(), "v5 defaults")
	check(migrated.abyss == old.abyss, "v4 abyss preserved")
	# Failed storage must restore physical objects and run phase.
	check(ex.start_run().success, "rollback run")
	var snapshot = game.state.duplicate(true)
	game.save_blocked = true
	check(not ex.retreat().success, "save fail reported")
	check(game.state == snapshot, "save failure rollback")
	game.save_blocked = false
	for owned in game.state.ownedCharacters.values():
		owned.level = 10
		owned.constellation = 6
		owned.awakening = 100
	check(ex.departure_party() == game.battle_party(false), "full growth snapshot unchanged")
	# Per-rank battle modifiers are isolated from story/abyss rules.
	var combat = Battle.new(game.catalog)
	var base_party: Array = game.battle_party(false)
	var boss_id: String = game.catalog.AbyssData.pools.boss[0]
	var cfg := {"isExtraction":true,"difficulty":3,"seed":7,"enemies":[boss_id],"scaleMult":1.0}
	combat.start(cfg, base_party)
	var ally: Dictionary = combat.state.allies[0]
	ally.currentHp = 1
	combat._heal(ally, ally, 100, "regen", false, "status")
	check(ally.currentHp == 101, "rank3 regeneration retains full healing")
	ally.currentHp = 1
	combat._heal(ally, ally, 100, "rogue_lifesteal", false, "status")
	check(ally.currentHp == 101, "rank3 lifesteal retains full healing")
	var boss: Dictionary = combat.state.enemies[0]
	combat.state.turn = 15
	check(is_equal_approx(combat.boss_enrage_mult(boss),1.0), "boss no early rage")
	combat.state.turn = 16
	check(is_equal_approx(combat.boss_enrage_mult(boss),1.05), "boss round16 rage")
	check(is_equal_approx(combat.boss_enrage_mult(boss),1.05), "rage does not compound per call")
	combat.state.turn = 100
	check(is_equal_approx(combat.boss_enrage_mult(boss),1.5), "boss rage capped")
	cfg.difficulty = 0
	combat.start(cfg, base_party)
	ally = combat.state.allies[0]
	ally.currentHp = 1
	combat._heal(ally, ally, 100, "heal", true, "skill")
	check(ally.currentHp == 101, "rank0 healing unchanged")
	combat.state.turn = 100
	check(is_equal_approx(combat.boss_enrage_mult(combat.state.enemies[0]),1.0), "rank0 no new rage")
	# Spatial overflow is retained exactly once in the mailbox.
	game = Game.new("")
	ex = game.extraction
	for y in range(12):
		for x in range(10):
			ex.state().stash.append({"uid":"fixture_%d_%d" % [x,y],"itemId":"wire","x":x,"y":y,"rotated":false,"revealed":true})
	check(ex.start_run().success,"overflow run starts")
	ex.run().bag.append({"uid":"earned_unique","itemId":"lens","x":0,"y":0,"rotated":false,"revealed":true})
	ex.run().phase = "boss_exit"
	ex.run().node = 4
	ex.run().bossesDefeated = 1
	check(game.valid_save(game.state),"full stash valid")
	check(ex.extract().success,"full stash extraction succeeds")
	check(ex.state().mailbox.size()==1,"overflow retained")
	check(ex.claim_mail().count==0,"full stash claim leaves mail")
	check(ex.sell_item("fixture_0_0").success,"make space")
	check(ex.claim_mail().count==1,"overflow claimed once")
	check(ex.claim_mail().count==0,"duplicate claim empty")
	check(ex.collect_item("earned_unique").success,"collection consumes physical item")
	check(not ex.sell_item("earned_unique").success,"collected item cannot sell")
	check(game.valid_save(game.state),"final collection save valid")
	# A genuine long fight finishes all forty rounds, then seals the zone.
	var tank: Dictionary = game.battle_party(false)[0].duplicate(true)
	tank.stats.maxHp = 100000000
	tank.stats.hp = 100000000
	tank.maxHp = 100000000
	tank.currentHp = 100000000
	tank.stats.atk = 1
	tank.stats.def = 100000000
	tank.skills = [tank.skills[0]]
	var stall_config := {"isExtraction":true,"difficulty":0,"seed":42,"enemies":["wolf"],"scaleMult":{"hpMod":1000000.0,"atkMod":0.01,"defMod":1000000.0,"spdMod":1.0}}
	combat.start(stall_config,[tank])
	while combat.state.phase not in ["victory","defeat"]: combat.auto_step()
	check(combat.state.phase == "defeat" and combat.state.reason == "战区封锁，行动失败", "full round timeout reason")
	check(int(combat.state.turn) == 40, "timeout exactly round40")
	check(int(combat.state.steps) >= 80, "both units completed forty rounds")
	var steps_before := int(combat.state.steps)
	combat.auto_step()
	check(int(combat.state.steps) == steps_before, "terminal timeout idempotent")
	stall_config.isExtraction = false
	combat.start(stall_config,[tank])
	while int(combat.state.turn) <= 40 and combat.state.phase not in ["victory","defeat"]: combat.auto_step()
	check(combat.state.phase not in ["victory","defeat"] and combat.state.turn == 41, "story unaffected by seal")
	stall_config.isExtraction = true
	combat.start(stall_config,[tank])
	combat.state.turn = 40
	combat.state.enemies[0].currentHp = 1
	while combat.state.phase not in ["victory","defeat"]: combat.auto_step()
	check(combat.state.phase == "victory", "round40 lethal action wins before seal")
	check(ex.data.items.size() == 96, "ninety-six distinct catalog items")
	var rarity_counts := [0,0,0,0,0,0]
	var equipped_trials := 0
	for item_id in ex.data.items:
		var definition: Dictionary = ex.item_def(item_id)
		rarity_counts[int(definition.rarity)] += 1
		check(int(definition.width) >= 1 and int(definition.height) >= 1 and int(definition.width) <= 6 and int(definition.height) <= 5, "catalog dimensions "+item_id)
		check(int(definition.value) > 0, "catalog price "+item_id)
		if definition.has("buyPrice"): check(int(definition.buyPrice) > int(definition.value), "shop prevents arbitrage "+item_id)
		if definition.kind == "equipment":
			var item_effects: Array = definition.effects.duplicate(true)
			for effect in item_effects:
				effect.rewardId = item_id
				effect.rewardInstanceId = item_id
				effect.rewardName = definition.name
			combat.start({"isExtraction":true,"difficulty":0,"seed":33,"enemies":["wolf"]}, game.battle_party(false),item_effects)
			while combat.state.phase not in ["victory","defeat"]: combat.auto_step()
			check(combat.state.phase == "victory", "equipment effect actual combat "+item_id)
			equipped_trials += 1
	for count in rarity_counts: check(count == 16, "sixteen items per rarity")
	check(equipped_trials >= 16,"mechanically distinct equipment coverage")
	test_maps()
	print("EXTRACTION CORE: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)

func test_maps() -> void:
	var signatures: Dictionary = {}
	var vault_maps := 0
	for seed in range(128):
		var game = Game.new("")
		game.rng.seed = seed
		var ex = game.extraction
		check(ex.start_run().success, "seeded map start")
		var map: Dictionary = ex.map_state()
		check(map.rooms.size() == 13 and map.districts.size() == 3, "13 rooms 3 districts")
		var vaults := 0
		for room in map.rooms:
			if room.type == "vault": vaults += 1
		check(vaults <= 1, "at most one rare vault")
		if vaults > 0: vault_maps += 1
		check(game.valid_save(game.state), "generated map valid")
		var distances := {map.currentRoomId: 0}
		for iteration in range(13):
			for edge in map.edges:
				for direction in range(2):
					var a: String = edge[direction]
					var b: String = edge[1-direction]
					if distances.has(a): distances[b] = mini(int(distances.get(b, 100)), distances[a] + 1)
		check(distances.size() == 13, "all rooms reachable")
		check(distances[map.bossRoomId] <= 7, "boss within seven graph steps")
		check(map.edges.size() > 12, "map contains loop edges")
		var snapshot: Dictionary = game.state.duplicate(true)
		check(not ex.enter_room(map.bossRoomId).success and game.state == snapshot, "locked boss cannot teleport")
		var shape: Array = []
		for room in map.rooms: shape.append([room.type,room.x,room.y,room.background])
		signatures[str(shape)] = true
		game.state = game._normalize(snapshot)
		check(ex.map_state() == map, "restart stable map")
	check(signatures.size() == 128, "seed varies map layout and POIs")
	check(vault_maps >= 35 and vault_maps <= 80, "vault spawn approximately forty-five percent")
	# Revisit keeps partial search and never repeats rewards. Fixture only changes room kind.
	var game = Game.new("")
	game.rng.seed = 3
	var ex = game.extraction
	ex.start_run()
	var entry: String = ex.map_state().currentRoomId
	var next: String = ex.route_options()[0].id
	for room in ex.run().map.rooms:
		if room.id == next: room.type = "workshop"
	check(ex.enter_room(next).success, "enter adjacent workshop")
	check(not ex.containers().is_empty(), "POI has scene containers")
	var cid: String = ex.containers()[0].id
	check(ex.choose_container(cid).success, "scene container selection")
	check(ex.reveal_next(cid).success, "partial room search")
	var objects: Array = ex.containers()
	var explored: int = ex.map_state().explored
	check(ex.enter_room(entry).success, "backtrack to entry")
	check(ex.enter_room(next).success, "return to searched workshop")
	check(ex.containers() == objects and ex.map_state().explored == explored, "revisit no reroll or duplicate exploration")
	check(game.valid_save(game.state), "revisited map valid")
	var snapshot: Dictionary = game.state.duplicate(true)
	game.save_blocked = true
	check(not ex.take_all_revealed(cid).success and game.state == snapshot, "bulk pickup atomic rollback")
	game.save_blocked = false
	var result: Dictionary = ex.take_all_revealed(cid)
	check(result.success and result.taken.size() == 1, "bulk pickup only revealed")
	check(ex.take_all_revealed(cid).taken.is_empty(), "bulk pickup cannot duplicate")
	check(ex.enter_room(entry).success and ex.enter_room(next).success, "revisit after pickup")
	check(ex.containers()[0].items.size() == objects[0].items.size() - 1, "taken item stays absent")
	var malformed: Dictionary = game.state.duplicate(true)
	malformed.extraction.run.map.edges.clear()
	check(not game.valid_save(malformed), "disconnected map rejected")
	malformed = game.state.duplicate(true)
	malformed.extraction.run.map.bossUnlocked = true
	check(not game.valid_save(malformed), "false boss unlock rejected")
	# A new act uses a newly seeded map, not prior search state.
	ex.run().phase = "boss_exit"
	ex.run().bossesDefeated = 1
	var first_id: String = ex.map_state().rooms[0].id
	check(ex.continue_act().success and ex.map_state().rooms[0].id != first_id and ex.map_state().explored == 0, "new act regenerates map once")

	# One-use room effects and resolved combat are never replayed on backtracking.
	for kind in ["rest", "event", "battle", "vault"]:
		game = Game.new("")
		for owned in game.state.ownedCharacters.values():
			owned.level = 10
			owned.constellation = 6
		ex = game.extraction
		ex.start_run()
		entry = ex.map_state().currentRoomId
		next = ex.route_options()[0].id
		for room in ex.run().map.rooms:
			if room.id == next: room.type = kind
		for unit in ex.run().party: unit.currentHp = maxi(1,int(unit.maxHp / 2))
		check(ex.enter_room(next).success, "first room effect " + kind)
		if kind in ["battle", "vault"]:
			check(ex.containers().is_empty() and not ex.reveal_next("missing").success, "guarded room cannot search before victory")
			var engine = Battle.new(game.catalog)
			check(ex.start_battle(engine).success, "map real combat")
			while engine.state.phase not in ["victory", "defeat"]: engine.auto_step()
			check(ex.settle_battle(ex.run().activeEncounter, engine.state).success and ex.active(), "map real combat cleared")
		if kind == "vault":
			check(ex.containers().size() == 2 and ex.containers()[0].items.size() == 3 and ex.containers()[1].items.size() == 3, "guarded vault rewards two times three")
		var hp: Array = []
		for unit in ex.run().party: hp.append(unit.currentHp)
		objects = ex.containers()
		explored = ex.map_state().explored
		snapshot = game.state.duplicate(true)
		game.save_blocked = true
		check(not ex.enter_room(entry).success and game.state == snapshot, "map transition rollback " + kind)
		game.save_blocked = false
		check(ex.enter_room(entry).success and ex.enter_room(next).success, "backtracking " + kind)
		var after_hp: Array = []
		for unit in ex.run().party: after_hp.append(unit.currentHp)
		check(hp == after_hp and objects == ex.containers() and explored == ex.map_state().explored and ex.run().phase == "room", "one-use room no repeats " + kind)
		check(game.valid_save(game.state), "room transition valid " + kind)

	# Full bag never destroys existing gear or silently loses container items.
	game = Game.new("")
	ex = game.extraction
	ex.start_run()
	ex.run().phase = "room"
	for i in range(30):
		var filler: Dictionary = ex._make_item("wire")
		filler.revealed = true
		check(ex._place(ex.run().bag, filler, ex.dimensions("bag")), "fill bag physically")
	ex._container("满包测试", 3, 0)
	cid = ex.containers()[0].id
	while ex.reveal_next(cid).success: pass
	objects = ex.containers()
	var bag: Array = ex.run().bag.duplicate(true)
	result = ex.take_all_revealed(cid)
	check(result.success and result.taken.is_empty() and result.left.size() == objects[0].items.size(), "full bag returns explicit leavebehind")
	check(ex.run().bag == bag and ex.containers() == objects, "full bag preserves all physical objects")
	check(not ex.take_item(cid, objects[0].items[0].uid).success and ex.run().bag == bag, "single pickup full no mutation")

	# Optional gear purchases reward progression without mandatory entry fees.
	game = Game.new("")
	ex = game.extraction
	ex.state().credits = 1000000
	for key in ["shield", "barrier_module", "scope", "arc_coil", "reactor", "blood_emblem", "guardian_seal"]:
		var definition: Dictionary = ex.item_def(key)
		ex.state().unlockedDifficulty = int(definition.buyMinRisk) - 1
		snapshot = game.state.duplicate(true)
		check(not ex.buy_supply(key).success and game.state == snapshot, "locked gear purchase blocked " + key)
		ex.state().unlockedDifficulty = int(definition.buyMinRisk)
		snapshot = game.state.duplicate(true)
		game.save_blocked = true
		check(not ex.buy_supply(key).success and game.state == snapshot, "gear purchase rollback " + key)
		game.save_blocked = false
		var credits: int = ex.state().credits
		check(ex.buy_supply(key).success, "unlocked gear purchase " + key)
		var bought: Dictionary = ex.state().stash.back()
		check(ex.sell_item(bought.uid).success and ex.state().credits == credits - int(definition.value) * 3, "gear resale no arbitrage " + key)
	check(not ex.buy_supply("prism").success and not ex.buy_supply("eclipse_relic").success and not ex.buy_supply("storm_heart").success, "red gear cannot be bought")

	# Confirmed smart swapping is conservative, recoverable and atomic.
	game = Game.new("")
	ex = game.extraction
	ex.start_run()
	ex.run().phase = "room"
	var protected_ids: Array = []
	for key in ["vest", "bandage"]:
		var protected_item: Dictionary = ex._make_item(key)
		protected_item.revealed = true
		protected_ids.append(protected_item.uid)
		ex._place(ex.run().bag, protected_item, ex.dimensions("bag"))
	while true:
		var filler: Dictionary = ex._make_item("wire")
		filler.revealed = true
		if not ex._place(ex.run().bag, filler, ex.dimensions("bag")): break
	ex._container("换入测试", 0, 0)
	cid = ex.containers()[0].id
	var valuable: Dictionary = ex._make_item("gold_watch")
	valuable.revealed = true
	var hidden: Dictionary = ex._make_item("red_core")
	ex._place(ex._find_container(cid).items, valuable, Vector2i(6,8))
	ex._place(ex._find_container(cid).items, hidden, Vector2i(6,8))
	snapshot = game.state.duplicate(true)
	var plan: Dictionary = ex.plan_smart_loot(cid)
	check(plan.success and plan.gain > 0 and not plan.removed.is_empty(), "smart plan improves full bag")
	check(game.state == snapshot, "smart preview read only")
	for added in plan.added: check(added.uid != hidden.uid, "smart plan excludes hidden item")
	for removed in plan.removed: check(removed.uid not in protected_ids, "smart plan protects equipment and supplies")
	ex.reveal_next(cid)
	snapshot = game.state.duplicate(true)
	check(not ex.apply_smart_loot(cid,plan.planHash).success and game.state == snapshot, "stale plan rejected without mutations")
	plan = ex.plan_smart_loot(cid)
	game.save_blocked = true
	check(not ex.apply_smart_loot(cid,plan.planHash).success and game.state == snapshot, "multi-object swap rolls back atomically")
	game.save_blocked = false
	var physical_ids: Array = []
	for item in ex.run().bag + ex._find_container(cid).items: physical_ids.append(item.uid)
	physical_ids.sort()
	check(ex.apply_smart_loot(cid,plan.planHash).success, "confirmed swap succeeds")
	var after_ids: Array = []
	var bag_ids: Array = []
	var container_ids: Array = []
	for item in ex.run().bag: bag_ids.append(item.uid)
	for item in ex._find_container(cid).items: container_ids.append(item.uid)
	for item in ex.run().bag + ex._find_container(cid).items: after_ids.append(item.uid)
	after_ids.sort()
	check(physical_ids == after_ids, "swap conserves every physical object exactly once")
	for id in protected_ids: check(id in bag_ids, "protected object stays in bag")
	for item in plan.removed: check(item.uid in container_ids, "outgoing loot remains recoverable in original container")
	check(game.valid_save(game.state), "swap packed save valid")
	check(not ex.apply_smart_loot(cid,plan.planHash).success, "double swap blocked")
	# No positive trade may evict a bag of protected supplies.
	ex.run().bag = []
	for i in range(30):
		var supply_item: Dictionary = ex._make_item("bandage")
		supply_item.revealed = true
		ex._place(ex.run().bag, supply_item, ex.dimensions("bag"))
	check(not ex.plan_smart_loot(cid).success, "protected full bag has no swap proposal")
