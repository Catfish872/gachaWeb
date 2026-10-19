extends Control

const INK := Color("080e19")
const PANEL := Color("111b2b")
const LINE := Color("293447")
const TEXT := Color("ece7dc")
const MUTED := Color("94a1b4")
const GOLD := Color("dfb779")
const CYAN := Color("7dcac9")
const RED := Color("ea827a")
const FONT = preload("res://assets/fonts/NotoSansSC.otf")
const SYMBOL_FONT = preload("res://assets/fonts/NotoSansSymbols2-Regular.ttf")
const Atmosphere = preload("res://scripts/ui/atmosphere.gd")
const BattleFX = preload("res://scripts/ui/battle_fx.gd")
const AbyssView = preload("res://scripts/ui/abyss_view.gd")
const UpdateChecker = preload("res://scripts/update_checker.gd")
const STATUS_NAMES := {"burn": "燃烧", "freeze": "冰冻", "shock": "感电", "electrify": "感电", "poison": "中毒", "regen": "再生", "def_up": "防御提升", "atk_up": "攻击提升", "spd_up": "速度提升", "def_down": "防御降低", "atk_down": "攻击降低", "spd_down": "减速", "taunt": "嘲讽", "shield": "护盾", "bleed": "流血", "stun": "眩晕", "vulnerable": "易伤", "invincible": "无敌"}
const TABS := [["home", "旅者营地", "01"], ["story", "世界探索", "02"], ["summon", "星辰祈愿", "03"], ["party", "冒险编队", "04"], ["growth", "角色养成", "05"], ["relics", "遗物工坊", "06"], ["abyss", "深渊远征", "07"], ["shop", "补给商店", "08"], ["save", "旅程档案", "09"]]

var model
var battle
var current_screen := "home"
var selected_character := "kaldi"
var selected_pool := "limited_kaldi"
var selected_chapter := 0
var selected_relic := ""
var relic_filter := "全部"
var draft_team: Array = []
var main_body: VBoxContainer
var shell: Control
var header_resources: HBoxContainer
var overlay: Control
var fx: Control
var toast_layer: Control
var nav_buttons: Dictionary = {}
var unit_cards: Dictionary = {}
var selected_skill := ""
var selected_target := ""
var battle_config: Dictionary = {}
var battle_auto := false
var battle_speed := 1.0
var battle_clock := 0.0
var battle_settled := false
var battle_generation := 0
var settlement_error := false
var abyss_auto_continue := false
var abyss_panel := "expedition"
var battle_log: Array = []
var last_reward: Dictionary = {}
var summon_results: Array = []
var summon_index := 0
var summon_flipped := false
var compact := false
var resource_clock := 0.0
var dialogue_lines: Array = []
var dialogue_index := 0
var dialogue_key := ""
var dialogue_done: Callable
var _ready_done := false
var _resize_queued := false
var dialogue_prose: Label
var dialogue_tween: Tween
var relic_slot_filter := "全部"
var test_session := false
var updater: Node
var navigation_history: Array[String] = []
var back_button: Button
var _last_layout_size := Vector2.ZERO
var _touch_scroll: ScrollContainer
var _touch_start := Vector2.ZERO
var _touch_previous := Vector2.ZERO
var _touch_dragging := false
var _touch_id := -1

func _ready() -> void:
	var main_font: FontFile = FONT.duplicate()
	main_font.fallbacks = [SYMBOL_FONT]
	var t := Theme.new()
	t.default_font = main_font
	t.default_font_size = 17
	for kind in ["Label", "Button", "CheckBox", "OptionButton", "LineEdit", "TextEdit"]:
		t.set_color("font_color", kind, TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color("586477"))
	t.set_color("font_pressed_color", "Button", GOLD)
	t.set_constant("separation", "VBoxContainer", 14)
	t.set_constant("separation", "HBoxContainer", 14)
	t.set_constant("h_separation", "GridContainer", 16)
	t.set_constant("v_separation", "GridContainer", 16)
	t.set_stylebox("panel", "PopupMenu", _box(PANEL, LINE))
	t.set_stylebox("normal", "LineEdit", _box(INK, LINE))
	t.set_stylebox("focus", "LineEdit", _box(INK, GOLD))
	theme = t
	test_session = "--test-session" in OS.get_cmdline_user_args()
	model = load("res://scripts/game_model.gd").new("" if test_session else "user://saves")
	updater = UpdateChecker.new()
	updater.name = "UpdateChecker"
	updater.state_changed.connect(_on_update_state_changed)
	add_child(updater)
	get_tree().quit_on_go_back = false
	_load_preferences()
	battle = load("res://scripts/battle_model.gd").new(model.catalog)
	var owned: Dictionary = model.state.get("ownedCharacters", {})
	if not owned.has(selected_character) and not owned.is_empty():
		selected_character = str(owned.keys()[0])
	_adapt_viewport()
	get_window().size_changed.connect(_adapt_viewport)
	compact = size.x < 1100 or _is_mobile()
	_last_layout_size = size
	_build_shell()
	_ready_done = true
	resized.connect(_resized)
	navigate("home")

func _process(delta: float) -> void:
	if not _ready_done:
		return
	resource_clock += delta
	if resource_clock > 10.0:
		resource_clock = 0.0
		model.recover_stamina()
		_update_resources()
	if current_screen == "battle" and not battle_settled and not battle.state.is_empty() and overlay.get_child_count() == 0:
		battle_clock += delta
		if battle.state.phase in ["victory", "defeat"]:
			_finish_battle()
		elif (battle.state.phase == "enemy_turn" or battle_auto) and battle_clock >= 0.85 / battle_speed:
			battle_clock = 0.0
			_do_battle_action("", "", true)

func _input(event: InputEvent) -> void:
	if not _ready_done:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed and _touch_dragging:
			get_viewport().set_input_as_handled()
			return
		if event.pressed and _touch_id == -1:
			_touch_dragging = false
	if event is InputEventScreenTouch:
		if event.pressed and _touch_id == -1:
			_touch_id = event.index
			_touch_start = event.position
			_touch_previous = event.position
			_touch_dragging = false
			_touch_scroll = _scroll_at(overlay if overlay.get_child_count() > 0 else shell, event.position)
		elif not event.pressed and event.index == _touch_id:
			if _touch_dragging:
				get_viewport().set_input_as_handled()
			_touch_id = -1
			_touch_scroll = null
	elif event is InputEventScreenDrag and event.index == _touch_id and is_instance_valid(_touch_scroll):
		if event.position.distance_to(_touch_start) >= 10:
			_touch_dragging = true
		if _touch_dragging:
			_touch_scroll.scroll_vertical -= int(event.position.y - _touch_previous.y)
			get_viewport().set_input_as_handled()
		_touch_previous = event.position

func _scroll_at(node: Node, at: Vector2) -> ScrollContainer:
	if node is Control and not node.is_visible_in_tree():
		return null
	for child in node.get_children():
		var found := _scroll_at(child, at)
		if found != null:
			return found
	if node is ScrollContainer and node.get_global_rect().has_point(at):
		return node
	return null

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and _ready_done:
		_go_back()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_go_back()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_SPACE and dialogue_key != "":
			_next_dialogue()

func _go_back() -> void:
	if dialogue_key != "":
		if dialogue_tween: dialogue_tween.kill()
		dialogue_key = ""
		dialogue_done = Callable()
		_clear_overlay()
		return
	if overlay.get_child_count() > 0:
		if settlement_error:
			_toast("请先重试保存本场战斗结果", RED)
			return
		_clear_overlay()
		return
	if current_screen == "battle":
		navigate("abyss" if battle_config.get("isAbyss", false) else "story")
	elif current_screen == "abyss" and abyss_panel != "expedition":
		abyss_panel = "expedition"
		_render_screen()
	elif not navigation_history.is_empty():
		var target: String = navigation_history.pop_back()
		navigate(target, false)
	elif current_screen != "home":
		navigate("home", false)
	else:
		_confirm("退出游戏？", "旅程已自动保存，随时可以继续。", func(): get_tree().quit())

func _show_navigation() -> void:
	var menu := _modal("前往", 520, 560)
	var grid := _grid(menu, 3 if size.x >= 600 else 2)
	for tab in TABS:
		_button(grid, tab[1], func(): navigate(tab[0]), tab[0] == current_screen).name = "MenuNav_" + tab[0]
	_button(menu, "返回游戏", _clear_overlay)

func _is_mobile() -> bool:
	return OS.has_feature("mobile") or "--mobile-ui" in OS.get_cmdline_user_args()

func _adapt_viewport() -> void:
	var window := get_window()
	var physical := Vector2(window.size)
	var ratio: float = physical.x / maxf(1.0, physical.y)
	# A phone keeps the same readable logical short edge after rotation.
	# Desktop windows below tablet size use the same responsive layout.
	var mobile := _is_mobile() or minf(physical.x, physical.y) < 700.0
	var logical_width: int = 360 if ratio < 1.15 else (int(360.0 * ratio) if mobile else 1440)
	var logical_size := Vector2i(logical_width, int(logical_width / maxf(0.3, ratio)))
	if window.content_scale_size != logical_size:
		window.content_scale_size = logical_size
	if _ready_done:
		_resized()

func _resized() -> void:
	if not _ready_done or _resize_queued:
		return
	if size != _last_layout_size:
		_resize_queued = true
		call_deferred("_resize_layout")

func _resize_layout() -> void:
	_resize_queued = false
	compact = size.x < 1100 or _is_mobile()
	_last_layout_size = size
	_clear(shell)
	shell.queue_free()
	_build_shell()
	_render_screen()
	if dialogue_key != "":
		_render_dialogue()
	else:
		for child in overlay.get_children():
			if child.name == "ModalPanel":
				_layout_modal(child)

