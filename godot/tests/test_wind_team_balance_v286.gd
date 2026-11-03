extends SceneTree
## Paired, bounded balance diagnostics. This file does not change production data.
const Game = preload("res://scripts/game_model.gd")
const Battle = preload("res://scripts/battle_model.gd")
const FLOORS := [50, 80, 100, 110, 120, 130]
const VARIANTS := ["fire", "wind_current", "wind_legacy", "wind_lumi_atk22", "wind_tiya_atk22", "wind_tiya_voyager"]
const SLOTS := ["helmet", "chest", "belt", "boots", "necklace"]
const CONTEXTS := [{"seed":286031,"enemy":"boss_flame_lord"},{"seed":286032,"enemy":"boss_storm_witch"}]
var checks := 0
var failures: Array = []
var rows: Array = []
var fixtures: Array = []
var started_ms := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func source_hashes() -> Dictionary:
	var result: Dictionary = {}
	for path in ["data/catalog.json","scripts/game_model.gd","scripts/battle_model.gd","scripts/abyss_balance.gd","scripts/relic_sets.gd","tests/test_wind_team_balance_v286.gd"]:
		result[path] = FileAccess.get_sha256("res://" + path)
	return result
func prepare_characters(game, ids: Array, constellation: int) -> void:
	for id in ids:
		game.state.ownedCharacters[id] = game.default_character()
		game.state.ownedCharacters[id].level = 10
		game.state.ownedCharacters[id].constellation = constellation
	game.state.team = ids.duplicate()
func make_basis(seed_value: int) -> Dictionary:
	var game = Game.new("")
	game.rng.seed = seed_value
	prepare_characters(game,["tiya","lumi","ayla"],0)
	var output: Dictionary = {}
	for id in ["tiya","lumi","ayla"]:
		var items: Array = []
		for slot in SLOTS:
			var best: Dictionary = {}
			var best_score := -INF
			for draw in range(12):
				var item: Dictionary = game.generate_relic(5,slot,"")
				while int(item.level) < 25: game._upgrade_relic_one(item)
				var stats: Dictionary = game.computed_stats_for_relic_loadout(id,[item])
				var score := float(stats.atk)
				if id == "tiya": score *= 1.0 + float(stats.cri) * (float(stats.criDmg)-1.0)
				if score > best_score: best_score = score; best = item
			check(game._valid_relic(best) and int(best.level)==25,"legal generated basis " + id + " " + slot)
			items.append(best)
		output[id] = items
	return output
func equip(game, id: String, basis: Array, set_id: String) -> void:
	game.state.ownedCharacters[id].equippedRelics = {}
	for index in range(basis.size()):
		var item: Dictionary = basis[index].duplicate(true)
		item.uid = id + "_balance_" + str(index)
		item.setId = ""
		if index < 4:
			item.setId = ("wind_blades" if index < 2 else "ember_lantern") if set_id == "atk22" else set_id
		item.equippedBy = id
		game.state.relics.append(item)
		game.state.ownedCharacters[id].equippedRelics[item.slotId] = item.uid
		check(game._valid_relic(item),"legal matched set assignment " + id + " " + set_id)
func make_game(basis: Dictionary, constellation: int, variant: String):
	var game = Game.new("")
	var fire := variant == "fire"
	var ids: Array = ["kaldi","selin","ayla"] if fire else ["tiya","lumi","ayla"]
	prepare_characters(game,ids,constellation)
	# Explicitly recover the previous two four-piece effects only. Character,
	# blessing, enemy, and all other equipment definitions remain current.
	if variant == "wind_legacy":
		game.catalog.RelicSets.wind_blades.bonuses[1].effects = [{"type":"windPierceOwner","value":0.2}]
		game.catalog.RelicSets.wind_strings.bonuses[1].effects = [{"type":"onStatusAppliedPartyFollowUpAmp","statusId":"wind_armor","buffId":"wind_oath","followUpTag":"innate_piercing","value":0.4,"duration":2}]
	var main_set := "flame_oath" if fire else "wind_blades"
	var support_set := "ember_lantern" if fire else "wind_strings"
	if variant == "wind_lumi_atk22": support_set = "atk22"
	if variant == "wind_tiya_atk22": main_set = "atk22"
	if variant == "wind_tiya_voyager": main_set = "wind_voyager"
	equip(game,ids[0],basis.tiya,main_set)
	equip(game,ids[1],basis.lumi,support_set)
	equip(game,"ayla",basis.ayla,"aurora_prayer")
	return game
