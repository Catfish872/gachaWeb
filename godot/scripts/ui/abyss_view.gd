extends RefCounted

# The expedition hub reads only model-owned state. Every decision is committed by
# the model before the screen is refreshed or automatic combat is resumed.
const VIOLET := Color("c4a4e8")
const GREEN := Color("a9cdb0")
const PHASE_NAMES := {"none": "准备出战", "reward": "选择祝福", "route": "选择路线", "event": "随机事件", "shop": "旅途商店", "rest": "篝火休整"}

static func render(app) -> void:
	var abyss: Dictionary = app.model.state.get("abyss", {})
	var rogue: Dictionary = abyss.get("rogue", {})
	var meta: Dictionary = abyss.get("meta", {})
	var phase := str(rogue.get("nextStep", {}).get("type", "none"))
	var active: bool = app.model.abyss_run_active()
	var floor_number := int(abyss.get("currentFloor", 1))
	app._page_title("深渊远征", "二十层裂隙远征 · 带着每一次探索的收获归来")
	var tabs = app._hbox(app.main_body, 12)
	app._button(tabs, "远征地图", func(): app.abyss_panel = "expedition"; app._render_screen(), app.abyss_panel == "expedition")
	app._button(tabs, "永久成长 · %d 记忆碎片" % int(meta.get("currency", 0)), func(): app.abyss_panel = "meta"; app._render_screen(), app.abyss_panel == "meta")
	if app.abyss_panel == "meta":
		_render_meta(app, meta, active)
		return
	var deciding := phase != "none"
	if active:
		var strip = app._panel(app.main_body, VIOLET.darkened(0.55), 12)
		var sv = app._vbox(strip, 5)
		app._label(sv, "第 %02d 层已通关 · 下一层 %02d / 20" % [maxi(1, floor_number - 1), floor_number] if deciding else "准备挑战第 %02d 层 / 20" % floor_number, 16, VIOLET, true)
		app._label(sv, "裂隙币 %d（本轮）   ·   记忆碎片 %d（永久）" % [int(rogue.get("temporaryCurrency", 0)), int(meta.get("currency", 0))], 14, app.GOLD, true)
	else:
		var hero = app._scene_panel(app.main_body, "res://assets/wilderness.png", 224 if not app.compact else 246)
		var shade := ColorRect.new()
		shade.color = Color(0.08, 0.04, 0.15, 0.50)
		shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hero.add_child(shade)
		var v = app._vbox(hero, 10)
		v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		v.offset_left = 24
		v.offset_right = -24
		v.offset_top = 22
		v.offset_bottom = -20
		app._label(v, "裂 隙 远 征   /   %s" % PHASE_NAMES.get(phase, "探索途中"), 12, VIOLET)
		app._label(v, "第 %02d 层  /  20" % mini(floor_number, 20) if active else "向裂隙深处", 36 if app.compact else 42, app.TEXT)
		app._label(v, "生命、能量与冷却跨层保留。路线、事件与祝福由你决定。", 14, app.TEXT, true)
		app._label(v, "最高纪录 %d 层    ·    本轮祝福 %d 项" % [int(abyss.get("maxFloor", 0)), rogue.get("selectedRewards", []).size()], 14, VIOLET, true)
		app._progress(v, maxi(0, floor_number - 1) if active else 0, 20, VIOLET, 5)
		var wallets = app._grid(app.main_body, 1 if app.compact else 2)
		_wallet(app, wallets, "裂隙币", int(rogue.get("temporaryCurrency", 0)), "本轮使用 · 商店补给与事件交易 · 结算后清空", app.GOLD)
		_wallet(app, wallets, "记忆碎片", int(meta.get("currency", 0)), "永久保留 · 用于营地升级 · 与金币、星尘晶分别结算", VIOLET)
	if not active and not abyss.get("lastRun", {}).is_empty():
		_render_summary(app, abyss.lastRun)
	var auto_box := CheckBox.new()
	auto_box.text = "连续自动挑战 · 遇到任何选择时暂停"
	auto_box.add_theme_font_size_override("font_size", 14 if app.compact else 16)
	auto_box.button_pressed = app.abyss_auto_continue
	auto_box.toggled.connect(func(on): app.abyss_auto_continue = on; app.battle_auto = true if on else app.battle_auto)
	if not deciding:
		app.main_body.add_child(auto_box)
	if phase == "reward" or not rogue.get("pendingChoices", []).is_empty():
		_render_blessings(app, rogue)
	elif phase == "shop":
		_render_shop(app, rogue)
	elif phase in ["route", "event", "rest"]:
		_render_node(app, phase)
	else:
		_render_departure(app, floor_number, active)
	if deciding:
		app.main_body.add_child(auto_box)
	_render_party(app, abyss)
	_render_path(app, floor_number, active)
	_render_build(app, rogue)
	if active:
		var footer = app._panel(app.main_body, app.LINE, 18)
		var fv = app._vbox(footer, 10)
		app._label(fv, "整装归营", 18, app.TEXT)
		app._label(fv, "可随时免费结束本轮。已经获得的永久资源保留，裂隙币与本轮祝福随远征结束。", 13, app.MUTED, true)
		app._button(fv, "结束本轮 · 免费重置", func(): app._confirm("结束本轮远征？", "回到第 1 层重新出发。当前裂隙币、祝福与队伍状态将清空，永久资源和成长保留。", func():
			app.abyss_auto_continue = false
			app._abyss_operation(app.model.reset_abyss(), "已返回营地，可以购买永久成长")))

