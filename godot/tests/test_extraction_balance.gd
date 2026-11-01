extends SceneTree
const Game = preload("res://scripts/game_model.gd")
const Navigation = preload("res://tools/extraction_navigation.gd")
const Battle = preload("res://scripts/battle_model.gd")
var checks := 0
var failures: Array = []
var battles := 0

func _init() -> void:
 test_navigation_graph()
 test_fixed_budgets()
 test_departure_preserves_growth()
 test_pressure_rules()
 test_inventory_values()
 test_genuine_runs()
 print("EXTRACTION BALANCE TESTS: %d checks, %d genuine battles, %d failures" % [checks, battles, failures.size()])
 for failure in failures: printerr("FAIL: ", failure)
 quit(0 if failures.is_empty() else 1)

func check(condition: bool, label: String) -> void:
 checks += 1
 if not condition: failures.append(label)

func profile(level: int, ids: Array, seed_value: int):
 var m = Game.new("")
 m.rng.seed = seed_value
 for id in ids:
  m.state.ownedCharacters[id] = m.default_character()
  m.state.ownedCharacters[id].level = level
 m.set_team(ids)
 m.extraction.state().unlockedDifficulty = 5
 return m

func test_fixed_budgets() -> void:
 var m = profile(1, ["ember", "zeph"], 912300)
 var adult = profile(10, ["kaldi", "ayla", "gus"], 912300)
 for difficulty in range(6):
  check(m.extraction.start_run(difficulty).success, "budget fixture start")
  check(adult.extraction.start_run(difficulty).success, "mature budget fixture start")
  var prior_hp := 0.0
  var prior_atk := 0.0
  for act in range(1,4):
   # Isolated configuration fixtures, not claimed as played/unlocked progress.
   m.extraction.run().act = act
   m.extraction.run().node = 4
   adult.extraction.run().act = act
   adult.extraction.run().node = 4
   m.extraction._generate_encounter("boss")
   adult.extraction._generate_encounter("boss")
   var a: Dictionary = m.extraction.prepare_battle().config
   var z: Dictionary = adult.extraction.prepare_battle().config
   check(a.scaleMult == z.scaleMult, "fixed budget independent of player team")
   check(a.enemies == z.enemies, "same RNG chooses same boss regardless of team")
   check(float(a.scaleMult.hpMod) >= prior_hp and float(a.scaleMult.atkMod) >= prior_atk, "later act monotone budgets")
   prior_hp = a.scaleMult.hpMod
   prior_atk = a.scaleMult.atkMod
   var b = Battle.new(m.catalog)
   check(m.extraction.start_battle(b).success, "bound actual engine")
   var enemy: Dictionary = b.state.enemies[0]
   var base: Dictionary = m.catalog.EnemyData[enemy.dataId].baseStats
   var final_boss_factor := 1.15 if act == 3 and enemy.isBoss else 1.0
   check(enemy.maxHp == int(base.hp * a.scaleMult.hpMod * final_boss_factor), "HP budget and final boss factor applied exactly once")
   check(enemy.stats.atk == int(base.atk * a.scaleMult.atkMod * final_boss_factor), "attack budget and final boss factor applied exactly once")
   check(enemy.stats.spd <= 145, "enemy speed remains bounded")
  m.extraction.retreat()
  adult.extraction.retreat()

func test_inventory_values() -> void:
 var m = Game.new("")
 var x = m.extraction
 var rarities: Dictionary = {}
 for id in x.data.items:
  var item: Dictionary = x.item_def(id)
  check(int(item.width) >= 1 and int(item.height) >= 1, "positive dimensions " + id)
  check(int(item.width) <= 6 and int(item.height) <= 5, "item fits bag by design " + id)
  check(int(item.value) > 0, "positive price " + id)
  check(int(item.rarity) >= 0 and int(item.rarity) <= 5, "known rarity " + id)
  rarities[int(item.rarity)] = true
 check(rarities.size() == 6, "six supported rarities have actual items")

func test_genuine_runs() -> void:
 for level in [1,5,10]:
  var ids: Array = ["ember","zeph"] if level == 1 else ["kaldi","ayla","gus"]
  for rank in [0,5]:
   for sample in range(6):
    var seed_value := 919000 + sample
    var first := actual_run(level,ids,rank,seed_value)
    var repeat := actual_run(level,ids,rank,seed_value)
    check(first == repeat, "deterministic genuine result lv%d rank%d seed%d" % [level,rank,seed_value])

