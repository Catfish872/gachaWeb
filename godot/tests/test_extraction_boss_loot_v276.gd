extends SceneTree
const GameModel = preload("res://scripts/game_model.gd")
var failed := 0
func check(ok: bool, label: String) -> void:
	if ok: print("PASS: " + label)
	else: failed += 1; push_error("FAIL: " + label)
func _initialize() -> void:
	call_deferred("run_checks")
func run_checks() -> void:
	var model = GameModel.new("")
	var ex = model.extraction
	check(ex.start_run().success,"start boss reward fixture")
	check(is_equal_approx(float(ex.data.lootEconomy.bossGoldWeight),1.0) and is_equal_approx(float(ex.data.lootEconomy.bossRedWeight),0.15),"boss-only bonus is gold 1 red 0.15")
	var source := FileAccess.get_file_as_string("res://scripts/extraction_model.gd")
	check(source.contains('_container("首领保险柜", 4, 2, [], true)'),"boss settlement keeps one four-item quality-two container")
	check(source.contains('boss_reward: bool = false') and source.contains('if boss_reward:\n\t\tweights[4]') and source.contains('weights[5] = float(weights[5]) + float(economy.get("bossRedWeight", 0.15))'),"bonus gated by explicit boss flag")
	var before: Dictionary = ex.run().duplicate(true)
	ex._container("ordinary fixture",3,1)
	var ordinary: Dictionary = ex.run().containers.back().duplicate(true)
	var after_rng: String = ex.run().rngState
	ex.state().run = before.duplicate(true)
	ex.data.lootEconomy.bossGoldWeight = 999.0
	ex.data.lootEconomy.bossRedWeight = 999.0
	ex._container("ordinary fixture",3,1)
	check(ex.run().containers.back()==ordinary and ex.run().rngState==after_rng,"ordinary box and RNG ignore boss bonuses")
	for key in ["qualityPurpleWeight","qualityGoldWeight","qualityRedWeight","riskPurpleWeight","riskGoldWeight","riskRedWeight","bossGoldWeight","bossRedWeight"]: ex.data.lootEconomy[key]=0.0
	ex.data.rarityWeightsByAct=[[1,0,0,0,0,0],[1,0,0,0,0,0],[1,0,0,0,0,0]]
	for act in [1,2,3]:
		ex.run().act=act
		ex._container("boss floor fixture",4,2,[],true)
		var box: Dictionary = ex.run().containers.back()
		check(box.items.size()==4 and box.width==6 and box.height==8,"boss keeps four items and 6x8 bounds act "+str(act))
		check(int(ex.item_def(box.items[3].itemId).rarity)==(4 if act==3 else 3),"last draw floor act "+str(act))
	var items: Array=[]
	for id in ["royal_scepter","dragon_egg","quantum_server","void_fossil"]: items.append(ex._make_item(id))
	var greedy: Array=[]
	for item in items: ex._place(greedy,item,Vector2i(6,8))
	check(greedy.size()==3,"known four-shape counterexample exercises fallback")
	var rng: String=ex.run().rngState
	var packed: Array=ex._repack_boss_reward(items)
	check(packed.size()==4 and ex.run().rngState==rng,"fallback retains four items without RNG")
	for i in range(packed.size()):
		check(packed[i].uid==items[i].uid and packed[i].itemId==items[i].itemId,"fallback preserves draw identity/order "+str(i))
		check(ex._fits(packed,packed[i],Vector2i(6,8)),"fallback fits without overlap "+str(i))
	quit(1 if failed else 0)
