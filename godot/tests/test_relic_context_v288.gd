extends "res://tests/test_relic_optimizer_review_v250.gd"
## Small real-search reproductions, not the user's unavailable full inventory.
const Sets = preload("res://scripts/relic_sets.gd")
var report: Dictionary = {"scope":"Published 2.8.5 optimizer with legal reference-team repair; synthetic fixed inventory and explicitly conditional screenshot reconstruction.","cases":[],"panels":[]}

func make_game(team: Array) -> Variant:
	var game=Game.new("")
	game.rng.seed=288031
	for id in ["tiya","lumi","ayla"]: game.state.ownedCharacters[id]=game.default_character()
	for id in game.state.ownedCharacters: game.state.ownedCharacters[id].equippedRelics={}
	game.state.relics=[]
	game.state.team=team.duplicate()
	return game

func fixture(game) -> Array:
	var slots: Array=[]
	for index in range(5):
		var options: Array=[]
		var base: Dictionary=game.generate_relic(5,Optimizer.SLOTS[index],"")
		for set_id in (["wind_strings","wind_blades","ember_lantern"] if index<4 else [""]):
			var item: Dictionary=base.duplicate(true)
			var preferred: String="wind_blades" if index<2 else "ember_lantern"
			item.uid=("a_" if set_id==preferred else "z_")+str(index)+set_id
			item.setId=set_id
			ck(game._valid_relic(item),"valid fixed generated candidate "+item.uid)
			game.state.relics.append(item);options.append(item)
		slots.append(options)
	return slots

func designated(slots: Array, four: bool) -> Array:
	var result: Array=[]
	for index in range(5):
		var set_id: String=("wind_strings" if four else ("wind_blades" if index<2 else "ember_lantern")) if index<4 else ""
		for item in slots[index]:
			if item.setId==set_id: result.append(item)
	return result

func verify_search(game, id: String, slots: Array, label: String, bounds: bool=true, apply: bool=true) -> Dictionary:
	var state_before: String=JSON.stringify(game.state)
	var rng_before: int=game.rng.state
	var search=game.begin_best_relic_loadout(id)
	prepare(search)
	var exact: float=oracle(search,slots)
	if bounds:
		var retained: Array=[]
		for slot in range(5): retained.append(leaves(search,slot,search._tree_roots[slot]))
		check_leaf_bounds(search,retained)
		check_random_boxes(search,16)
	var result: Dictionary=finish(search)
	ck(result.done and result.provenOptimal,"certified exact completion "+label)
	ck(absf(float(result.lowerBound)-exact)<.000001,"raw inventory exhaustive oracle "+label)
	ck(JSON.stringify(game.state)==state_before and game.rng.state==rng_before,"preview preserves live state and RNG "+label)
	ck(result.referenceTeam.size()<=3 and result.referenceTeam.has(id),"legal reference size and actor "+label)
	var actual: Array=[]
	search._reference(result.after.stats,result.after.ownerEffects)
	for unit in search._battle.state.allies: actual.append(unit.id)
	if id in ["tiya","lumi"]: ck(actual.size()==result.referenceTeam.size(),"battle reference has declared member count "+label)
	var team_before: Array=game.state.team.duplicate()
	var gold_before: int=int(game.state.resources.gold)
	if apply and result.canApply:
		var applied: Dictionary=game.apply_relic_loadout(result)
		ck(applied.success,"real atomic apply "+label+" "+str(applied.get("error","")))
		ck(game.state.team==team_before and int(game.state.resources.gold)==gold_before,"apply preserves team and gold "+label)
		ck(game.relic_loadout_snapshot(id).relicUids==result.after.relicUids,"apply matches exact displayed choice "+label)
	report.cases.append({"label":label,"referenceTeam":result.referenceTeam,"candidateCounts":result.candidateCounts,"highestRarities":result.highestRarities,"exact":exact,"found":result.lowerBound,"sets":result.after.counts,"uids":result.after.relicUids,"before":result.before.stats,"after":result.after.stats})
	return result

