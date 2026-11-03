extends "res://tests/test_relic_context_v288.gd"
const Cycle = preload("res://scripts/relic_cycle.gd")
var role_rows: Array=[]
var kernel_rows: Array=[]
var maximum_cold_eval_us := 0

func test_modes_and_roles() -> void:
	for id in Game.new("").catalog.CharacterData:
		for constellation in [0,6]:
			var game=make_game([id,null,null])
			game.state.ownedCharacters[id]=game.default_character()
			game.state.ownedCharacters[id].constellation=constellation
			game.state.ownedCharacters[id].level=5
			var scorer=Optimizer.new(game,id)
			var opening=Optimizer.new(game,id,{"actions":6})
			ck(scorer._context.evaluation=="steady" and opening._context.evaluation=="opening","explicit opening separate from steady "+id)
			var stats: Dictionary=game.computed_stats(id)
			scorer._evaluation_cache.clear();Cycle.clear_cache()
			var start: int=Time.get_ticks_usec()
			var value: float=scorer._evaluate(stats,[])
			var elapsed: int=Time.get_ticks_usec()-start
			maximum_cold_eval_us=maxi(maximum_cold_eval_us,elapsed)
			var upper: float=scorer._evaluate(stats,[],true)
			ck(scorer._error.is_empty() and is_finite(value) and value>0.,"finite valid long-run role score "+id+str(constellation))
			ck(upper+.000001>=value,"steady LP bounds role "+id+str(constellation))
			if scorer._profile.type=="survival":
				ck(is_equal_approx(value,opening._evaluate(stats,[])),"static shield EHP is not divided by window "+id)
				ck(scorer._objective_label()=="施放自身护盾后的有效承伤","survival metric remains explicit "+id)
			else:
				var cycle: Dictionary=scorer.cycle_summary(stats,[])
				ck(cycle.success and float(cycle.residual)<1e-8,"exact cycle probabilities "+id)
				var total: float=0.
				for weight in cycle.skillWeights:total+=float(weight)
				ck(absf(total-1.)<1e-8,"action weights normalize "+id)
			role_rows.append({"id":id,"constellation":constellation,"score":value,"upper":upper,"coldEvalUs":elapsed})

func test_random_kernels() -> void:
	for entry in [
		{"id":"gus","c":0,"set":"thunder_hunt"},
		{"id":"gus","c":6,"set":"thunder_hunt"},
		{"id":"ember","c":6,"set":""},
		{"id":"ayla","c":0,"set":"aurora_prayer"},
		{"id":"tiya","c":0,"set":"thunder_hunt"},
		{"id":"selin","c":0,"set":"thunder_hunt"}]:
		var game=make_game([entry.id,null,null])
		game.state.ownedCharacters[entry.id]=game.default_character()
		game.state.ownedCharacters[entry.id].constellation=entry.c
		var items: Array=[]
		for slot in Optimizer.SLOTS:items.append(game.generate_relic(5,slot,entry.set))
		var scorer=Optimizer.new(game,entry.id)
		var snapshot: Dictionary=scorer.evaluate_loadout(items)
		var cycle: Dictionary=scorer.cycle_summary(snapshot.stats,snapshot.ownerEffects)
		ck(cycle.success,"stochastic renewal success "+entry.id+str(entry.c))
		var finite: Dictionary=Cycle.finite_weights(scorer._skills,scorer._transitions,scorer._auto_skill_order,4096,0)
		ck(finite.success,"independent forward expectation success "+entry.id)
		var maximum: float=0.
		for index in range(cycle.skillWeights.size()):maximum=maxf(maximum,absf(float(cycle.skillWeights[index])-float(finite.skillWeights[index])))
		ck(maximum<.004,"4096-action independent frequency converges to renewal "+entry.id+str(entry.c))
		ck(absf(float(cycle.auraUptime)-float(finite.auraUptime))<.004,"two-action aura coverage converges "+entry.id)
		ck(scorer._evaluate(snapshot.stats,snapshot.ownerEffects,true)+.000001>=float(snapshot.objective),"random energy cycle below LP "+entry.id)
		kernel_rows.append({"id":entry.id,"constellation":entry.c,"cycle":cycle,"finite4096":finite,"maximumFrequencyDifference":maximum})
		if entry.id=="tiya":
			for branches in scorer._transitions:
				for branch in branches:ck(int(branch.energy) in [0,4],"thunder energy once per action, not once per hit")
	# Exact hand-solvable energies, cap and post-ultimate event gain.
	var skills: Array=[{"type":"normal","gain":15,"cost":0,"cooldown":0},{"type":"skill","gain":20,"cost":0,"cooldown":3},{"type":"ultimate","gain":99,"cost":100,"cooldown":0}]
	var transitions: Array=[[{"p":1.,"energy":0}],[{"p":1.,"energy":0}],[{"p":1.,"energy":4}]]
	var base: Dictionary=Cycle.weights(skills,transitions,[2,1,0],0)
	for initial in [0,99,100]:
		var cycle: Dictionary=Cycle.weights(skills,transitions,[2,1,0],initial)
		ck(cycle.success and cycle.skillWeights==base.skillWeights,"declared deterministic recurrent cycle independent of initial "+str(initial))
		var model: Dictionary=Cycle._model(skills,transitions,[2,1,0])
		var after: Dictionary=Cycle._next(model,[100,2,0],2)
		var unpacked: Array=Cycle._unpack(after.keys()[0],model.stride)
		ck(unpacked[0]==4 and unpacked[1]==1 and unpacked[2]==1,"ultimate clears100 then adds4 and decrements cooldown")
		var capped: Dictionary=Cycle._next(model,[99,0,0],0)
		ck(Cycle._unpack(capped.keys()[0],model.stride)[0]==100,"normal energy addition caps at100")

