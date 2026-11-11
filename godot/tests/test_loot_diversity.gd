extends SceneTree
const Game = preload("res://scripts/game_model.gd")
var checks := 0
var failures := 0
func ck(ok: bool, label: String) -> void:
 checks += 1
 if not ok: failures += 1; printerr("FAIL ", label)
func _initialize() -> void: call_deferred("run_tests")
func run_tests() -> void:
 var g = Game.new(""); g.rng.seed = 310
 var ex = g.extraction
 ck(ex.start_run().success, "run begins")
 ex.run().environmentOrder = ["thunder_city","ruins","forest"]
 ex._generate_map(); ex.run().phase = "room"
 var count := 0
 for id in ex.data.items:
  var d: Dictionary = ex.item_def(id)
  if not str(id).begins_with("general_"): continue
  count += 1
  var a: Dictionary = ex.item_def(d.economyAnchor)
  ck(not d.has("variantOf"), "independent candidate " + id)
  for key in ["rarity","width","height","kind","category","effects","heal","energy"]:
   ck(d.get(key)==a.get(key), "functional bucket " + id + "/" + key)
  ck(d.value != a.value and d.value > 0, "distinct positive price " + id)
 ck(count==201, "201 independent common additions")
 for n in range(40):
  var medical_id: String = ex._environment_loot_id("insulin_case", ["补给","疗愈用品"])
  ck(ex._matches_loot_categories(ex.item_def(medical_id), ["补给","疗愈用品"]), "medical cupboard category remains sensible")
 for id in ex.data.items:
  var d: Dictionary = ex.item_def(id)
  if d.get("lootTheme", "") != "thunder_city": continue
  var seen := {}
  for n in range(160): seen[ex._environment_loot_id(d.economyAnchor)] = true
  ck(seen.has(id) and seen.size()>=2, "city independent candidate " + id)
 ex.run().environmentOrder = ["forest","ruins","thunder_city"]
 ex._generate_map(); ex.run().phase = "room"
 for n in range(150):
  ex.run().containers=[]; ex._container("test",4,2)
  for item in ex.run().containers.back().items:
   ck(not ex.item_def(item.itemId).has("lootTheme"), "no city-only leak")
 ex.run().environmentOrder = ["thunder_city","ruins","forest"]
 ex._generate_map(); ex.run().phase = "room"; ex.run().bag=[]; ex.run().containers=[]
 ex._container("test",3,0)
 var box: Dictionary = ex.run().containers.back()
 var ids := []
 for item in box.items: ids.append(item.itemId)
 var frozen: Dictionary = g.state.duplicate(true)
 g.state = g._normalize(JSON.parse_string(JSON.stringify(g.state)))
 for bi in range(ex.run().containers.size()):
  var restored: Dictionary = ex.run().containers[bi]
  var original: Dictionary = frozen.extraction.run.containers[bi]
  ck(restored.id == original.id and restored.items.size() == original.items.size(), "container identity retained")
  for ii in range(restored.items.size()):
   for key in ["itemId","uid","x","y","rotated","revealed"]:
    ck(restored.items[ii][key] == original.items[ii][key], "issued loot stable "+key)
 ck(ex.run().rngState == frozen.extraction.run.rngState, "issued rng stable after normalization")
 box = ex.run().containers.back()
 for item in box.items.duplicate(true):
  ck(ex.reveal_next(box.id).success, "reveal works")
  ck(ex.take_item(box.id,item.uid).success, "pickup works")
 ck(ex.run().bag.size()==ids.size(), "all instances retained")
 ex.run().bag=[]
 var med: Dictionary = ex._make_item("general_ration_5_1"); med.revealed=true
 ex.run().bag.append(med)
 ex.run().party[0].currentHp=1; ex.run().party[0].energy=0
 ck(ex.use_item(med.uid).success, "new red medicine usable")
 ck(ex.run().party[0].currentHp>1 and ex.run().party[0].energy==55, "red medicine effects preserved")
 ex.run().bag=[]; ex.run().equipped=[]
 var weapon: Dictionary = ex._make_item("general_blade_1"); weapon.revealed=true
 ex.run().bag.append(weapon)
 ck(ex.equip_item(weapon.uid).success, "new physical equipment usable")
 for duplicate_id in ["blade","general_blade_2","general_blade_3"]:
  var other: Dictionary = ex._make_item(duplicate_id); other.revealed=true
  ex.run().bag.append(other)
  ck(not ex.equip_item(other.uid).success, "same economic family cannot stack "+duplicate_id)
  ex.run().bag.erase(other)
 ck(ex._same_equipment_family(weapon, ex._make_item("blade")), "original and redesigned gear share family")
 print("LOOT DIVERSITY ", checks, " checks ", failures, " failures")
 quit(1 if failures else 0)
