extends SceneTree
const Game = preload("res://scripts/game_model.gd")
var checks := 0
var failures := 0
func check(ok:bool,label:String) -> void:
 checks += 1
 if not ok: failures += 1; print("FAIL ",label)
func _init() -> void:
 var game = Game.new("")
 var ex = game.extraction
 game.rng.seed = 739192
 check(ex.start_run(0).success,"free entry remains available with zero credits")
 var counts := [0,0,0,0,0,0]
 for d in ex.data.items.values():
  counts[int(d.rarity)] += 1
  check(d.width >= 1 and d.height >= 1 and d.width*d.height <= 9,"bounded footprint")
  check(d.value > 0,"every common item has resale value")
  if d.has("buyPrice"): check(d.buyPrice > d.value,"no purchase resale arbitrage")
 for count in counts: check(count == 16,"sixteen items each rarity")
 var knobs: Dictionary = ex.data.get("lootEconomy",{})
 for act in range(1,4):
  for risk in range(6):
   var w: Array = ex.data.rarityWeightsByAct[act-1].duplicate()
   w[3] += knobs.get("riskPurpleWeight",2)*risk
   w[4] += knobs.get("riskGoldWeight",1)*risk
   w[5] += knobs.get("riskRedWeight",0.05)*risk
   var total := 0.0
   for value in w: total += value
   var ordinary := float(w[5])/total
   var rich: float = (float(w[5])+knobs.get("qualityRedWeight",0.7))/(total+knobs.get("qualityPurpleWeight",3)+knobs.get("qualityGoldWeight",2)+knobs.get("qualityRedWeight",0.7))
   check(ordinary > 0 and ordinary < .012,"ordinary jackpot nonzero and scarce")
   check(rich > ordinary,"guarded cache red probability better")
   ex.run().act = act; ex.run().difficulty = risk
   for sample in range(20):
    ex.run().containers = []
    ex._container("boss",4,2)
    var items: Array = ex.containers()[0].items
    check(items.size() == 4,"no reward lost to container packing")
    check(ex.item_def(items[-1].itemId).rarity >= (4 if act == 3 else 3),"boss guarantees meaningful offer")
    var occupied := {}
    for item in items:
     var size: Vector2i = ex._size(item)
     for y in range(item.y,item.y+size.y):
      for x in range(item.x,item.x+size.x):
       var cell := "%d,%d" % [x,y]
       check(not occupied.has(cell),"no overlapping loot")
       occupied[cell] = true
 print("LOOT_ECONOMY_TEST checks=",checks," failures=",failures)
 quit(1 if failures else 0)
