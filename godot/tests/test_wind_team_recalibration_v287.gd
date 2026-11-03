extends "res://tests/test_wind_team_balance_v286.gd"
const ScoreOptimizer = preload("res://scripts/relic_optimizer.gd")
const BASELINE_PATH := "res://validation/v285-balance/data_catalog.json.before"
const NEW_VARIANTS := ["fire","wind_current","wind_legacy","wind_lumi_atk22","wind_tiya_atk22","wind_tiya_voyager","wind_transition_current","wind_transition_legacy"]
var baseline_catalog: Dictionary = {}
func source_hashes() -> Dictionary:
 var result: Dictionary = super.source_hashes()
 for path in ["tests/test_wind_team_recalibration_v287.gd","validation/v285-balance/data_catalog.json.before"]:
  result[path]=FileAccess.get_sha256("res://"+path)
 return result
func make_game(basis: Dictionary, constellation: int, variant: String):
 var game=super.make_game(basis,constellation,variant)
 if variant in ["wind_legacy","wind_transition_legacy"]:
  if baseline_catalog.is_empty():baseline_catalog=JSON.parse_string(FileAccess.get_file_as_string(BASELINE_PATH))
  game.catalog=baseline_catalog.duplicate(true)
  check(not game.catalog.CharacterData.lumi.has("windArmorDamageDeepening") or is_equal_approx(float(game.catalog.CharacterData.lumi.windArmorDamageDeepening),0.20),"old catalog original Lumi20")
 if variant in ["wind_transition_current","wind_transition_legacy"]:
  for item in game.state.relics:
   if item.equippedBy in ["tiya","lumi"] and item.slotId in ["belt","boots"]:item.setId=""
 return game
func early_basis(seed_value: int) -> Dictionary:
 var game=Game.new("")
 game.rng.seed=seed_value
 var result:Dictionary={}
 for id in ["tiya","lumi","ayla"]:
  var items:Array=[]
  for slot in SLOTS:
   var item:Dictionary=game.generate_relic(5,slot,"")
   check(game._valid_relic(item) and int(item.level)==0,"legal early five-star+0")
   items.append(item)
  result[id]=items
 return result
func expected_sets(game, basis: Dictionary, seed_value: int, constellation: int) -> Array:
 var result:Array=[]
 for context in [{"enemyCount":3,"enemyDefense":100.0,"otherSpeed":100.0},{"enemyCount":1,"enemyDefense":1771.0,"otherSpeed":285.0},{"enemyCount":1,"enemyDefense":287788.0,"otherSpeed":579.0}]:
  for id in ["tiya","lumi"]:
   var scorer=ScoreOptimizer.new(game,id,context)
   var scores:Dictionary={}
   var best_score:=-INF
   var best_set:=""
   var alternatives:Array=game.catalog.RelicSets.keys()
   alternatives.append("atk22")
   for set_id in alternatives:
    var items:Array=basis[id].duplicate(true)
    for index in range(items.size()):
     items[index].uid="expected_"+str(set_id)+"_"+str(index)
     items[index].setId=""
     if index<4:items[index].setId=("wind_blades" if index<2 else "ember_lantern") if set_id=="atk22" else set_id
    var evaluation:Dictionary=scorer.evaluate_loadout(items)
    scores[set_id]=float(evaluation.objective)
    if float(evaluation.objective)>best_score:best_score=float(evaluation.objective);best_set=set_id
   var signature:="wind_blades" if id=="tiya" else "wind_strings"
   check(float(scores[signature])+0.00001>=best_score,"signature expected best "+id+" C"+str(constellation)+" seed"+str(seed_value)+" def"+str(context.enemyDefense)+" best="+best_set)
   result.append({"seed":seed_value,"constellation":constellation,"character":id,"context":context,"scores":scores,"bestSet":best_set,"signature":signature,"scope":"Six-action maintained-armor optimizer expectation; exact crit expectation, zero blessings, teammate equipment fixed. Own legal action policy per set; no battle RNG or initiative-dependent teammate crit redistribution."})
 return result