static func _wallet(app, parent: Node, title: String, amount: int, description: String, color: Color) -> void:
	var p = app._panel(parent, color.darkened(0.58), 16)
	var v = app._vbox(p, 6)
	app._label(v, "%s  %d" % [title, amount], 23, color)
	app._label(v, description, 12, app.MUTED, true)

static func _render_departure(app, floor_number: int, active: bool) -> void:
	var p = app._panel(app.main_body, VIOLET.darkened(0.45), 20)
	var v = app._vbox(p, 10)
	var boss := floor_number % 10 == 0
	var elite := floor_number % 5 == 0 and not boss
	app._label(v, "首领战将至" if boss else ("精英迎战" if elite else ("继续深入" if active else "准备新的远征")), 23, VIOLET)
	var row = app._responsive_box(v, app.compact, 12)
	var begin = app._button(row, "挑战第 %d 层   →" % floor_number, func(): app._begin_abyss(), true)
	begin.name = "AbyssBegin"
	app._button(row, "查看出战队伍", func(): app.navigate("party"))
	app._label(v, "挑战消耗 0 体力。通关获得裂隙币与记忆碎片，20 层完成本轮；失败后可带着永久成长再次出发。", 15, app.MUTED, true)
	_render_difficulty(app, v, active)

static func _render_blessings(app, rogue: Dictionary) -> void:
	app._section("裂隙回响 · 三选一", "选择一项，本轮持续生效")
	app._label(app.main_body, "自动挑战已停在这里。确认祝福后，才会继续前进。", 13, app.MUTED, true)
	var grid = app._grid(app.main_body, 1 if app.compact else 3)
	for raw in rogue.get("pendingChoices", []):
		var choice: Dictionary = raw if raw is Dictionary else app._abyss_reward(str(raw))
		var color: Color = {"gold": app.GOLD, "blue": app.CYAN, "white": app.TEXT}.get(str(choice.get("rarity", "white")), app.TEXT)
		var p = app._panel(grid, color.darkened(0.3), 20)
		var v = app._vbox(p, 12)
		app._label(v, {"gold": "金色祝福", "blue": "蓝色祝福", "white": "基础祝福"}.get(str(choice.get("rarity", "white")), "裂隙祝福"), 12, color)
		app._label(v, str(choice.get("name", "裂隙回响")), 24, color, true)
		app._label(v, str(choice.get("target", "全队")), 13, app.MUTED, true)
		var desc = app._label(v, str(choice.get("description", "")), 16, app.TEXT, true)
		desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		app._label(v, "免费选择 · 本轮持续生效", 12, app.MUTED, true)
		var b = app._button(v, "选择此项回响", func(): app._abyss_operation(app.model.choose_abyss_reward(str(choice.get("choiceId", choice.get("id", "")))), "回响已融入本轮构筑", true), true)
		b.name = "Blessing_" + str(choice.get("choiceId", choice.get("id", "")))

