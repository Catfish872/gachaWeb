extends SceneTree

var app
var checks := 0
var failures: Array = []
var captured: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error("UI V2 CHECK: " + description)

func texts(node: Node) -> String:
	var text := str(node.text) + "\n" if node is Label or node is Button else ""
	for child in node.get_children():
		text += texts(child)
	return text

func button(needle: String, parent: Node = null) -> Button:
	if parent == null:
		parent = app.main_body
	if parent is Button and (parent.name == needle or needle in parent.text):
		return parent
	for child in parent.get_children():
		var found := button(needle, child)
		if found != null:
			return found
	return null

func press(needle: String, parent: Node = null) -> bool:
	var target := button(needle, parent)
	check(target != null, "Actual UI control exists: " + needle)
	if target == null:
		return false
	check(not target.disabled, "Actual UI control enabled: " + needle)
	if target.disabled:
		return false
	target.pressed.emit()
	return true

func frames() -> void:
	await process_frame
	await process_frame

func capture(label: String) -> void:
	print("UI V2 view: ", label, " display=", DisplayServer.get_name())
	if DisplayServer.get_name() == "headless" or captured.has(label):
		return
	captured[label] = true
	await create_timer(0.25).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://validation/v2-ui-%s.png" % label)

func fit_page(label: String) -> void:
	await frames()
	var available: float = app.main_body.get_parent().size.x
	check(app.main_body.get_combined_minimum_size().x <= available + 2, "Layout fits " + label + ": " + str(app.main_body.get_combined_minimum_size().x) + " <= " + str(available))

func battle_to_result() -> bool:
	check(app.current_screen == "battle", "Encounter is a real battle scene")
	var steps := 0
	while app.battle.state.phase not in ["victory", "defeat"] and steps < 1000:
		var action: Dictionary = app.battle.auto_step()
		if not action.get("success", false):
			check(false, "Real combat action accepted")
			return false
		steps += 1
	check(steps < 1000, "Battle terminates within action bound")
	app._finish_battle()
	await create_timer(0.7).timeout
	return app.battle.state.phase == "victory"

