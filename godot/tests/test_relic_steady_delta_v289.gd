extends "res://tests/test_relic_steady_v289.gd"
var advance_durations: Array=[]
func finish(search) -> Dictionary:
	var result: Dictionary=search.preview()
	while not result.done:
		var started: int=Time.get_ticks_usec()
		result=search.advance(4000)
		advance_durations.append(Time.get_ticks_usec()-started)
	return result

func cold_gus_timing() -> int:
	var game=make_game(["gus",null,null]);game.state.ownedCharacters.gus=game.default_character();game.state.ownedCharacters.gus.constellation=6
	var items: Array=[]
	for slot in Optimizer.SLOTS:items.append(game.generate_relic(5,slot,"thunder_hunt"))
	var scorer=Optimizer.new(game,"gus");var snapshot: Dictionary=scorer.evaluate_loadout(items)
	scorer._evaluation_cache.clear();Cycle.clear_cache()
	var started: int=Time.get_ticks_usec()
	var value: float=scorer._evaluate(snapshot.stats,snapshot.ownerEffects)
	var elapsed: int=Time.get_ticks_usec()-started
	ck(scorer._error.is_empty() and is_equal_approx(value,float(snapshot.objective)),"cold GusC6 thunder timing retains exact score")
	return elapsed

func piece(game,uid: String,slot: String,atk: float) -> Dictionary:
	return observed_item(game,uid,slot,"",0,"hp_flat" if slot=="helmet" else ("atk_flat" if slot=="chest" else "spd"),{"atk_flat":atk,"def_flat":15.,"def_pct":.03,"hp_pct":.03} if slot!="chest" else {"def_flat":15.,"def_pct":.03,"hp_pct":.03,"spd":2.})
func run_perf() -> void:
	var started: int=Time.get_ticks_usec()
	var cold: int=cold_gus_timing()
	var game=make_game(["tiya","lumi","ayla"]);var slots: Array=fixture(game)
	game.state.relics=[]
	for index in range(5):
		if index<4:slots[index]=slots[index].slice(1,3)
		game.state.relics.append_array(slots[index])
	var result: Dictionary=finish(game.begin_best_relic_loadout("tiya"))
	ck(result.success and result.provenOptimal,"measured cooperative search completes exactly")
	advance_durations.sort()
	var output: Dictionary={"checks":checks,"failures":failures,"coldGusC6ThunderEvalUs":cold,"advanceBudgetUs":4000,"advanceCalls":advance_durations.size(),"maximumAdvanceUs":advance_durations[-1],"p95AdvanceUs":advance_durations[mini(advance_durations.size()-1,int(ceil(advance_durations.size()*.95))-1)],"elapsedUs":Time.get_ticks_usec()-started,"scope":"Desktop CPU timing, not Android hardware performance; one existing16-combination reference inventory."}
	var file=FileAccess.open("res://validation/v289-relic-steady/performance.json",FileAccess.WRITE)
	if file:file.store_string(JSON.stringify(output,"  "));file.close()
	print("RELIC STEADY PERF V289: ",JSON.stringify(output))
	quit(0 if failures.is_empty() else 1)

func run() -> void:
	if OS.get_cmdline_user_args().has("--perf-only"):
		run_perf();return
	random.seed=289032
	report={"scope":"Only corrections from first long-run audit: genuine set-support context and Selin burn-source dominance threshold.","cases":[],"panels":[]}
	for partner_set in [false,true]:
		var game=make_game(["lumi","tiya","ayla"])
		var slots: Array=fixture(game)
		if partner_set:
			for index in range(4):
				var item: Dictionary=game.generate_relic(5,Optimizer.SLOTS[index],"wind_strings")
				item.equippedBy="lumi";game.state.ownedCharacters.lumi.equippedRelics[item.slotId]=item.uid;game.state.relics.append(item)
		var result: Dictionary=verify_search(game,"tiya",slots,"Tiya exact81 with Lumi four-set="+str(partner_set))
		ck(int(result.after.counts.get("wind_blades" if partner_set else "wind_strings",0))>=4,"actual shared buff determines useful Tiya four-set "+str(partner_set))
		var scorer=Optimizer.new(game,"tiya")
		var scores: Dictionary={}
		for set_id in ["wind_strings","wind_blades","atk22"]:
			var items: Array=[]
			for index in range(5):
				var desired: String=("wind_blades" if index<2 else "ember_lantern") if set_id=="atk22" else set_id
				if index==4:desired=""
				for item in slots[index]:
					if item.setId==desired:items.append(item)
			scores[set_id]=scorer.evaluate_loadout(items).objective
		report.cases[-1].setScores=scores
	var game=make_game(["selin","kaldi",null])
	for id in ["selin","kaldi"]:game.state.ownedCharacters[id]=game.default_character()
	var low: Dictionary=piece(game,"z_lower_atk","helmet",32.)
	var high: Dictionary=piece(game,"a_higher_atk","helmet",33.)
	var chest: Dictionary=piece(game,"fixed_chest","chest",0.)
	var boots: Dictionary=piece(game,"fixed_boots","boots",32.)
	var slots: Array=[[low,high],[chest],[{}],[boots],[{}]]
	game.state.relics=[low,high,chest,boots]
	var scorer=Optimizer.new(game,"selin")
	var low_score: Dictionary=scorer.evaluate_loadout([low,chest,boots]);var high_score: Dictionary=scorer.evaluate_loadout([high,chest,boots])
	ck(low_score.stats.atk==184 and high_score.stats.atk==185 and game.computed_stats("kaldi").atk==185,"legal generated-range substat threshold fixture")
	ck(float(low_score.objective)>float(high_score.objective),"Selin burn ownership can make one extra attack worse")
	var result: Dictionary=verify_search(game,"selin",slots,"Selin two legal ATK184/185 threshold candidates")
	ck(result.candidateCounts[0]==2 and result.after.relicUids.helmet==low.uid,"both attack candidates survive and lower attack wins exact search")
	report.cases[-1].lowAttack=low_score;report.cases[-1].highAttack=high_score
	var cold_gus_us: int=cold_gus_timing()
	advance_durations.sort()
	report.performance={"coldGusC6ThunderEvalUs":cold_gus_us,"advanceBudgetUs":4000,"advanceCalls":advance_durations.size(),"maximumAdvanceUs":advance_durations[-1] if not advance_durations.is_empty() else 0,"p95AdvanceUs":advance_durations[mini(advance_durations.size()-1,int(ceil(advance_durations.size()*.95))-1)] if not advance_durations.is_empty() else 0}
	report.checks=checks;report.failures=failures;report.auditedLeaves=audited_leaves;report.auditedBoxes=audited_boxes;report.minimumBoundMargin=minimum_margin
	var file=FileAccess.open("res://validation/v289-relic-steady/delta.json",FileAccess.WRITE)
	if file:file.store_string(JSON.stringify(report,"  "));file.close()
	print("RELIC STEADY DELTA V289: %d checks; %d leaves; %d boxes; %d failures"%[checks,audited_leaves,audited_boxes,failures.size()])
	quit(0 if failures.is_empty() else 1)
