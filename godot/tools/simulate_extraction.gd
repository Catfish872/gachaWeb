extends SceneTree
## 实际搜打撤状态机和战斗引擎联动模拟。结果从真实战斗自然结算。
const Game = preload("res://scripts/game_model.gd")
const Navigation = preload("res://tools/extraction_navigation.gd")
const Battle = preload("res://scripts/battle_model.gd")
const PROFILES = [
 {"id":"starter_lv1", "team":["ember","zeph"], "level":1, "constellation":0},
 {"id":"grown_three_lv5", "team":["ember","tide","bolt"], "level":5, "constellation":0},
 {"id":"grown_healer_lv5", "team":["kaldi","ayla","gus"], "level":5, "constellation":0},
 {"id":"mature_healer_lv10", "team":["kaldi","ayla","gus"], "level":10, "constellation":0},
 {"id":"mature_damage_lv10", "team":["kaldi","cinder","gus"], "level":10, "constellation":0},
 {"id":"mature_c6_lv10", "team":["kaldi","ayla","gus"], "level":10, "constellation":6},
 {"id":"prepared_damage_lv10", "team":["kaldi","cinder","gus"], "level":10, "constellation":0, "gear":true, "supplies":true},
 {"id":"prepared_c6_lv10", "team":["kaldi","ayla","gus"], "level":10, "constellation":6, "gear":true, "supplies":true}
]
var errors: Array = []
var total_battles := 0
var input_hashes: Dictionary = {}
var trial_hp := 0.0
var trial_atk := 0.0

func _init() -> void:
 for path in ["tools/simulate_extraction.gd", "tools/extraction_navigation.gd", "scripts/game_model.gd", "scripts/extraction_model.gd", "scripts/battle_model.gd", "data/extraction.json", "data/catalog.json"]:
  input_hashes[path] = simulation_hash(path)
 var samples := 8
 var first_seed := 834000
 var output := "extraction-development.json"
 var selected_profiles: Array = PROFILES.duplicate(true)
 var ranks: Array = [0, 1, 2, 3, 4, 5]
 var exits: Array = [1, 2, 3]
 var policies: Array = ["shortest", "poi", "completionist"]
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--trial-rank-hp="): trial_hp = float(arg.trim_prefix("--trial-rank-hp="))
  if arg.begins_with("--trial-rank-atk="): trial_atk = float(arg.trim_prefix("--trial-rank-atk="))
  if arg.begins_with("--samples="): samples = clampi(int(arg.trim_prefix("--samples=")), 1, 512)
  if arg.begins_with("--seed-start="): first_seed = int(arg.trim_prefix("--seed-start="))
  if arg.begins_with("--output="): output = arg.trim_prefix("--output=").get_file()
  if arg.begins_with("--profile="):
   var requested: String = arg.trim_prefix("--profile=")
   selected_profiles = PROFILES.filter(func(p): return p.id == requested)
  if arg.begins_with("--rank="): ranks = [clampi(int(arg.trim_prefix("--rank=")), 0, 5)]
  if arg.begins_with("--exit="): exits = [clampi(int(arg.trim_prefix("--exit=")), 1, 3)]
  if arg.begins_with("--policy="): policies = [arg.trim_prefix("--policy=")]
 var matched := OS.get_cmdline_user_args().has("--matched-map")
 var rows: Array = []
 var aggregate: Array = []
 for profile in selected_profiles:
  var rank_by_profile := {"starter_lv1":0,"grown_three_lv5":1,"grown_healer_lv5":2,"mature_healer_lv10":3,"mature_damage_lv10":4,"mature_c6_lv10":5,"prepared_damage_lv10":5,"prepared_c6_lv10":5}
  var profile_ranks: Array = [rank_by_profile[profile.id]] if matched else ranks
  for rank in profile_ranks:
   for exit_act in exits:
    for policy in policies:
     var group: Array = []
     for sample in range(samples):
      var row := simulate(profile, int(rank), int(exit_act), str(policy), first_seed + sample)
      rows.append(row)
      group.append(row)
     var summary := summarize(group)
     aggregate.append(summary)
     print(JSON.stringify(summary))
 for path in input_hashes:
  if simulation_hash(path) != input_hashes[path]: errors.append("input changed during simulation: " + path)
 var report := {"trialRankHp":trial_hp,"trialRankAtk":trial_atk,"inputHashes":input_hashes,"hashScope":"Full source/catalog hashes; extraction JSON hash excludes item name/description/icon presentation fields only; category now affects themed loot (parallel art/lore import), all balance/shape/effect/value fields included.","method":"Connected-map policies shortest gate-aware BFS gate6, POI-priority target10, completionist17 nonentry rooms per act, BFS backtracking. Real ExtractionModel public route/search/take/equip/consume/advance/start_battle/settle_battle/extract methods; BattleModel.auto_step naturally determines every battle. Initial save fixtures unlock rank but do not fake gameplay results. Unprepared profiles have no relics or supplies. Prepared profiles use legal generated 5-star +25 relics and buy/bring three medkits (initial wallet fixture); no manufactured run loot or meta upgrades. Party health/energy/cooldowns persist, no between-fight XP. Policies choose offered rooms and revealed loot only. First-fit packing with lower-density replacement is heuristic, not optimal. Timing not measured.", "profiles": selected_profiles, "seedStart":first_seed, "samplesPerCell":samples, "totalRuns":rows.size(), "totalBattles":total_battles, "errors":errors, "aggregate":aggregate, "rows":rows}
 var file := FileAccess.open("res://validation/" + output, FileAccess.WRITE)
 if file: file.store_string(JSON.stringify(report, "\t"))
 else: errors.append("report could not be written")
 print("EXTRACTION SIMULATIONS: %d runs, %d real battles, %d errors" % [rows.size(), total_battles, errors.size()])
 for error in errors: printerr(error)
 quit(0 if errors.is_empty() else 1)