func test_closed_classes_and_failures() -> void:
	# A 60% one-action class and 40% three-action class. Mixing cycle lengths
	# before class-normalization would give the wrong long-run answer.
	var skills: Array=[{"type":"ultimate","cost":100,"gain":0,"cooldown":0},{"type":"ultimate","cost":75,"gain":0,"cooldown":0},{"type":"ultimate","cost":50,"gain":0,"cooldown":0},{"type":"normal","cost":0,"gain":25,"cooldown":0}]
	var transitions: Array=[[{"p":1.,"energy":100}],[{"p":.6,"energy":100},{"p":.4,"energy":0}],[{"p":1.,"energy":0}],[{"p":1.,"energy":0}]]
	var cycle: Dictionary=Cycle.weights(skills,transitions,[0,1,2,3],75)
	ck(cycle.success and cycle.closedClasses==2,"multiple recurrent classes retained")
	for index in range(4):ck(absf(float(cycle.skillWeights[index])-float([.6,0.,.4/3.,.8/3.][index]))<1e-9,"absorption-weighted action rate "+str(index))
	ck(absf(float(cycle.auraUptime)-13./15.)<1e-9,"two-action aura in distinct cycle lengths")
	var low: Dictionary=Cycle.weights(skills,transitions,[0,1,2,3],0)
	ck(low.success and absf(float(low.skillWeights[0]))<1e-9,"initial state legitimately controls reachable class")
	for source in ["lumi","tiya"]:
		var game=make_game(["lumi","tiya",null])
		for sid in game.catalog.CharacterData[source].skills:
			if game.catalog.SkillData[sid].type!="ultimate":game.catalog.SkillData[sid].energyGain=0
		for slot in Optimizer.SLOTS:
			var item: Dictionary=game.generate_relic(5,slot,"thunder_hunt")
			if source=="tiya":
				item.equippedBy="tiya";game.state.ownedCharacters.tiya.equippedRelics[slot]=item.uid
			game.state.relics.append(item)
		var scorer=Optimizer.new(game,"lumi")
		var result: Dictionary=finish(scorer)
		ck(not result.success and result.phase=="error" and not result.canApply and not result.provenOptimal,"unsupported stochastic zero-gain loop fails cleanly "+source)
		# A caller cannot overwrite the phase to revive a numerical failure.
		scorer._phase="prepare";result=scorer.advance(100)
		ck(result.phase=="error" and not result.canApply and not result.provenOptimal,"failure survives later work-unit phase "+source)

func test_full_inventory_long_term() -> void:
	for id in ["lumi","tiya","selin"]:
		var game=make_game(["lumi","tiya","ayla"])
		if id=="selin":
			game.state.ownedCharacters.selin=game.default_character();game.state.ownedCharacters.kaldi=game.default_character()
			game.state.team=["ayla","zeph","kaldi"]
		var slots: Array=fixture(game)
		if id=="selin":
			for index in range(4):slots[index]=slots[index].filter(func(item):return item.setId!="wind_strings")
			game.state.relics=[]
			for options in slots:game.state.relics.append_array(options)
		var result: Dictionary=verify_search(game,id,slots,"steady complete inventory "+id)
		ck(result.evaluationMode=="steady","real preview is long-term "+id)
		if id=="lumi":ck(int(result.after.counts.get("wind_strings",0))>=4,"equal attributes prioritize useful Lumi4 under actual cycles")
		if id=="tiya":ck(int(result.after.counts.get("wind_strings",0))>=4,"Tiya can supply stronger shared buff when Lumi has no four-set")
		if id=="selin":ck(result.referenceTeam==["selin","kaldi","ayla"],"legal reference fix survives long-cycle change")
	var game=make_game(["lumi","ember","zeph"])
	var slots: Array=fixture(game)
	var scorer=Optimizer.new(game,"lumi")
	ck(is_equal_approx(scorer.evaluate_loadout(designated(slots,true)).objective,scorer.evaluate_loadout(designated(slots,false)).objective),"no off-party Tiya invented for long-term set score")

