extends "res://tests/test_equipped_relic_upgrade_ui_v261.gd"
func run()->void:
	if DisplayServer.get_name()=="headless":quit(2);return
	DirAccess.make_dir_recursive_absolute(OUT261)
	app=load("res://main.tscn").instantiate();root.add_child(app);await frames(12);app.set_process(false)
	root.size=Vector2i(960,540);await frames()
	app.model=load("res://scripts/game_model.gd").new("");app.model.rng.seed=261501
	for spec in [["strong_four",4,20,2000.0],["new_five",5,0,1.0]]:
		var relic:Dictionary=app.model.generate_relic(spec[1],"helmet","")
		relic.uid=spec[0];relic.level=spec[2];relic.mainStat={"stat":"atk_flat","name":"攻击","base":spec[3],"perLevel":0.0};relic.subStats=[]
		app.model.add_relic(relic)
	ck(app.model.equip_relic("strong_four","ember").success,"strong four-star currently equipped")
	app.selected_character="ember";app.growth_panel="gear";app.navigate("growth");await frames()
	var wallet:Dictionary=app.model.state.resources.duplicate(true)
	await tap(app.find_child("GrowthAutoRelics",true,false));await wait_plan();await frames()
	var action=app.overlay.find_child("RelicLoadoutApply",true,false)
	fits(action,"rarity upgrade apply visible at mobile width")
	ck(action!=null and not action.disabled,"lower current score five-star plan is applicable")
	var all_text:=text_all(app.overlay)
	ck(not "+-" in all_text,"negative change is not falsely plus-prefixed")
	ck("-" in all_text and "%" in all_text,"real negative current-score change shown")
	ck("★★★★★" in all_text and "★★★★" in all_text,"comparison shows current and recommended rarity")
	await capture("rarity-priority-960")
	await tap(action);await frames()
	ck(app.model.state.ownedCharacters.ember.equippedRelics.helmet=="new_five","actual apply chooses higher rarity despite lower current score")
	ck(app.model.state.resources==wallet,"rarity preference consumes no resources")
	ck(app.overlay.get_child_count()==0,"apply completes and closes preview")
	await capture("rarity-applied-960")
	# Incremental scope only: mixed rarities stop at their own caps.
	app.model=load("res://scripts/game_model.gd").new("");app.model.rng.seed=261315;app.model.state.resources.gold=100000
	for i in range(3):
		var relic:Dictionary=app.model.generate_relic(3+i,str(app.model.catalog.RelicSlots[i].id),"")
		relic.uid="mixed_"+str(3+i);app.model.add_relic(relic);ck(app.model.equip_relic(str(relic.uid),"ember").success,"mixed cap fixture equipped")
	app.growth_panel="gear";app.navigate("growth");await frames()
	var max_action=app.find_child("GrowthUpgradeAllRelics",true,false)
	ck("16700" in max_action.text,"mixed total quote exact")
	await tap(max_action)
	ck("各自满级" in text_all(app.overlay) and "16700" in text_all(app.overlay),"mixed confirmation is not fixed +25")
	await capture("mixed-caps-confirm-960");await tap(find_text(app.overlay,"确认"));await frames()
	for rarity in range(3,6):ck(int(app.model.get_relic("mixed_"+str(rarity)).level)=={3:15,4:20,5:25}[rarity],"rarity-specific cap reached")
	ck(int(app.model.state.resources.gold)==83300,"mixed exact single deduction")
	app.selected_relic="mixed_3";app.navigate("relics");await frames()
	var single=app.find_child("RelicUpgrade",true,false)
	ck(single!=null and single.disabled and single.text=="已满级","single three-star cannot exceed +15")
	ck("满级 +15" in text_all(app.main_body),"single cap presented correctly")
	await capture("single-three-star-cap-960")
	app.queue_free();await frames();print("RARITY PRIORITY UI V261: %d checks, %d failures"%[checks,failures.size()]);quit(0 if failures.is_empty() else 1)