static func _render_node(app, phase: String) -> void:
	var node: Dictionary = app.model.node_options()
	var accent: Color = GREEN if phase == "rest" else (VIOLET if phase == "event" else app.CYAN)
	var banner = app._panel(app.main_body, accent.darkened(0.4), 16)
	var intro = app._vbox(banner, 7)
	app._label(intro, str(node.get("title", "旅途抉择")), 28, app.TEXT, true)
	app._label(intro, str(node.get("description", "")), 16, app.MUTED, true)
	var options: Array = node.get("options", [])
	var grid = app._grid(app.main_body, 1 if app.compact else mini(3, maxi(1, options.size())))
	for option in options:
		var p = app._panel(grid, accent.darkened(0.5), 20)
		var v = app._vbox(p, 12)
		app._label(v, str(option.get("label", "继续探索")), 22, accent, true)
		var desc = app._label(v, str(option.get("description", "")), 15, app.TEXT, true)
		desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		if not str(option.get("reward", "")).is_empty():
			app._label(v, "收益：" + str(option.reward), 13, GREEN, true)
		if not str(option.get("risk", "")).is_empty():
			app._label(v, "风险：" + str(option.risk), 13, app.RED, true)
		var cost := int(option.get("cost", 0))
		app._label(v, "花费：%d 裂隙币" % cost if cost > 0 else "花费：免费", 13, app.GOLD, true)
		var enabled := bool(option.get("enabled", true))
		var b = app._button(v, "选择此路" if phase == "route" else "确认选择", func(): app._abyss_operation(app.model.choose_abyss_node(str(option.id)), "", true), true)
		b.name = "NodeChoice_" + str(option.id)
		b.disabled = not enabled
		if not enabled:
			app._label(v, str(option.get("disabledReason", "裂隙币不足，选择其他行动可继续")), 12, app.RED, true)

static func _render_shop(app, rogue: Dictionary) -> void:
	app._section("旅途商店", "每件商品本次到访限购一件")
	app._label(app.main_body, "可用裂隙币 %d。补给与祝福即时生效，离店后继续路线。" % int(rogue.get("temporaryCurrency", 0)), 15, app.MUTED, true)
	var items: Array = app.model.abyss_shop_items()
	var grid = app._grid(app.main_body, 1 if app.compact else 3)
	for item in items:
		var sold := bool(item.get("sold", false))
		var p = app._panel(grid, app.LINE if sold else app.GOLD.darkened(0.5), 18)
		var v = app._vbox(p, 11)
		app._label(v, "已售罄" if sold else "限购 1 件", 12, app.MUTED if sold else app.GOLD)
		app._label(v, str(item.get("name", "旅行补给")), 22, app.TEXT, true)
		var desc = app._label(v, str(item.get("description", "")), 15, app.MUTED, true)
		desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		app._label(v, "%d 裂隙币" % int(item.get("cost", 0)), 21, app.GOLD)
		var b = app._button(v, "已购买" if sold else "购买补给", func(): app._abyss_operation(app.model.purchase_abyss_item(str(item.id)), "补给已收入行囊"), not sold)
		b.name = "RunShop_" + str(item.id)
		b.disabled = sold or not bool(item.get("enabled", true))
		if not sold and b.disabled:
			app._label(v, str(item.get("disabledReason", "裂隙币不足或祝福已达上限")), 12, app.RED, true)
	var leave = app._button(app.main_body, "离开商店 · 继续远征   →", func(): app._abyss_operation(app.model.leave_abyss_shop(), "已离开旅途商店", true))
	leave.name = "RunShopLeave"