func add_reward(game, counts: Dictionary, id: String, rarity: String) -> void:
	for reward in game.catalog.AbyssData.rogue.rewards:
		if reward.id != id: continue
		check(str(reward.rarity)==rarity,"declared rarity " + id)
		check(game.reward_eligible_for_characters(reward,game.state.team),"eligible reward " + id)
		counts[id] = int(counts.get(id,0)) + 1
		return
	check(false,"unknown reward " + id)
func blessings(game, total: int, fire: bool) -> Dictionary:
	# Same total and white/blue/gold counts for every team. The same common
	# survival and stat allocation is paired with each team's own offense.
	var targets := {"white":int(floor(float(total)*0.50)),"blue":int(floor(float(total)*0.35))}
	targets.gold = total - int(targets.white) - int(targets.blue)
	var fixed := {"white":["common_hp_white","common_def_white","selin_burn_duration_white" if fire else "lumi_duration_white"],"blue":["common_vampiric_blue","ayla_regen_guard_blue"],"gold":["ayla_heal_regen_gold","common_guard_gold","kaldi_start_burn_gold" if fire else "lumi_open_gold"]}
	var pools := {
		"white":["common_atk_white","common_hp_white","common_def_white","selin_burn_duration_white" if fire else "tiya_follow_white","kaldi_burn_amp_white" if fire else "wind_opening_white","ayla_heal_amp_white"],
		"blue":["common_vampiric_blue","ayla_regen_guard_blue","kaldi_burn_spread_blue" if fire else "wind_linked_blue","kaldi_burn_spread_blue" if fire else "wind_linked_blue","selin_burn_energy_blue" if fire else "lumi_guard_blue","kaldi_ult_burn_blue" if fire else "tiya_rhythm_blue"],
		"gold":["common_guard_gold","kaldi_burn_execute_gold" if fire else "wind_pierce_gold","kaldi_burn_execute_gold" if fire else "wind_pierce_gold","selin_burn_amp_gold" if fire else "tiya_follow_gold"]}
	var counts: Dictionary = {}
	for rarity in ["white","blue","gold"]:
		for id in fixed[rarity]: add_reward(game,counts,id,rarity)
		for index in range(int(targets[rarity])-fixed[rarity].size()):
			add_reward(game,counts,pools[rarity][index % pools[rarity].size()],rarity)
	var effects: Array = []
	var observed_total := 0
	for reward in game.catalog.AbyssData.rogue.rewards:
		for copy in range(int(counts.get(reward.id,0))):
			observed_total += 1
			for original in reward.effects:
				var effect: Dictionary = original.duplicate(true)
				effect.rewardId = reward.id; effect.rewardInstanceId = str(reward.id)+"_"+str(copy)
				effects.append(effect)
	check(observed_total==total,"exact paired blessing total " + str(total))
	return {"effects":effects,"counts":counts,"rarities":targets,"total":observed_total}
func metric() -> Dictionary:
	return {"outgoing":0.0,"outgoingEffective":0.0,"incomingEffective":0.0,"healing":0.0,"native":0.0,"followUp":0.0,"statusDamage":0.0,"byActor":{},"bySkill":{},"allyActions":0,"enemyActions":0}
