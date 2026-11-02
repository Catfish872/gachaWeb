extends SceneTree
const GameModel = preload("res://scripts/game_model.gd")
var failures := 0
func check(value: bool, label: String) -> void:
	if value: print("PASS: "+label)
	else: failures += 1; push_error("FAIL: "+label)
func _initialize() -> void:
	call_deferred("run_tests")
func run_tests() -> void:
	var model = GameModel.new("")
	var ex = model.extraction
	check(ex.start_run().success,"new run starts")
	check(ex.max_acts()==3 and ex.run().environmentOrder.size()==3,"new run always three acts")
	var themes: Dictionary = {}
	for theme in ex.run().environmentOrder: themes[theme]=true
	check(themes.size()==3 and themes.keys().all(func(theme): return ex.data.environmentThemes.has(theme)),"three unique environments from available pool")
	check(model.valid_save(model.state),"new run valid save")
	# The schema fallback keeps unfinished pre-update three-act runs unchanged.
	ex.run().erase("maxActs")
	ex.run().environmentOrder=["ruins","forest","sanctum"]
	var saved_map: Dictionary = ex.run().map.duplicate(true)
	check(ex.max_acts()==3 and ex.environment_theme()=="ruins","legacy three-act fallback")
	check(ex.run().map==saved_map,"legacy read does not regenerate map")
	ex.run().maxActs=3; ex.run().environmentOrder=["lantern","ruins","forest"]
	ex.run().act=1; ex._generate_map()
	check(ex.run().map.districts.size()==3 and ex.run().map.theme=="lantern","new theme three submaps")
	for index in range(3):
		ex.run().room={"districtId":"district_%d"%index}
		check(ex.environment_music_track()==["lantern_road","lantern_hall","lantern_core"][index],"district music "+str(index))
	# New chapter-sized bases cannot make a random first-act theme several times harder.
	var encounter_sets := {"battle":["ash_moth","furnace_guard"],"elite":["lamp_overseer"],"boss":["boss_hedor","furnace_lamp","furnace_lamp"]}
	var targets := {"battle":[(380.0+350.0+300.0)/3.0*2.0,(45.0+50.0+60.0)/3.0*2.0],"elite":[1000.0,77.5],"boss":[4750.0,130.0]}
	for kind in encounter_sets:
		var enemies: Array = encounter_sets[kind]
		var scaled: Dictionary = ex._theme_encounter_budget(kind,enemies,1,0)
		var hp := 0.0; var attack := 0.0
		for enemy_id in enemies:
			hp += float(model.catalog.EnemyData[enemy_id].baseStats.hp)
			attack += float(model.catalog.EnemyData[enemy_id].baseStats.atk)
		check(is_equal_approx(hp*float(scaled.hpMod),float(targets[kind][0])*1.08),"theme HP budget "+kind)
		check(is_equal_approx(attack*float(scaled.atkMod),float(targets[kind][1])*1.05),"theme attack budget "+kind)
	var saved_rng: String = str(ex.run().rngState)
	var issued_before: Dictionary = ex.run().get("activeEncounter",{}).duplicate(true)
	var high_rank_budget: Dictionary = ex._theme_encounter_budget("boss",encounter_sets.boss,1,5)
	check(is_equal_approx(21600.0*float(high_rank_budget.hpMod),(4750.0+1200.0+420.0)*1.08),"rank5 includes old escort budget")
	check(str(ex.run().rngState)==saved_rng and ex.run().get("activeEncounter",{})==issued_before,"budget calculation consumes no RNG or rewrites issued encounter")
	for act in [2,3]:
		ex.run().act=act; ex.run().node=4; ex._generate_encounter("boss")
		check(is_equal_approx(float(ex.run().activeEncounter.finalBossStatMultiplier),1.15 if act==3 else 1.0),"final multiplier act "+str(act))
	ex.run().maxActs=3; ex.run().environmentOrder=["ruins","forest","sanctum"]; ex.run().act=3
	ex._generate_encounter("boss")
	check(is_equal_approx(float(ex.run().activeEncounter.finalBossStatMultiplier),1.15),"legacy final boss retained")
	var variants := 0
	var rarities: Dictionary = {}
	for id in ex.data.items:
		var item: Dictionary = ex.data.items[id]
		if item.get("environmentTheme","")!="lantern" or item.get("kind","")!="loot": continue
		variants+=1; rarities[int(item.rarity)]=int(rarities.get(int(item.rarity),0))+1
		var base: Dictionary = ex.item_def(item.variantOf)
		check(item.value==base.value and item.width==base.width and item.height==base.height and item.rarity==base.rarity,"variant economy "+str(id))
	check(variants==24 and rarities.size()==6,"24 variants across six qualities")
	check(ex.item_def("key_lantern").buyPrice==500 and ex.item_def("key_lantern").keyTheme=="lantern","new theme key costs 500")
	check(ex.data.rarityWeightsByAct.size()==3,"three act quality curve retained")
	var appraisal: Array = ex.data.lootEconomy.actAppraisalMultiplier
	check(appraisal.size()==3 and is_equal_approx(float(appraisal[0]),1.0) and is_equal_approx(float(appraisal[1]),1.25) and is_equal_approx(float(appraisal[2]),1.6),"three act prices unchanged")
	check(ex.RELAY_PARCEL_SIZE==Vector2i(5,5) and ex.BOSS_PARCEL_SIZE==Vector2i(6,6),"parcel sizes retained")
	for item_id in ["repair_patch","repair_kit","repair_core"]:
		check(ex._matches_loot_categories(ex.item_def(item_id),ex._container_categories("cache","lantern_medicine",{})),"repair supply "+item_id)
	ex.run().characterFocus={"kaldi":1.0,"selin":1.0}
	var ids: Dictionary = {}
	for reward in ex._growth_pool():
		check(not ids.has(reward.id),"unique reward "+str(reward.id)); ids[reward.id]=true
	print("LANTERN EXPEDITION FAILURES: ",failures)
	quit(1 if failures else 0)