static func _render_meta(app, meta: Dictionary, active: bool) -> void:
	var p = app._panel(app.main_body, VIOLET.darkened(0.4), 24)
	var v = app._vbox(p, 10)
	app._label(v, "记忆营地", 32, VIOLET)
	app._label(v, "可用记忆碎片  %d" % int(meta.get("currency", 0)), 25, app.GOLD)
	app._label(v, "远征中积累的记忆碎片永久保留。营地升级作用于深渊，跨轮生效。", 16, app.TEXT, true)
	app._label(v, "当前远征结束后可升级；新的能力将在下轮出发时生效。" if active else "营地已开放。选择升级，为下一次远征做好准备。", 14, app.MUTED, true)
	var grid = app._grid(app.main_body, 1 if app.compact else 2)
	for upgrade in app.model.meta_upgrade_list():
		var card = app._panel(grid, VIOLET.darkened(0.55), 22)
		var col = app._vbox(card, 12)
		var level := int(upgrade.get("level", 0))
		var maximum := int(upgrade.get("maxLevel", 1))
		app._label(col, str(upgrade.get("name", "营地升级")), 25, app.TEXT, true)
		app._label(col, "等级 %d / %d" % [level, maximum], 14, VIOLET)
		app._progress(col, level, maximum, VIOLET, 5)
		app._label(col, str(upgrade.get("description", "")), 16, app.MUTED, true)
		var capped := level >= maximum
		var b = app._button(col, "已满级" if capped else "升级 · %d 记忆碎片" % int(upgrade.get("cost", 0)), func(): app._abyss_operation(app.model.purchase_meta_upgrade(str(upgrade.id)), "营地升级完成"), not capped)
		b.name = "MetaUpgrade_" + str(upgrade.id)
		b.disabled = capped or not bool(upgrade.get("enabled", false))
		if b.disabled and not capped:
			app._label(col, "本轮结束后可升级" if active else "记忆碎片不足，继续远征可积累", 12, app.MUTED, true)
	app._label(app.main_body, "累计获得 %d 记忆碎片    ·    通关 %d 轮    ·    战败 %d 轮" % [int(meta.get("totalEarned", 0)), int(meta.get("runsCompleted", 0)), int(meta.get("runsLost", 0))], 13, app.MUTED, true)
	app._button(app.main_body, "返回远征地图", func(): app.abyss_panel = "expedition"; app._render_screen())

static func _render_party(app, abyss: Dictionary) -> void:
	app._section("远征队伍", "生命与能量延续到下一场战斗")
	var persisted = abyss.get("savedPartyState")
	var members: Array = persisted if persisted is Array else app.model.battle_party(true)
	var row = app._grid(app.main_body, 1 if app.compact else 3)
	for unit in members:
		var max_hp := maxi(1, int(unit.get("maxHp", unit.get("stats", {}).get("maxHp", 1))))
		var hp := int(unit.get("currentHp", max_hp))
		var p = app._panel(row, app.LINE, 14)
		var v = app._vbox(p, 8)
		app._label(v, app._char_name(str(unit.get("id", ""))), 18, app.TEXT, true)
		app._label(v, "生命 %d / %d" % [hp, max_hp] if hp > 0 else "已倒下 · 可在旅途中复苏", 12, GREEN if hp > 0 else app.RED, true)
		app._progress(v, hp, max_hp, GREEN if hp > 0 else app.RED, 6)
		app._label(v, "能量 %d / 100" % int(unit.get("energy", 0)), 12, app.CYAN)

