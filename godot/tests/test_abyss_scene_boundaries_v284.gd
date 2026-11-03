extends "res://tests/test_abyss_scenes_v284.gd"
func run()->void:
 for f in [10,20]:
  var g=fixture284(f);g.random_source=func():return .81
  var p:Dictionary=g.prepare_abyss();var b=Battle.new(g.catalog);b.start(p.config,g.battle_party(true));b.state.phase="victory"
  var result:Dictionary=g.finish_battle(p.config,b.state)
  ck(result.get("success",false),"real settlement "+str(f))
  ck(g.state.abyss.currentFloor==f+1 and g.state.abyss.rogue.sceneBlocks.has(str(f+1)),"boundary locks next scene before menu")
  ck(g.valid_save(JSON.parse_string(JSON.stringify(g.state))),"next scene post-settlement valid save")
 var g=fixture284();var before:Dictionary=g.state.duplicate(true);g.save_blocked=true
 ck(not g.prepare_abyss().success and g.state==before,"failed commit rolls back scene allocation")
 g=fixture284();var p:Dictionary=g.prepare_abyss();var bad:Dictionary=g.state.duplicate(true);bad.abyss.rogue.sceneBlocks["11"].background="res://invalid.png"
 ck(not g.valid_save(bad),"invalid scene backdrop rejected")
 print("ABYSS BOUNDARIES V284: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