func _build_shell() -> void:
	if not has_node("Backdrop"):
		var bg := ColorRect.new()
		bg.name = "Backdrop"
		bg.color = INK
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg)
		var art := TextureRect.new()
		art.texture = load("res://assets/wilderness.png")
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.modulate = Color(0.28, 0.32, 0.4, 0.20)
		art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(art)
		var atmosphere := Atmosphere.new()
		atmosphere.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(atmosphere)
	shell = MarginContainer.new()
	shell.name = "Shell"
	shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var safe := _usable_rect()
	var inset := 12 if compact else 32
	shell.add_theme_constant_override("margin_left", inset + int(safe.position.x))
	shell.add_theme_constant_override("margin_right", inset + int(maxf(0, size.x - safe.end.x)))
	shell.add_theme_constant_override("margin_top", 8 + int(safe.position.y))
	shell.add_theme_constant_override("margin_bottom", 8 + int(maxf(0, size.y - safe.end.y)))
	add_child(shell)
	var vertical := _vbox(shell, 8 if compact else 18)
	var header := _hbox(vertical, 8)
	back_button = _button(header, "‹ 返回", _go_back)
	back_button.name = "BackButton"
	var brand := _vbox(header, 2)
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(brand, "虚空裂变", 22 if compact else 28, GOLD)
	if not compact:
		_label(brand, "VOID RIFT  /  旅者纪事", 11, MUTED)
	_button(header, "菜单", _show_navigation).name = "MenuButton"
	header_resources = _hbox(vertical if compact else header, 6)
	_update_resources()
	var main := _responsive_box(vertical, compact, 10 if compact else 28)
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var nav := _vbox(main, 8)
	nav.visible = not compact
	if not compact:
		nav.custom_minimum_size.x = 166
	nav_buttons.clear()
	for tab in TABS:
		var b := _button(nav, tab[1] if compact else tab[2] + "   " + tab[1], func(): navigate(tab[0]))
		b.name = "Nav_" + tab[0]
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER if compact else HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(108 if compact else 166, 45)
		nav_buttons[tab[0]] = b
	if not compact:
		var nav_space := Control.new()
		nav_space.size_flags_vertical = Control.SIZE_EXPAND_FILL
		nav.add_child(nav_space)
		_label(nav, "✦  星辉指引归途", 13, GOLD)
		_label(nav, "旅程自动保存\n本地档案 · 槽位 %d" % model.active_slot, 12, MUTED)
	var scroll := ScrollContainer.new()
	scroll.name = "PageScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main.add_child(scroll)
	main_body = _vbox(scroll, 22)
	main_body.name = "PageContent"
	main_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if is_instance_valid(overlay):
		move_child(overlay, -1)
		move_child(fx, -1)
		move_child(toast_layer, -1)
	else:
		overlay = Control.new()
		overlay.name = "ModalLayer"
		overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(overlay)
		fx = BattleFX.new()
		fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(fx)
		toast_layer = Control.new()
		toast_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		toast_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(toast_layer)

func navigate(screen: String, record_history: bool = true) -> void:
	if current_screen == "battle" and settlement_error and screen != "battle":
		_toast("请先重试保存本场战斗结果", RED)
		return
	if current_screen == "battle" and not battle_settled and screen != "battle":
		_confirm("离开战斗？", "撤退将结束当前战斗，已消耗的体力保留。深渊撤退会结束本轮构筑。", func():
			if not _check(model.abandon_battle(battle_config, battle.state)):
				return
			abyss_auto_continue = false
			battle_settled = true
			navigate(screen))
		return
	_clear_overlay()
	if record_history and screen != current_screen and current_screen != "battle":
		navigation_history.append(current_screen)
		if navigation_history.size() > 30:
			navigation_history.pop_front()
	current_screen = screen
	if screen == "party":
		draft_team = model.state.get("team", []).filter(func(id): return id is String and not id.is_empty()).duplicate()
	_render_screen()
	main_body.get_parent().set_deferred("scroll_vertical", 0)

func _render_screen() -> void:
	if current_screen != "battle": unit_cards.clear()
	_clear(main_body)
	_update_resources()
	for key in nav_buttons:
		var b: Button = nav_buttons[key]
		b.add_theme_stylebox_override("normal", _box(Color("253044") if key == current_screen else Color(0, 0, 0, 0), GOLD if key == current_screen else Color(0, 0, 0, 0)))
		b.add_theme_color_override("font_color", GOLD if key == current_screen else MUTED)
	match current_screen:
		"home": _home()
		"story": _story()
		"summon": _summon()
		"party": _party()
		"growth": _growth()
		"relics": _relics()
		"abyss": _abyss()
		"shop": _shop()
		"save": _save_screen()
		"battle": _render_battle()
	main_body.modulate.a = 0.0
	create_tween().tween_property(main_body, "modulate:a", 1.0, 0.2)

func _update_resources() -> void:
	if not is_instance_valid(header_resources):
		return
	_clear(header_resources)
	var r: Dictionary = model.state.get("resources", {})
	for item in [["星尘晶", r.get("diamonds", 0), CYAN], ["金币", r.get("gold", 0), GOLD], ["体力", "%s / %s" % [r.get("stamina", 0), r.get("maxStamina", 100)], Color("a6c9a5")]]:
		var p := _panel(header_resources, item[2].darkened(0.7), 5 if compact else 12)
		var col := _vbox(p, 0)
		_label(col, item[0], 12, MUTED)
		_label(col, str(item[1]), 16 if compact else 20, item[2])

func _home() -> void:
	var hero := _scene_panel(main_body, "res://assets/wilderness.png", 370 if not compact else 390)
	var row = _vbox(hero, 10)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 16 if compact else 32
	row.offset_right = -16 if compact else -32
	row.offset_top = 32
	row.offset_bottom = -30
	_label(row, "旅 者 纪 事   ·   第一章", 13, GOLD)
	_label(row, "穿越灰烬\n追寻群星", 46 if not compact else 36, TEXT)
	_label(row, "古老的龙焰再次苏醒。\n召集同行者，踏上流火荒原的旅程。", 17, Color("d2d0cc"))
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(sp)
	var actions := _responsive_box(row, compact, 12)
	_button(actions, "继续旅程   →", func(): navigate("story"), true)
	_button(actions, "查看当前队伍", func(): navigate("party"))
	var grid := _grid(main_body, 1 if compact else 3)
	_info_tile(grid, "星辰的回应", "炎龙觉醒", "五星旅者 · 焰龙卡尔迪概率提升", "前往祈愿", func(): navigate("summon"), GOLD)
	_info_tile(grid, "裂隙之下", "深渊远征", "深入未知领域，选择专属祝福构筑", "挑战深渊", func(): navigate("abyss"), Color("b49cdd"))
	_info_tile(grid, "旅途的准备", "成长与遗物", "培养角色，强化装备，调整战斗策略", "进入工坊", func(): navigate("relics"), CYAN)
	_section("与你同行", "当前出战阵容")
	var teamrow := _grid(main_body, 1 if compact else 3)
	for id in model.state.get("team", []):
		if id == null or str(id).is_empty(): continue
		_character_card(teamrow, str(id), 175, func(): selected_character = str(id); navigate("growth"))
	var stats: Dictionary = model.state.get("stats", {})
	_label(main_body, "已收集 %d / %d 位角色   ·   累计祈愿 %d 次   ·   战斗胜利 %d 场" % [model.state.get("ownedCharacters", {}).size(), model.catalog.CharacterData.size(), stats.get("totalPulls", 0), stats.get("totalVictories", 0)], 13, MUTED)

func _story() -> void:
	_page_title("世界探索", "循着星光，书写你的旅者纪事")
	var chapters: Array = model.catalog.StageData.chapters
	var tabs := _flow(main_body, 12)
	for i in chapters.size():
		_button(tabs, str(chapters[i].name), func(): selected_chapter = i; _render_screen(), selected_chapter == i)
	var chapter: Dictionary = chapters[selected_chapter]
	var banner := _scene_panel(main_body, "res://assets/wilderness.png", 195)
	var title := _vbox(banner, 10)
	title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title.offset_left = 16
	title.offset_right = -16
	title.offset_top = 20
	title.offset_bottom = -16
	_label(title, "旅 程 章 节  /  %02d" % (selected_chapter + 1), 12, GOLD)
	_label(title, chapter.name, 29, TEXT)
	_label(title, chapter.description, 15, MUTED)
	var stage_map: Dictionary = {}
	for s in model.stage_list():
		stage_map[s.id] = s
	var grid := _grid(main_body, 1 if compact else 2)
	for index in chapter.stages.size():
		var raw: Dictionary = chapter.stages[index]
		var stage: Dictionary = stage_map.get(raw.id, raw)
		var unlocked: bool = stage.get("unlocked", false)
		var done: bool = stage.get("completed", stage.get("cleared", false))
		var p := _panel(grid, GOLD.darkened(0.65) if done else LINE, 22)
		var v := _vbox(p, 10)
		var top := _hbox(v, 10)
		_label(top, "%02d" % (index + 1), 28, GOLD if unlocked else MUTED)
		_label(top, stage.name, 22, TEXT if unlocked else MUTED)
		_label(v, "已通关  ·  ★ ★ ★" if done else ("可探索" if unlocked else "完成前置关卡后解锁"), 13, GOLD if done else CYAN)
		var names: Array = []
		for wave in stage.get("waves", []):
			for eid in wave.get("enemies", []):
				var enemy: Dictionary = model.catalog.EnemyData.get(eid, {})
				var n: String = enemy.get("name", str(eid))
				if n not in names:
					names.append(n)
		_label(v, "敌人  " + " · ".join(names), 13, MUTED, true)
		_label(v, "体力 %d   ·   %d 波敌人   ·   首通星尘晶 %d" % [stage.get("staminaCost", 6), stage.get("waves", []).size(), stage.get("firstClearRewards", {}).get("diamonds", 0)], 13, MUTED)
		var actions := _flow(v, 10)
		var enter := _button(actions, "再次挑战" if done else "开始探索   →", func(): _begin_stage(stage.id), unlocked)
		enter.disabled = not unlocked
		if done:
			_button(actions, "回顾剧情", func(): _play_dialogue(stage.id + "_pre", func(): _play_dialogue(stage.id + "_post", func(): pass)))

func _begin_stage(stage_id: String) -> void:
	var key := stage_id + "_pre"
	var begin := func():
		var result: Dictionary = model.prepare_stage(stage_id)
		if _check(result):
			_start_battle(result.config)
	if not model.state.get("dialogueSeen", {}).get(key, false):
		_play_dialogue(key, begin)
	else:
		begin.call()

func _summon() -> void:
	_page_title("星辰祈愿", "以星尘为信，让群星回应你的呼唤")
	var pools: Dictionary = model.catalog.GachaPoolData.pools
	var switches := _flow(main_body, 12)
	for id in model.catalog.GachaPoolData.activePools:
		_button(switches, pools[id].name, func(): selected_pool = str(id); _render_screen(), selected_pool == id)
	var pool: Dictionary = pools[selected_pool]
	var summon_actions := HFlowContainer.new()
	summon_actions.add_theme_constant_override("h_separation", 12)
	summon_actions.add_theme_constant_override("v_separation", 12)
	main_body.add_child(summon_actions)
	var balance: int = int(model.state.resources.get(pool.currency, 0))
	var one := _button(summon_actions, "祈愿一次   %d 星尘晶" % pool.costPerPull, func(): _pull(1))
	one.disabled = balance < int(pool.costPerPull)
	one.tooltip_text = "需要 %d 星尘晶，当前 %d" % [pool.costPerPull, balance]
	var ten := _button(summon_actions, "祈愿十次   %d 星尘晶" % (int(pool.costPerPull) * 10), func(): _pull(10), true)
	ten.disabled = balance < int(pool.costPerPull) * 10
	ten.tooltip_text = "需要 %d 星尘晶，当前 %d" % [int(pool.costPerPull) * 10, balance]
	_button(summon_actions, "概率与规则", _pool_details)
	var hero := _scene_panel(main_body, "res://assets/characters/kaldi.png" if selected_pool == "limited_kaldi" else "res://assets/characters/ayla.png", 330)
	var v := _vbox(hero, 12)
	v.position = Vector2(30, 30)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 16
	v.offset_right = -16
	v.offset_top = 24
	v.offset_bottom = -16
	_label(v, pool.subtitle, 14, GOLD)
	_label(v, pool.name, 48 if not compact else 38, TEXT)
	_label(v, "★★★★★", 24, GOLD)
	_label(v, "不灭炎焰 · 焰龙卡尔迪" if selected_pool == "limited_kaldi" else "让旅途，与群星相遇", 21, TEXT)
	var rate: float = float(model.pity_info(selected_pool).get("rate5", 0.016))
	var pool_description: String = "限定祈愿：非大保底五星实际有 75% 为卡尔迪（沿用原版抽取规则），大保底为 100%。" if selected_pool == "limited_kaldi" else str(pool.description)
	var desc := _label(main_body, pool_description + ("\n五星基础概率 1.6%% · 四星 15%% · 十次祈愿至少获得一位四星及以上角色。\n当前五星概率 %.2f%%" % (rate * 100.0)), 16, MUTED, true)
	desc.custom_minimum_size.y = 30
	var pity: Dictionary = model.state.get("pityCounters", {}).get(selected_pool, {})
	var p := _panel(main_body, LINE, 22)
	var col := _vbox(p, 12)
	var count: int = int(pity.get("count", 0))
	_label(col, "五星保底进度   %d / %d" % [count, pool.pity.hard], 17, GOLD)
	_progress(col, count, pool.pity.hard, GOLD, 7)
	_label(col, "第 %d 次起概率递增 · 第 %d 次必出五星%s" % [int(pool.pity.soft) + 1, pool.pity.hard, " · 下次五星为限定角色" if pity.get("guaranteedFeatured", false) else ""], 13, MUTED, true)

