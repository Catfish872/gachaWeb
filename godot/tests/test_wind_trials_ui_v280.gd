extends "res://tests/test_lantern_journey_ui_v270.gd"
func capture(label:String)->void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://validation/v280-focused/"+label+".png")
func named(node_name: String) -> Node: return app.find_child(node_name, true, false)
func leave_trial() -> void:
	app.navigate("summon")
	ck(app.current_screen == "battle" and app.overlay.get_child_count() > 0, "trial retreat retains confirmation")
	for button in app.overlay.find_children("*", "Button", true, false):
		if button.text == "确认":
			button.pressed.emit()
			break
	ck(app.current_screen == "summon" and app.overlay.get_child_count() == 0, "confirmed trial retreat returns to banner")
func run() -> void:
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await frames(10)
	app.set_process(false)
	fresh()
	for viewport in [Vector2i(390,844), Vector2i(960,540), Vector2i(1280,720)]:
		root.size = viewport
		await frames(8)
		for kind in ["tiya", "lumi"]:
			app.selected_pool = "limited_" + kind
			app.navigate("summon")
			await frames(8)
			if viewport==Vector2i(960,540):await capture("summon-"+kind+"-960")
			# Compact pages scroll as a whole; landscape keeps both entry buttons fixed.
			ck(named("WindTrial_" + kind) != null and named("WindTrial_duo") != null, "independent and joint trial entry " + kind)
			if not app.compact:
				fits(named("WindTrial_" + kind), "%s solo trial entry" % viewport)
				fits(named("WindTrial_duo"), "%s joint trial entry" % viewport)
			named("WindTrial_" + kind).pressed.emit()
			await frames(4)
			ck(app.current_screen == "battle" and app.battle_config.trialCharacter == kind and app.overlay.get_child_count() == 0, "%s trial opens directly from banner" % viewport)
			leave_trial()
	root.size = Vector2i(960,540)
	await frames(8)
	for kind in ["tiya", "lumi", "duo"]:
		fresh()
		app.selected_pool = "limited_lumi" if kind == "lumi" else "limited_tiya"
		app.navigate("summon")
		app.preferred_battle_auto = kind != "lumi"
		named("WindTrial_" + kind).pressed.emit()
		await frames(8)
		ck(app.current_screen == "battle" and app.battle_config.trialCharacter == kind, kind + " starts via actual UI entry")
		ck(app.battle_auto == app.preferred_battle_auto and app.battle.state.allies[0].id == ("lumi" if kind == "duo" else kind), kind + " follows saved auto preference with intended party")
		var token: String = app.battle_config.token
		app._show_wind_trial(kind)
		ck(app.battle_config.token == token and app.overlay.get_child_count() == 0, kind + " repeated direct start preserves active battle")
		if kind=="duo":await capture("duo-trial-960")
		ck(app._battle_return_screen() == "summon", kind + " retreat destination is summon")
		app.battle.state.phase = "victory"
		await app._finish_battle()
		await frames(8)
		ck(not app.settlement_error, kind + " UI settlement succeeds")
		ck(app.last_reward.rewards.diamonds == (0 if kind == "duo" else 160), kind + " UI displays correct first clear reward")
		named("BattleSettlementContinue").pressed.emit()
		await frames(8)
		ck(app.current_screen == "summon" and app.overlay.get_child_count() == 0, kind + " settlement returns cleanly to summon")
	fresh()
	app.model.extraction.start_run()
	app.selected_pool = "limited_tiya"
	app.navigate("summon")
	named("WindTrial_tiya").pressed.emit()
	ck(app.current_screen == "summon" and app.model.extraction.active() and app.battle_config.is_empty(), "direct trial preserves active expedition lock")
	# Consecutive post-battle dialogue keys use the same scene and preserve order.
	fresh()
	app.model.catalog.DialogueData.wind_test_post = [{"speaker":"narrator","text":"桥边风声渐缓。"}]
	app.model.catalog.DialogueData.wind_test_interlude = [{"speaker":"narrator","text":"众人在外驿歇脚。"}]
	var keys := ["wind_test_post", "wind_test_interlude"]
	var done := {"value":false}
	app._play_dialogue_sequence(keys, func(): done.value = true)
	ck(app.dialogue_key == "wind_test_post", "sequence opens first post dialogue")
	app._finish_dialogue()
	ck(app.dialogue_key == "wind_test_interlude" and not done.value, "sequence continues to interlude")
	app._finish_dialogue()
	ck(done.value and app.dialogue_key.is_empty() and app.overlay.get_child_count() == 0, "sequence completes once and clears overlay")
	ck(app.model.state.dialogueSeen.wind_test_post and app.model.state.dialogueSeen.wind_test_interlude, "each completed section recorded")
	app.model.state.dialogueSeen.erase("wind_test_interlude")
	done.value = false
	app._play_dialogue_sequence(keys, func(): done.value = true, true)
	ck(app.dialogue_key == "wind_test_interlude", "settlement resumes only unseen sections")
	app._finish_dialogue()
	ck(done.value, "resumed sequence completes")
	ck(app._stage_post_dialogue_keys({"id":"ch1_1"}) == ["ch1_1_post"], "legacy stage keeps single post dialogue")
	ck(app._stage_post_dialogue_keys({"id":"ch4_3","postDialogueKeys":keys}) == keys, "new chapter keys retain catalog order")
	app.queue_free()
	await frames()
	print("WIND TRIAL UI V280: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
