extends "res://tools/simulate_extraction.gd"
## Actual battles: starter reinvests 3,840 extraction credits in three medkits.
func _init() -> void:
 for path in ["tools/simulate_extraction.gd","tools/simulate_extraction_reinvestment.gd","tools/extraction_navigation.gd","scripts/game_model.gd","scripts/extraction_model.gd","scripts/battle_model.gd","data/extraction.json","data/catalog.json"]:
  input_hashes[path] = simulation_hash(path)
 var rows: Array = []
 var aggregate: Array = []
 for prepared in [false,true]:
  var starter: Dictionary = PROFILES[0].duplicate(true)
  starter.id = "starter_medkits_preserved" if prepared else "starter_found_supplies_preserved"
  starter.supplies = prepared
  for policy in ["shortest","poi","completionist"]:
   var group: Array = []
   for sample in range(16):
    var row := simulate(starter,0,3,policy,1297000+sample)
    group.append(row)
    rows.append(row)
   aggregate.append(summarize(group))
 for path in input_hashes:
  if simulation_hash(path) != input_hashes[path]: errors.append("input changed: "+path)
 var report := {"method":"Real battles, paired lv1 two-character profiles, no relic/level/constellation changes; second profile starts with wallet fixture to buy three medkits at 3840. Both use actual core plan_smart_loot/apply_smart_loot confirmed positive-value proposals (existing equipment and consumables protected, outgoing loot retained in container), consume below75% health, all other rules inherited. Departure RNG state is restored to pre-purchase fixture state, making initial maps identical despite UID generation during purchases. Thereafter route/loot RNG evolves naturally. Tests preparation with bag-space tradeoff; no fabricated wins, health, battle seeds or run loot.","inputHashes":input_hashes,"totalRuns":rows.size(),"totalBattles":total_battles,"errors":errors,"aggregate":aggregate,"rows":rows}
 var file := FileAccess.open("res://validation/extraction-map-reinvestment.json",FileAccess.WRITE)
 file.store_string(JSON.stringify(report,"\t"))
 print(JSON.stringify(aggregate))
 print("REINVESTMENT %d runs %d battles %d errors" % [rows.size(),total_battles,errors.size()])
 quit(0 if errors.is_empty() else 1)

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
    var relic: Dictionary = m.generate_relic(4, slot.id)
    must(m.add_relic(relic), "fixture generated relic")
    must(m.equip_relic(relic.uid,id), "fixture equip relic")
    for upgrade in range(10): must(m.upgrade_relic(relic.uid), "fixture upgrade relic")
 var x = m.extraction
 if trial_hp > 0: x.data.balance.rankHp[rank] = trial_hp
 if trial_atk > 0: x.data.balance.rankAtk[rank] = trial_atk
 x.state().unlockedDifficulty = rank
 var departure_rng_state = m.rng.state
 var supply_cost := 0
 if profile.get("supplies", false):
  x.state().credits = 10000
  for supply in range(3):
   var bought: Dictionary = x.buy_supply("medkit")
   if must(bought, "buy departure medkit"):
    supply_cost += int(bought.cost)
    var uid: String = x.state().stash.back().uid
    must(x.bring_item(uid), "bring purchased medkit")
 var row := {"vaultsGenerated":0,"vaultsEntered":0,"vaultsWon":0,"rarityByRoom":{},"seenIds":[],"carriedIds":[],"moves":0,"roomsExplored":0,"profile":profile.id,"rank":rank,"exitAct":exit_act,"policy":policy,"seed":seed_value,"outcome":"error","battles":0,"rounds":0,"maxBattleRounds":0,"actions":0,"safetyEnds":0,"sealEnds":0,"maxHitPct":0.0,"maxOpeningHitPct":0.0,"value":0,"lostValue":0,"items":0,"replacements":0,"bosses":0,"deathAct":0,"reveals":0,"redFound":0,"supplyCost":supply_cost,"netValue":-supply_cost}
 m.rng.state = departure_rng_state
 if not must(x.start_run(rank), "start run"): return row
 for room in x.map_state().rooms: row.vaultsGenerated += int(room.type == "vault")
 for guard in range(500):
  if not x.active(): break
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

func loot_room(x, row: Dictionary) -> void:
 for container in x.containers():
  for old_item in container.items:
   if old_item.revealed: continue
   var reveal: Dictionary = x.reveal_next(container.id)
   if not must(reveal,"smart-policy reveal"): return
   if old_item.itemId not in row.seenIds: row.seenIds.append(old_item.itemId)
   var room_kind: String = x.run().room.type
   if not row.rarityByRoom.has(room_kind): row.rarityByRoom[room_kind] = [0,0,0,0,0,0]
   row.rarityByRoom[room_kind][int(reveal.definition.rarity)] += 1
   row.reveals += 1
   row.redFound += int(int(reveal.definition.rarity)==5)
  for attempt in range(4):
   var plan: Dictionary = x.plan_smart_loot(container.id)
   if not plan.get("success",false): break
   if not must(x.apply_smart_loot(container.id,plan.planHash),"confirm core smart packing"): return
   row.replacements += int(not plan.removed.is_empty())
   for item in x.run().bag.duplicate(true):
    if x.item_def(item.itemId).kind == "equipment" and x.run().equipped.size()<3:
     must(x.equip_item(item.uid),"smart-policy equip")
   use_supplies(x)
 use_supplies(x)
