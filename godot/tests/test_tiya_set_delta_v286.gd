extends "res://tests/test_wind_relic_audit_v285.gd"
func run()->void:
 for constellation in [0,6]:
  var game=Game.new("");game.rng.seed=286
  for id in ["tiya","lumi"]:
   game.state.ownedCharacters[id]=game.default_character();game.state.ownedCharacters[id].level=10;game.state.ownedCharacters[id].constellation=constellation
  game.state.team=["tiya","lumi"]
  var basis:Array=gear(game,25);var scorer=Optimizer.new(game,"tiya")
  var two:Array=loadout(basis,"atk22");var four:Array=loadout(basis,"wind_blades")
  var a:Dictionary=scorer.evaluate_loadout(two);var b:Dictionary=scorer.evaluate_loadout(four)
  check(a.stats==b.stats,"Tiya four set equals attack22 stats C"+str(constellation))
  check(b.objective>a.objective,"Tiya four set improves reference objective C"+str(constellation))
  var candidates:Array=[]
  for slot in range(5):
   var entries:Array=[]
   for set_id in (["wind_blades","ember_lantern"] if slot<4 else [""]):
    var item:Dictionary=basis[slot].duplicate(true);item.uid="candidate_"+str(slot)+set_id;item.setId=set_id;game.state.relics.append(item);entries.append(item)
   candidates.append(entries)
  var search=Optimizer.new(game,"tiya");var exact:float=-INF
  for mask in range(16):
   var items:Array=[]
   for slot in range(4):items.append(candidates[slot][(mask>>slot)&1])
   items.append(candidates[4][0]);exact=maxf(exact,float(search.evaluate_loadout(items).objective))
  var result:Dictionary=finish(search)
  check(result.provenOptimal and absf(float(result.lowerBound)-exact)<.00001,"Tiya optimizer matches exact16 C"+str(constellation))
  check(int(result.after.counts.get("wind_blades",0))>=4,"equal attributes recommend full Tiya set C"+str(constellation))
 print("TIYA SET DELTA V286: %d checks, %d failures"%[checks,failures.size()]);quit(1 if not failures.is_empty() else 0)
