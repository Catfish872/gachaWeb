extends SceneTree
## Loot-only experiment. Never creates or settles a battle; all rewards are conditional.
const Game = preload("res://scripts/game_model.gd")
var rng := RandomNumberGenerator.new()
var pools := {}
var catalog := {}
var loot_weights := {}
var masks := {}
var packing_checks := 0
var report := {"scope":"V6 unified gold; conditional standardized loot generation only, not a prediction of the 19-room map. No combat, survival, growth choice or playtime claims. Actual-map economics are in extraction-v6-holdout.json. Collection bag uses hindsight packing (density or collection priority), not default autopick; bitmask placement cross-checked against core.","seed":739192,"groups":[],"footprints":[],"collection":[]}
func _init() -> void:
 rng.seed = 739192
 var game = Game.new("")
 var ex = game.extraction
 ex.start_run(0)
 catalog = ex.data.items
 report.sourceHash = FileAccess.get_sha256("res://scripts/extraction_model.gd")
 report.dataHash = FileAccess.get_sha256("res://data/extraction.json")
 for rarity in range(6):
  var values := []; var areas := []; var density := []
  for d in ex.data.items.values():
   if int(d.rarity) != rarity: continue
   values.append(d.value); areas.append(d.width*d.height); density.append(float(d.value)/(d.width*d.height))
  report.footprints.append({"rarity":rarity,"count":values.size(),"value":summary(values),"cells":summary(areas),"valuePerCell":summary(density)})
 for risk in [0,3,5]:
  for act in [1,2,3]:
   for quality in [0,1,2]:
    ex.run().act = act; ex.run().difficulty = risk
    var w: Array = ex.data.rarityWeightsByAct[act-1].duplicate()
    var k: Dictionary = ex.data.lootEconomy
    w[3] += k.riskPurpleWeight*risk+k.qualityPurpleWeight*quality
    w[4] += k.riskGoldWeight*risk+k.qualityGoldWeight*quality
    w[5] += k.riskRedWeight*risk+k.qualityRedWeight*quality
    loot_weights["%d_%d_%d" % [risk,act,quality]] = w
    var boss_sets := []; var ids := []; var values := []; var cells := []; var counts := [0,0,0,0,0,0]; var gold_containers := 0; var red_containers := 0
    for sample in range(1500):
     ex.run().containers = []
     ex._container("simulation",4 if quality == 2 else 3,quality,["珠宝","贵金属","王室遗物","奇珍","遗迹珍藏"] if quality == 1 else [])
     var boss_set := []; var gold := false; var red := false
     for item in ex.containers()[0].items:
      var d = ex.item_def(item.itemId)
      ids.append(item.itemId); boss_set.append(item.itemId); counts[int(d.rarity)] += 1; values.append(ex.item_value(item)); cells.append(d.width*d.height)
      gold = gold or d.rarity >= 4; red = red or d.rarity == 5
     boss_sets.append(boss_set)
     gold_containers += int(gold); red_containers += int(red)
    pools["%d_%d_%d" % [risk,act,quality]] = boss_sets if quality == 2 else ids
    report.groups.append({"risk":risk,"act":act,"quality":quality,"draws":ids.size(),"rarityCounts":counts,"meanValue":summary(values).mean,"meanCells":summary(cells).mean,"containerGoldChance":gold_containers/1500.0,"containerRedChance":red_containers/1500.0})
 print("LOOT_GROUPS_DONE")
 # Standardized offer budget, not map-policy prediction: 18 ordinary + 4 boss items/act,
 # plus guarded vault 45% x 6 items. Every encountered fight assumed won.
 for scenario in range(8):
  var risk := 0 if scenario < 4 else 3
  for exit_act in [1 if scenario % 4 < 2 else 3]:
   var policy := "collection_first" if scenario % 2 else "value_density"
   var seen_checks := {10:[],30:[],100:[]}; var checkpoints := {10:[],30:[],100:[]}; var reds := []; var golds := []; var offered_cells := []; var retained_value := []
   for cohort in range(40):
    var collection := {}; var seen := {}
    for run_index in range(1,101):
     var offer := []
     for act in range(1,exit_act+1):
      for draw in range(18): offer.append(draw_id(risk,act,0))
      for draw in range(4): offer.append(draw_id(risk,act,2, (4 if act == 3 else 3) if draw == 3 else 0))
      if rng.randf() < 0.45:
       for draw in range(6): offer.append(draw_id(risk,act,1))
     var total_cells := 0; var red_count := 0; var gold_count := 0
     for id in offer:
      seen[id] = true
      var d = ex.item_def(id); total_cells += int(d.width*d.height); red_count += int(d.rarity == 5); gold_count += int(d.rarity >= 4)
     offered_cells.append(total_cells); reds.append(red_count); golds.append(gold_count)
     offer.sort_custom(func(a,b):
      if policy == "collection_first" and collection.has(a) != collection.has(b): return not collection.has(a)
      var da = ex.item_def(a); var db = ex.item_def(b)
      return float(da.value)/(da.width*da.height) > float(db.value)/(db.width*db.height))
     var packed := []; var value := 0; var occupied := 0
     for id in offer:
      var placement := place_mask(id,occupied)
      if cohort == 0 and run_index == 1:
       var item = ex._make_item(id)
       var actual: bool = ex._place(packed,item,Vector2i(6,5))
       if actual != (placement != 0): push_error("packing equivalence failed"); quit(1); return
       if actual:
        var size: Vector2i = ex._size(item)
        var actual_mask := 0
        for y in range(item.y,item.y+size.y):
         for x in range(item.x,item.x+size.x): actual_mask |= 1 << (y*6+x)
        if placement != actual_mask: push_error("packing coordinates failed"); quit(1); return
       packing_checks += 1
      if placement != 0:
       occupied |= placement
       collection[id] = true; value += ex.item_value({"itemId":id,"appraisalRisk":risk})
     retained_value.append(value)
     if checkpoints.has(run_index):
      checkpoints[run_index].append(collection.size()); seen_checks[run_index].append(seen.size())
   print("COLLECTION_DONE risk=",risk," exit=",exit_act)
   var no_gold := golds.count(0)/float(golds.size())
   report.collection.append({"risk":risk,"exitAct":exit_act,"policy":policy,"successfulRuns":4000,"cohorts":40,"offeredUnique10":summary(seen_checks[10]),"offeredUnique30":summary(seen_checks[30]),"offeredUnique100":summary(seen_checks[100]),"distinct10":summary(checkpoints[10]),"distinct30":summary(checkpoints[30]),"distinct100":summary(checkpoints[100]),"offeredCells":summary(offered_cells),"offeredRed":summary(reds),"retainedValueOptimistic":summary(retained_value),"noGoldOfferChance":no_gold,"threeNoGoldIndependent":pow(no_gold,3)})
 report.packingEquivalenceChecks = packing_checks
 var file = FileAccess.open("res://validation/extraction-v6-loot-economy.json",FileAccess.WRITE)
 file.store_string(JSON.stringify(report,"  ")); file.close()
 print("LOOT_ECONOMY_COMPLETE groups=",report.groups.size()," collection=",report.collection.size())
 quit()
