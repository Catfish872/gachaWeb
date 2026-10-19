extends SceneTree

var app
var checks := 0
var failures: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("UI CHECK: " + message)

func find_button(node: Node, needle: String) -> Button:
	if node is Button and needle in node.text:
		return node
	for child in node.get_children():
		var found := find_button(child, needle)
		if found != null: return found
	return null

func texts(node: Node) -> String:
	var result := str(node.text) + "\n" if node is Label or node is Button else ""
	for child in node.get_children(): result += texts(child)
	return result

func frame() -> void:
	await process_frame
	await process_frame

func run() -> void:
	root.size = Vector2i(1440, 900)
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await frame()
	app.model = load("res://scripts/game_model.gd").new("")
	app.battle = load("res://scripts/battle_model.gd").new(app.model.catalog)
	app.navigate("home")
	await frame()
	check(app.main_body.get_child_count() > 0, "Home constructs content")
	check("虚空裂变" in texts(app), "Original game title retained")
	check("100 / 100" in texts(app), "Stamina maximum shown accurately")
	for page in ["story", "summon", "party", "growth", "relics", "abyss", "shop", "save"]:
		app.navigate(page)
		await frame()
		check(app.current_screen == page and app.main_body.get_child_count() > 0, "Default state renders " + page)
	app.navigate("party")
	check(app.draft_team.size() == 2, "Null default party seat filtered")
	check("待命席位 3" in texts(app.main_body), "Default empty third seat rendered")
	app._toggle_team("ember")
	check(app.draft_team.size() == 1, "Party remove action")
	app._toggle_team("ember")
	find_button(app.main_body, "保存出战队伍").pressed.emit()
	check(app.model.state.team.has("ember"), "Party save button persists")
	app.selected_character = "kaldi"
	app.navigate("growth")
	check("尚未获得" in texts(app.main_body), "Unowned codex detail available")
	check("对处于燃烧状态" in texts(app.main_body), "Passive description exposed")
	check("炎牙斩" in texts(app.main_body), "Skills exposed")
	app.navigate("shop")
	var gems_before: int = app.model.state.resources.diamonds
	find_button(app.main_body, "模拟领取").pressed.emit()
	check(app.model.state.resources.diamonds > gems_before, "Simulated recharge button grants bundle")
	app.navigate("summon")
	var saved_balance: int = app.model.state.resources.diamonds
	app.model.state.resources.diamonds = 15
	app.navigate("summon")
	check(find_button(app.main_body, "祈愿一次").disabled and find_button(app.main_body, "祈愿十次").disabled, "Insufficient currency disables summon buttons")
	app.model.state.resources.diamonds = 160
	app.navigate("summon")
	check(not find_button(app.main_body, "祈愿一次").disabled and find_button(app.main_body, "祈愿十次").disabled, "Affordability handles single and ten-pull independently")
	app.model.state.resources.diamonds = saved_balance
	app.navigate("summon")
	app.model.rng.seed = 45
	app._pull(1)
	await frame()
	check(app.summon_results.size() == 1, "Single pull through UI")
	find_button(app.overlay, "揭晓旅者").pressed.emit()
	check(app.summon_flipped, "Reveal button flips card")
	find_button(app.overlay, "查看结果").pressed.emit()
	check("祈愿结果" in texts(app.overlay), "Summon summary visible")
	find_button(app.overlay, "收下").pressed.emit()
	check(app.overlay.get_child_count() == 0, "Summon closes")
	app.model.state.resources.diamonds = 100000
	app._pull(10)
	find_button(app.overlay, "全部揭示").pressed.emit()
	check(app.summon_results.size() == 10, "Ten-pull and skip reveal")
	app._clear_overlay()
	for id in app.model.catalog.CharacterData:
		app.model.state.ownedCharacters[id] = app.model.default_character()
		app.model.state.ownedCharacters[id].shards = 200
	app.model.state.resources.gold = 10000000
	app.selected_character = "kaldi"
	app.navigate("growth")
	var old_exp: int = app.model.state.ownedCharacters.kaldi.exp
	find_button(app.main_body, "训练一次").pressed.emit()
	check(app.model.state.ownedCharacters.kaldi.level == 2, "Training button grants level")
	find_button(app.main_body, "解锁").pressed.emit()
	check(app.model.state.ownedCharacters.kaldi.constellation == 1, "Constellation button unlocks")
	for i in range(8):
		app.model.state.relics.append(app.model.generate_relic(3 + i % 3, app.model.catalog.RelicSlots[i % 5].id))
	app.navigate("relics")
	await frame()
	check(not app.selected_relic.is_empty(), "Relic first selection")
	var relic = app.model.get_relic(app.selected_relic)
	find_button(app.main_body, "强化 +1").pressed.emit()
	check(relic.level == 1, "Relic upgrade button")
	find_button(app.main_body, "装备给角色").pressed.emit()
	find_button(app.overlay, "焰龙").pressed.emit()
	check(relic.equippedBy == "kaldi", "Relic equip UI")
	find_button(app.main_body, "卸下").pressed.emit()
	check(relic.equippedBy == null, "Relic unequip UI")
	find_button(app.main_body, "强化至 +25").pressed.emit()
	find_button(app.overlay, "确认").pressed.emit()
	check(relic.level == 25, "Relic max upgrade confirmed")
	app._batch_salvage()
	check("全部未强化" in texts(app.overlay), "Batch salvage unupgraded control")
	app._clear_overlay()
	app.navigate("save")
	check("旅者 10 位" in texts(app.main_body), "Save summary matches owned count")
	find_button(app.main_body, "切换至此档案").pressed.emit()
	find_button(app.overlay, "确认").pressed.emit()
	check(app.model.active_slot == 2, "Save slot switch confirmed")
	app.model.load_slot(1)
	app.navigate("story")
	app._begin_stage("ch1_1")
	await frame()
	check(app.dialogue_key == "ch1_1_pre", "Prebattle dialogue opens")
	find_button(app.overlay, "跳过剧情").pressed.emit()
	await frame()
	check(app.current_screen == "battle", "Dialogue skip starts battle")
	check("第 1 波" in texts(app.main_body), "First wave one based")
	check(app.unit_cards.size() >= 4, "Arena contains allies and enemies")
	while app.battle.state.phase == "enemy_turn":
		app._do_battle_action("", "", true)
	check(find_button(app.main_body, "施放") != null, "Player skill controls available")
	var turn_before: int = app.battle.state.get("actionCount", 0)
	find_button(app.main_body, "施放").pressed.emit()
	check(app.battle_log.size() > 0, "Manual action emits combat log")
	app.navigate("story")
	check("离开战斗" in texts(app.overlay), "Navigation requires retreat confirmation")
	find_button(app.overlay, "返回").pressed.emit()
	check(app.current_screen == "battle", "Cancelled retreat preserves battle")
	app.navigate("story")
	find_button(app.overlay, "确认").pressed.emit()
	check(app.current_screen == "story", "Confirmed retreat returns to map")
	# Render every character and every roster filter against the complete collection.
	for id in app.model.catalog.CharacterData:
		app.selected_character = id
		app.navigate("growth")
		await frame()
		check(str(app.model.catalog.CharacterData[id].name) in texts(app.main_body), "Codex detail " + id)
	for filter in ["fire", "water", "wind", "thunder", "全部"]:
		app.character_filter = filter
		app.navigate("party")
		await frame()
		check(app.main_body.get_child_count() > 0, "Roster filter " + filter)
	# Complete native battle through UI engine dispatch and check reward result.
	app.model.state.team = ["kaldi", "ayla", "gus"]
	for id in app.model.state.team:
		app.model.state.ownedCharacters[id].level = 10
	var prepared = app.model.prepare_stage("ch1_1")
	app._start_battle(prepared.config)
	var cap := 0
	while app.battle.state.phase not in ["victory", "defeat"] and cap < 400:
		app._do_battle_action("", "", true)
		cap += 1
		await process_frame
	check(app.battle.state.phase == "victory", "UI battle loop wins")
	await create_timer(0.8).timeout
	check(app.battle_settled and app.last_reward.get("success", false), "UI settles battle reward")
	check("远征胜利" in texts(app.overlay), "Victory overlay shown")
	find_button(app.overlay, "继续旅程").pressed.emit()
	check(app.dialogue_key == "ch1_1_post", "Postbattle dialogue shown")
	app._finish_dialogue()
	check(app.current_screen == "story", "Postbattle dialogue returns to chapter")
	# All dialogue paths can be rendered and skipped with callbacks.
	for key in app.model.catalog.DialogueData:
		app._play_dialogue(key, func(): pass)
		check(app.dialogue_key == key, "Dialogue script " + key)
		app._finish_dialogue()

	# Native file dialogs dispatch per-slot export/import and preserve active slot.
	app.navigate("save")
	app._export_dialog(1)
	var dialog: FileDialog
	for child in app.get_children():
		if child is FileDialog: dialog = child
	check(dialog != null, "Export opens native FileDialog")
	var exported := "user://ui-roundtrip-slot1.json"
	dialog.file_selected.emit(exported)
	check(FileAccess.file_exists(exported), "Export dialog writes chosen file")
	await frame()
	app._import_dialog(3)
	for child in app.get_children():
		if child is FileDialog: dialog = child
	dialog.file_selected.emit(exported)
	check("档案 3" in texts(app.overlay), "Import confirmation identifies target slot")
	find_button(app.overlay, "确认").pressed.emit()
	check(app.model.active_slot == 1, "Inactive slot import preserves active slot")
	check(app.model.slot_summaries()[2].ownedCount == 10, "Imported third slot matches collection")
	# Repeated summon controls and balanced results layout.
	app.navigate("summon")
	app._pull(10)
	app._summon_summary()
	await frame()
	check(find_button(app.overlay, "再祈愿 10 次") != null, "Repeat ten-pull control exposed")
	find_button(app.overlay, "收下").pressed.emit()
	# Automatic combat pauses at every real v2 decision and resumes only after
	# each nested choice has been explicitly resolved through its UI button.
	app.model.reset_abyss()
	app.navigate("abyss")
	var automatic: CheckBox = find_button(app.main_body, "连续自动挑战")
	automatic.button_pressed = true
	find_button(app.main_body, "挑战第").pressed.emit()
	for floor_number in range(1, 4):
		check(app.current_screen == "battle" and app.battle_config.floor == floor_number, "Automatic abyss starts floor " + str(floor_number))
		var steps := 0
		while app.battle.state.phase not in ["victory", "defeat"] and steps < 600:
			app._do_battle_action("", "", true)
			steps += 1
			await process_frame
		check(app.battle.state.phase == "victory", "Automatic abyss wins floor " + str(floor_number))
		await create_timer(0.75).timeout
		check(app.current_screen == "abyss", "Automatic abyss stops at decision after floor " + str(floor_number))
		if floor_number == 2:
			check(app.model.state.abyss.rogue.nextStep.type == "route", "Floor two shows route choice")
			app.main_body.find_child("NodeChoice_rest", true, false).pressed.emit()
			check(app.current_screen == "abyss" and app.model.state.abyss.rogue.nextStep.type == "rest", "Route choice waits for nested rest decision")
			app.main_body.find_child("NodeChoice_recover", true, false).pressed.emit()
		else:
			check(app.model.state.abyss.rogue.pendingChoices.size() == 3, "Three actual abyss choices shown")
			find_button(app.main_body, "选择此项回响").pressed.emit()
	check(app.current_screen == "battle" and app.battle_config.floor == 4, "Resolved choices resume requested continuous run")
	check(app.model.state.abyss.rogue.selectedRewards.size() == 2, "Both floor one and three blessings saved")
	find_button(app.main_body, "自动 · 开启").pressed.emit()
	check(not app.abyss_auto_continue and not app.battle_auto, "Turning auto off cancels continuous advancement")
	app.navigate("abyss")
	find_button(app.overlay, "确认").pressed.emit()
	# Transactional settlement failure remains recoverable through the actual retry button.
	var retry_config = app.model.prepare_stage("ch1_1")
	app._start_battle(retry_config.config)
	while app.battle.state.phase not in ["victory", "defeat"]:
		app.battle.auto_step()
	app.model.save_blocked = true
	app._finish_battle()
	check(app.settlement_error, "Settlement failure enters recoverable state")
	app.navigate("save")
	check(app.current_screen == "battle", "Failed settlement keeps pending battle accessible")
	app.model.save_blocked = false
	find_button(app.overlay, "重试保存结算").pressed.emit()
	await create_timer(0.75).timeout
	check(not app.settlement_error and app.last_reward.success, "Settlement retry succeeds once storage recovers")
	# A completed old battle must not display a stale result on a newer scene.
	app.navigate("story")
	var stale_config = app.model.prepare_stage("ch1_1")
	app._start_battle(stale_config.config)
	while app.battle.state.phase not in ["victory", "defeat"]:
		app.battle.auto_step()
	app._finish_battle()
	app.navigate("home")
	await create_timer(0.75).timeout
	check(app.current_screen == "home" and app.overlay.get_child_count() == 0, "Late settlement animation cannot reopen modal after navigation")
	# First Continue completes typing and only the next click advances the story.
	app._play_dialogue("ch1_1_pre", func(): pass)
	var old_line: int = app.dialogue_index
	app._next_dialogue()
	check(app.dialogue_index == old_line and app.dialogue_prose.visible_characters == -1, "First Continue reveals complete current line")
	app._next_dialogue()
	check(app.dialogue_index == old_line + 1, "Second Continue advances dialogue")
	app._finish_dialogue()

	# Portrait responsive shell covers every screen too.
	root.size = Vector2i(480, 800)
	await frame()
	await frame()
	check(app.compact, "Real portrait window triggers compact layout")
	check(app.size.x <= 600, "Portrait logical viewport has readable scale")
	for page in ["home", "story", "summon", "party", "growth", "relics", "abyss", "shop", "save"]:
		app.navigate(page)
		await frame()
		check(app.main_body.get_child_count() > 0, "Portrait renders " + page)
		check(app.main_body.get_combined_minimum_size().x <= app.main_body.get_parent().size.x + 2, "Portrait page fits horizontally: " + page + " min=" + str(app.main_body.get_combined_minimum_size().x) + " available=" + str(app.main_body.get_parent().size.x))
	app.queue_free()
	await frame()
	if failures.is_empty():
		print("PASS UI: %d checks" % checks)
		quit(0)
	else:
		print("FAIL UI: %d / %d checks" % [failures.size(), checks])
		quit(1)