func _pool_details() -> void:
	var pool: Dictionary = model.catalog.GachaPoolData.pools[selected_pool]
	var box := _modal("祈愿规则", 680)
	_label(box, "五星 1.6% · 四星 15% · 三星 83.4%\n每十次至少出现四星及以上角色。五星软保底从第 %d 次开始，硬保底为第 %d 次。\n重复角色转化为对应角色碎片，可用于解锁命座。\n沿用原版抽取规则：限定池非大保底五星实际有 75%% 概率为当期角色；若未获得，当期池下次五星必为限定角色。" % [int(pool.pity.soft) + 1, pool.pity.hard], 17, TEXT, true)
	_label(box, "五星角色  " + _char_names(pool.pool5) + "\n四星角色  " + _char_names(pool.pool4) + "\n三星角色  " + _char_names(pool.pool3), 15, MUTED, true)
	_button(box, "我知道了", _clear_overlay, true)

func _pull(count: int) -> void:
	var r: Dictionary = model.pull(selected_pool, count)
	if not _check(r):
		return
	summon_results = r.results
	summon_index = 0
	summon_flipped = false
	_update_resources()
	_reveal_summon()

func _reveal_summon() -> void:
	_clear_overlay()
	var result: Dictionary = summon_results[summon_index]
	var id: String = result.charId
	var data: Dictionary = model.catalog.CharacterData[id]
	var color := _rarity_color(int(data.rarity))
	var box := _modal("星辰回应   %d / %d" % [summon_index + 1, summon_results.size()], 750)
	if summon_flipped:
		var p := _portrait(box, id, 320, true)
		p.modulate.a = 0
		p.scale = Vector2(0.93, 0.93)
		create_tween().tween_property(p, "modulate:a", 1.0, 0.45)
		create_tween().tween_property(p, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK)
		_center_label(box, str(data.name), 32, color)
		_center_label(box, "★".repeat(int(data.rarity)), 24, color)
		_center_label(box, "初次相遇 · 新角色" if result.get("isNew", false) else "命运重逢 · 角色碎片 +%d" % result.get("shards", 0), 16, CYAN)
		fx.burst(size * Vector2(0.5, 0.42), color, true)
	else:
		var card := _panel(box, color, 32)
		var v := _vbox(card, 22)
		_center_label(v, "✦", 110, color)
		_center_label(v, "群星的光芒正在汇聚", 23, TEXT)
		_center_label(v, "触碰星门，揭晓与你同行之人", 14, MUTED)
		_button(v, "揭晓旅者", func(): summon_flipped = true; _reveal_summon(), true)
	var actions := _flow(box, 14)
	_button(actions, "全部揭示", _summon_summary)
	if summon_flipped:
		_button(actions, "查看结果" if summon_index == summon_results.size() - 1 else "下一位   →", func():
			if summon_index == summon_results.size() - 1:
				_summon_summary()
			else:
				summon_index += 1
				summon_flipped = false
				_reveal_summon(), true)

func _summon_summary() -> void:
	var box := _modal("星辰之约 · 祈愿结果", 520 if summon_results.size() == 1 else 1100)
	var grid := _grid(box, mini(summon_results.size(), 1 if compact else 5))
	for r in summon_results:
		var v := _vbox(grid, 6)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_character_card(v, r.charId, 240 if summon_results.size() == 1 else 145, Callable())
		_center_label(v, "新角色" if r.get("isNew", false) else "碎片 +%d" % r.get("shards", 0), 12, CYAN)
	var repeat := _flow(box, 12)
	var cost: int = int(model.catalog.GachaPoolData.pools[selected_pool].costPerPull)
	var again := _button(repeat, "再祈愿 %d 次 · %d 星尘晶" % [summon_results.size(), cost * summon_results.size()], func(): _pull(summon_results.size()))
	again.disabled = int(model.state.resources.diamonds) < cost * summon_results.size()
	again.tooltip_text = "星尘晶不足时可前往补给商店兑换"
	if summon_results.size() != 10:
		_button(repeat, "祈愿十次 · %d 星尘晶" % (cost * 10), func(): _pull(10)).disabled = int(model.state.resources.diamonds) < cost * 10
	_button(box, "收下星辰的赠礼", func(): _clear_overlay(); _render_screen(), true)

var character_filter := "全部"
var salvage_options := {"all3Star": false, "all4Star": false, "allUnupgraded": false}

func _party() -> void:
	_page_title("冒险编队", "选择三位同行者 · 点击卡片加入或移出队伍")
	var header := _responsive_box(main_body, compact, 14)
	_label(header, "当前阵容   %d / 3" % draft_team.size(), 21, GOLD)
	var save_team := _button(header, "保存出战队伍", func():
		if _check(model.set_team(draft_team)):
			_toast("出战队伍已保存", CYAN)
			_render_screen(), true)
	var run_locked: bool = model.abyss_run_active()
	save_team.disabled = run_locked
	if run_locked:
		_label(main_body, "本轮深渊队伍已锁定。结束远征后可以调整阵容。", 15, CYAN, true)
	var formation := _grid(main_body, 1 if compact else 3)
	for i in range(3):
		if i < draft_team.size():
			var id: String = draft_team[i]
			_character_card(formation, id, 155, func(): _toggle_team(id))
		else:
			var empty := _panel(formation, LINE, 22)
			var v := _vbox(empty, 12)
			_center_label(v, "◇", 50, MUTED)
			_center_label(v, "待命席位 %d" % (i + 1), 17, MUTED)
	_section("旅者图鉴", "全部十位旅者 · 已拥有 %d 位" % model.state.ownedCharacters.size())
	var filters := _flow(main_body, 8)
	for el in ["全部", "fire", "water", "wind", "thunder"]:
		_button(filters, _element_name(el), func(): character_filter = el; _render_screen(), character_filter == el)
	var grid := _grid(main_body, 1 if compact else 4)
	for id in model.catalog.CharacterData:
		var data: Dictionary = model.catalog.CharacterData[id]
		if character_filter != "全部" and data.element != character_filter:
			continue
		var v := _vbox(grid, 8)
		_character_card(v, id, 175, func(): _toggle_team(id))
		var owned: bool = model.state.ownedCharacters.has(id)
		var row := _responsive_box(v, compact, 7)
		var b := _button(row, "移出队伍" if id in draft_team else ("加入队伍" if owned else "尚未获得"), func(): _toggle_team(id), id in draft_team)
		b.disabled = not owned or run_locked
		_button(row, "详情", func(): selected_character = id; navigate("growth"))

func _toggle_team(id: String) -> void:
	if model.abyss_run_active() and model.state.ownedCharacters.has(id):
		_toast("本轮深渊阵容已锁定，结束远征后可以调整", CYAN)
		return
	if not model.state.ownedCharacters.has(id):
		selected_character = id
		navigate("growth")
		return
	if id in draft_team:
		draft_team.erase(id)
	elif draft_team.size() < 3:
		draft_team.append(id)
	else:
		_toast("队伍已满，请先移出一位角色", GOLD)
	_render_screen()