func must(result: Dictionary, label: String) -> bool:
 if result.get("success", false): return true
 errors.append(label + ": " + str(result))
 return false

func simulate(profile: Dictionary, rank: int, exit_act: int, policy: String, seed_value: int) -> Dictionary:
 var m = Game.new("")
 m.rng.seed = seed_value
 for id in profile.team:
  m.state.ownedCharacters[id] = m.default_character()
  m.state.ownedCharacters[id].level = profile.level
  m.state.ownedCharacters[id].constellation = profile.constellation
 m.set_team(profile.team)
 if profile.get("gear", false):
  m.state.resources.gold = 1000000
  for id in profile.team:
   for slot in m.catalog.RelicSlots:
    var relic: Dictionary = m.generate_relic(5, slot.id)
    must(m.add_relic(relic), "fixture generated relic")
    must(m.equip_relic(relic.uid,id), "fixture equip relic")
    for upgrade in range(25): must(m.upgrade_relic(relic.uid), "fixture upgrade relic")
 var x = m.extraction
 if trial_hp > 0: x.data.balance.rankHp[rank] = trial_hp
 if trial_atk > 0: x.data.balance.rankAtk[rank] = trial_atk
 x.state().unlockedDifficulty = rank
 var supply_cost := 0
 if profile.get("supplies", false):
  m.state.resources.gold = 10000
  for supply in range(3):
   var bought: Dictionary = x.buy_supply("medkit")
   if must(bought, "buy departure medkit"):
    supply_cost += int(bought.cost)
    var uid: String = x.state().stash.back().uid
    must(x.bring_item(uid), "bring purchased medkit")
 var row := {"vaultsGenerated":0,"vaultsEntered":0,"vaultsWon":0,"rarityByRoom":{},"seenIds":[],"carriedIds":[],"moves":0,"roomsExplored":0,"profile":profile.id,"rank":rank,"exitAct":exit_act,"policy":policy,"seed":seed_value,"outcome":"error","battles":0,"rounds":0,"maxBattleRounds":0,"actions":0,"safetyEnds":0,"sealEnds":0,"maxHitPct":0.0,"maxOpeningHitPct":0.0,"value":0,"lostValue":0,"items":0,"replacements":0,"bosses":0,"deathAct":0,"reveals":0,"redFound":0,"supplyCost":supply_cost,"netValue":-supply_cost}
 if not must(x.start_run(rank), "start run"): return row
 for room in x.map_state().rooms: row.vaultsGenerated += int(room.type == "vault")
 for guard in range(500):
  if not x.active(): break
  if not x.growth_choices().is_empty():
   must(x.choose_growth(x.growth_choices()[0].choiceId), "resolve earned growth")
   continue
  match str(x.run().phase):
   "route":
    var target: String = Navigation.next_room(x, policy, party_health(x))
    if target.is_empty():
     errors.append("navigation found no legal target")
     break
    for room in x.map_state().rooms:
     if room.id == target and not room.visited: row.vaultsEntered += int(room.type == "vault")
    if not must(x.choose_route(target), "choose connected map room"): break
    row.moves += 1
   "battle":
    var b = Battle.new(m.catalog)
    var begun: Dictionary = x.start_battle(b)
    if not must(begun,"start actual battle"): break
    var act := int(x.run().act)
    while b.state.phase not in ["victory", "defeat"]:
     var round_before := int(b.state.turn)
     var step: Dictionary = b.auto_step()
     for event in step.get("events", []):
      if event.get("type", "") == "damage" and str(event.get("target", "")).begins_with("ally_"):
       var target: Dictionary = b.get_unit(event.target)
       var fraction := float(event.amount) / maxf(1, float(target.maxHp))
       row.maxHitPct = maxf(row.maxHitPct, fraction)
       if round_before == 1: row.maxOpeningHitPct = maxf(row.maxOpeningHitPct, fraction)
    row.battles += 1
    total_battles += 1
    row.rounds += int(b.state.turn)
    row.maxBattleRounds = maxi(int(row.maxBattleRounds), int(b.state.turn))
    row.actions += int(b.state.steps)
    row.safetyEnds += int(str(b.state.reason).contains("上限"))
    row.sealEnds += int(str(b.state.reason).contains("封锁"))
    if b.state.phase == "defeat": row.deathAct = act
    if b.state.phase == "victory" and x.run().room.type == "vault": row.vaultsWon += 1
    if not must(x.settle_battle(begun.config, b.state), "settle actual battle"): break
   "room", "boss_exit":
    for action in x.room_actions():
     if action.enabled and action.cost == 0:
      must(x.choose_room_action(action.id), "active room choice")
      break
    if not x.growth_choices().is_empty(): continue
    loot_room(x, row)
    use_supplies(x)
    if str(x.run().phase) == "room":
     if not must(x.advance_room(), "advance room"): break
    elif int(x.run().act) >= exit_act:
     for carried in x.run().bag + x.run().equipped:
      if carried.itemId not in row.carriedIds: row.carriedIds.append(carried.itemId)
     if not must(x.extract(), "extract at chosen boss"): break
    else:
     if not must(x.continue_act(), "continue next act"): break
     for room in x.map_state().rooms: row.vaultsGenerated += int(room.type == "vault")
   _:
    errors.append("unknown run phase")
    break
 if x.active():
  errors.append("run failed to terminate")
 else:
  var last: Dictionary = x.state().lastRun
  row.outcome = last.get("outcome", "error")
  row.roomsExplored = last.get("roomsCleared",0)
  row.bosses = last.get("bossesDefeated", 0)
  row.items = last.get("items", 0) if row.outcome == "extracted" else 0
  row.value = last.get("value", 0) if row.outcome == "extracted" else 0
  row.netValue = row.value - supply_cost
  row.lostValue = last.get("value", 0) if row.outcome == "defeat" else 0
 return row

