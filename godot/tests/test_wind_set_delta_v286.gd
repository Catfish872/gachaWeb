extends "res://tests/test_wind_relic_audit_v285.gd"
func run()->void:
 for constellation in [0,6]:
  var game=Game.new("");game.rng.seed=286
  for id in ["tiya","lumi"]:
   game.state.ownedCharacters[id]=game.default_character();game.state.ownedCharacters[id].level=10;game.state.ownedCharacters[id].constellation=constellation
  game.state.team=["tiya","lumi"]
  var basis:Array=gear(game,25)
  var two:Array=loadout(basis,"atk22");var four:Array=loadout(basis,"wind_strings")
  var scorer=Optimizer.new(game,"lumi")
  var a:Dictionary=scorer.evaluate_loadout(two);var b:Dictionary=scorer.evaluate_loadout(four)
  check(a.stats==b.stats,"Lumi four set equals attack22 stats C"+str(constellation))
  check(b.objective>a.objective,"Lumi four set team objective improves C"+str(constellation))
  game.state.team=["lumi"];scorer=Optimizer.new(game,"lumi")
  a=scorer.evaluate_loadout(two);b=scorer.evaluate_loadout(four)
  check(is_equal_approx(a.objective,b.objective),"Lumi solo without innate followups ties C"+str(constellation))
 print("WIND SET DELTA V286: %d checks, %d failures"%[checks,failures.size()]);quit(1 if not failures.is_empty() else 0)