func _growth() -> void:
	_page_title("角色养成", "每一次相遇，都能点亮新的星座")
	var selector := HFlowContainer.new()
	selector.add_theme_constant_override("h_separation", 8)
	selector.add_theme_constant_override("v_separation", 8)
	main_body.add_child(selector)
	for id in model.catalog.CharacterData:
		_button(selector, model.catalog.CharacterData[id].name, func(): selected_character = id; _render_screen(), selected_character == id)
	var data: Dictionary = model.catalog.CharacterData.get(selected_character, {})
	if data.is_empty():
		return
	var owned: bool = model.state.ownedCharacters.has(selected_character)
	var progress: Dictionary = model.state.ownedCharacters.get(selected_character, {})
	var row := _responsive_box(main_body, compact, 22 if compact else 24)
	var profile := _panel(row, _rarity_color(int(data.rarity)).darkened(0.5), 20)
	profile.custom_minimum_size.x = 320 if not compact else 0
	profile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var art := _vbox(profile, 12)
	_portrait(art, selected_character, 300)
	_center_label(art, data.get("title", ""), 13, MUTED)
	_center_label(art, data.name, 27, TEXT)
	_center_label(art, "★".repeat(int(data.rarity)), 20, _rarity_color(int(data.rarity)))
	_center_label(art, _element_name(data.element) + "   /   " + model.catalog.RoleNames.get(data.role, data.role), 15, CYAN)
	_label(art, data.get("description", ""), 14, MUTED, true)
	_label(art, data.get("flavorText", ""), 14, GOLD, true)
	var details := _vbox(row, 16)
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var levelp := _panel(details, LINE, 20)
	var levelv := _vbox(levelp, 10)
	_label(levelv, "等级 %d / 10" % progress.get("level", 1) if owned else "旅者档案 · 尚未获得", 23, GOLD)
	if owned:
		var needed: int = model.exp_to_next_level(int(progress.get("level", 1)))
		_progress(levelv, progress.get("exp", 0), maxi(1, needed), CYAN, 8)
		_label(levelv, "经验 %d / %d" % [progress.get("exp", 0), needed] if needed > 0 else "已达最高等级", 13, MUTED)
		var train := _button(levelv, "训练一次   500 金币 / 100 经验", func():
			if _check(model.train_character(selected_character)):
				_toast("训练完成，经验已获得", CYAN)
				_render_screen(), true)
		train.disabled = int(progress.get("level", 1)) >= 10
	else:
		_label(levelv, "前往祈愿，或完成对应章节，邀请旅者加入队伍。", 15, MUTED, true)
		_button(levelv, "前往星辰祈愿", func(): navigate("summon"), true)
	var stats: Dictionary = model.computed_stats(selected_character) if owned else data.baseStats
	var statgrid := _grid(details, 2 if compact else 3)
	for s in [["生命", "hp"], ["攻击", "atk"], ["防御", "def"], ["速度", "spd"], ["暴击率", "cri"], ["暴击伤害", "criDmg"]]:
		var p := _panel(statgrid, LINE, 14)
		var v := _vbox(p, 3)
		_label(v, s[0], 12, MUTED)
		var value: float = float(stats.get(s[1], 0))
		_label(v, "%.1f%%" % (value * 100) if s[1] in ["cri", "criDmg"] else str(int(value)), 23, TEXT)
	var passive := _panel(details, CYAN.darkened(0.65), 16)
	var pv := _vbox(passive, 7)
	_label(pv, "天赋被动", 14, CYAN)
	_label(pv, data.get("passiveDesc", ""), 15, TEXT, true)
	_section("战斗技能", "普通攻击 · 战技 · 终结技")
	var skillgrid := _grid(main_body, 1 if compact else 3)
	for sid in data.skills:
		var skill: Dictionary = model.catalog.SkillData[sid]
		var p := _panel(skillgrid, _element_color(data.element).darkened(0.55), 20)
		var v := _vbox(p, 10)
		_label(v, {"normal": "普通攻击", "skill": "战技", "ultimate": "终结技"}.get(skill.type, "技能"), 12, CYAN)
		_label(v, skill.name, 23, TEXT)
		_label(v, skill.description, 15, MUTED, true)
		_label(v, "冷却 %d 回合   ·   %s" % [skill.get("cooldown", 0), "消耗 %d 能量" % skill.get("energyCost", 100) if skill.type == "ultimate" else "获得 %d 能量" % skill.get("energyGain", 0)], 12, GOLD)
	_section("命之座", "当前命座 %d / 6   ·   角色碎片 %d" % [progress.get("constellation", progress.get("awakening", 0)), progress.get("shards", 0)])
	var consgrid := _grid(main_body, 1 if compact else 3)
	var infos: Array = model.constellation_info(selected_character)
	for i in range(6):
		var info: Dictionary = infos[i] if i < infos.size() else {}
		var current: int = int(progress.get("constellation", progress.get("awakening", 0)))
		var unlocked: bool = i < current
		var p := _panel(consgrid, GOLD.darkened(0.4) if unlocked else LINE, 18)
		var v := _vbox(p, 9)
		_label(v, "✦  %d  %s" % [i + 1, info.get("label", info.get("name", "命座"))], 19, GOLD if unlocked else TEXT)
		_label(v, info.get("desc", info.get("description", "")), 14, MUTED, true)
		if i == current and owned:
			_button(v, "解锁  ·  %d 碎片" % info.get("cost", model.catalog.ConstellationCost[str(int(data.rarity))][i]), func():
				if _check(model.unlock_constellation(selected_character)):
					_toast("命座已点亮", GOLD)
					_render_screen(), true)
		else:
			_label(v, "已点亮" if unlocked else "依次解锁命座", 12, GOLD if unlocked else MUTED)
	if owned:
		_section("装备遗物", "每件装备都将计入角色实际属性")
		var gear := _grid(main_body, 1 if compact else 5)
		for slot in model.catalog.RelicSlots:
			var p := _panel(gear, LINE, 14)
			var v := _vbox(p, 8)
			_label(v, slot.name, 16, GOLD)
			var uid = progress.get("equippedRelics", {}).get(slot.id, null)
			var relic := _find_relic(str(uid))
			_label(v, "+%d  %s" % [relic.get("level", 0), "★".repeat(int(relic.get("rarity", 3)))] if not relic.is_empty() else "空置", 13, MUTED)
			if not relic.is_empty():
				_button(v, "卸下", func(): _check(model.unequip_relic(selected_character, slot.id)); _render_screen())
			else:
				_button(v, "选择遗物", func(): navigate("relics"))

func _relics() -> void:
	_page_title("遗物工坊", "整理古老遗物，将力量铭刻于旅者的装备")
	var controls := _flow(main_body, 8)
	for f in ["全部", "背包", "已装备", "三星", "四星", "五星"]:
		_button(controls, f, func(): relic_filter = f; _save_preferences(); _render_screen(), relic_filter == f)
	_button(controls, "批量出售", _batch_salvage)
	var slots := HFlowContainer.new()
	slots.add_theme_constant_override("h_separation", 8)
	slots.add_theme_constant_override("v_separation", 8)
	main_body.add_child(slots)
	_button(slots, "全部部位", func(): relic_slot_filter = "全部"; _save_preferences(); _render_screen(), relic_slot_filter == "全部")
	for slot in model.catalog.RelicSlots:
		_button(slots, slot.name, func(): relic_slot_filter = slot.id; _save_preferences(); _render_screen(), relic_slot_filter == slot.id)
	var inventory: Array = model.state.get("relics", [])
	if inventory.is_empty():
		_empty_state(main_body, "尚未获得遗物", "完成章节战斗与深渊挑战，即可收集不同部位的遗物。", "开始探索", func(): navigate("story"))
		return
	var row := _responsive_box(main_body, compact, 20)
	var listing := _grid(row, 1 if compact else 3)
	listing.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var visible: Array = []
	for relic in inventory:
		if relic_slot_filter != "全部" and relic.slotId != relic_slot_filter: continue
		if relic_filter == "背包" and relic.get("equippedBy") != null:
			continue
		if relic_filter == "已装备" and relic.get("equippedBy") == null:
			continue
		if relic_filter in ["三星", "四星", "五星"] and int(relic.rarity) != {"三星": 3, "四星": 4, "五星": 5}[relic_filter]:
			continue
		visible.append(relic)
	if visible.is_empty():
		_label(listing, "当前筛选下没有遗物", 18, MUTED)
	if selected_relic == "" and not visible.is_empty():
		selected_relic = str(visible[0].uid)
	for relic in visible:
		var color := _rarity_color(int(relic.rarity))
		var card := _panel(listing, color if str(relic.uid) == selected_relic else LINE, 16)
		var v := _vbox(card, 9)
		_center_label(v, {"helmet": "◇", "chest": "⬡", "belt": "◈", "boots": "◇", "necklace": "✦"}.get(relic.slotId, "◇"), 42, color)
		_center_label(v, "%s  +%d" % [_slot_name(relic.slotId), relic.level], 18, TEXT)
		_center_label(v, "★".repeat(int(relic.rarity)), 13, color)
		_center_label(v, _relic_main(relic), 13, MUTED)
		_center_label(v, _char_name(str(relic.equippedBy)) if relic.get("equippedBy") != null else "背包", 12, CYAN if relic.get("equippedBy") != null else MUTED)
		_button(v, "查看遗物", func(): selected_relic = str(relic.uid); _save_preferences(); _render_screen(), str(relic.uid) == selected_relic)
	var selected := _find_relic(selected_relic)
	if selected.is_empty():
		return
	var detail := _panel(row, _rarity_color(int(selected.rarity)).darkened(0.4), 24)
	detail.custom_minimum_size.x = 320 if not compact else 0
	var dv := _vbox(detail, 12)
	_label(dv, "%s  +%d" % [_slot_name(selected.slotId), selected.level], 27, TEXT)
	_label(dv, "★".repeat(int(selected.rarity)), 19, _rarity_color(int(selected.rarity)))
	_label(dv, "主属性  " + _relic_main(selected), 18, GOLD)
	for s in selected.get("subStats", []):
		_label(dv, "%s  +%s" % [s.name, _stat_value(s.stat, s.value)], 15, MUTED)
	_label(dv, "每 4 级随机强化一条副属性 · 上限 +25", 12, MUTED, true)
	var upgrade := _button(dv, "强化 +1   %d 金币" % model.relic_upgrade_cost(int(selected.level)), func():
		if _check(model.upgrade_relic(selected_relic)):
			_toast("遗物强化成功", GOLD)
			_render_screen(), true)
	upgrade.disabled = int(selected.level) >= 25
	var max_cost: int = int(model.relic_upgrade_cost_to_max(selected_relic))
	var maxup := _button(dv, "强化至 +25   %d 金币" % max_cost, func():
		_confirm("强化至满级", "将消耗 %d 金币，将这件遗物提升至 +25。" % max_cost, func():
			if _check(model.upgrade_relic_to_max(selected_relic)):
				_toast("遗物已升至满级", GOLD)
				_render_screen()))
	maxup.disabled = int(selected.level) >= 25
	_button(dv, "装备给角色", func(): _equip_dialog(selected_relic))
	if selected.get("equippedBy") != null:
		_button(dv, "从 %s 卸下" % _char_name(selected.equippedBy), func(): _check(model.unequip_relic(selected.equippedBy, selected.slotId)); _render_screen())
	else:
		_button(dv, "出售遗物", func():
			_confirm("出售这件遗物？", "出售后获得金币，遗物将从背包移除。", func():
				if _check(model.sell_relic(selected_relic)):
					selected_relic = ""
					_toast("遗物已出售", GOLD)
					_render_screen()))

func _batch_salvage() -> void:
	var box := _modal("批量出售遗物", 620)
	_label(box, "选择满足任一条件的背包遗物。已装备的遗物将保留。", 16, MUTED, true)
	for option in [["all3Star", "全部三星遗物"], ["all4Star", "全部四星遗物"], ["allUnupgraded", "全部未强化遗物（+0）"]]:
		var check := CheckBox.new()
		check.custom_minimum_size.y = 48
		check.text = option[1]
		check.button_pressed = salvage_options[option[0]]
		check.toggled.connect(func(pressed): salvage_options[option[0]] = pressed; _save_preferences())
		box.add_child(check)
	_button(box, "确认出售所选类别", func():
		if _check(model.batch_sell_relic_options(salvage_options)):
			_clear_overlay()
			selected_relic = ""
			_toast("背包整理完成", GOLD)
			_render_screen(), true)
	_button(box, "保留遗物", _clear_overlay)

func _equip_dialog(uid: String) -> void:
	var box := _modal("选择装备角色", 660)
	_label(box, "装备后会替换该角色同部位的遗物，原有装备返回背包。", 15, MUTED, true)
	var grid := _grid(box, 2)
	for id in model.state.ownedCharacters:
		_button(grid, _char_name(id), func():
			if _check(model.equip_relic(uid, id)):
				_clear_overlay()
				_toast("已装备给 " + _char_name(id), CYAN)
				_render_screen())
	_button(box, "返回", _clear_overlay)

func _shop() -> void:
	_page_title("补给商店", "为下一段旅程做好准备")
	var notice := _panel(main_body, CYAN.darkened(0.5), 18)
	_label(notice, "离线模拟商店 · 所有礼包即时发放，仅用于游戏体验。标价为原版展示信息，操作不会产生真实付款或订阅。", 15, CYAN, true)
	_section("金币兑换", "使用游戏内金币换取旅途补给")
	var items := _grid(main_body, 1 if compact else 2)
	for item in model.catalog.ShopData.itemShop:
		var p := _panel(items, LINE, 22)
		var v := _vbox(p, 12)
		_label(v, item.name, 25, TEXT)
		_label(v, _reward_text(item.rewards), 16, MUTED, true)
		_button(v, "%d 金币   兑换" % item.price, func():
			if _check(model.purchase("item", item.id)):
				_toast("补给已发放", CYAN)
				_render_screen(), true)
	_section("模拟礼包", "点击领取即可体验原版充值奖励")
	var packs := _grid(main_body, 1 if compact else 3)
	for item in model.catalog.ShopData.rechargeItems:
		var p := _panel(packs, GOLD.darkened(0.5), 22)
		var v := _vbox(p, 13)
		_label(v, item.name, 25, GOLD)
		_label(v, item.description, 14, MUTED, true)
		_label(v, _reward_text(item.rewards), 16, TEXT, true)
		_label(v, "原版展示价 " + str(item.priceDisplay), 12, MUTED)
		_button(v, "模拟领取", func():
			if _check(model.purchase("recharge", item.id)):
				_toast("模拟礼包已发放", GOLD)
				_render_screen(), true)