func draw_id(risk:int,act:int,quality:int,floor_rarity:int=0) -> String:
 var w: Array = loot_weights["%d_%d_%d" % [risk,act,quality]]
 var total := 0.0
 for value in w: total += value
 var target := rng.randf()*total
 var rarity := 0
 for i in range(6):
  target -= w[i]
  if target <= 0: rarity = maxi(i,floor_rarity); break
 var key := "%d_%d" % [quality,rarity]
 if not pools.has(key):
  var pool := []; var preferred := []
  for id in catalog:
   if int(catalog[id].rarity) != rarity: continue
   pool.append(id)
   if catalog[id].get("category","") in ["珠宝","贵金属","王室遗物","奇珍","遗迹珍藏"]: preferred.append(id)
  pools[key] = preferred if quality == 1 and not preferred.is_empty() else pool
 var pool: Array = pools[key]
 return str(pool[rng.randi_range(0,pool.size()-1)])
func place_mask(id:String,occupied:int) -> int:
 if not masks.has(id):
  var candidates := []
  var d: Dictionary = catalog[id]
  for rotated in [false,true]:
   var w: int = d.height if rotated else d.width
   var h: int = d.width if rotated else d.height
   for y in range(6-h):
    for x in range(7-w):
     var mask := 0
     for dy in range(h):
      for dx in range(w): mask |= 1 << ((y+dy)*6+x+dx)
     candidates.append(mask)
  masks[id] = candidates
 for mask in masks[id]:
  if (occupied & int(mask)) == 0: return int(mask)
 return 0
func summary(values:Array) -> Dictionary:
 values.sort()
 var total := 0.0
 for value in values: total += float(value)
 return {"mean":total/values.size(),"min":values[0],"p10":values[int(values.size()*.1)],"median":values[int(values.size()*.5)],"p90":values[mini(values.size()-1,int(values.size()*.9))],"max":values[-1]}