func actual_run(level: int, ids: Array, rank: int, seed_value: int) -> Dictionary:
 var m = profile(level,ids,seed_value)
 var x = m.extraction
 check(x.start_run(rank).success,"actual expedition starts")
 var rounds := 0
 var acts := 0
 var safety := 0
 for guard in range(500):
  if not x.active(): break
  if not x.growth_choices().is_empty():
   check(x.choose_growth(x.growth_choices()[0].choiceId).success,"choose actual earned growth")
   continue
  match str(x.run().phase):
   "route":
    var target: String = Navigation.next_room(x,"shortest")
    check(not target.is_empty(),"map navigation finds legal target")
    if target.is_empty(): break
    check(x.choose_route(target).success,"choose actual adjacent map room")
   "battle":
    var b = Battle.new(m.catalog)
    var started: Dictionary = x.start_battle(b)
    check(started.success,"start genuine combat")
    if not started.success: break
    while b.state.phase not in ["victory","defeat"]: b.auto_step()
    battles += 1
    rounds += int(b.state.turn)
    safety += int(str(b.state.reason).contains("上限"))
    check(x.settle_battle(started.config,b.state).success,"settle genuine combat")
   "room": check(x.advance_room().success,"advance cleared room")
   "boss_exit":
    acts += 1
    if int(x.run().act) == 3: check(x.extract().success,"finite third-act exit")
    else: check(x.continue_act().success,"carry party into next act")
 check(not x.active(),"run terminates within bounded decisions")
 check(safety == 0,"no battle action-limit termination")
 check(acts <= 3,"three-act endpoint respected")
 var expected_level:=level
 var expected_exp:int=x.state().lastRun.get("expEarned",0)
 while expected_level<10 and expected_exp>=m.exp_to_next_level(expected_level):
  expected_exp-=m.exp_to_next_level(expected_level);expected_level+=1
 for id in ids:
  check(int(m.state.ownedCharacters[id].level)==expected_level,"run level follows actually awarded battle XP")
  check(int(m.state.ownedCharacters[id].exp)==(0 if expected_level==10 else expected_exp),"run XP conserved without extra levels")
 return {"outcome":x.state().lastRun.get("outcome","error"),"rounds":rounds,"acts":acts,"safety":safety}

func test_departure_preserves_growth() -> void:
 for level in [1,5,10]:
  var m = profile(level,["kaldi","ayla","gus"],912399)
  for constellation in [0,6]:
   for id in ["kaldi","ayla","gus"]:
    m.state.ownedCharacters[id].constellation = constellation
   var raw: Array = m.battle_party(false)
   var before: Dictionary = m.state.duplicate(true)
   var departure: Array = m.extraction.departure_party()
   check(m.state == before,"mode snapshot preserves original save")
   for unit in departure:
    check(unit.permanentGrowth==m.growth_snapshot(unit.id),"permanent growth snapshot preserves bonuses")
    unit.erase("permanentGrowth")
   check(departure == raw,"all original player stats and identity preserved")
   for i in range(departure.size()):
    check(departure[i].stats == raw[i].stats,"no level/gear/critical/speed compression")
    check(departure[i].skills == raw[i].skills,"owned skills retained")
    check(departure[i].constellation == constellation,"constellation retained")

func test_pressure_rules() -> void:
 var m = profile(5,["kaldi","ayla","gus"],913333)
 for rank in range(6):
  var b = Battle.new(m.catalog)
  b.start({"isExtraction":true,"difficulty":rank,"enemies":["boss_flame_lord"],"scaleMult":{"hpMod":1000.0,"atkMod":0.01,"defMod":1.0,"spdMod":1.0},"seed":77331}, m.extraction.departure_party())
  var boss: Dictionary = b.state.enemies[0]
  # Isolated mechanic fixtures, not a simulated win or balance result.
  b.state.turn = 15
  check(is_equal_approx(b.boss_enrage_mult(boss),1.0),"enrage waits through round15")
  b.state.turn = 16
  check(is_equal_approx(b.boss_enrage_mult(boss),1.05 if rank >= 3 else 1.0),"explicit rank3 enrage starts round16")
  b.state.turn = 25
  check(is_equal_approx(b.boss_enrage_mult(boss),1.5 if rank >= 3 else 1.0),"explicit rank3 enrage cap")
  b.state.turn = 1
  var target: Dictionary = b.state.allies[0]
  target.currentHp = int(target.maxHp)-200
  var before := int(target.currentHp)
  b._heal(target,target,100,"mechanic_fixture",false,"status")
  check(int(target.currentHp)-before == 100,"full friendly healing retained at all ranks")
  # Fresh natural combat from configured stalemate fixture tests the deadline.
  b.start({"isExtraction":true,"difficulty":rank,"enemies":["boss_flame_lord"],"scaleMult":{"hpMod":1000.0,"atkMod":0.01,"defMod":1.0,"spdMod":1.0},"seed":77331}, m.extraction.departure_party())
  while b.state.phase not in ["victory","defeat"]: b.auto_step()
  check(b.state.phase == "defeat" and b.state.reason == "战区封锁，行动失败","stalemate ends through stated rule")
  check(int(b.state.turn) == 40,"exactly forty full rounds")

func test_navigation_graph() -> void:
 # Navigation-only graph fixtures: do not count these as played rooms or battle wins.
 for seed_value in range(1289000,1289016):
  for policy in ["shortest","poi","completionist"]:
   var m = profile(1,["ember","zeph"],seed_value)
   var x = m.extraction
   check(x.start_run(0).success,"graph fixture starts")
   var arrived := false
   for step in range(100):
    var target: String = Navigation.next_room(x,policy)
    check(not target.is_empty(),"navigation graph has a next step")
    if target.is_empty(): break
    var map: Dictionary = x.run().map
    check(x._has_edge(map.edges,map.currentRoomId,target),"navigation uses connected edge")
    if target == map.bossRoomId:
     check(map.bossUnlocked,"navigation respects boss gate")
     check(int(map.explored)>= (17 if policy=="completionist" else (10 if policy=="poi" else 6)),"navigation satisfies exploration policy")
     arrived = true
     break
    map.currentRoomId = target
    for room in map.rooms:
     if room.id == target and not room.visited:
      room.visited = true
      room.cleared = true
      map.explored += 1
    map.bossUnlocked = int(map.explored)>=int(map.requiredExploration)
   check(arrived,"navigation reaches boss without infinite backtracking")
   x.retreat()
