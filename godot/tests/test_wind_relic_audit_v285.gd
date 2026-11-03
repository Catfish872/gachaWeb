extends SceneTree
## Focused explanatory audit. Reuses production generation, upgrades, optimizer,
## and native battle skill/round code. No production data or save is changed.
const Game = preload("res://scripts/game_model.gd")
const Optimizer = preload("res://scripts/relic_optimizer.gd")
const Sets = preload("res://scripts/relic_sets.gd")
const Battle = preload("res://scripts/battle_model.gd")
const SLOTS = ["helmet", "chest", "belt", "boots", "necklace"]
const SAMPLES = 8
var checks := 0
var failures: Array = []
func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); push_error(label)
func gear(game, level: int) -> Array:
	# Every piece comes from twelve legal generated candidates, upgraded through
	# the production routine. This is a reproducible sample, not perfect gear.
	var result: Array = []
	var scorer = Optimizer.new(game, "tiya")
	for slot in SLOTS:
		var best: Dictionary = {}
		var score := -INF
		for draw in range(12):
			var item: Dictionary = game.generate_relic(5, slot, "")
			while int(item.level) < level: game._upgrade_relic_one(item)
			var candidate: float = float(scorer.evaluate_loadout([item]).objective)
			if candidate > score: score = candidate; best = item
		check(game._valid_relic(best) and int(best.level) == level, "legal gear " + slot)
		result.append(best)
	return result
func loadout(basis: Array, kind: String) -> Array:
	var result: Array = basis.duplicate(true)
	for index in range(result.size()):
		result[index].uid = "audit_" + kind + "_" + str(index)
		result[index].setId = ""
		if kind == "atk22" and index < 4: result[index].setId = "wind_blades" if index < 2 else "ember_lantern"
		elif kind == "atk2" and index < 2: result[index].setId = "wind_blades"
		elif kind != "atk22" and kind != "atk2" and index < 4: result[index].setId = kind
	return result
func equip(game, id: String, items: Array) -> void:
	game.state.ownedCharacters[id].equippedRelics = {}
	for original in items:
		var item: Dictionary = original.duplicate(true)
		item.uid = id + "_" + str(item.uid); item.equippedBy = id
		game.state.relics.append(item)
		game.state.ownedCharacters[id].equippedRelics[item.slotId] = item.uid
func blessing_effects(game, profile: String) -> Array:
	var copies: Dictionary = {}
	if profile == "pierce3": copies = {"tiya_follow_white":1,"tiya_follow_gold":1,"wind_pierce_gold":1}
	if profile == "balanced100": copies = {"wind_opening_white":20,"wind_linked_blue":20,"wind_pierce_gold":20,"tiya_follow_white":20,"tiya_follow_gold":20}
	var result: Array = []
	for reward in game.catalog.AbyssData.rogue.rewards:
		for copy in range(int(copies.get(reward.id,0))): result.append_array(reward.effects.duplicate(true))
	return result
func battle_damage(game, items: Array, duo: bool, effects: Array, seed_value: int, defense: float = 100.0, critical: float = -1.0, maintained: bool = false) -> Dictionary:
	var battle = Battle.new(game.catalog)
	battle.rng.seed = seed_value
	battle._effects = effects.duplicate(true)
	var allies: Array = []
	if duo:
		allies.append(battle._make_ally({"id":"lumi","stats":game.computed_stats("lumi"),"constellation":int(game.state.ownedCharacters.lumi.constellation),"ownerEffects":Sets.evaluate(game.catalog,game.equipped_relics("lumi")).ownerEffects},0))
	var stats: Dictionary = game.computed_stats_for_relic_loadout("tiya",items)
	if critical >= 0.0: stats.cri = critical
	var tiya: Dictionary = battle._make_ally({"id":"tiya","stats":stats,"constellation":int(game.state.ownedCharacters.tiya.constellation),"ownerEffects":Sets.evaluate(game.catalog,items).ownerEffects},allies.size())
	allies.append(tiya)
	var enemies: Array = []
	for index in range(3):
		var target: Dictionary = battle._make_ally({"id":"reference","stats":{"maxHp":1000000000,"atk":100,"def":defense,"spd":100,"cri":0.0,"criDmg":1.5}},9+index)
		target.uid = "enemy_" + str(index); target.isAlly = false; target.passiveId = ""; target.element = "neutral"
		enemies.append(target)
	battle.state = {"allies":allies,"enemies":enemies,"turn":1,"config":{},"events":[],"log":[]}
	var total := 0.0; var native := 0.0; var follow_up := 0.0
	for action in range(6):
		if maintained:
			for target in enemies: target.statuses = [{"id":"wind_armor","duration":99,"value":0.35,"stacks":1}]
		for unit in allies:
			var available: Array = battle._available(unit)
			var chosen: String = str(available[0])
			for sid in available:
				var kind: String = str(game.catalog.SkillData[sid].type)
				if kind == "ultimate": chosen = sid; break
				if kind == "skill": chosen = sid
			battle._events = []
			battle._execute_skill(unit,chosen)
			battle._after_active_action(unit)
			for event in battle._events:
				if event.type == "damage" and unit.id == "tiya":
					total += float(event.amount)
					if event.get("follow_up",false): follow_up += float(event.amount)
					else: native += float(event.amount)
		battle._end_round(); battle.state.turn += 1
	return {"total":total,"native":native,"followUp":follow_up}