func test_normalized_search_bounds() -> void:
	for entry in [{"id":"ember","c":6,"sets":["flame_oath","thunder_hunt"]},{"id":"shana","c":0,"sets":["aurora_prayer","star_watch"]}]:
		var game=make_game([entry.id,null,null]);game.state.ownedCharacters[entry.id]=game.default_character();game.state.ownedCharacters[entry.id].constellation=entry.c
		var slots: Array=fixture(game)
		game.state.relics=[]
		for index in range(5):
			if index<4:
				slots[index]=slots[index].slice(0,2)
				for variant in range(2):slots[index][variant].setId=entry.sets[variant]
			game.state.relics.append_array(slots[index])
		var search=Optimizer.new(game,entry.id);prepare(search)
		var exact: float=oracle(search,slots)
		var retained: Array=[]
		for slot in range(5):retained.append(leaves(search,slot,search._tree_roots[slot]))
		check_leaf_bounds(search,retained);check_random_boxes(search,16)
		var result: Dictionary=finish(search)
		ck(result.success and result.provenOptimal and absf(float(result.lowerBound)-exact)<1e-6,"normalized steady search equals16 exhaustive "+entry.id)
		report.cases.append({"label":"ordinary normalized steady search "+entry.id,"exact":exact,"found":result.lowerBound,"sets":result.after.counts,"fastBounds":result.fastBounds,"candidateCounts":result.candidateCounts})

func test_panels_long_and_opening() -> void:
	for constellation in [0,2,6]:
		var game=make_game(["tiya",null,null]);game.state.ownedCharacters.tiya.constellation=constellation
		var steady=Optimizer.new(game,"tiya")
		var opening=Optimizer.new(game,"tiya",{"evaluation":"opening","actions":6})
		var old_stats: Dictionary=game.computed_stats("tiya")
		old_stats.merge({"hp":2033,"maxHp":2033,"atk":381,"def":136,"spd":122.,"cri":.305,"critRate":.305,"criDmg":1.82,"critDmg":1.82,"energyRate":.132},true)
		var new_stats: Dictionary=old_stats.duplicate(true)
		new_stats.merge({"hp":1983,"maxHp":1983,"atk":449,"def":322,"cri":.337,"critRate":.337,"criDmg":1.816,"critDmg":1.816,"energyRate":.222},true)
		var effects: Array=[{"type":"windPierceOwner","value":.20}]
		var old_value: float=steady._evaluate(old_stats,effects);var new_value: float=steady._evaluate(new_stats,[])
		var old_open: float=opening._evaluate(old_stats,effects);var new_open: float=opening._evaluate(new_stats,[])
		var old_cycle: Dictionary=steady.cycle_summary(old_stats,effects);var new_cycle: Dictionary=steady.cycle_summary(new_stats,[])
		ck(old_cycle.success and new_cycle.success,"shown panels exact cycles C"+str(constellation))
		ck(new_value/old_value<new_open/old_open,"steady removes six-action opening spike C"+str(constellation))
		ck(steady._evaluate(old_stats,effects,true)+1e-6>=old_value and steady._evaluate(new_stats,[],true)+1e-6>=new_value,"shown panel long-run bounds")
		report.panels.append({"constellationAssumption":constellation,"steadyOld":old_value,"steadyNew":new_value,"steadyGain":new_value/old_value-1.,"openingOld":old_open,"openingNew":new_open,"openingGain":new_open/old_open-1.,"oldCycle":old_cycle,"newCycle":new_cycle,"conditions":"Shown rounded panels; solo Tiya, three neutral DEF100 targets with maintained35%armor; not a full user save."})

func run() -> void:
	random.seed=289031
	report={"scope":"Exact long-run automatic action cadence under declared maintained-status reference, not a complete live battle simulation.","cases":[],"panels":[]}
	var started: int=Time.get_ticks_msec()
	test_modes_and_roles()
	test_random_kernels()
	test_closed_classes_and_failures()
	test_full_inventory_long_term()
	test_normalized_search_bounds()
	test_partial_screenshot_inventory()
	test_panels_long_and_opening()
	report.roles=role_rows;report.kernels=kernel_rows;report.checks=checks;report.failures=failures;report.auditedLeaves=audited_leaves;report.auditedBoxes=audited_boxes;report.minimumBoundMargin=minimum_margin;report.maximumColdEvaluationUs=maximum_cold_eval_us;report.elapsedMs=Time.get_ticks_msec()-started
	DirAccess.make_dir_recursive_absolute("res://validation/v289-relic-steady")
	var file=FileAccess.open("res://validation/v289-relic-steady/report.json",FileAccess.WRITE)
	if file:file.store_string(JSON.stringify(report,"  "));file.close()
	print("RELIC STEADY V289: %d checks; %d leaves; %d boxes; %d failures; max cold evaluation %dus; elapsed %dms"%[checks,audited_leaves,audited_boxes,failures.size(),maximum_cold_eval_us,report.elapsedMs])
	quit(0 if failures.is_empty() else 1)
