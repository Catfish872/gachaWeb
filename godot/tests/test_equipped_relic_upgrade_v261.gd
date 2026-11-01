extends SceneTree
const Game=preload("res://scripts/game_model.gd")
var checks:=0
var failures:=0
func ck(value:bool,label:String)->void:
	checks+=1
	if not value:failures+=1;printerr("FAIL ",label)
func fixture():
	var game=Game.new("")
	game.random_source=func():return 0.37
	for slot in game.catalog.RelicSlots:
		var relic:Dictionary=game.generate_relic(5,str(slot.id),"flame_oath")
		relic.uid="equipped_"+str(slot.id)
		game.add_relic(relic)
		game.equip_relic(str(relic.uid),"ember")
	var spare:Dictionary=game.generate_relic(4,"helmet","")
	spare.uid="spare";game.add_relic(spare)
	var teammate:Dictionary=game.generate_relic(5,"boots","")
	teammate.uid="teammate";game.add_relic(teammate);game.equip_relic("teammate","zeph")
	return game
func _init()->void:
	var game=fixture()
	var before:Dictionary=game.state.duplicate(true)
	var quote:Dictionary=game.equipped_relic_upgrade_preview("ember")
	ck(quote.success and quote.uids.size()==5 and quote.cost==40000,"five level-zero pieces cost original 40000")
	ck(game.state==before,"preview is read only")
	var single=Game.new("");single.state=game.state.duplicate(true);single.random_source=func():return 0.37
	for uid in quote.uids:ck(single.upgrade_relic_to_max(uid).success,"existing single max succeeds")
	var result:Dictionary=game.upgrade_equipped_relics_to_max("ember")
	ck(result.success and result.count==5 and result.totalCost==40000,"batch success exact count and cost")
	ck(game.state.relics==single.state.relics,"batch main and random substats match unchanged single upgrade")
	ck(game.state.resources==single.state.resources and game.state.stats==single.state.stats,"same wallet and expenditure as five single upgrades")
	ck(game.get_relic("spare").level==0 and game.get_relic("teammate").level==0,"only current character equipped relics upgrade")
	ck(game.computed_stats("ember")!=Game.new("").computed_stats("ember"),"computed equipment stats available immediately")
	ck(game.valid_save(game.state),"upgraded save valid")
	before=game.state.duplicate(true)
	ck(not game.upgrade_equipped_relics_to_max("ember").success and game.state==before,"repeat does not spend")
	ck(game.equipped_relic_upgrade_preview("ember").cost==0,"max preview costs zero")
	game=fixture();game.get_relic("equipped_helmet").level=25;game.get_relic("equipped_boots").level=24
	quote=game.equipped_relic_upgrade_preview("ember")
	ck(quote.uids.size()==4 and quote.cost==24560,"mixed levels and already-max ignored")
	game.state.resources.gold=quote.cost-1;before=game.state.duplicate(true)
	var rng_before:int=game.rng.state
	ck(not game.upgrade_equipped_relics_to_max("ember").success and game.state==before and game.rng.state==rng_before,"insufficient funds preserves every item and all resources")
	game.state.resources.gold=quote.cost
	ck(game.upgrade_equipped_relics_to_max("ember").success and game.state.resources.gold==0,"exact balance works")
	game=fixture();game.random_source=Callable();game.save_blocked=true;before=game.state.duplicate(true);rng_before=game.rng.state
	ck(not game.upgrade_equipped_relics_to_max("ember").success and game.state==before and game.rng.state==rng_before,"save failure rolls back full batch and RNG")
	game=Game.new("");before=game.state.duplicate(true)
	ck(game.equipped_relic_upgrade_preview("ember").equippedCount==0,"empty equipped preview")
	ck(not game.upgrade_equipped_relics_to_max("ember").success and game.state==before,"empty upgrade has no mutations")
	ck(not game.upgrade_equipped_relics_to_max("unknown").success and game.state==before,"unknown character has no mutations")
	check_rarity_caps()
	print("EQUIPPED RELIC UPGRADE V261: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)

func check_rarity_caps()->void:
	for rarity in [3,4,5]:
		var game=Game.new("")
		game.random_source=func():return 0.37
		var relic:Dictionary=game.generate_relic(rarity,"helmet","")
		relic.uid="cap_%d" % rarity;game.add_relic(relic);game.equip_relic(relic.uid,"ember")
		var cap:int={3:15,4:20,5:25}[rarity]
		var cost:int={3:3300,4:5400,5:8000}[rarity]
		ck(game.relic_level_cap(game.get_relic(relic.uid))==cap,"rarity cap %d" % rarity)
		ck(game.relic_upgrade_cost_to_max(relic.uid)==cost,"original per-level fee sum %d" % rarity)
		ck(game.upgrade_relic_to_max(relic.uid).success and game.get_relic(relic.uid).level==cap,"single max obeys rarity %d" % rarity)
		var previous:Dictionary=game.state.duplicate(true)
		ck(not game.upgrade_relic(relic.uid).success and game.state==previous,"single +1 respects cap %d" % rarity)
		ck(not game.upgrade_relic_to_max(relic.uid).success and game.state==previous,"single max repeat respects cap %d" % rarity)
		game.get_relic(relic.uid).level=0
		ck(game.upgrade_equipped_relics_to_max("ember").success and game.get_relic(relic.uid).level==cap,"batch respects rarity %d" % rarity)
		if rarity<5:
			game.get_relic(relic.uid).level=25
			previous=game.state.duplicate(true)
			var stats:Dictionary=game.computed_stats("ember")
			ck(game.valid_save(game.state),"legacy +25 low-star save accepted %d" % rarity)
			ck(game.relic_upgrade_cost_to_max(relic.uid)==0,"legacy above-cap cost zero %d" % rarity)
			ck(not game.upgrade_equipped_relics_to_max("ember").success and game.state==previous,"legacy batch preserves level and stats %d" % rarity)
			ck(not game.upgrade_relic(relic.uid).success and game.state==previous,"legacy +1 blocked without mutation %d" % rarity)
			ck(not game.upgrade_relic_to_max(relic.uid).success and game.computed_stats("ember")==stats,"legacy max preserves attributes %d" % rarity)
