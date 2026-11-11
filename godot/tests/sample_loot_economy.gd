extends SceneTree
const Game = preload("res://scripts/game_model.gd")
func _initialize() -> void: call_deferred("sample")
func sample() -> void:
 var baseline: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("/tmp/loot_baseline.json"))
 var output := []
 for theme in ["ruins","thunder_city"]:
  for risk in [0,3,5]:
   for quality in [0,2]:
    for version in ["before","after"]:
     var g = Game.new(""); g.rng.seed = 71031; var ex = g.extraction; ex.start_run()
     if version=="before": ex.data=baseline.duplicate(true)
     ex.run().environmentOrder=[theme,"forest","sanctum"]; ex.run().act=3; ex.run().environmentOrder[2]=theme; ex.run().difficulty=risk
     var total := 0; var count := 0; var high := 0; var supplies := 0; var histogram := {}
     for n in range(6000):
      ex.run().containers=[]; ex._container("sample",4,quality,[],quality==2)
      for item in ex.run().containers.back().items:
       var d: Dictionary = ex.item_def(item.itemId)
       total += ex.item_value(item); count+=1
       if d.rarity>=4: high+=1
       if d.kind=="consumable": supplies+=1
       histogram[item.itemId]=true
     output.append({"theme":theme,"risk":risk,"quality":quality,"version":version,"containers":6000,"value":total,"items":count,"high":high,"supplies":supplies,"distinct":histogram.size()})
 var f := FileAccess.open("/tmp/loot_economy_samples.json",FileAccess.WRITE); f.store_string(JSON.stringify(output,"  ")); f.close()
 print("LOOT ECONOMY sampled ",output.size()*6000," actual containers")
 quit()
