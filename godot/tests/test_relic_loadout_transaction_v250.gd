extends SceneTree
const Game=preload("res://scripts/game_model.gd")
var checks:=0
var failures:=0
func ck(value:bool,label:String)->void:
	checks+=1
	if not value:failures+=1;printerr("FAIL ",label)
func fixture():
	var game=Game.new("")
	for slot in game.catalog.RelicSlots:
		var item:Dictionary=game.generate_relic(5,slot.id,"flame_oath")
		item.uid="fit_"+slot.id
		item.mainStat={"stat":"atk_flat","name":"攻击","base":150.0,"perLevel":0.0}
		item.subStats=[]
		game.add_relic(item)
	return game
func _init()->void:
	var game=fixture()
	var before:Dictionary=game.state.duplicate(true)
	var rng_before:int=game.rng.state
	var plan:Dictionary=game.preview_best_relic_loadout("ember")
	ck(plan.success and plan.provenOptimal and plan.canApply,"exact pure plan available")
	ck(game.state==before and game.rng.state==rng_before,"whole inventory preview pure")
	game.save_blocked=true
	var failed:Dictionary=game.apply_relic_loadout(plan)
	ck(not failed.success and game.state==before,"save failure rolls back every owner and resource")
	game.save_blocked=false
	var applied:Dictionary=game.apply_relic_loadout(plan)
	ck(applied.success and applied.costGold==0,"atomic plan applies at zero cost")
	ck(game.state.resources==before.resources and game.state.stats.totalGoldSpent==before.stats.totalGoldSpent,"resources and spending counters unchanged")
	ck(game.rng.state==rng_before,"apply consumes no randomness")
	for item in game.state.relics:
		ck(item.level==0 and item.equippedBy=="ember" and game.state.ownedCharacters.ember.equippedRelics[item.slotId]==item.uid,"bidirectional complete loadout")
	ck(game.valid_save(game.state),"applied full loadout remains valid")
	var after:Dictionary=game.state.duplicate(true)
	ck(not game.apply_relic_loadout(plan).success and game.state==after,"double apply stale plan preserves successful loadout")
	for mutation in ["level","owner","slot","character","set"]:
		game=fixture();plan=game.preview_best_relic_loadout("ember")
		match mutation:
			"level":game.state.relics[0].level=1
			"owner":
				game.state.relics[0].equippedBy="zeph"
				game.state.ownedCharacters.zeph.equippedRelics.helmet=game.state.relics[0].uid
			"slot":game.active_slot=2
			"character":game.state.ownedCharacters.ember.level=2
			"set":game.state.relics[0].setId="star_watch"
		before=game.state.duplicate(true)
		ck(not game.apply_relic_loadout(plan).success and game.state==before,"stale "+mutation+" rejected atomically")
	game=fixture()
	game.equip_relic("fit_helmet","zeph")
	plan=game.preview_best_relic_loadout("ember")
	ck(not plan.after.relicUids.values().has("fit_helmet"),"optimizer protects teammate equipment")
	ck(game.apply_relic_loadout(plan).success and game.get_relic("fit_helmet").equippedBy=="zeph","atomic apply leaves teammate owner unchanged")
	var blocked:Dictionary=game.preview_best_relic_loadout("ember",{"includeEquippedByOthers":true})
	ck(not blocked.success and blocked.done and not blocked.canApply,"unsupported teammate inclusion remains explicit")
	game=fixture()
	var search=game.begin_best_relic_loadout("ember")
	before=game.state.duplicate(true)
	var cancelled:Dictionary=search.cancel()
	ck(not game.apply_relic_loadout(cancelled).success and game.state==before,"cancelled plan cannot mutate state")
	game=fixture()
	ck(game.extraction.start_run().success,"raid before external equipment change")
	var frozen:Array=game.extraction.run().party.duplicate(true)
	plan=game.preview_best_relic_loadout("ember")
	ck(game.apply_relic_loadout(plan).success and game.extraction.run().party==frozen,"apply preserves raid frozen growth and party")
	game=fixture()
	var prepared:Dictionary=game.prepare_abyss()
	frozen=game.battle_party(true)
	plan=game.preview_best_relic_loadout("ember")
	ck(game.apply_relic_loadout(plan).success and game.battle_party(true)==frozen and game.state.abyss.rogue.activeEncounter==prepared.config,"apply preserves signed encounter party and rewards")
	explicit_current_recommendation()
	fill_empty_without_primary_loss()
	print("RELIC LOADOUT TRANSACTIONS V250: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)

func partial_fixture(context:Dictionary={})->Dictionary:
	var game=Game.new("")
	var sets:Array=game.catalog.RelicSets.keys()
	for slot in game.catalog.RelicSlots:
		for index in range(sets.size()):
			var item:Dictionary=game.generate_relic(5,slot.id,sets[index])
			item.uid="partial_%s_%d"%[slot.id,index]
			item.mainStat={"stat":"atk_flat","name":"攻击","base":100.0+index*3.0,"perLevel":0.0}
			item.subStats=[{"stat":"cri_rate","name":"暴击率","value":.04*(5-index)}]
			game.state.relics.append(item)
	var search=game.begin_best_relic_loadout("ember",context)
	var guard:=0
	# Step the real cooperative state machine to its first complete candidate.
	# This avoids CPU-speed dependence in the partial-result contract test.
	while search.preview().phase not in ["seed","done","error"] and guard<100000:
		match search.preview().phase:
			"scan","prune":search._scan_step()
			"prepare":search._prepare_step()
		guard+=1
	if search.preview().phase=="seed":search._seed_step()
	var plan:Dictionary=search.preview().duplicate(true)
	ck(plan.canApply and not plan.provenOptimal and not plan.done,"genuine intermediate candidate remains unproven")
	return {"game":game,"search":search,"plan":plan}

func explicit_current_recommendation()->void:
	var partial:=partial_fixture()
	var game=partial.game
	var plan:Dictionary=partial.plan
	var plan_before:Dictionary=plan.duplicate(true)
	var before:Dictionary=game.state.duplicate(true)
	var rng_before:int=game.rng.state
	ck(not game.apply_relic_loadout(plan).success and game.state==before,"default rejects unproven recommendation")
	partial.search.cancel()
	game.save_blocked=true
	ck(not game.apply_relic_loadout(plan,true).success and game.state==before,"explicit unproven apply save failure restores whole state")
	game.save_blocked=false
	ck(game.apply_relic_loadout(plan,true).success,"explicit approval applies displayed intermediate candidate after stopping search")
	ck(plan==plan_before and not plan.provenOptimal and plan.context.allowUnproven==false,"approval keeps context fingerprint and proof fields intact")
	ck(game.state.resources==before.resources and game.rng.state==rng_before,"explicit current recommendation stays zero cost and RNG free")
	ck(not game.apply_relic_loadout(plan,true).success,"explicit current recommendation replay rejected")
	partial=partial_fixture({"allowUnproven":true})
	game=partial.game;before=game.state.duplicate(true)
	ck(not game.apply_relic_loadout(partial.plan).success and game.state==before,"context flag alone grants no approval")
	for mutation in ["level","owner","slot","character","set","context","uid","hash","mapping"]:
		partial=partial_fixture();game=partial.game;plan=partial.plan
		match mutation:
			"level":game.state.relics[0].level=1
			"owner":game.state.relics[0].equippedBy="zeph"
			"slot":game.active_slot=2
			"character":game.state.ownedCharacters.ember.level=2
			"set":game.state.relics[0].setId="star_watch"
			"context":plan.context.enemyDefense+=1
			"uid":game.state.relics[0].uid+="_changed"
			"hash":plan.fingerprint="stale_hash"
			"mapping":plan.after.relicUids.helmet="missing_item"
		before=game.state.duplicate(true)
		ck(not game.apply_relic_loadout(plan,true).success and game.state==before,"explicit approval preserves stale "+mutation+" rejection")

func fill_empty_without_primary_loss()->void:
	var game=Game.new("")
	for slot in game.catalog.RelicSlots:
		var item:Dictionary=game.generate_relic(5,slot.id,"")
		item.uid="empty_fill_"+slot.id
		item.mainStat={"stat":"hp_flat" if slot.id in ["helmet","belt","necklace"] else "def_flat","name":"生存属性","base":100.0,"perLevel":0.0}
		item.subStats=[]
		game.state.relics.append(item)
	var before:Dictionary=game.state.duplicate(true)
	var plan:Dictionary=game.preview_best_relic_loadout("ember")
	ck(plan.provenOptimal and plan.canApply and plan.usefulChange and plan.filledEmptySlots==5,"empty slots accept useful HP DEF at tied main objective")
	ck(is_equal_approx(plan.before.objective,plan.after.objective) and plan.after.stats.maxHp>plan.before.stats.maxHp and plan.after.stats.def>plan.before.stats.def,"empty fill improves real attributes without reducing primary score")
	game.save_blocked=true
	ck(not game.apply_relic_loadout(plan).success and game.state==before,"fill-empty failure rolls whole outfit back")
	game.save_blocked=false
	ck(game.apply_relic_loadout(plan).success and game.equipped_relics("ember").size()==5 and game.state.resources==before.resources,"useful tied primary fill applies atomically at zero cost")
	var stable:Dictionary=game.preview_best_relic_loadout("ember")
	ck(not stable.canApply and stable.before.relicUids==stable.after.relicUids,"already filled tied outfit stays in place")