func _save_screen() -> void:
	_page_title("旅程档案", "三份独立存档 · 自动保存 · 兼容网页原版存档")
	var grid := _grid(main_body, 1 if compact else 3)
	for s in model.slot_summaries():
		var slot: int = int(s.get("slot", s.get("id", 1)))
		var active: bool = slot == model.active_slot
		var p := _panel(grid, GOLD if active else LINE, 24)
		var v := _vbox(p, 14)
		_label(v, "档案  %02d" % slot, 28, GOLD if active else TEXT)
		_label(v, "当前旅程" if active else ("已有存档" if s.get("hasData", false) else "新的旅程"), 14, CYAN if active else MUTED)
		_label(v, "旅者 %d 位\n累计祈愿 %d 次\n战斗胜利 %d 场" % [s.get("ownedCount", 0), s.get("totalPulls", 0), s.get("totalVictories", 0)], 16, MUTED)
		var b := _button(v, "已在当前档案" if active else "切换至此档案", func():
			_confirm("切换旅程档案", "当前进度已自动保存。接下来将载入档案 %d。" % slot, func():
				if _check(model.load_slot(slot)):
					selected_relic = ""
					_clear_overlay()
					_render_screen()), active)
		b.disabled = active
		_label(v, "最后保存：" + (Time.get_datetime_string_from_unix_time(int(s.get("lastSaved", 0)) / 1000).replace("T", " ") if int(s.get("lastSaved", 0)) > 0 else "尚未保存"), 11, MUTED, true)
		if s.get("corrupt", false): _label(v, "数据异常 · 可导入备份恢复", 13, RED, true)
		var transfer := _flow(v, 8)
		_button(transfer, "导出", func(): _export_dialog(slot)).disabled = not s.get("hasData", false) or s.get("corrupt", false)
		_button(transfer, "导入", func(): _import_dialog(slot))
		_button(v, "重新开始", func():
			_confirm("重置档案 %d？" % slot, "该档案中的角色、资源与进度将被初始状态替换。建议先导出备份。", func():
				if _check(model.reset_slot(slot)):
					selected_relic = ""
					_clear_overlay()
					_render_screen()))
	var p := _panel(main_body, LINE, 24)
	var v := _vbox(p, 14)
	_label(v, "存档迁移与备份", 24, TEXT)
	_label(v, "导出为可迁移的存档文件。导入会验证数据，并替换当前槽位。可使用原网页版本导出的第三版存档。", 16, MUTED, true)
	var row := _flow(v, 14)
	_button(row, "导出当前档案", _export_dialog, true)
	_button(row, "导入存档文件", _import_dialog)
	_button(row, "立即保存", func(): _toast("旅程已保存" if model.save_game() else "保存失败，请检查目录权限", CYAN))

	_update_panel()

func _update_panel() -> void:
	var panel := _panel(main_body, LINE, 24)
	var content := _vbox(panel, 14)
	_label(content, "版本与更新", 24, TEXT)
	var local: Dictionary = updater.local_version
	_label(content, "当前版本 %s · 构建 %s" % [str(local.get("version_name", "未知")), str(local.get("version_code", "未知"))], 16, MUTED, true)
	_label(content, "点击检查后连接 GitHub 查询版本，存档保留在本机。APK 将在浏览器中下载，由你确认安装。更新前建议导出存档备份。", 14, MUTED, true)
	var status: Dictionary = updater.state
	_label(content, str(status.get("message", "尚未检查更新")), 16, GOLD if status.get("status") == "available" else TEXT, true).name = "UpdateStatus"
	var actions := _responsive_box(content, compact, 10)
	var check_button := _button(actions, "检查更新", updater.check_for_updates, true)
	check_button.name = "CheckForUpdates"
	check_button.disabled = updater.busy
	_button(actions, "GitHub 发布页", func():
		if updater.open_releases() != OK:
			_toast("无法打开浏览器，请稍后重试。", RED)).name = "OpenReleases"
	if status.get("status") == "available":
		# Untrusted release prose is plain Label text, never rich text or code.
		_label(content, "发布说明", 18, GOLD)
		_label(content, str(status.get("release_notes", "")), 15, MUTED, true).name = "UpdateReleaseNotes"
		_button(content, "在浏览器下载 APK", func():
			if updater.open_download() != OK:
				_toast("无法打开下载链接，请重新检查更新。", RED), true).name = "DownloadUpdate"

func _on_update_state_changed(_state: Dictionary) -> void:
	if _ready_done and current_screen == "save":
		_render_screen()

func _export_dialog(slot: int = -1) -> void:
	if slot == -1: slot = model.active_slot
	var d := FileDialog.new()
	d.title = "导出旅程档案"
	d.access = FileDialog.ACCESS_FILESYSTEM
	d.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	d.filters = PackedStringArray(["*.json ; 旅程存档"])
	d.current_file = "void-rift-slot-%d.json" % slot
	d.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	add_child(d)
	d.file_selected.connect(func(path):
		if _check(model.export_save(path, slot)):
			_toast("档案已导出至 " + path, CYAN)
		d.queue_free())
	d.canceled.connect(d.queue_free)
	d.popup_centered_ratio(0.75)

func _import_dialog(slot: int = -1) -> void:
	if slot == -1: slot = model.active_slot
	var d := FileDialog.new()
	d.title = "导入旅程档案"
	d.access = FileDialog.ACCESS_FILESYSTEM
	d.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	d.filters = PackedStringArray(["*.json ; 旅程存档"])
	d.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	add_child(d)
	d.file_selected.connect(func(path):
		d.queue_free()
		_confirm("导入并替换所选档案？", "将以所选文件替换档案 %d。数据通过完整验证后才会写入。旧版档案会保留角色、装备、资源与剧情，并从第 1 层开始新版远征；旧轮次的生命、祝福与待选事件随迁移重置。\n%s" % [slot, path.get_file()], func():
			if _check(model.import_save(path, slot)):
				selected_relic = ""
				_toast("存档已导入", CYAN)
				_render_screen()))
	d.canceled.connect(d.queue_free)
	d.popup_centered_ratio(0.75)

func _abyss() -> void:
	AbyssView.render(self)

func _begin_abyss() -> void:
	var result: Dictionary = model.prepare_abyss()
	if _check(result):
		_start_battle(result.config)

func _abyss_has_decision() -> bool:
	var rogue: Dictionary = model.state.abyss.rogue
	return str(rogue.get("nextStep", {}).get("type", "none")) != "none" or not rogue.get("pendingChoices", []).is_empty() or not rogue.get("pendingNode", {}).is_empty()

func _abyss_operation(result: Dictionary, message: String = "", continue_auto: bool = false) -> void:
	if not _check(result):
		return
	var feedback: String = str(result.get("message", message))
	if not feedback.is_empty():
		_toast(feedback, CYAN)
	_render_screen()
	if continue_auto:
		_maybe_continue_abyss()

func _maybe_continue_abyss() -> void:
	if not abyss_auto_continue or current_screen != "abyss" or _abyss_has_decision():
		return
	var rogue: Dictionary = model.state.abyss.rogue
	if rogue.get("runId") == null or str(rogue.get("runId", "")).is_empty():
		return
	_begin_abyss()

func _abyss_reward(id: String) -> Dictionary:
	for r in model.catalog.AbyssData.rogue.rewards:
		if r.id == id:
			return r
	return {}

func _start_battle(config: Dictionary) -> void:
	_clear_overlay()
	battle_generation += 1
	battle_config = config
	battle_settled = false
	settlement_error = false
	selected_skill = ""
	selected_target = ""
	battle_clock = 0.0
	battle_log = []
	var is_abyss: bool = config.get("isAbyss", false)
	if is_abyss:
		abyss_panel = "expedition"
	battle.start(config, model.battle_party(is_abyss), model.rogue_effects() if is_abyss else [])
	current_screen = "battle"
	_render_screen()
	_show_combat_events(battle.state.get("events", []))