static func _render_path(app, floor_number: int, active: bool) -> void:
	var p = app._panel(app.main_body, app.LINE, 18)
	var v = app._vbox(p, 12)
	app._label(v, "远征进度", 20, app.TEXT)
	app._label(v, "每十层迎战首领 · 层间抉择会改变接下来的旅程", 12, app.MUTED, true)
	var grid = app._grid(v, 5 if app.compact else 10)
	for marker in app.model.abyss_route_preview():
		var number := int(marker.floor)
		var passed := active and number < floor_number
		var current := number == floor_number and active
		var cell = app._panel(grid, VIOLET if current else app.LINE, 5)
		var col = app._vbox(cell, 4)
		app._center_label(col, "✓" if passed else ("♜" if number % 10 == 0 else ("◆" if number % 5 == 0 else "◇")), 19, app.GOLD if number % 10 == 0 else (VIOLET if current else app.MUTED))
		app._center_label(col, "%02d" % number, 13, app.TEXT if current else app.MUTED)
		app._center_label(col, "首领" if number % 10 == 0 else ("精英" if number % 5 == 0 else "战斗"), 10, app.MUTED)
		app._center_label(col, {"reward": "祝福", "shop": "商店", "rest": "休整", "route": "路线", "complete": "归营", "end": "归营"}.get(str(marker.get("after", "")), "归营"), 10, VIOLET)

static func _render_build(app, rogue: Dictionary) -> void:
	app._section("当前构筑", "祝福共同作用于本轮队伍")
	var focus: Dictionary = rogue.get("characterFocus", {})
	if not focus.is_empty():
		var focus_text: Array = []
		for id in focus:
			focus_text.append("%s %.0f%%" % [app._char_name(str(id)), float(focus[id]) * 100.0])
		app._label(app.main_body, "专属回响偏向  " + " · ".join(focus_text), 13, app.CYAN, true)
	var rewards: Array = rogue.get("selectedRewards", [])
	if rewards.is_empty():
		app._label(app.main_body, "通过战斗、事件和商店获取祝福，塑造这一轮的战术。", 15, app.MUTED, true)
	else:
		var grid = app._grid(app.main_body, 1 if app.compact else 2)
		for raw in rewards:
			var reward: Dictionary = raw if raw is Dictionary else app._abyss_reward(str(raw))
			var p = app._panel(grid, app.LINE, 16)
			var v = app._vbox(p, 8)
			app._label(v, str(reward.get("name", "裂隙回响")), 20, app.GOLD, true)
			app._label(v, str(reward.get("description", "")), 14, app.MUTED, true)

static func _render_summary(app, summary: Dictionary) -> void:
	var p = app._panel(app.main_body, VIOLET.darkened(0.5), 18)
	var v = app._vbox(p, 8)
	var outcome := str(summary.get("outcome", ""))
	app._label(v, "上一轮 · 裂隙已平息" if outcome in ["victory", "completed", "complete"] else "上一轮 · 已返回营地", 21, VIOLET, true)
	app._label(v, "通关 %d 层   ·   收获 %d 记忆碎片   ·   构筑 %d 项祝福" % [int(summary.get("floorsCleared", 0)), int(summary.get("metaEarned", 0)), int(summary.get("blessings", 0))], 14, app.TEXT, true)
	app._button(v, "使用记忆碎片 · 查看永久成长", func(): app.abyss_panel = "meta"; app._render_screen())


static func _render_difficulty(app, parent: Node, active: bool) -> void:
	var options: Array = app.model.abyss_difficulty_options()
	var selected: Dictionary = {}
	for option in options:
		if option.selected:
			selected = option
	if active:
		app._label(parent, "本轮难度：%s · 已锁定" % str(selected.get("name", "初探")), 13, VIOLET, true)
		return
	var row = app._grid(parent, 2 if app.compact else 4)
	for option in options:
		var b = app._button(row, str(option.name) + (" · 已锁定" if not option.unlocked else (" · 当前" if option.selected else "")), func(): app._abyss_operation(app.model.set_abyss_difficulty(int(option.id)), ""), bool(option.selected))
		b.name = "AbyssDifficulty_" + str(option.id)
		b.disabled = not bool(option.enabled)
		b.tooltip_text = str(option.description) if option.unlocked else "通关前一难度的 20 层后解锁"
	app._label(parent, str(selected.get("description", "")), 13, app.MUTED, true)
	app._label(parent, "通关当前难度的 20 层，可解锁下一难度。", 12, VIOLET, true)