func test_equal_attributes() -> void:
	for entry in [
		{"name":"Lumi active without Tiya","team":["lumi","ember","zeph"],"expected":["lumi","ember","zeph"],"duo":false},
		{"name":"Lumi active with Tiya","team":["tiya","lumi","ayla"],"expected":["tiya","lumi","ayla"],"duo":true},
		{"name":"Lumi off full party preserves late actual synergy","team":["ember","zeph","tiya"],"expected":["lumi","tiya","ember"],"duo":true},
		{"name":"Lumi off party does not pull owned off-party Tiya","team":["ember","zeph","ayla"],"expected":["lumi","ember","zeph"],"duo":false}]:
		var game=make_game(entry.team)
		var slots: Array=fixture(game)
		var scorer=Optimizer.new(game,"lumi")
		var four: Dictionary=scorer.evaluate_loadout(designated(slots,true))
		var two: Dictionary=scorer.evaluate_loadout(designated(slots,false))
		ck(four.stats==two.stats,"equal stats 4pc and 22 "+entry.name)
		ck(four.objective>two.objective if entry.duo else is_equal_approx(four.objective,two.objective),"set synergy is conditional "+entry.name)
		var result: Dictionary=verify_search(game,"lumi",slots,entry.name)
		ck(result.referenceTeam==entry.expected,"exact reference selection "+entry.name)
		ck(int(result.after.counts.get("wind_strings",0))>=4 if entry.duo else int(result.after.counts.get("wind_blades",0))==2 and int(result.after.counts.get("ember_lantern",0))==2,"conditional equal-attribute recommendation "+entry.name)
		report.cases[-1].fourScore=four.objective;report.cases[-1].twoScore=two.objective

func test_eligibility() -> void:
	for mode in ["rarity","ownership"]:
		var game=make_game(["lumi","tiya","ember"])
		var slots: Array=fixture(game)
		var eligible: Array=slots.duplicate(true)
		if mode=="rarity":
			for index in range(4):
				for item in slots[index]:
					if item.setId=="wind_strings": item.rarity=4
				eligible[index]=slots[index].filter(func(item): return item.rarity==5)
		else:
			var item: Dictionary=slots[0][0]
			item.equippedBy="ember";game.state.ownedCharacters.ember.equippedRelics.helmet=item.uid
			eligible[0]=slots[0].filter(func(piece):return piece.equippedBy==null)
		var result: Dictionary=verify_search(game,"lumi",eligible,"explicit "+mode+" eligibility",false)
		ck(int(result.after.counts.get("wind_strings",0))<4,"unavailable full set not invented "+mode)
		if mode=="ownership": ck(game.state.ownedCharacters.ember.equippedRelics.helmet==slots[0][0].uid and slots[0][0].equippedBy=="ember","other character's gear remains equipped")
		else: ck(result.candidateCounts==[2,2,2,2,1],"per-slot highest rarity restriction is explicit")

func observed_item(game, uid: String, slot: String, set_id: String, level: int, main: String, values: Dictionary) -> Dictionary:
	var item: Dictionary={"uid":uid,"slotId":slot,"setId":set_id,"rarity":5,"level":level,"equippedBy":null,"mainStat":{},"subStats":[]}
	for candidate in game.catalog.RelicMainStatPool[slot]:
		if candidate.stat==main:item.mainStat=candidate.duplicate(true)
	for key in values:item.subStats.append({"stat":key,"name":key,"value":values[key]})
	ck(game._valid_relic(item),"valid screenshot transcription "+uid)
	return item

func test_partial_screenshot_inventory() -> void:
	var game=make_game(["tiya",null,null])
	var slots: Array=[]
	# Head/chest are declared generated stand-ins because the screenshots hide them.
	for slot in ["helmet","chest"]:
		var item: Dictionary=game.generate_relic(5,slot,"wind_blades")
		item.uid="declared_fixed_"+slot;slots.append([item]);game.state.relics.append(item)
	slots.append([
		observed_item(game,"shown_old_belt","belt","wind_blades",0,"atk_pct",{"cri_dmg":.042,"spd":4.,"hp_pct":.044,"def_pct":.06}),
		observed_item(game,"shown_new_belt","belt","flame_oath",25,"def_flat",{"energy_rate":.161,"def_pct":.122,"cri_dmg":.101,"spd":8.})])
	slots.append([
		observed_item(game,"shown_old_boots","boots","ember_lantern",0,"spd",{"def_pct":.039,"atk_flat":20.,"hp_pct":.054,"def_flat":27.}),
		observed_item(game,"shown_new_boots","boots","ember_lantern",0,"hp_pct",{"cri_rate":.032,"atk_pct":.054,"atk_flat":28.,"spd":2.})])
	slots.append([
		observed_item(game,"shown_old_necklace","necklace","wind_blades",0,"cri_rate",{"energy_rate":.071,"cri_dmg":.063,"def_flat":16.,"hp_pct":.038}),
		observed_item(game,"shown_new_necklace","necklace","ember_lantern",0,"cri_rate",{"atk_flat":33.,"hp_pct":.047,"def_pct":.037,"atk_pct":.049})])
	for index in range(2,5):game.state.relics.append_array(slots[index])
	for options in slots:
		var item: Dictionary=options[0];item.equippedBy="tiya"
		game.state.ownedCharacters.tiya.equippedRelics[item.slotId]=item.uid
	var result: Dictionary=verify_search(game,"tiya",slots,"visible three slots with declared fixed synthetic head/chest")
	report.cases[-1].inventory=slots
	ck(float(result.after.objective)>=float(result.before.objective),"partial fixture never downgrades reference objective")

