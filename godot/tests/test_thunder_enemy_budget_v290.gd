extends "res://tests/test_wind_enemies_v280.gd"
func run_tests() -> void:
	game=Game.new("")
	for mode in [{},{"isAbyss":true,"floor":10},{"isExtraction":true}]:
		var b=battle(["boss_city_sealer","sealer_core","sealer_ward"],mode)
		var boss: Dictionary=b.state.enemies[0]
		for action in range(6):
			var expected: String=["sealer_warning","sealer_storm"][action%2]
			var before: int=b.rng.state
			ck(b._enemy_choice(boss,b._available(boss))==expected and b.rng.state==before,"stable promised action")
			var outcome: Dictionary=force_enemy_action(b,boss)
			ck(outcome.success and outcome.events.any(func(e):return e.get("skill_id","")==expected),"actual promised action")
		boss.actionCycleCursor=0;boss.actionCycleLastSkill="";boss.actionCyclePhase2=false;boss.inPhase2=false
		force_enemy_action(b,boss);boss.inPhase2=true
		ck(b._enemy_choice(boss,b._available(boss))=="sealer_tempest","phase change keeps area warning")
		for i in [1,2]:ck(b.state.enemies[i].uid!=boss.uid and b.state.enemies[i].currentHp>0,"selectable attached target")
	var controlled=battle(["boss_city_sealer"],{"isAbyss":true,"floor":10})
	var cu: Dictionary=controlled.state.enemies[0];force_enemy_action(controlled,cu)
	var uid: String=cu.uid;var cursor: int=cu.actionCycleCursor;var hp: int=cu.currentHp
	controlled.apply_status(cu,"freeze",1,null,controlled.state.allies[0]);controlled._cursor=controlled._queue.find(cu);controlled._seek_actor()
	ck(cu.uid==uid and cu.currentHp==hp and cu.actionCycleCursor==cursor,"control preserves pending cycle and entity")
	var rows: Array=[]
	for defense in [0,100,500]:
		for phase in [false,true]:
			for extraction_mode in [false,true]:
				var new_ids: Array=["boss_city_sealer","sealer_core","sealer_ward"] if extraction_mode else ["boss_city_sealer"]
				var old_ids: Array=["boss_storm_witch","dark_knight","thunder_hawk"] if extraction_mode else ["boss_storm_witch"]
				var config: Dictionary=extraction_config("thunder_city","boss") if extraction_mode else {"isAbyss":true,"floor":10}
				config.fixtureDef=defense
				var old_config: Dictionary=extraction_config("ruins","boss") if extraction_mode else config.duplicate(true)
				old_config.fixtureDef=defense
				var new_result: Dictionary=sample_budget(new_ids,config,phase,8)
				var old_result: Dictionary=sample_budget(old_ids,old_config,phase,8)
				var ratio: float=float(new_result.damage)/maxf(1.0,float(old_result.damage))
				ck(ratio>=.60 and ratio<=1.20,"same-mode six-action boss pressure")
				ck(float(new_result.singlePeak)<=float(old_result.singlePeak)*1.20,"single-player peak bounded")
				ck(new_result.attackActions==18.0 if extraction_mode else new_result.attackActions==6.0,"continuous attack participation")
				rows.append({"mode":"extraction_A3_rank5" if extraction_mode else "abyss_10","defense":defense,"phase2":phase,"samples":8,"new":new_result,"reference":old_result,"damageRatio":ratio})
	for enemy in ["breaker_cavalier","thunder_core_guard"]:
		var config: Dictionary={"isAbyss":true,"floor":5,"fixtureDef":100}
		var new_result: Dictionary=sample_budget([enemy],config,false,8)
		var old_result: Dictionary=sample_budget(["dark_knight"],config,false,8)
		var ratio: float=float(new_result.damage)/maxf(1.0,float(old_result.damage))
		ck(ratio>=.70 and ratio<=1.20,"elite six-action budget "+enemy)
		rows.append({"enemy":enemy,"mode":"abyss_5","new":new_result,"reference":old_result,"damageRatio":ratio})
	var shield_cfg: Dictionary={"isAbyss":true,"floor":10,"fixtureDef":100,"fixtureShield":10000000}
	var protected: Dictionary=sample_budget(["boss_city_sealer"],shield_cfg,true,8)
	ck(protected.hpDamage==0.0 and protected.shieldAbsorbed>0.0,"player shields absorb lightning")
	DirAccess.make_dir_recursive_absolute("res://validation/v290-thunder")
	var report=FileAccess.open("res://validation/v290-thunder/world-enemy-budget.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"scope":"six enemy actions per unit, neutral three-player fixtures, 8 fixed seeds; current damage chain; not player progression simulation","rows":rows},"  "))
	print("THUNDER ENEMIES V290: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