func accumulate(battle, stats: Dictionary, events: Array) -> void:
	for event in events:
		var target: Dictionary = battle.get_unit(str(event.get("target","")))
		if target.is_empty(): continue
		if event.type=="damage":
			if target.isAlly:
				stats.incomingEffective += float(event.get("effectiveHpDamage",event.amount))
			else:
				var amount := float(event.amount)
				stats.outgoing += amount; stats.outgoingEffective += float(event.get("effectiveHpDamage",amount))
				if event.has("status"): stats.statusDamage += amount
				elif bool(event.get("follow_up",false)): stats.followUp += amount
				else: stats.native += amount
				var actor: Dictionary = battle.get_unit(str(event.get("actor","")))
				var id := str(actor.get("id","status"))
				stats.byActor[id] = float(stats.byActor.get(id,0.0)) + amount
				var skill_id := str(event.get("skill_id",event.get("status","unknown")))
				stats.bySkill[skill_id] = float(stats.bySkill.get(skill_id,0.0)) + amount
		elif event.type=="heal" and target.isAlly: stats.healing += float(event.amount)
func pressure(game, effects: Array, floor_number: int, context: Dictionary) -> Dictionary:
	var before := Time.get_ticks_msec()
	var config := {"isAbyss":true,"difficulty":3,"abyssGrowthVersion":3,"floor":floor_number,"enemies":[context.enemy],"seed":context.seed,"maxSteps":1000}
	var battle = Battle.new(game.catalog)
	battle.start(config,game.battle_party(false),effects)
	var initial_enemies: Array = []
	var initial_allies: Array = []
	for enemy in battle.state.enemies: initial_enemies.append({"id":enemy.id,"stats":enemy.stats.duplicate(true)})
	for ally in battle.state.allies: initial_allies.append({"id":ally.id,"stats":ally.stats.duplicate(true)})
	var stats := metric()
	accumulate(battle,stats,battle.state.events)
	var guard := 0
	while battle.state.phase not in ["victory","defeat"] and guard < 500 and int(battle.state.turn)<=40:
		var actor: Dictionary = battle.current_actor()
		if not actor.is_empty():
			if actor.isAlly: stats.allyActions += 1
			else: stats.enemyActions += 1
		var step: Dictionary = battle.auto_step()
		check(bool(step.get("success",false)),"native battle step")
		accumulate(battle,stats,step.get("events",[])); guard += 1
	var hp := 0.0; var maximum := 0.0; var alive := 0
	var final_allies: Array = []
	for ally in battle.state.allies:
		hp += float(ally.currentHp); maximum += float(ally.maxHp)
		if int(ally.currentHp)>0: alive += 1
		final_allies.append({"id":ally.id,"hp":ally.currentHp,"maxHp":ally.maxHp,"energy":ally.energy,"shield":ally.shield})
	var enemy_hp := 0.0; var enemy_max := 0.0
	for enemy in battle.state.enemies: enemy_hp += float(enemy.currentHp); enemy_max += float(enemy.maxHp)
	stats.merge({"result":battle.state.phase if battle.state.phase in ["victory","defeat"] else "censored","steps":guard,"round":battle.state.turn,"alive":alive,"teamHpRatio":hp/maxf(1.0,maximum),"enemyHpRatio":enemy_hp/maxf(1.0,enemy_max),"initialEnemies":initial_enemies,"initialAllies":initial_allies,"finalAllies":final_allies,"elapsedMs":Time.get_ticks_msec()-before})
	return stats