func action_trace(search, stats: Dictionary, effects: Array) -> Array:
	var reference: Dictionary=search._reference(stats,effects)
	search._prepare_skills(reference.actor,reference.target)
	var energy: int=0;var cooldown: int=0;var result: Array=[]
	for step in range(6):
		for index in search._auto_skill_order:
			var skill: Dictionary=search._skills[index]
			if skill.type=="ultimate" and energy<int(skill.cost):continue
			if skill.type=="skill" and cooldown>0:continue
			energy=0 if skill.type=="ultimate" else mini(100,energy+int(skill.gain))
			cooldown=maxi(0,int(skill.cooldown)-1) if skill.type=="skill" else maxi(0,cooldown-1)
			result.append({"action":skill.type,"energyAfter":energy});break
	return result

func test_displayed_panels() -> void:
	for constellation in [0,2,6]:
		var game=make_game(["tiya",null,null])
		game.state.ownedCharacters.tiya.constellation=constellation
		var search=Optimizer.new(game,"tiya")
		var old_stats: Dictionary=game.computed_stats("tiya")
		old_stats.merge({"hp":2033,"maxHp":2033,"atk":381,"def":136,"spd":122.,"cri":.305,"critRate":.305,"criDmg":1.82,"critDmg":1.82,"energyRate":.132},true)
		var new_stats: Dictionary=old_stats.duplicate(true)
		new_stats.merge({"hp":1983,"maxHp":1983,"atk":449,"def":322,"cri":.337,"critRate":.337,"criDmg":1.816,"critDmg":1.816,"energyRate":.222},true)
		var effects: Array=[{"type":"windPierceOwner","value":.20}]
		var before: float=search._evaluate(old_stats,effects)
		var after: float=search._evaluate(new_stats,[])
		var without_threshold: Dictionary=new_stats.duplicate(true);without_threshold.energyRate=.132
		var attributes_only: float=search._evaluate(without_threshold,[])
		var old_trace: Array=action_trace(search,old_stats,effects)
		var new_trace: Array=action_trace(search,new_stats,[])
		ck(old_trace[-1].action!="ultimate" and new_trace[-1].action=="ultimate","shown energy crosses sixth-action threshold C"+str(constellation))
		ck(after>before and after>attributes_only,"shown recommendation increases conditional reference C"+str(constellation))
		report.panels.append({"constellationAssumption":constellation,"referenceTeam":["tiya"],"before":before,"after":after,"gain":after/before-1.,"newWithOldEnergy":attributes_only,"oldTrace":old_trace,"newTrace":new_trace,"caveat":"Shown rounded panel; maintained 35% armor, three neutral DEF100 targets; no blessings or hidden teammates, not full save reconstruction."})

func run() -> void:
	random.seed=288031
	test_equal_attributes()
	test_eligibility()
	test_partial_screenshot_inventory()
	test_displayed_panels()
	report.checks=checks;report.failures=failures;report.auditedLeaves=audited_leaves;report.auditedBoxes=audited_boxes;report.minimumBoundMargin=minimum_margin
	DirAccess.make_dir_recursive_absolute("res://validation/v288-relic-context")
	var file=FileAccess.open("res://validation/v288-relic-context/report.json",FileAccess.WRITE)
	if file:file.store_string(JSON.stringify(report,"  "));file.close()
	print("RELIC CONTEXT V288: %d checks; %d leaves; %d boxes; %d failures"%[checks,audited_leaves,audited_boxes,failures.size()])
	quit(0 if failures.is_empty() else 1)
