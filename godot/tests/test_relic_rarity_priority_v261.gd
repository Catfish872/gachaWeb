extends SceneTree
const Game=preload("res://scripts/game_model.gd")
const Optimizer=preload("res://scripts/relic_optimizer.gd")
var checks:=0
var failures:=0
func ck(value:bool,label:String)->void:
	checks+=1
	if not value: failures+=1;printerr("FAIL ",label)
func piece(game,uid:String,slot:String,rarity:int,level:int)->Dictionary:
	var item:Dictionary=game.generate_relic(rarity,slot,"")
	item.uid=uid;item.level=level;item.subStats=[]
	return item
func finish(game)->Dictionary:
	return game.preview_best_relic_loadout("ember")
func _init()->void:
	var game=Game.new("")
	game.state.relics=[]
	game.state.ownedCharacters.ember.equippedRelics={}
	var low:Dictionary=piece(game,"low","chest",4,20)
	var high:Dictionary=piece(game,"high","chest",5,0)
	ck(game.add_relic(low).success and game.add_relic(high).success,"two valid rarities added")
	ck(game.equip_relic("low","ember").success,"strong four-star equipped")
	var previous:Dictionary=game.state.duplicate(true)
	var plan:Dictionary=finish(game)
	ck(plan.provenOptimal and plan.after.relicUids.chest=="high","higher star selected despite lower current strength")
	ck(plan.improvement<0 and plan.after.objective<plan.before.objective,"actual negative reference difference retained")
	ck(plan.canApply and plan.usefulChange,"rarity upgrade may be applied")
	ck(game.state==previous,"preview keeps inventory and wallet unchanged")
	ck(game.apply_relic_loadout(plan).success,"negative-score high-star plan applies")
	ck(game.state.ownedCharacters.ember.equippedRelics.chest=="high","high star physically equipped")
	ck(game.state.resources==previous.resources,"auto loadout spends no currency")
	plan=finish(game)
	ck(not plan.canApply,"same optimum does not request redundant change")
	# Same highest rarity still uses the original actual-performance objective.
	var stronger:Dictionary=piece(game,"stronger","chest",5,2)
	ck(game.add_relic(stronger).success,"second high-star candidate added")
	plan=finish(game)
	ck(plan.after.relicUids.chest=="stronger" and plan.improvement>0,"same rarity optimizes current attributes")
	# Other characters' higher-star equipment is excluded before rarity choice.
	var four:Dictionary=piece(game,"own_four","helmet",4,0)
	var other:Dictionary=piece(game,"other_five","helmet",5,25)
	ck(game.add_relic(four).success and game.add_relic(other).success,"ownership candidates added")
	ck(game.equip_relic("other_five","zeph").success,"teammate keeps five-star helmet")
	plan=finish(game)
	ck(plan.after.relicUids.helmet=="own_four" and plan.highestRarities[0]==4,"fallback uses highest available without stealing")
	var three:Dictionary=piece(game,"only_three","boots",3,0)
	ck(game.add_relic(three).success,"three-star fallback added")
	plan=finish(game)
	ck(plan.after.relicUids.boots=="only_three","three-star used when best available")
	ck(not plan.after.relicUids.has("belt") and not plan.after.relicUids.has("necklace"),"empty inventory slots remain empty")
	var expected:Dictionary=plan.after.relicUids.duplicate(true)
	game.state.relics.reverse()
	plan=finish(game)
	ck(plan.after.relicUids==expected and plan.provenOptimal,"inventory order does not affect highest-star result")
	var empty=Game.new("");empty.state.relics=[];empty.state.ownedCharacters.ember.equippedRelics={}
	plan=finish(empty)
	ck(plan.provenOptimal and not plan.canApply and plan.improvement==0,"empty inventory is stable")
	print("V261_RARITY_PRIORITY checks=",checks," failures=",failures)
	quit(1 if failures else 0)