func route_score(kind: String, policy: String, health: float) -> float:
 if kind == "rest": return 120.0 if health < 0.72 else (8.0 if policy == "greedy" else 25.0)
 if policy == "greedy": return {"elite":90.0,"cache":85.0,"event":70.0,"battle":60.0}.get(kind,0.0)
 return {"cache":100.0,"event":80.0,"battle":15.0,"elite":5.0}.get(kind,0.0)

func party_health(x) -> float:
 var hp := 0.0
 var maximum := 0.0
 for unit in x.run().party:
  hp += float(unit.currentHp)
  maximum += float(unit.maxHp)
 return hp / maxf(1, maximum)

func density(x, item: Dictionary) -> float:
 var d: Dictionary = x.item_def(item.itemId)
 return float(x.item_value(item)) / maxf(1, float(d.width * d.height))

func loot_room(x, row: Dictionary) -> void:
 for container in x.containers():
  for old_item in container.items:
   if old_item.revealed: continue
   var reveal: Dictionary = x.reveal_next(container.id)
   if not must(reveal, "reveal stored item"): return
   if old_item.itemId not in row.seenIds: row.seenIds.append(old_item.itemId)
   var room_kind: String = x.run().room.type
   if not row.rarityByRoom.has(room_kind): row.rarityByRoom[room_kind] = [0,0,0,0,0,0]
   row.rarityByRoom[room_kind][int(reveal.definition.rarity)] += 1
   row.reveals += 1
   row.redFound += int(int(reveal.definition.rarity) == 5)
  var current: Array = []
  for refreshed in x.containers():
   if refreshed.id == container.id: current = refreshed.items
  current.sort_custom(func(a,b): return density(x,a) > density(x,b))
  for item in current:
   var picked: Dictionary = x.take_item(container.id, item.uid)
   if not picked.get("success", false):
    x.sort_grid("bag")
    picked = x.take_item(container.id,item.uid)
   if not picked.get("success", false):
    var candidates: Array = x.run().bag.duplicate(true)
    candidates.sort_custom(func(a,b): return density(x,a) < density(x,b))
    var candidate_area := 0
    var candidate_value := 0
    var remove: Array = []
    var def: Dictionary = x.item_def(item.itemId)
    for existing in candidates:
     if density(x,existing) >= density(x,item): break
     var existing_def: Dictionary = x.item_def(existing.itemId)
     candidate_area += int(existing_def.width * existing_def.height)
     candidate_value += x.item_value(existing)
     remove.append(existing.uid)
     if candidate_area >= int(def.width * def.height): break
    if candidate_area >= int(def.width * def.height) and candidate_value < x.item_value(item):
     for uid in remove:
      must(x.discard_item(uid), "discard lower-value item")
      row.replacements += 1
     x.sort_grid("bag")
     picked = x.take_item(container.id, item.uid)
   if picked.get("success", false):
    var definition: Dictionary = x.item_def(item.itemId)
    if definition.kind == "equipment" and x.run().equipped.size() < 3:
     must(x.equip_item(item.uid), "equip discovered item")
 use_supplies(x)