func _render_battle() -> void:
	_clear(main_body)
	unit_cards.clear()
	var state: Dictionary = battle.state
	if state.is_empty():
		return
	var head := _responsive_box(main_body, compact, 10 if compact else 16)
	var names := _vbox(head, 2)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(names, str(battle_config.get("name", "裂隙战斗")), 26, TEXT)
	_label(names, "第 %d 回合   ·   第 %d 波" % [state.get("turn", 1), int(state.get("wave", 1))], 13, GOLD)
	var head_controls := _flow(head, 10)
	_button(head_controls, "自动 · 开启" if battle_auto else "自动 · 关闭", func(): battle_auto = not battle_auto; abyss_auto_continue = abyss_auto_continue and battle_auto; _render_battle(), battle_auto)
	_button(head_controls, "%d 倍速" % battle_speed, func(): battle_speed = 2.0 if battle_speed == 1.0 else (4.0 if battle_speed == 2.0 else 1.0); _render_battle())
	_button(head_controls, "撤退", func(): navigate("abyss" if battle_config.get("isAbyss", false) else "story"))
	var active: Dictionary = battle.current_actor()
	var active_uid: String = active.get("uid", "")
	var order := HFlowContainer.new()
	order.add_theme_constant_override("h_separation", 7)
	order.add_theme_constant_override("v_separation", 7)
	main_body.add_child(order)
	_label(order, "行动顺序", 12, MUTED)
	for uid in state.get("turnOrder", []):
		var unit := _battle_unit(str(uid))
		if unit.is_empty() or float(unit.get("currentHp", 0)) <= 0:
			continue
		var chip := _panel(order, GOLD if uid == active_uid else LINE, 8)
		_label(chip, str(unit.name), 11, GOLD if uid == active_uid else MUTED)
	if battle_config.get("isAbyss", false):
		var echoes: Array = model.state.abyss.rogue.get("selectedRewards", [])
		var build_row := _responsive_box(main_body, compact, 10)
		_button(build_row, "本轮回响构筑 · %d 项" % echoes.size(), _show_battle_echoes)
		_button(build_row, "深渊战斗规则", _show_abyss_rules)
		var modifier: Dictionary = battle_config.get("encounterModifier", {})
		if not modifier.is_empty():
			_label(main_body, "敌方阵势 · %s  %s" % [modifier.get("name", "特殊阵势"), modifier.get("description", "")], 14, RED, true)
	var arena := _panel(main_body, LINE, 14)
	var field := _responsive_box(arena, compact, 14 if compact else 20)
	var allies_group := _vbox(field, 9)
	allies_group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(allies_group, "我方阵容", 12, CYAN)
	var allies_grid := _grid(allies_group, 3)
	for unit in state.get("allies", []):
		_battle_unit_card(allies_grid, unit, active_uid)
	if not compact:
		var vs := _vbox(field, 5)
		vs.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_label(vs, "✧", 32, GOLD)
	var enemies_group := _vbox(field, 9)
	enemies_group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(enemies_group, "敌方阵容", 12, RED)
	var enemies_grid := _grid(enemies_group, 3)
	for unit in state.get("enemies", []):
		_battle_unit_card(enemies_grid, unit, active_uid)
	if state.phase == "player_turn" and not active.is_empty():
		var available: Array = battle.available_actions()
		if selected_skill not in available:
			selected_skill = str(available[0]) if not available.is_empty() else ""
		var legal: Array = battle.legal_targets(selected_skill) if selected_skill != "" else []
		if selected_target not in legal:
			selected_target = str(legal[0]) if not legal.is_empty() else ""
		var controls := _panel(main_body, CYAN.darkened(0.5), 18)
		var cv := _vbox(controls, 12)
		_label(cv, "%s 的回合" % active.name, 20, CYAN)
		var skills := _grid(cv, 1 if compact else 3)
		for sid in active.get("skills", []):
			var skill: Dictionary = model.catalog.SkillData.get(sid, {})
			var cd: int = int(active.get("cooldowns", {}).get(sid, 0))
			var cost: int = int(skill.get("energyCost", 0))
			var suffix := "冷却 %d 回合" % cd if cd > 0 else ("能量 %d / %d" % [active.get("energy", 0), cost] if cost > 0 else "获得 %d 能量" % skill.get("energyGain", 0))
			var b := _button(skills, str(skill.get("name", sid)) + "\n" + suffix, func(): selected_skill = str(sid); selected_target = ""; _render_battle(), selected_skill == sid)
			b.custom_minimum_size.y = 70
			b.disabled = sid not in available or battle_auto
			b.tooltip_text = str(skill.get("description", ""))
		var skill: Dictionary = model.catalog.SkillData.get(selected_skill, {})
		_label(cv, str(skill.get("description", "选择技能")), 14, MUTED, true)
		var footer := _responsive_box(cv, compact, 10 if compact else 14)
		var target_name: String = _battle_unit(selected_target).get("name", "选择目标")
		_label(footer, "目标：" + target_name + "  ·  点击单位切换", 13, MUTED)
		var cast := _button(footer, "施放  " + str(skill.get("name", "技能")) + "   →", func(): _do_battle_action(selected_skill, selected_target), true)
		cast.name = "CastSkill"
		cast.disabled = battle_auto or selected_skill == "" or selected_target == ""
		for uid in unit_cards:
			var card: PanelContainer = unit_cards[uid]
			if uid in legal:
				card.add_theme_stylebox_override("panel", _box(Color("172337"), GOLD if uid == selected_target else CYAN.darkened(0.5), 12))
	else:
		var waitp := _panel(main_body, LINE, 24)
		_center_label(waitp, "敌方正在行动…" if state.phase == "enemy_turn" else "战斗结算中…", 23, MUTED)
	var logp := _panel(main_body, LINE, 14)
	var logs := _vbox(logp, 4)
	_label(logs, "战斗记录", 12, GOLD)
	for entry in battle_log.slice(maxi(0, battle_log.size() - 3)):
		_label(logs, str(entry), 12, MUTED, true)

func _battle_unit_card(parent: Node, unit: Dictionary, active_uid: String) -> void:
	var alive: bool = float(unit.get("currentHp", 0)) > 0
	var color := _element_color(unit.get("element", "fire"))
	var p := _panel(parent, GOLD if unit.uid == active_uid else LINE, 10)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.custom_minimum_size.x = 0 if compact else 120
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	_bind_card_tap(p, func():
		if battle.state.phase == "player_turn" and str(unit.uid) in battle.legal_targets(selected_skill):
			selected_target = str(unit.uid)
			_render_battle())
	unit_cards[unit.uid] = p
	var v := _vbox(p, 6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var art := _portrait(v, unit.id, 125 if compact else 165, false, not unit.get("isAlly", true))
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_center_label(v, str(unit.name), 14, TEXT)
	_progress(v, unit.get("currentHp", 0), maxi(1, int(unit.get("maxHp", 1))), CYAN if unit.get("isAlly", true) else RED, 8)
	_center_label(v, "%d / %d" % [unit.get("currentHp", 0), unit.get("maxHp", 1)], 11, MUTED)
	if unit.get("isAlly", true):
		_progress(v, unit.get("energy", 0), unit.get("maxEnergy", 100), GOLD, 4)
		_center_label(v, "能量 %d" % unit.get("energy", 0), 10, GOLD)
	var statuses: Array = []
	if float(unit.get("shield", 0)) > 0:
		statuses.append("护盾 %d" % unit.shield)
	var labels: Dictionary = STATUS_NAMES
	for status in unit.get("statuses", []):
		statuses.append("%s %d回合%s" % [labels.get(status.get("id", ""), status.get("id", "")), int(status.get("duration", 0)), " ×%d" % int(status.get("stacks", 1)) if int(status.get("stacks", 1)) > 1 else ""])
	_center_label(v, " · ".join(statuses) if not statuses.is_empty() else _element_name(unit.get("element", "")), 10, color)
	if not alive:
		p.modulate = Color(0.5, 0.5, 0.55, 0.55)
		_center_label(v, "已倒下", 12, RED)

func _do_battle_action(skill_id: String, target_id: String, automatic: bool = false) -> void:
	if battle_settled:
		return
	var result: Dictionary = battle.auto_step() if automatic else battle.act(skill_id, target_id)
	if not result.get("success", false):
		_toast(str(result.get("error", "当前无法行动")), RED)
		battle_auto = false
		return
	battle_clock = 0.0
	selected_skill = ""
	selected_target = ""
	for event in result.get("events", []):
		if event.get("text", "") != "":
			battle_log.append(_localized_combat_text(str(event.text)))
	if battle_log.size() > 80:
		battle_log = battle_log.slice(-50)
	_render_battle()
	_show_combat_events(result.get("events", []))

func _show_combat_events(events: Array) -> void:
	var generation := battle_generation
	await get_tree().process_frame
	if current_screen != "battle" or generation != battle_generation: return
	for e in events:
		if e.get("type", "") == "skill" and model.catalog.SkillData.get(e.get("skill_id", ""), {}).get("type", "") == "ultimate":
			fx.flash(_element_color(str(e.get("element", "fire"))))
		var target = unit_cards.get(str(e.get("target", "")))
		var actor = unit_cards.get(str(e.get("actor", "")))
		if not is_instance_valid(target):
			continue
		var pos: Vector2 = target.global_position + target.size * Vector2(0.5, 0.42)
		var type: String = e.get("type", "")
		var color := CYAN if type == "heal" else (GOLD if e.get("isCrit", false) else RED)
		if type in ["damage", "heal", "shield", "miss", "block"]:
			var text_value := ("+" if type == "heal" else "−") + str(int(e.get("amount", 0)))
			if type == "miss": text_value = "闪避"
			if type == "block": text_value = "格挡"
			if type == "shield": text_value = "护盾 −%d" % e.get("amount", 0)
			if e.get("isCrit", false): text_value += "!"
			_float_text(pos, text_value, color, 30 if e.get("isCrit", false) else 23)
			fx.burst(pos, color, e.get("isCrit", false))
			if is_instance_valid(actor) and type == "damage":
				fx.streak(actor.global_position + actor.size * 0.5, pos, _element_color(str(e.get("element", "fire"))))
			var original: Color = target.modulate
			if type == "damage":
				target.pivot_offset = target.size * 0.5
				target.rotation = -0.025
				var impact: Tween = target.create_tween()
				impact.tween_property(target, "rotation", 0.0, 0.22).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
			target.modulate = Color(1.8, 0.6, 0.5) if type == "damage" else Color(0.5, 1.4, 1.1)
			create_tween().tween_property(target, "modulate", original, 0.35)
		elif type in ["status", "enrage", "resist"]:
			_float_text(pos + Vector2(0, -24), _localized_combat_text(str(e.get("text", "状态变化"))), GOLD, 14)

func _finish_battle() -> void:
	if battle_settled:
		return
	battle_settled = true
	var generation := battle_generation
	var result: Dictionary = model.finish_battle(battle_config, battle.state)
	if not result.get("success", false):
		settlement_error = true
		var retrybox := _modal("保存战斗结果遇到问题", 660, 360)
		_label(retrybox, str(result.get("error", "存储不可用")), 18, RED, true)
		_button(retrybox, "重试保存结算", func():
			_clear_overlay()
			settlement_error = false
			battle_settled = false
			_finish_battle(), true)
		return
	last_reward = result
	_update_resources()
	await get_tree().create_timer(0.6).timeout
	if generation != battle_generation or current_screen != "battle":
		return
	var victory: bool = battle.state.phase == "victory"
	var run_ended: bool = battle_config.get("isAbyss", false) and (model.state.abyss.rogue.get("runId") == null or str(model.state.abyss.rogue.get("runId", "")).is_empty())
	if run_ended:
		abyss_auto_continue = false
	if victory and battle_config.get("isAbyss", false) and abyss_auto_continue:
		if _abyss_has_decision():
			_toast("已抵达旅途抉择，请确认后继续", GOLD)
			navigate("abyss")
			return
		_toast("第 %d 层通关，继续自动远征" % battle_config.get("floor", 1), GOLD)
		var next: Dictionary = model.prepare_abyss()
		if _check(next):
			_start_battle(next.config)
			return
		navigate("abyss")
		return
	if not victory: abyss_auto_continue = false
	var box := _modal(("远征通关" if run_ended else "远征胜利") if victory else "整装再出发", 760, 520)
	box.add_theme_constant_override("separation", 10)
	_center_label(box, "✦" if victory else "◇", 38, GOLD if victory else MUTED)
	_center_label(box, "星光与你同在" if victory else "旅途仍将继续", 25, TEXT)
	_center_label(box, "%d 回合 · %s" % [battle.state.get("turn", 0), battle_config.get("name", "深渊远征")], 15, MUTED)
	if victory:
		var rewards: Dictionary = result.get("rewards", {})
		_center_label(box, "金币 +%d     经验 +%d     星尘晶 +%d" % [rewards.get("gold", 0), rewards.get("exp", 0), rewards.get("diamonds", 0)], 19, GOLD)
		if result.get("firstClear", false):
			_center_label(box, "首次通关奖励已领取", 14, CYAN)
		if rewards.get("relicDrop") != null:
			_center_label(box, "获得遗物 · 已收入背包", 16, Color("b7a4df"))
		if battle_config.get("isAbyss", false):
			_center_label(box, "裂隙币 +%d     记忆碎片 +%d" % [rewards.get("runCoins", 0), rewards.get("meta", 0)], 18, Color("c4a4e8"))
			_center_label(box, "裂隙币用于本轮补给 · 记忆碎片可用于永久成长", 13, MUTED)
		var gift = result.get("gift")
		if gift is Dictionary and not gift.is_empty():
			_center_label(box, "章节赠礼  " + str(gift.get("charName", gift.get("name", "五星旅者加入"))), 20, GOLD)
		for p in result.get("progression", []):
			if p.get("leveledUp", 0) > 0:
				_center_label(box, "%s 升至等级 %d" % [_char_name(str(p.get("charId", ""))), p.get("newLevel", 1)], 14, CYAN)
	else:
		_label(box, "提升角色等级、强化遗物，或调整元素与队伍搭配后再次挑战。", 17, MUTED, true)
	if not result.get("success", true):
		_label(box, str(result.get("error", "结算异常")), 14, RED, true)
	if run_ended and not result.get("lastRun", {}).is_empty():
		var summary: Dictionary = result.lastRun
		_center_label(box, "本轮通关 %d 层 · 永久获得 %d 记忆碎片" % [int(summary.get("floorsCleared", 0)), int(summary.get("metaEarned", 0))], 17, CYAN)
	_button(_modal_footer(box), "返回营地 · 继续旅程   →" if run_ended else "继续旅程   →", func():
		_clear_overlay()
		var next_screen := "abyss" if battle_config.get("isAbyss", false) else "story"
		var key: String = str(battle_config.get("id", "")) + "_post"
		if victory and not battle_config.get("isAbyss", false) and not model.state.get("dialogueSeen", {}).get(key, false):
			_play_dialogue(key, func(): navigate(next_screen))
		else:
			navigate(next_screen), true)

func _battle_unit(uid: String) -> Dictionary:
	for group in [battle.state.get("allies", []), battle.state.get("enemies", [])]:
		for unit in group:
			if str(unit.uid) == uid:
				return unit
	return {}

func _play_dialogue(key: String, done: Callable) -> void:
	dialogue_lines = model.catalog.DialogueData.get(key, [])
	if dialogue_lines.is_empty():
		if done.is_valid(): done.call()
		return
	dialogue_key = key
	dialogue_index = 0
	dialogue_done = done
	_render_dialogue()

func _render_dialogue() -> void:
	if compact:
		_render_mobile_dialogue()
		return
	_clear_overlay()
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.06, 0.97)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(bg)
	var art := TextureRect.new()
	art.texture = load("res://assets/wilderness.png")
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.modulate = Color(0.65, 0.65, 0.7)
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(art)
	var line: Dictionary = dialogue_lines[dialogue_index]
	var speaker: String = line.get("speaker", "narrator")
	var portrait_id = line.get("portrait")
	if portrait_id is String and model.catalog.CharacterData.has(portrait_id):
		var portrait := _portrait(overlay, portrait_id, size.y * 0.62, true)
		portrait.position = Vector2(size.x * 0.52, size.y * 0.06)
		portrait.size.x = size.x * 0.44
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	margin.offset_top = -320 if not compact else -410
	margin.offset_bottom = -38
	margin.offset_left = 60 if not compact else 24
	margin.offset_right = -60 if not compact else -24
	overlay.add_child(margin)
	var p := _panel(margin, GOLD.darkened(0.35), 30)
	p.add_theme_stylebox_override("panel", _box(Color(0.035, 0.06, 0.10, 0.96), GOLD.darkened(0.5), 30))
	var v := _vbox(p, 20)
	var speaker_name: String = line.get("speakerName", _char_name(speaker))
	if speaker == "narrator": speaker_name = "旅者纪事"
	if speaker == "traveler": speaker_name = "旅行者"
	_label(v, speaker_name, 22, _element_color(line.get("element", "fire")) if speaker != "narrator" else GOLD)
	var prose := _label(v, line.get("text", ""), 22 if not compact else 19, TEXT, true)
	prose.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dialogue_prose = prose
	prose.visible_characters = 0
	dialogue_tween = create_tween()
	dialogue_tween.tween_property(prose, "visible_characters", str(line.get("text", "")).length(), minf(1.5, str(line.get("text", "")).length() * 0.023))
	var row := _hbox(v, 15)
	_label(row, "%d / %d" % [dialogue_index + 1, dialogue_lines.size()], 13, MUTED)
	var space := Control.new()
	space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(space)
	_button(row, "跳过剧情", _finish_dialogue)
	_button(row, "继续   →" if dialogue_index < dialogue_lines.size() - 1 else "踏上旅途   →", _next_dialogue, true)

