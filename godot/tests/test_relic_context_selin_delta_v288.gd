extends "res://tests/test_relic_context_v288.gd"
## Only the shared-selector / Selin delta; do not rerun the previous wind audit.
func run() -> void:
	random.seed=288032
	var game=make_game(["ember","zeph","lumi"])
	ck(Optimizer.reference_team_ids(game,"tiya")==["tiya","lumi","ember"],"Tiya preserves existing late wind partner")
	game.state.team=["zeph",null,"lumi"]
	ck(Optimizer.reference_team_ids(game,"tiya")==["tiya","lumi","zeph"],"off-party preview fills current empty slot")
	game.state.team=["lumi","lumi",null]
	ck(Optimizer.reference_team_ids(game,"tiya")==["tiya","lumi"],"selector removes duplicate malformed members")
	game.state.ownedCharacters.selin=game.default_character()
	game.state.ownedCharacters.kaldi=game.default_character()
	game.state.team=["ayla","zeph","kaldi"]
	ck(Optimizer.reference_team_ids(game,"selin")==["selin","kaldi","ayla"],"Selin preserves late actual burn applier")
	var slots: Array=fixture(game)
	# Two sets per variable slot = 16 combinations, enough for the changed path.
	for index in range(4):slots[index]=slots[index].filter(func(item):return item.setId!="wind_strings")
	game.state.relics=[]
	for options in slots:game.state.relics.append_array(options)
	var off=Optimizer.new(game,"selin")
	var chosen: Array=[]
	for options in slots:chosen.append(options[0])
	var off_score: float=off.evaluate_loadout(chosen).objective
	game.state.ownedCharacters.zeph.level=10
	var omitted=Optimizer.new(game,"selin")
	ck(is_equal_approx(off_score,omitted.evaluate_loadout(chosen).objective),"excluded fourth character cannot increase Selin contribution")
	game.state.team=["selin","kaldi","ayla"]
	var active=Optimizer.new(game,"selin")
	ck(is_equal_approx(off_score,active.evaluate_loadout(chosen).objective),"off-party reference equals the same legal active party")
	ck(Optimizer.reference_team_ids(game,"selin")==game.state.team,"Selin active party stays exact")
	game.state.team=["ayla","zeph","kaldi"]
	var result: Dictionary=verify_search(game,"selin",slots,"Selin legal off-party16 exact search")
	ck(result.referenceTeam==["selin","kaldi","ayla"],"Selin preview publishes scored members")
	for item in game.state.relics:
		if item.equippedBy=="selin":item.equippedBy=null
	game.state.ownedCharacters.selin.equippedRelics={}
	var held: Dictionary=game.preview_best_relic_loadout("selin")
	ck(held.canApply,"pending Selin plan is genuinely applicable before team changes")
	game.state.team=["selin","ember","zeph"]
	ck(held.fingerprint!=Optimizer.plan_fingerprint(game,"selin",held.context),"party change invalidates reference fingerprint")
	var changed_state: String=JSON.stringify(game.state)
	var rejected: Dictionary=game.apply_relic_loadout(held)
	ck(not rejected.success and rejected.get("error","")=="装备或角色状态已变化，请重新计算" and JSON.stringify(game.state)==changed_state,"changed party rejects stale plan without mutation")
	game.state.team=["ayla","zeph",null]
	ck(Optimizer.reference_team_ids(game,"selin")==["selin","ayla","zeph"],"owned off-party Kaldi is not silently introduced")
	report.checks=checks;report.failures=failures;report.auditedLeaves=audited_leaves;report.auditedBoxes=audited_boxes;report.minimumBoundMargin=minimum_margin
	var file=FileAccess.open("res://validation/v288-relic-context/selin-delta.json",FileAccess.WRITE)
	if file:file.store_string(JSON.stringify(report,"  "));file.close()
	print("RELIC CONTEXT SELIN DELTA V288: %d checks; %d leaves; %d boxes; %d failures"%[checks,audited_leaves,audited_boxes,failures.size()])
	quit(0 if failures.is_empty() else 1)