func output_window(game, effects: Array, floor_number: int, context: Dictionary) -> Dictionary:
	var before := Time.get_ticks_msec()
	var config := {"isAbyss":true,"difficulty":3,"abyssGrowthVersion":3,"floor":floor_number,"enemies":[context.enemy],"seed":context.seed}
	var battle = Battle.new(game.catalog)
	battle.start(config,game.battle_party(false),effects)
	# This separate, explicitly artificial output diagnostic keeps actual scaled
	# enemy defense/speed, but makes a neutral immortal target with no actions.
	for enemy in battle.state.enemies:
		enemy.maxHp = 1000000000; enemy.currentHp = enemy.maxHp; enemy.stats.maxHp = enemy.maxHp; enemy.element = "neutral"
	var stats := metric()
	for round_index in range(6):
		var order: Array = battle._queue.filter(func(unit): return unit.isAlly)
		for ally in order:
			var available: Array = battle._available(ally)
			var chosen := str(available[0])
			for sid in available:
				var skill: Dictionary = battle.skill_data(sid)
				if battle._hold_healing_skill(ally,skill): continue
				if skill.get("type","")=="ultimate": chosen=sid; break
				if skill.get("type","")=="skill": chosen=sid
			battle._events = []
			battle._execute_skill(ally,chosen)
			battle._after_active_action(ally)
			battle._consume_action_statuses(ally)
			accumulate(battle,stats,battle._events); stats.allyActions += 1
		battle._events = []
		battle._end_round()
		accumulate(battle,stats,battle._events)
		battle._build_queue()
	stats.elapsedMs = Time.get_ticks_msec()-before
	return stats
func run() -> void:
	started_ms = Time.get_ticks_msec()
	var hashes_before := source_hashes()
	for context in CONTEXTS:
		var basis := make_basis(int(context.seed))
		for constellation in [0,6]:
			for variant in VARIANTS:
				var game = make_game(basis,constellation,variant)
				fixtures.append({"seed":context.seed,"constellation":constellation,"variant":variant,"team":game.state.team.duplicate(),"party":game.battle_party(false),"relics":game.state.relics.duplicate(true),"windSets":{"wind_blades":game.catalog.RelicSets.wind_blades.duplicate(true),"wind_strings":game.catalog.RelicSets.wind_strings.duplicate(true)}})
				for floor_number in FLOORS:
					var plan := blessings(game,int(floor_number),variant=="fire")
					var row := {"seed":context.seed,"enemy":context.enemy,"constellation":constellation,"variant":variant,"floor":floor_number,"blessingTotal":plan.total,"blessingRarities":plan.rarities,"blessingCounts":plan.counts}
					row.pressure = pressure(game,plan.effects,int(floor_number),context)
					row.output = output_window(game,plan.effects,int(floor_number),context)
					rows.append(row)
				print("BALANCE_CONTEXT ",context.seed," C",constellation," ",variant," elapsed_ms=",Time.get_ticks_msec()-started_ms)
	var hashes_after := source_hashes()
	check(hashes_before==hashes_after,"frozen source hashes")
	check(rows.size()==144,"complete 144 paired pressure and output contexts")
	var report := {"scope":"Bounded sensitivity snapshots, not climbed routes or statistical win rates. Lv10 C0/C6, awakening0, legal five-star +25 gear selected from 12 candidates per slot. Identical rolled item attributes pair Kaldi/Tiya and Selin/Lumi. Each floor has exactly floor-number blessings with matched 50/35/15 percent rarity allocation rounded to integers; this is a prescribed budget, not observed acquisition. Common survival/stat allocation is identical; fire/wind offense follows declared pool-specific cycles. Full HP, zero energy, empty cooldown cold start, no camp upgrades. Pressure uses unchanged production enemy budgets, native auto battle, <=40 rounds/500 steps. Two paired contexts use legacy flame/storm bosses and different seeds/gear. The separate six-round output diagnostic uses scaled DEF/SPD but neutral immortal target with no enemy actions. No pressure success implies route reachability.","rows":rows,"fixtures":fixtures,"sourceHashesBefore":hashes_before,"sourceHashesAfter":hashes_after,"checks":checks,"failures":failures,"elapsedMs":Time.get_ticks_msec()-started_ms}
	DirAccess.make_dir_recursive_absolute("res://validation/v286-team-balance")
	var file = FileAccess.open("res://validation/v286-team-balance/report.json",FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report,"  "))
	else: check(false,"write team balance report")
	print("WIND_TEAM_BALANCE_V286 ",checks," checks / ",failures.size()," failures, ",rows.size()," contexts, elapsed_ms=",Time.get_ticks_msec()-started_ms)
	quit(1 if not failures.is_empty() else 0)