func _render_mobile_dialogue() -> void:
	var line: Dictionary = dialogue_lines[dialogue_index]
	var speaker := str(line.get("speaker", "narrator"))
	var speaker_name := str(line.get("speakerName", _char_name(speaker)))
	if speaker == "narrator": speaker_name = "旅者纪事"
	if speaker == "traveler": speaker_name = "旅行者"
	var v := _modal(speaker_name, 700, size.y - 24)
	var portrait_id = line.get("portrait")
	if portrait_id is String and model.catalog.CharacterData.has(portrait_id):
		_portrait(v, portrait_id, 180)
	dialogue_prose = _label(v, str(line.get("text", "")), 19, TEXT, true)
	dialogue_prose.visible_characters = 0
	if dialogue_tween: dialogue_tween.kill()
	dialogue_tween = create_tween()
	dialogue_tween.tween_property(dialogue_prose, "visible_characters", dialogue_prose.text.length(), minf(1.5, dialogue_prose.text.length() * 0.023))
	var footer := _modal_footer(v)
	_label(footer, "%d / %d" % [dialogue_index + 1, dialogue_lines.size()], 14, MUTED)
	var actions := _flow(footer, 8)
	_button(actions, "跳过剧情", _finish_dialogue)
	_button(actions, "继续 →" if dialogue_index < dialogue_lines.size() - 1 else "踏上旅途 →", _next_dialogue, true)

func _next_dialogue() -> void:
	if dialogue_key == "": return
	if is_instance_valid(dialogue_prose) and dialogue_prose.visible_characters >= 0 and dialogue_prose.visible_characters < dialogue_prose.text.length():
		if dialogue_tween: dialogue_tween.kill()
		dialogue_prose.visible_characters = -1
		return
	dialogue_index += 1
	if dialogue_index >= dialogue_lines.size():
		_finish_dialogue()
	else:
		_render_dialogue()

func _finish_dialogue() -> void:
	if dialogue_key == "": return
	if dialogue_tween: dialogue_tween.kill()
	model.mark_dialogue_seen(dialogue_key)
	dialogue_key = ""
	_clear_overlay()
	var callback := dialogue_done
	dialogue_done = Callable()
	if callback.is_valid(): callback.call()

func _box(color: Color, border: Color = LINE, padding: int = 14) -> StyleBoxFlat:
	padding = mini(padding, 14) if compact else padding
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding
	style.content_margin_bottom = padding
	return style

func _panel(parent: Node, border: Color = LINE, padding: int = 18) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _box(Color(0.055, 0.085, 0.135, 0.94), border, padding))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	p.mouse_force_pass_scroll_events = true
	parent.add_child(p)
	return p

func _responsive_box(parent: Node, vertical: bool, gap: int) -> BoxContainer:
	if vertical: return _vbox(parent, gap)
	return _hbox(parent, gap)

func _vbox(parent: Node, gap: int = 14) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", gap)
	parent.add_child(v)
	return v

func _hbox(parent: Node, gap: int = 14) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", gap)
	parent.add_child(h)
	return h

func _flow(parent: Node, gap: int = 12) -> HFlowContainer:
	var row := HFlowContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("h_separation", gap)
	row.add_theme_constant_override("v_separation", gap)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(row)
	return row

func _grid(parent: Node, columns: int) -> GridContainer:
	var g := GridContainer.new()
	g.columns = columns
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.add_theme_constant_override("h_separation", 14)
	g.add_theme_constant_override("v_separation", 14)
	parent.add_child(g)
	return g

func _label(parent: Node, text: String, font_size: int = 17, color: Color = TEXT, wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", maxi(14, font_size) if compact else font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if wrap or compact:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(l)
	return l

func _center_label(parent: Node, text: String, font_size: int = 17, color: Color = TEXT) -> Label:
	var l := _label(parent, text, font_size, color, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

func _button(parent: Node, text: String, action: Callable, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = 48
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	b.mouse_force_pass_scroll_events = true
	b.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_color_override("font_color", INK if primary else TEXT)
	b.add_theme_color_override("font_hover_color", INK if primary else Color.WHITE)
	b.add_theme_stylebox_override("normal", _box(GOLD if primary else Color("182336"), GOLD if primary else LINE, 12))
	b.add_theme_stylebox_override("hover", _box(GOLD.lightened(0.13) if primary else Color("26364d"), GOLD if primary else CYAN.darkened(0.3), 12))
	b.add_theme_stylebox_override("pressed", _box(GOLD.darkened(0.16) if primary else Color("101a2b"), GOLD, 12))
	b.add_theme_stylebox_override("focus", _box(Color(0, 0, 0, 0), CYAN, 12))
	b.add_theme_stylebox_override("disabled", _box(Color("111925"), Color("202b3b"), 12))
	if action.is_valid():
		b.pressed.connect(action)
	parent.add_child(b)
	return b

func _progress(parent: Node, value: float, maximum: float, color: Color, height: int = 8) -> ProgressBar:
	var p := ProgressBar.new()
	p.max_value = maxf(1.0, maximum)
	p.value = value
	p.show_percentage = false
	p.custom_minimum_size.y = height
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("background", _box(Color("080e18"), Color(0, 0, 0, 0), 0))
	p.add_theme_stylebox_override("fill", _box(color, Color(0, 0, 0, 0), 0))
	parent.add_child(p)
	return p

func _page_title(title: String, subtitle: String) -> void:
	var v := _vbox(main_body, 5)
	_label(v, title, 32, TEXT)
	_label(v, subtitle, 14, MUTED)

func _section(title: String, subtitle: String = "") -> void:
	var row := _responsive_box(main_body, compact, 6 if compact else 14)
	_label(row, title, 23, TEXT)
	if subtitle != "":
		var l := _label(row, subtitle, 12, MUTED, true)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER

func _scene_panel(parent: Node, path: String, height: int) -> Control:
	var p := Control.new()
	p.custom_minimum_size.y = height
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.clip_contents = true
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(p)
	var image := TextureRect.new()
	image.texture = load(path)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(image)
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.025, 0.045, 0.08, 0.93))
	gradient.set_color(1, Color(0.02, 0.03, 0.05, 0.05))
	gradient.add_point(0.53, Color(0.03, 0.04, 0.07, 0.42))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2.ZERO
	texture.fill_to = Vector2.RIGHT
	var shade := TextureRect.new()
	shade.texture = texture
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(shade)
	var border := Panel.new()
	border.add_theme_stylebox_override("panel", _box(Color(0, 0, 0, 0), GOLD.darkened(0.6), 0))
	border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(border)
	return p

func _portrait(parent: Node, id: String, height: float, _wide: bool = false, enemy: bool = false) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = height
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.clip_contents = true
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(c)
	var path := "res://assets/characters/%s.png" % id
	if not ResourceLoader.exists(path):
		path = "res://assets/portraits/%s.svg" % id
	if ResourceLoader.exists(path):
		var t := TextureRect.new()
		t.texture = load(path)
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.add_child(t)
	else:
		var bg := ColorRect.new()
		bg.color = Color("142335") if not enemy else Color("2b1929")
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.add_child(bg)
		var l := _label(c, "✦", int(height * 0.48), GOLD)
		l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return c

func _character_card(parent: Node, id: String, art_height: int, action: Callable) -> PanelContainer:
	var data: Dictionary = model.catalog.CharacterData.get(id, {})
	var rarity: int = int(data.get("rarity", 3))
	var color := _rarity_color(rarity)
	var owned: bool = model.state.ownedCharacters.has(id)
	var p := _panel(parent, color.darkened(0.5), 10)
	var v := _vbox(p, 7)
	_portrait(v, id, art_height)
	_label(v, "★".repeat(rarity) + "   " + _element_name(data.get("element", "")), 11, color)
	_label(v, data.get("name", id), 18, TEXT)
	_label(v, "等级 %d   ·   %s" % [model.state.ownedCharacters.get(id, {}).get("level", 1), model.catalog.RoleNames.get(data.get("role", ""), "")] if owned else "未拥有 · 可查看完整档案", 12, MUTED)
	if action.is_valid():
		p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_bind_card_tap(p, action)
		_ignore_children(v)
	if not owned:
		p.modulate = Color(0.72, 0.75, 0.8, 0.8)
	return p

func _bind_card_tap(card: Control, action: Callable) -> void:
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	card.mouse_force_pass_scroll_events = true
	var gesture := {"down": false, "start": Vector2.ZERO, "drag": false}
	card.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				gesture.down = true
				gesture.start = event.global_position
				gesture.drag = false
			else:
				var activate: bool = gesture.down and not gesture.drag and not _touch_dragging and card.get_global_rect().has_point(event.global_position)
				gesture.down = false
				if activate:
					action.call()
		elif event is InputEventMouseMotion and gesture.down:
			if event.global_position.distance_to(gesture.start) > 8:
				gesture.drag = true)