func run() -> void:
	root.size = Vector2i(1440, 900)
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await frames()
	app.set_process(false)
	app.model = load("res://scripts/game_model.gd").new("")
	app.model.rng.seed = 20261017
	app.battle = load("res://scripts/battle_model.gd").new(app.model.catalog)
	for id in ["kaldi", "ayla", "gus"]:
		app.model.state.ownedCharacters[id] = app.model.default_character()
		app.model.state.ownedCharacters[id].level = 10
	app.model.set_team(["kaldi", "ayla", "gus"])
	for id in app.model.state.team:
		for slot in app.model.catalog.RelicSlots:
			var relic: Dictionary = app.model.generate_relic(5, str(slot.id))
			relic.level = 25
			app.model.state.relics.append(relic)
			check(app.model.equip_relic(relic.uid, id).success, "Fixture equips actual relic")
	app.navigate("abyss")
	check("裂隙币" in texts(app.main_body) and "记忆碎片" in texts(app.main_body), "Run and permanent currencies shown distinctly")
	check(button("AbyssDifficulty_1").disabled and not button("AbyssDifficulty_0").disabled, "Fresh game has only introductory rank unlocked")
	check("金币" in texts(app.header_resources) and "星尘晶" in texts(app.header_resources), "Original wallet remains distinct")
	await fit_page("desktop hub")
	await capture("hub")
	press("永久成长")
	check(button("MetaUpgrade_vitality").disabled, "Zero permanent currency disables upgrade")
	check("记忆碎片不足" in texts(app.main_body), "Upgrade affordability is explained")
	app.model.state.abyss.meta.currency = 400
	app.model.state.abyss.meta.totalEarned = 400
	app._render_screen()
	var gold: int = app.model.state.resources.gold
	var upgrade_cost: int = app.model.meta_upgrade_list()[0].cost
	press("MetaUpgrade_vitality")
	check(app.model.state.abyss.meta.upgrades.vitality == 1, "Upgrade button applies permanent level")
	check(app.model.state.abyss.meta.currency == 400 - upgrade_cost and app.model.state.resources.gold == gold, "Upgrade spends only permanent run-earned currency")
	await fit_page("desktop permanent upgrades")
	await capture("meta")
	press("返回远征地图")
	button("连续自动挑战").button_pressed = true
	press("AbyssBegin")
	check(app.model.abyss_run_active(), "Starting encounter creates persistent run")
	var observed: Dictionary = {}
	var victory_count := 0
	for floor_number in range(1, 21):
		print("UI V2 encounter: ", floor_number)
		check(app.battle_config.floor == floor_number, "UI starts expected floor " + str(floor_number))
		var won: bool = await battle_to_result()
		if not won:
			break
		victory_count += 1
		if floor_number == 20:
			check(not app.abyss_auto_continue and app.battle_settled, "Completing floor20 stops continuous combat")
			check("本轮通关 20 层" in texts(app.overlay), "Completion overlay reports full expedition")
			await frames()
			var continue_button := button("继续旅程", app.overlay)
			check(continue_button.get_global_rect().end.y <= app.size.y and continue_button.get_global_rect().position.y >= 0, "Settlement footer stays visibly inside viewport")
			press("继续旅程", app.overlay)
			break
		check(app.current_screen == "abyss", "Every post-battle decision pauses automatic combat")
		var nested := 0
		while app._abyss_has_decision() and nested < 4:
			nested += 1
			var phase: String = app.model.state.abyss.rogue.nextStep.type
			observed[phase] = true
			await fit_page("desktop " + phase)
			await capture(phase)
			var coins_before: int = app.model.state.abyss.rogue.temporaryCurrency
			await create_timer(0.15).timeout
			check(app.current_screen == "abyss" and app.model.state.abyss.rogue.nextStep.type == phase, "Waiting never skips " + phase)
			if floor_number == 1:
				app.navigate("party")
				check(button("保存出战队伍").disabled, "Active expedition roster visibly locked")
				app.navigate("abyss")
				press("永久成长")
				check(button("MetaUpgrade_vitality").disabled, "Permanent upgrades visibly locked during run")
				press("返回远征地图")
			match phase:
				"reward":
					var count: int = app.model.state.abyss.rogue.selectedRewards.size()
					if floor_number == 1:
						button("连续自动挑战").button_pressed = false
					press("选择此项回响")
					check(app.model.state.abyss.rogue.selectedRewards.size() == count + 1, "Chosen blessing joins build")
					if floor_number == 1:
						await fit_page("active ready hub")
						await capture("ready")
						check(button("AbyssBegin").get_global_rect().end.y <= app.size.y, "Active hub primary action visible without scrolling")
						check(button("AbyssDifficulty_0") == null and "本轮难度：初探 · 已锁定" in texts(app.main_body), "Active difficulty uses compact lock label")
						button("连续自动挑战").button_pressed = true
						press("AbyssBegin")
				"route":
					var target := "event" if floor_number == 2 else ("rest" if floor_number % 2 == 0 else "shop")
					press("NodeChoice_" + target)
					check(app.current_screen == "abyss", "Route entry waits for its nested decision")
				"event":
					check("收益：" in texts(app.main_body) and "花费：" in texts(app.main_body), "Event benefits and costs visible")
					var options: Array = app.model.node_options().options
					var chosen := ""
					for option in options:
						if option.enabled and int(option.get("cost", 0)) == 0 and str(option.get("risk", "")).is_empty():
							chosen = str(option.id)
							break
					if chosen.is_empty():
						for option in options:
							if option.enabled:
								chosen = str(option.id)
								break
					press("NodeChoice_" + chosen)
				"rest":
					var hp_before := 0
					for member in app.model.state.abyss.savedPartyState:
						hp_before += int(member.currentHp)
					press("NodeChoice_recover")
					var hp_after := 0
					for member in app.model.state.abyss.savedPartyState:
						hp_after += int(member.currentHp)
					check(hp_after >= hp_before, "Rest button restores real persistent party health")
				"shop":
					var items: Array = app.model.abyss_shop_items()
					if items[0].enabled:
						press("RunShop_heal")
						check(button("RunShop_heal").disabled, "Bought shop item becomes sold out")
						check(app.model.state.abyss.rogue.temporaryCurrency == coins_before - int(items[0].cost), "Shop spends exact run coin price")
						check(app.current_screen == "abyss", "Buying never automatically exits shop")
					press("RunShopLeave")
			check(nested < 4, "Decision chain terminates")
		check(app.current_screen == "battle", "Explicitly resolving decisions resumes automatic encounter")
	check(victory_count == 20, "Real geared party completes all20 encounters through UI settlement")
	for phase in ["reward", "route", "event", "shop", "rest"]:
		check(observed.has(phase), "Exercised actual " + phase + " screen")
	check(not app.model.abyss_run_active() and app.model.state.abyss.currentFloor == 1, "Completed run returns to start")
	check(app.model.state.abyss.meta.runsCompleted == 1 and app.model.state.abyss.meta.currency > 400 - upgrade_cost, "Victory banks permanent progress")
	check("上一轮" in texts(app.main_body) and "20 层" in texts(app.main_body), "Run summary remains available in hub")
	check(not button("AbyssDifficulty_1").disabled, "Completing rank0 visibly unlocks rank1")
	press("AbyssDifficulty_1")
	check(app.model.state.abyss.meta.selectedDifficulty == 1, "Difficulty selection commits model setting")
	check("攻击 +100%" in texts(app.main_body), "Selected rank explains its exact challenge multiplier")
	press("AbyssDifficulty_0")
	check(app._localized_combat_text("角色 · spd_down") == "角色 · 减速", "Status feedback uses Chinese names")
	# Real narrow-window layouts cover every new view with a second run.
	root.size = Vector2i(480, 800)
	await frames()
	await frames()
	app.navigate("abyss")
	await fit_page("portrait hub")
	press("永久成长")
	await fit_page("portrait permanent upgrades")
	press("返回远征地图")
	button("连续自动挑战").button_pressed = true
	press("AbyssBegin")
	for floor_number in range(1, 9):
		if not await battle_to_result():
			check(false, "Portrait setup battle victorious")
			break
		var nested := 0
		while app._abyss_has_decision() and nested < 4:
			nested += 1
			var phase: String = app.model.state.abyss.rogue.nextStep.type
			await fit_page("portrait " + phase)
			await capture("portrait-" + phase)
			match phase:
				"reward": press("选择此项回响")
				"route": press("NodeChoice_event" if floor_number == 2 else ("NodeChoice_rest" if floor_number % 2 == 0 else "NodeChoice_shop"))
				"event":
					for option in app.model.node_options().options:
						if option.enabled:
							press("NodeChoice_" + str(option.id))
							break
				"rest": press("NodeChoice_recover")
				"shop": press("RunShopLeave")
	# Cancel then confirm retreat; permanent progress is still banked.
	app.navigate("abyss")
	press("返回", app.overlay)
	check(app.current_screen == "battle", "Cancelled retreat preserves active encounter")
	var permanent_before: int = app.model.state.abyss.meta.currency
	app.navigate("abyss")
	press("确认", app.overlay)
	check(not app.model.abyss_run_active() and app.model.state.abyss.meta.currency == permanent_before, "Confirmed retreat resets run while retaining earned memory")
	app.queue_free()
	await frames()
	if failures.is_empty():
		print("PASS UI V2: %d checks" % checks)
		quit(0)
	else:
		print("FAIL UI V2: %d / %d checks" % [failures.size(), checks])
		quit(1)