func finish(search) -> Dictionary:
	var result: Dictionary = search.preview()
	while not result.done: result = search.advance(10000)
	return result
func run() -> void:
	var report: Dictionary = {"runtimeCommit":"9aeb948ad5851cfb283056e57bebc424a77d9776","samples":SAMPLES,"scope":"Matched legal five-star pieces; 6 native battle rounds; three neutral immortal targets, DEF100/SPD100; no incoming attacks; Lumi acts before Tiya; cold start, natural status expiry. Actual Tiya damage only. Fixed 100-blessing composition is a sensitivity case, not a random acquisition simulation.","cases":[]}
	for config in [{"name":"level1_c0_plus0_solo","level":1,"c":0,"gear":0,"duo":false},{"name":"level1_c0_plus0_duo","level":1,"c":0,"gear":0,"duo":true},{"name":"level10_c0_plus25_duo","level":10,"c":0,"gear":25,"duo":true},{"name":"level10_c6_plus25_duo","level":10,"c":6,"gear":25,"duo":true}]:
		var game = Game.new("")
		game.rng.seed = 285011
		for id in ["tiya","lumi"]:
			game.state.ownedCharacters[id] = game.default_character()
			game.state.ownedCharacters[id].level = config.level
			game.state.ownedCharacters[id].constellation = config.c
		game.state.team = ["tiya","lumi"] if config.duo else ["tiya"]
		var basis: Array = gear(game,int(config.gear))
		if config.duo: equip(game,"lumi",loadout(basis,"wind_strings"))
		var scorer = Optimizer.new(game,"tiya")
		var output: Dictionary = {"config":config,"gear":basis,"scores":{},"stats":{},"live":{}}
		for kind in ["atk2","atk22","wind_blades","wind_strings","wind_voyager","thunder_hunt"]:
			var items: Array = loadout(basis,kind)
			var value: Dictionary = scorer.evaluate_loadout(items)
			output.scores[kind] = value.objective; output.stats[kind] = value.stats
			check(value.stats == game.computed_stats_for_relic_loadout("tiya",items),config.name + " exact stats " + kind)
			if kind not in ["atk22","wind_blades"]: continue
			output.live[kind] = {}
			for profile in ["none","pierce3","balanced100"]:
				var effects: Array = blessing_effects(game,profile)
				var sum := 0.0; var follow_up := 0.0; var values: Array = []
				for sample in range(SAMPLES):
					var actual: Dictionary = battle_damage(game,items,bool(config.duo),effects,285100+sample)
					sum += actual.total; follow_up += actual.followUp; values.append(actual.total)
				output.live[kind][profile] = {"mean":sum/SAMPLES,"followUpMean":follow_up/SAMPLES,"values":values}
		# Restricted inventory keeps the same attributes in every slot and allows
		# every assignment of four wind/ember pieces; compare exact enumeration.
		var options: Array = []
		for slot in range(5):
			var entries: Array = []
			for set_id in (["wind_blades","ember_lantern"] if slot < 4 else [""]):
				var item: Dictionary = basis[slot].duplicate(true)
				item.uid = "search_"+str(slot)+"_"+set_id; item.setId = set_id
				game.state.relics.append(item); entries.append(item)
			options.append(entries)
		var search = Optimizer.new(game,"tiya")
		var exact := -INF
		for mask in range(16):
			var items: Array = []
			for slot in range(4): items.append(options[slot][(mask >> slot) & 1])
			items.append(options[4][0])
			exact = maxf(exact,float(search.evaluate_loadout(items).objective))
		var result: Dictionary = finish(search)
		check(result.provenOptimal and absf(float(result.lowerBound)-exact)<0.00001,config.name + " optimizer equals exhaustive enumeration")
		output.search = {"score":result.lowerBound,"counts":result.after.counts,"proven":result.provenOptimal}
		if not config.duo:
			for critical in [0.0,1.0]:
				var items: Array = loadout(basis,"wind_blades")
				var stats: Dictionary = game.computed_stats_for_relic_loadout("tiya",items)
				stats.cri = critical
				var predicted: float = scorer._evaluate(stats,Sets.evaluate(game.catalog,items).ownerEffects)
				var actual: Dictionary = battle_damage(game,items,false,[],285000,100.0,critical,true)
				check(absf(predicted-float(actual.total))<0.00001,"wind reference equals maintained native battle crit="+str(critical))
		report.cases.append(output)
	report.checks = checks; report.failures = failures
	DirAccess.make_dir_recursive_absolute("res://validation/v285-relic-audit")
	var file = FileAccess.open("res://validation/v285-relic-audit/report.json",FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report,"  "))
	else: check(false,"write audit report")
	print("WIND_RELIC_AUDIT_V285: ",checks," checks / ",failures.size()," failures; report validation/v285-relic-audit/report.json")
	quit(1 if not failures.is_empty() else 0)