func _ignore_children(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_children(child)

func _info_tile(parent: Node, eyebrow: String, title: String, desc: String, button_text: String, callback: Callable, accent: Color) -> void:
	var panel := _panel(parent, accent.darkened(0.65), 22)
	var v := _vbox(panel, 11)
	_label(v, eyebrow, 11, accent)
	_label(v, title, 25, TEXT)
	var l := _label(v, desc, 14, MUTED, true)
	l.custom_minimum_size.y = 44
	_button(v, button_text + "   →", callback)

func _empty_state(parent: Node, title: String, description: String, button_text: String, callback: Callable) -> void:
	var p := _panel(parent, LINE, 40)
	var v := _vbox(p, 20)
	_center_label(v, "◇", 80, GOLD)
	_center_label(v, title, 26, TEXT)
	_center_label(v, description, 16, MUTED)
	_button(v, button_text, callback, true)

func _modal(title: String, width: float = 700, height: float = 700) -> VBoxContainer:
	_clear_overlay()
	var dim := ColorRect.new()
	dim.color = Color(0.015, 0.022, 0.04, 0.91)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	var p := PanelContainer.new()
	p.name = "ModalPanel"
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	p.set_meta("requested_size", Vector2(width, height))
	_layout_modal(p)
	p.add_theme_stylebox_override("panel", _box(PANEL, GOLD.darkened(0.55), 14 if compact else 26))
	overlay.add_child(p)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	p.add_child(scroll)
	var v := _vbox(scroll, 18)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(v, title, 24, GOLD)
	return v

func _usable_rect() -> Rect2:
	var safe := Rect2(Vector2.ZERO, size)
	if _is_mobile():
		var physical_safe := DisplayServer.get_display_safe_area()
		if physical_safe.size.x > 0 and physical_safe.size.y > 0:
			var scale_factor := size / Vector2(get_window().size)
			safe = Rect2(Vector2(physical_safe.position) * scale_factor, Vector2(physical_safe.size) * scale_factor).intersection(safe)
	return safe

func _layout_modal(panel: Control) -> void:
	var requested: Vector2 = panel.get_meta("requested_size", Vector2(700, 700))
	var safe := _usable_rect()
	var available := safe.size - Vector2(24, 32)
	var modal_size := Vector2(minf(requested.x, available.x), minf(requested.y, available.y))
	var center_offset := safe.get_center() - size / 2
	panel.offset_left = center_offset.x - modal_size.x / 2
	panel.offset_right = center_offset.x + modal_size.x / 2
	panel.offset_top = center_offset.y - modal_size.y / 2
	panel.offset_bottom = center_offset.y + modal_size.y / 2

func _confirm(title: String, message: String, accept: Callable) -> void:
	var box := _modal(title, 660, 330)
	_label(box, message, 18, TEXT, true)
	var row := _hbox(box, 14)
	_button(row, "返回", _clear_overlay)
	_button(row, "确认", func(): _clear_overlay(); accept.call(), true)

func _clear_overlay() -> void:
	if is_instance_valid(overlay):
		_clear(overlay)

func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()

func _check(result: Dictionary) -> bool:
	if not result.get("success", false):
		_toast(str(result.get("error", "操作未完成")), RED)
		return false
	_update_resources()
	return true

func _toast(message: String, color: Color = GOLD) -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _box(Color("142235"), color.darkened(0.3), 16))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_layer.add_child(p)
	var l := _label(p, message, 16, color, true)
	l.custom_minimum_size.x = minf(size.x - 100, 650)
	p.position = Vector2(maxf(35, (size.x - l.custom_minimum_size.x - 32) / 2), size.y - 100)
	var tween := create_tween()
	tween.tween_interval(2.6)
	tween.tween_property(p, "modulate:a", 0.0, 0.4)
	tween.tween_callback(p.queue_free)

func _float_text(at: Vector2, value: String, color: Color, font_size: int = 25) -> void:
	var l := _label(fx, value, font_size, color)
	l.add_theme_constant_override("outline_size", 5)
	l.add_theme_color_override("font_outline_color", INK)
	l.position = at - Vector2(30, 0)
	var tween := create_tween().set_parallel()
	tween.tween_property(l, "position:y", l.position.y - 75, 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(l, "modulate:a", 0.0, 0.7).set_delay(0.2)
	tween.chain().tween_callback(l.queue_free)

func _char_name(id: String) -> String:
	return str(model.catalog.CharacterData.get(id, {}).get("name", id))

func _char_names(ids: Array) -> String:
	var names: Array = []
	for id in ids: names.append(_char_name(str(id)))
	return "、".join(names)

func _element_name(id: String) -> String:
	return {"fire": "火", "water": "水", "wind": "风", "thunder": "雷", "全部": "全部"}.get(id, id)

func _element_color(id: String) -> Color:
	return {"fire": Color("ee9b7c"), "water": Color("83bceb"), "wind": Color("99cba5"), "thunder": Color("d5b5eb")}.get(id, GOLD)

func _rarity_color(rarity: int) -> Color:
	return {3: Color("a7b6cc"), 4: Color("b6a0df"), 5: GOLD}.get(rarity, TEXT)

func _slot_name(id: String) -> String:
	for s in model.catalog.RelicSlots:
		if s.id == id: return str(s.name)
	return id

func _find_relic(uid: String) -> Dictionary:
	for relic in model.state.get("relics", []):
		if str(relic.uid) == uid: return relic
	return {}

func _relic_main(relic: Dictionary) -> String:
	var stat: Dictionary = relic.get("mainStat", {})
	var value: float = float(stat.get("base", 0)) + float(stat.get("perLevel", 0)) * int(relic.get("level", 0))
	return str(stat.get("name", "属性")) + " +" + _stat_value(str(stat.get("stat", "")), value)

func _stat_value(stat: String, value: float) -> String:
	return "%.1f%%" % (value * 100) if stat.ends_with("_pct") or stat in ["cri_rate", "cri_dmg", "energy_rate"] else str(int(value))

func _reward_text(rewards: Array) -> String:
	var lines: Array = []
	for r in rewards:
		lines.append("%s ×%d" % [{"gold": "金币", "diamonds": "星尘晶", "stamina": "体力", "exp": "经验"}.get(str(r.get("type", "")), str(r.get("type", ""))), r.get("amount", 0)])
	return "\n".join(lines)

func _show_battle_echoes() -> void:
	var box := _modal("本轮回响构筑", 720)
	for raw in model.state.abyss.rogue.get("selectedRewards", []):
		var reward: Dictionary = raw if raw is Dictionary else _abyss_reward(str(raw))
		_label(box, str(reward.get("name", "回响")), 22, GOLD)
		_label(box, str(reward.get("description", "")), 16, TEXT, true)
	if model.state.abyss.rogue.get("selectedRewards", []).is_empty():
		_label(box, "本轮还未获得回响。继续挑战，回响层将为你提供新的祝福。", 17, MUTED, true)
	_button(box, "回到战斗", _clear_overlay, true)

func _load_preferences() -> void:
	if test_session: return
	var config := ConfigFile.new()
	if config.load("user://ui-settings.cfg") != OK: return
	relic_filter = str(config.get_value("relics", "rarity_filter", "全部"))
	relic_slot_filter = str(config.get_value("relics", "slot_filter", "全部"))
	selected_relic = str(config.get_value("relics", "selection", ""))
	for key in salvage_options:
		salvage_options[key] = bool(config.get_value("salvage", key, false))

func _save_preferences() -> void:
	if test_session: return
	var config := ConfigFile.new()
	config.set_value("relics", "rarity_filter", relic_filter)
	config.set_value("relics", "slot_filter", relic_slot_filter)
	config.set_value("relics", "selection", selected_relic)
	for key in salvage_options:
		config.set_value("salvage", key, salvage_options[key])
	config.save("user://ui-settings.cfg")

func _show_abyss_rules() -> void:
	var box := _modal("深渊战斗规则", 680, 460)
	_label(box, "火克风、风克雷、雷克水、水克火。调整技能和目标，可以集中突破敌方关键单位。", 17, TEXT, true)
	_label(box, "首领至多连续跳过一次行动，其他深渊敌人至多连续跳过两次，随后获得一次保证行动。中毒最多叠加 5 层；普通敌人每层受到最大生命 5% 的伤害，首领每层为 1.5%。首领战超过 20 回合后，每回合攻击提升 5%，上限为 100%。", 16, MUTED, true)
	_label(box, "自动战斗负责战斗行动。祝福、路线、事件、篝火和商店都会等待你的选择。生命、能量与冷却在本轮远征中延续。", 16, MUTED, true)
	_button(box, "回到战斗", _clear_overlay, true)

func _modal_footer(content: VBoxContainer) -> VBoxContainer:
	# Keep the outcome action visible while longer rewards scroll above it.
	var scroll: ScrollContainer = content.get_parent()
	var panel: PanelContainer = scroll.get_parent()
	panel.remove_child(scroll)
	var layout := _vbox(panel, 14)
	layout.add_child(scroll)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return _vbox(layout, 0)

func _localized_combat_text(text_value: String) -> String:
	for id in STATUS_NAMES:
		text_value = text_value.replace(str(id), str(STATUS_NAMES[id]))
	return text_value