func run() -> void:
 started_ms=Time.get_ticks_msec()
 var hashes_before:=source_hashes()
 var expected:Array=[]
 for context in CONTEXTS:
  var basis:=make_basis(int(context.seed))
  for constellation in [0,6]:
   for variant in NEW_VARIANTS:
    var game=make_game(basis,constellation,variant)
    if variant=="wind_current":expected.append_array(expected_sets(game,basis,int(context.seed),constellation))
    fixtures.append({"seed":context.seed,"constellation":constellation,"variant":variant,"team":game.state.team.duplicate(),"party":game.battle_party(false),"relics":game.state.relics.duplicate(true),"deepening":float(game.catalog.CharacterData.lumi.get("windArmorDamageDeepening",0.20)),"windSets":{"wind_blades":game.catalog.RelicSets.wind_blades.duplicate(true),"wind_strings":game.catalog.RelicSets.wind_strings.duplicate(true)}})
    for floor_number in FLOORS:
     var plan:=blessings(game,int(floor_number),variant=="fire")
     var row:Dictionary={"seed":context.seed,"enemy":context.enemy,"constellation":constellation,"variant":variant,"floor":floor_number,"blessingTotal":plan.total,"blessingRarities":plan.rarities,"blessingCounts":plan.counts}
     row.pressure=pressure(game,plan.effects,int(floor_number),context)
     row.output=output_window(game,plan.effects,int(floor_number),context)
     rows.append(row)
    print("RECALIBRATION_CONTEXT ",context.seed," C",constellation," ",variant," elapsed_ms=",Time.get_ticks_msec()-started_ms)
 var paired:Dictionary={}
 for row in rows:paired[str(row.seed)+"_"+str(row.constellation)+"_"+str(row.floor)+"_"+str(row.variant)]=row
 for row in rows:
  if row.variant!="wind_current":continue
  var old:Dictionary=paired[str(row.seed)+"_"+str(row.constellation)+"_"+str(row.floor)+"_wind_legacy"]
  var ratio:=float(row.output.outgoing)/float(old.output.outgoing)
  check(ratio>=0.97 and ratio<=1.03,"full wind within +/-3 percent "+str(row.seed)+" C"+str(row.constellation)+" F"+str(row.floor)+" ratio="+str(ratio))
 var early:Array=[]
 for context in CONTEXTS:
  var basis:=early_basis(int(context.seed))
  for variant in ["wind_transition_current","wind_transition_legacy"]:
   var game=make_game(basis,0,variant)
   for id in game.state.team:game.state.ownedCharacters[id].level=1
   for floor_number in [1,10]:
    early.append({"seed":context.seed,"variant":variant,"floor":floor_number,"level":1,"constellation":0,"gearLevel":0,"blessingTotal":0,"party":game.battle_party(false),"output":output_window(game,[],floor_number,context)})
 var hashes_after:=source_hashes()
 check(hashes_before==hashes_after,"recalibration source hashes stable")
 check(rows.size()==192 and early.size()==8,"complete recalibration contexts")
 var report:Dictionary={"scope":"Paired full-build and two-piece transition comparisons. All legacy actors use the complete immutable pre-change v2.8.4 catalog, including original Lumi20 deepening and both original four-piece effects. Current catalog uses declared candidate. Same bounded pressure and six-round diagnostic methodology as v286. Early cases are Lv1/C0/legal five-star+0 two-piece gear, zero blessings, six-round output only; floor1/10 reference enemy defense, not climbed routes.","rows":rows,"early":early,"expectedSets":expected,"fixtures":fixtures,"checks":checks,"failures":failures,"elapsedMs":Time.get_ticks_msec()-started_ms,"sourceHashesBefore":hashes_before,"sourceHashesAfter":hashes_after}
 DirAccess.make_dir_recursive_absolute("res://validation/v287-team-balance")
 var file=FileAccess.open("res://validation/v287-team-balance/report.json",FileAccess.WRITE)
 if file:file.store_string(JSON.stringify(report,"  "))
 else:check(false,"write recalibration report")
 print("WIND_TEAM_RECALIBRATION_V287 ",checks," checks / ",failures.size()," failures; ",rows.size()," contexts, ",early.size()," early, elapsed_ms=",Time.get_ticks_msec()-started_ms)
 quit(1 if not failures.is_empty() else 0)