func use_supplies(x) -> void:
 for item in x.run().bag.duplicate(true):
  if party_health(x) >= 0.75: break
  if x.item_def(item.itemId).kind == "consumable" and x.can_use_consumable(item.itemId): must(x.use_item(item.uid), "use discovered supply")

func summarize(rows: Array) -> Dictionary:
 var first: Dictionary = rows[0]
 var r := {"profile":first.profile,"rank":first.rank,"exitAct":first.exitAct,"policy":first.policy,"samples":rows.size(),"meanMoves":0.0,"meanRoomsExplored":0.0,"meanReveals":0.0,"extracted":0,"defeated":0,"safetyEnds":0,"sealEnds":0,"meanValue":0.0,"meanNetValue":0.0,"meanSupplyCost":0.0,"meanLoss":0.0,"meanBattles":0.0,"meanRounds":0.0,"maxBattleRounds":0,"meanActions":0.0,"maxHitPct":0.0,"maxOpeningHitPct":0.0,"meanReplacements":0.0,"redFound":0,"valueP10":0,"valueP50":0,"valueP90":0}
 var values: Array = []
 for row in rows:
  r.extracted += int(row.outcome == "extracted")
  r.defeated += int(row.outcome == "defeat")
  r.safetyEnds += row.safetyEnds
  r.sealEnds += row.sealEnds
  r.meanMoves += row.moves
  r.meanRoomsExplored += row.roomsExplored
  r.meanReveals += row.reveals
  r.meanValue += row.value
  r.meanNetValue += row.netValue
  r.meanSupplyCost += row.supplyCost
  r.meanLoss += row.lostValue
  r.meanBattles += row.battles
  r.meanRounds += row.rounds
  r.maxBattleRounds = maxi(int(r.maxBattleRounds),int(row.maxBattleRounds))
  r.meanActions += row.actions
  r.meanReplacements += row.replacements
  r.maxHitPct = maxf(r.maxHitPct,row.maxHitPct)
  r.maxOpeningHitPct = maxf(r.maxOpeningHitPct,row.maxOpeningHitPct)
  r.redFound += row.redFound
  values.append(row.value)
 for key in ["meanMoves","meanRoomsExplored","meanReveals","meanValue","meanNetValue","meanSupplyCost","meanLoss","meanBattles","meanRounds","meanActions","meanReplacements"]: r[key] = snappedf(r[key] / rows.size(), 0.01)
 values.sort()
 r.valueP10 = values[int((values.size()-1)*0.1)]
 r.valueP50 = values[int((values.size()-1)*0.5)]
 r.valueP90 = values[int((values.size()-1)*0.9)]
 return r

func simulation_hash(path: String) -> String:
 if path != "data/extraction.json": return FileAccess.get_sha256("res://" + path)
 var configuration: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://" + path))
 # 美术与世界观字段允许并行更新；其他数值、形状、效果与价格严格验证。
 for item in configuration.get("items", {}).values():
  for key in ["icon", "name", "description"]: item.erase(key)
 return JSON.stringify(configuration).sha256_text()
