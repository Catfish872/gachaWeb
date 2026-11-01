extends "res://tests/test_redesign_layout.gd"
func portrait_rects() -> Dictionary:
	var result:Dictionary={}
	for uid in app.unit_cards:
		for texture in app.unit_cards[uid].find_children("*","TextureRect",true,false):
			if texture.texture==null:continue
			var path:String=texture.texture.resource_path
			if path.begins_with("res://assets/characters/") or path.begins_with("res://assets/enemies/"):
				result[uid]=texture.get_global_rect();break
	return result
func run() -> void:
	root.size=SIZES[0]
	app=load("res://main.tscn").instantiate();root.add_child(app);await frames();app.set_process(false)
	for case_index in SIZES.size()*2:
		var resolution:Vector2i=SIZES[case_index%SIZES.size()]
		var grown:bool=case_index>=SIZES.size()
		root.size=resolution;await frames()
		app.model=load("res://scripts/game_model.gd").new("")
		app.model.rng.seed=24091
		app.battle=load("res://scripts/battle_model.gd").new(app.model.catalog)
		if grown:
			app.model.state.resources.gold=10000000
			for id in ["kaldi","ayla","gus"]:
				app.model.state.ownedCharacters[id]=app.model.default_character()
				app.model.state.ownedCharacters[id].level=10;app.model.state.ownedCharacters[id].constellation=6
				for slot in app.model.catalog.RelicSlots:
					var relic:Dictionary=app.model.generate_relic(5,str(slot.id))
					check(app.model.add_relic(relic).get("success",false),"real five-star relic fixture")
					check(app.model.upgrade_relic_to_max(relic.uid).get("success",false),"real max relic upgrade")
					check(app.model.equip_relic(relic.uid,id).get("success",false),"real max relic equipped")
			app.model.set_team(["kaldi","ayla","gus"])
		var prepared:Dictionary=app.model.prepare_stage("ch1_1")
		check(prepared.get("success",false),"real battle fixture")
		app._start_battle(prepared.config);app.battle_auto=false
		var snapshot:Dictionary=app.battle.state.duplicate(true)
		if grown:print("BATTLE GEOMETRY GROWN ",resolution," ",snapshot.allies.map(func(unit):return {"id":unit.id,"maxHp":unit.maxHp}))
		var baseline:Dictionary={}
		for variant in ["plain","enemy_turn","shield","statuses","shield_and_statuses"]:
			app.battle.state=snapshot.duplicate(true)
			app.battle.state.phase="enemy_turn" if variant=="enemy_turn" else "player_turn"
			for unit in app.battle.state.allies:
				unit.shield=int(unit.maxHp*float(app.model.extraction.item_def("armor_5").armorPct)) if "shield" in variant else 0
				unit.statuses=[{"id":"shield","source":"expedition_equipment","duration":99},{"id":"atk_up","duration":2}] if "statuses" in variant else []
			app._render_battle();await frames()
			var rectangles:Dictionary=portrait_rects()
			check(rectangles.size()==app.unit_cards.size(),"actual art rect available for every unit")
			if variant=="plain":baseline=rectangles.duplicate(true)
			else:
				for uid in baseline:
					check(rectangles.has(uid) and (rectangles[uid] as Rect2).size.is_equal_approx((baseline[uid] as Rect2).size),"portrait size stable "+str(resolution)+" grown="+str(grown)+" "+variant+" "+str(uid)+" baseline="+str(baseline[uid])+" actual="+str(rectangles.get(uid)))
			fits(app.main_body.find_child("BattleArena",true,false),variant+" arena")
			fits(app.main_body.find_child("BattleActions",true,false),variant+" actions")
			for control in app.unit_cards.values():fits(control,variant+" combatant")
			for control in app.main_body.find_children("BattleSkill_*","Button",true,false):fits(control,variant+" skill")
			check(app.page_scroll.get_v_scroll_bar().max_value-app.page_scroll.get_v_scroll_bar().page<=1,"battle bottom stays visible "+variant)
		app.battle.state={};app.navigate("home");await frames()
	app.queue_free();await frames();await create_timer(.3).timeout
	print("BATTLE GEOMETRY V24: %d checks, %d failures" %[checks,failures.size()]);quit(0 if failures.is_empty() else 1)
