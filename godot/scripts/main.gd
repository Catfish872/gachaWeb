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
const ExtractionView = preload("res://scripts/ui/extraction_view.gd")
const UpdateChecker = preload("res://scripts/update_checker.gd")
const STATUS_NAMES := {"burn": "燃烧", "freeze": "冰冻", "shock": "感电", "electrify": "感电", "poison": "中毒", "regen": "再生", "def_up": "防御提升", "atk_up": "攻击提升", "spd_up": "速度提升", "def_down": "防御降低", "atk_down": "攻击降低", "spd_down": "减速", "taunt": "嘲讽", "shield": "护盾", "bleed": "流血", "stun": "眩晕", "vulnerable": "易伤", "invincible": "无敌"}
const TABS := [["home", "旅者营地", "01"], ["story", "世界探索", "02"], ["summon", "星辰祈愿", "03"], ["party", "冒险编队", "04"], ["growth", "角色养成", "05"], ["relics", "遗物工坊", "06"], ["abyss", "深渊远征", "07"], ["extraction", "遗境搜打撤", "08"], ["shop", "补给商店", "09"], ["save", "旅程档案", "10"]]

var model
var battle
var current_screen := "home"
var selected_character := "kaldi"
var selected_pool := "limited_kaldi"
var selected_chapter := 0
var selected_stage_id := ""
var growth_panel := "stats"
var selected_relic := ""
var relic_filter := "全部"
var draft_team: Array = []
var page_scroll: ScrollContainer
var main_body: VBoxContainer
var shell: Control
var header_resources: HBoxContainer
var shell_header: HBoxContainer
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
var extraction_panel := "expedition"
var extraction_selected := ""
var extraction_scope := "bag"
var extraction_difficulty := 0
var extraction_sound := true
var extraction_reduced_motion := false
var extraction_search_generation := 0
var extraction_searching := false
var extraction_search_container := ""
var extraction_auto_pick := true
var extraction_recent: Dictionary = {}
var extraction_audio: AudioStreamPlayer
var extraction_search_audio: AudioStreamPlayer
var music_audio: AudioStreamPlayer
var ui_audio: AudioStreamPlayer
var music_enabled := true
var sound_enabled := true
var music_volume_db := -8.0
var effects_volume_db := -10.0
var _last_ui_sound_msec := 0
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
var update_notice: Button
var navigation_history: Array[String] = []
var back_button: Button
var _last_layout_size := Vector2.ZERO
var _touch_scroll: ScrollContainer
var _touch_start := Vector2.ZERO
var _touch_previous := Vector2.ZERO
var _touch_dragging := false
var _touch_id := -1
var _ui_input_dispatch := false
var _scroll_velocity := 0.0
var _scroll_position := 0.0
var _inertia_scroll: ScrollContainer
var _touch_timestamp := 0
var _page_fixed := false

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
	t.set_constant("separation", "VBoxContainer", 10)
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
	compact = size.x < 760
	_last_layout_size = size
	_build_shell()
	_ready_done = true
	resized.connect(_resized)
	navigate("home")
	updater.schedule_startup_check(test_session)

func _process(delta: float) -> void:
	if not _ready_done:
		return
	_tick_scroll(delta)
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
	# GUI callbacks can remove their own ancestors. Keep the tree intact until
	# Godot has finished propagating this native/emulated input event.
	if not _ui_input_dispatch:
		_ui_input_dispatch = true
		_end_ui_input_dispatch.call_deferred()
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
			_touch_timestamp = Time.get_ticks_msec()
			_touch_dragging = false
			_scroll_velocity = 0.0
			_inertia_scroll = null
			var touch_root: Node = overlay if overlay.get_child_count() > 0 else shell
			_touch_scroll = null if _extraction_gesture_at(touch_root,event.position) else _scroll_at(touch_root,event.position)
			if is_instance_valid(_touch_scroll): _scroll_position = _touch_scroll.scroll_vertical
		elif not event.pressed and event.index == _touch_id:
			if _touch_dragging:
				get_viewport().set_input_as_handled()
				_inertia_scroll = _touch_scroll
				if Time.get_ticks_msec() - _touch_timestamp > 90: _scroll_velocity = 0.0
			_touch_id = -1
			_touch_scroll = null
	elif event is InputEventScreenDrag and event.index == _touch_id and is_instance_valid(_touch_scroll):
		var touch_root:Node=overlay if overlay.get_child_count()>0 else shell
		if _extraction_gesture_at(touch_root,event.position):
			_touch_scroll=null
			_inertia_scroll=null
			_scroll_velocity=0.0
			return
		if not _touch_dragging:
			var travel:Vector2=event.position-_touch_start
			if absf(travel.x)>=6 and absf(travel.x)>absf(travel.y):
				_touch_scroll=null
				return
			if absf(travel.y)>=6 and absf(travel.y)>=absf(travel.x)*1.15:
				_touch_dragging=true
		if _touch_dragging:
			var now := Time.get_ticks_msec()
			var elapsed := maxf(0.004, float(now - _touch_timestamp) / 1000.0)
			var distance: float = event.position.y - _touch_previous.y
			_scroll_velocity = lerpf(_scroll_velocity, -distance / elapsed, 0.55)
			_scroll_position -= distance
			_apply_scroll(_touch_scroll)
			_touch_timestamp = now
			get_viewport().set_input_as_handled()
		_touch_previous = event.position

func _apply_scroll(scroll: ScrollContainer) -> void:
	var bar := scroll.get_v_scroll_bar()
	_scroll_position = clampf(_scroll_position, 0.0, maxf(0.0, bar.max_value - bar.page))
	scroll.scroll_vertical = roundi(_scroll_position)

func _tick_scroll(delta: float) -> void:
	if _touch_id != -1 or not is_instance_valid(_inertia_scroll): return
	if not _inertia_scroll.is_inside_tree() or absf(_scroll_velocity) < 8:
		_inertia_scroll = null
		_scroll_velocity = 0.0
		return
	var previous := _scroll_position
	_scroll_position += _scroll_velocity * delta
	_apply_scroll(_inertia_scroll)
	_scroll_velocity *= exp(-5.5 * delta)
	if is_equal_approx(previous, _scroll_position): _scroll_velocity = 0.0

func _visible_control_rect(control: Control) -> Rect2:
	var rect := control.get_global_rect()
	var parent := control.get_parent()
	while parent != null:
		if parent is Control and (parent.clip_contents or parent is ScrollContainer):
			rect = rect.intersection(parent.get_global_rect())
		parent = parent.get_parent()
	return rect

func _exit_tree() -> void:
	for child in get_children():
		if child is AudioStreamPlayer:
			child.stop()
			child.stream = null

func _extraction_gesture_at(node: Node, at: Vector2) -> bool:
	if node is Control and not node.is_visible_in_tree(): return false
	if node is Control and (node.get_meta("extraction_pan", false) or node.get_meta("inventory_selection",false)) and _visible_control_rect(node).has_point(at): return true
	for child in node.get_children():
		if _extraction_gesture_at(child,at): return true
	return false

func _scroll_at(node: Node, at: Vector2) -> ScrollContainer:
	if node is Control and not node.is_visible_in_tree():
		return null
	for child in node.get_children():
		var found := _scroll_at(child, at)
		if found != null:
			return found
	if node is ScrollContainer and node.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED and _visible_control_rect(node).has_point(at):
		return node
	return null

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		_extraction_stop_search_audio()
		if is_inside_tree():
			for voice in get_tree().get_nodes_in_group("transient_audio"):
				voice.stop();voice.queue_free()
		if is_instance_valid(ui_audio):ui_audio.stop()
		for player in get_children():
			if player is AudioStreamPlayer and player.has_meta("track"):player.stream_paused=true
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		for player in get_children():
			if player is AudioStreamPlayer and player.has_meta("track"):player.stream_paused=false
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
		if current_screen == "extraction" and extraction_searching:
			ExtractionView._stop_search(self,false)
		if settlement_error:
			_toast("请先重试保存本场战斗结果", RED)
			return
		_clear_overlay()
		return
	if current_screen == "battle":
		navigate(_battle_return_screen())
	elif current_screen == "extraction" and not extraction_selected.is_empty():
		extraction_selected = ""
		_render_screen()
	elif current_screen == "extraction" and extraction_panel != "expedition":
		ExtractionView._switch_panel(self, "expedition")
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
		var destination := _button(grid, tab[1], func(): navigate(tab[0]), tab[0] == current_screen)
		destination.name = "MenuNav_" + tab[0]
		destination.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(menu, "声音与动画", _show_audio_settings)
	_button(menu, "返回游戏", _clear_overlay)

func _is_mobile() -> bool:
	return OS.has_feature("mobile") or "--mobile-ui" in OS.get_cmdline_user_args()

func _adapt_viewport() -> void:
	var window := get_window()
	var physical := Vector2(window.size)
	var ratio: float = physical.x / maxf(1.0, physical.y)
	# Landscape uses a 540-point short edge, keeping text and touch targets readable.
	var mobile := _is_mobile() or ratio < 1.15 or minf(physical.x, physical.y) < 700.0
	var logical_width: int = (int(540.0 * ratio) if ratio >= 1.15 else 540) if mobile else 1440
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
	compact = size.x < 760
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
		art.name = "SceneBackdrop"
		art.texture = load(_background_path())
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
	var inset := 12
	shell.add_theme_constant_override("margin_left", inset + int(safe.position.x))
	shell.add_theme_constant_override("margin_right", inset + int(maxf(0, size.x - safe.end.x)))
	shell.add_theme_constant_override("margin_top", 8 + int(safe.position.y))
	shell.add_theme_constant_override("margin_bottom", 8 + int(maxf(0, size.y - safe.end.y)))
	add_child(shell)
	var vertical := _vbox(shell, 8)
	var header := _hbox(vertical, 8)
	shell_header=header
	back_button = _button(header, "‹ 返回", _go_back)
	back_button.name = "BackButton"
	var brand := _vbox(header, 2)
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(brand, "虚空裂变", 22 if compact else 28, GOLD)
	if size.y >= 700:
		_label(brand, "VOID RIFT  /  旅者纪事", 10, MUTED)
	_button(header, "菜单", _show_navigation).name = "MenuButton"
	header_resources = _hbox(vertical if compact else header, 6)
	_update_resources()
	update_notice = _button(header, "有更新", _show_updates, true)
	update_notice.custom_minimum_size = Vector2(96,48)
	update_notice.size_flags_horizontal = Control.SIZE_SHRINK_END
	update_notice.name = "UpdateNotice"
	update_notice.clip_text = true
	update_notice.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_refresh_update_notice()
	var main := _hbox(vertical, 16)
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var nav := _vbox(main, 8)
	nav.visible = size.x >= 1500
	if nav.visible:
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
	page_scroll = scroll
	scroll.name = "PageScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main.add_child(scroll)
	main_body = _vbox(scroll, 12)
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
		_confirm("离开战斗？", ("撤退将结束本轮搜打撤，背包和本局装备会遗失。角色、仓库与原有养成保留。" if battle_config.get("isExtraction", false) else "撤退将结束当前战斗，已消耗的体力保留。深渊撤退会结束本轮构筑。"), func():
			if not _check(model.abandon_battle(battle_config, battle.state)):
				return
			abyss_auto_continue = false
			battle_settled = true
			navigate(screen))
		return
	if screen != "extraction":
		extraction_search_generation += 1
		extraction_searching = false
		_extraction_stop_search_audio()
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

func _background_path() -> String:
	if current_screen in ["abyss", "extraction"] or (current_screen == "battle" and (battle_config.get("isAbyss", false) or battle_config.get("isExtraction", false))):
		return "res://assets/backgrounds/abyss.png"
	if current_screen in ["story", "battle"]:
		return "res://assets/backgrounds/snowfield.png" if selected_chapter == 1 else "res://assets/wilderness.png"
	return "res://assets/backgrounds/camp.png"

func _render_screen() -> void:
	var backdrop := get_node_or_null("SceneBackdrop") as TextureRect
	if backdrop != null:
		backdrop.texture = load(_background_path())
		backdrop.modulate = Color(0.65,0.68,0.75,0.7) if current_screen == "battle" else Color(0.28,0.32,0.4,0.20)
	_refresh_update_notice()
	_sync_music()
	shell_header.visible=current_screen!="battle"
	fx.reduced_motion = extraction_reduced_motion
	if current_screen != "battle":
		unit_cards.clear()
		fx.clear_effects()
	_clear(main_body)
	set_page_fixed(false)
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
		"extraction": ExtractionView.render(self)
		"shop": _shop()
		"save": _save_screen()
		"battle": _render_battle()
	main_body.modulate.a = 1.0

func _update_resources() -> void:
	if not is_instance_valid(header_resources):
		return
	_clear(header_resources)
	var r: Dictionary = model.state.get("resources", {})
	for item in [["星尘晶", r.get("diamonds", 0), CYAN], ["金币", r.get("gold", 0), GOLD], ["体力", "%s / %s" % [r.get("stamina", 0), r.get("maxStamina", 100)], Color("a6c9a5")]]:
		var p := _panel(header_resources, item[2].darkened(0.7), 5)
		if size.x > size.y:
			_label(p, "%s  %s" % [item[0], str(item[1])], 12, item[2])
		else:
			var col := _vbox(p, 0)
			_label(col, item[0], 12, MUTED)
			_label(col, str(item[1]), 16 if compact else 20, item[2])

func _home() -> void:
	set_page_fixed(not compact)
	var row:=_responsive_box(main_body,compact,14)
	row.size_flags_vertical=Control.SIZE_EXPAND_FILL
	var hero:=_scene_panel(row,"res://assets/backgrounds/camp.png",430 if compact else 260)
	hero.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	hero.size_flags_stretch_ratio=1.65
	var content:=_vbox(hero,12)
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left=24;content.offset_right=-24;content.offset_top=28;content.offset_bottom=-20
	_label(content,"旅 者 纪 事 · 第一章",13,GOLD)
	_label(content,"穿越灰烬\n追寻群星",40,TEXT)
	_label(content,"召集同行者，踏上流火荒原。",16,MUTED,true)
	var spacer:=Control.new();spacer.size_flags_vertical=Control.SIZE_EXPAND_FILL;content.add_child(spacer)
	var actions:=_hbox(content,8)
	_button(actions,"继续旅程",func():navigate("story"),true)
	_button(actions,"冒险编队",func():navigate("party"))
	var shortcuts:=_vbox(row,10)
	shortcuts.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	for item in [["extraction","遗境搜打撤","搜寻珍宝 · 满载归来",CYAN],["abyss","深渊远征","选择回响 · 构筑力量",Color("b49cdd")],["summon","星辰祈愿","与群星相遇",GOLD]]:
		var art_path:String={"extraction":"res://assets/extraction/rooms/ruins_1.webp","abyss":"res://assets/backgrounds/abyss.png","summon":"res://assets/backgrounds/snowfield.png"}[item[0]]
		var card:=_scene_panel(shortcuts,art_path,100)
		card.size_flags_vertical=Control.SIZE_EXPAND_FILL
		card.mouse_filter=Control.MOUSE_FILTER_STOP
		var v:=_vbox(card,6)
		v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		v.offset_left=16;v.offset_right=-16;v.offset_top=18;v.offset_bottom=-12
		_label(v,item[1],23,item[3])
		_label(v,item[2],13,MUTED)
		_bind_card_tap(card,func():navigate(str(item[0])))
		_ignore_children(v)
	var team:=_responsive_box(main_body,compact,10)
	for id in model.state.get("team",[]):
		if id==null or str(id).is_empty():continue
		var panel:=_panel(team,LINE,6)
		var body:=_hbox(panel,10)
		var portrait:=_portrait(body,str(id),58)
		portrait.custom_minimum_size.x=55
		var labels:=_vbox(body,3)
		labels.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		_label(labels,_char_name(str(id)),16,TEXT)
		_label(labels,"等级 %d" % model.state.ownedCharacters.get(id,{}).get("level",1),12,GOLD)
		_bind_card_tap(panel,func():selected_character=str(id);navigate("growth"))
		_ignore_children(body)
	var tools:=_hbox(team,8)
	_button(tools,"遗物工坊",func():navigate("relics"))
	_button(tools,"补给商店",func():navigate("shop"))

func _story() -> void:
	set_page_fixed(not compact)
	_page_title("世界探索", "选择目的地，继续旅程")
	var chapters: Array = model.catalog.StageData.chapters
	var tabs := _hbox(main_body, 8)
	for i in chapters.size():
		_button(tabs,str(chapters[i].name),func():selected_chapter=i;selected_stage_id="";_render_screen(),selected_chapter==i)
	var row := _responsive_box(main_body,compact,16)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var stages_panel := _panel(row,LINE,10)
	stages_panel.size_flags_stretch_ratio = 0.85
	var stage_list := _scroll_column(stages_panel)
	var stage_map: Dictionary = {}
	for stage in model.stage_list(): stage_map[stage.id]=stage
	var chapter: Dictionary=chapters[selected_chapter]
	if selected_stage_id.is_empty() or not stage_map.has(selected_stage_id): selected_stage_id=str(chapter.stages[0].id)
	for index in chapter.stages.size():
		var data: Dictionary=stage_map.get(chapter.stages[index].id,chapter.stages[index])
		var card := _panel(stage_list,GOLD if str(data.id)==selected_stage_id else LINE,10)
		var line := _hbox(card,10)
		var number:=_label(line,"%02d" % (index+1),22,GOLD if data.get("unlocked",false) else MUTED)
		number.custom_minimum_size.x=35
		var labels:=_vbox(line,2);labels.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		_label(labels,str(data.name),17,TEXT,true)
		_label(labels,"已通关" if data.get("completed",data.get("cleared",false)) else ("可探索" if data.get("unlocked",false) else "尚未解锁"),12,CYAN)
		_bind_card_tap(card,func():selected_stage_id=str(data.id);_render_screen())
		_ignore_children(line)
	var preview := _panel(row,GOLD.darkened(0.65),12)
	preview.size_flags_stretch_ratio=1.15
	var pv:=_vbox(preview,8)
	var selected:Dictionary=stage_map.get(selected_stage_id,chapter.stages[0])
	var banner:=_scene_panel(pv,_background_path(),110)
	banner.size_flags_vertical=Control.SIZE_EXPAND_FILL
	_label(pv,str(selected.name),25,TEXT,true)
	var description:=_label(pv,str(chapter.description),14,MUTED,true)
	description.max_lines_visible=2
	var names:Array=[]
	for wave in selected.get("waves",[]):
		for enemy_id in wave.get("enemies",[]):
			var enemy_name:String=str(model.catalog.EnemyData.get(enemy_id,{}).get("name",enemy_id))
			if enemy_name not in names:names.append(enemy_name)
	var tags:=_flow(pv,6)
	for name in names:
		var chip:=_panel(tags,RED.darkened(0.65),5)
		_label(chip,str(name),12,MUTED)
	var info:=_hbox(pv,12)
	_label(info,"体力 %d" % selected.get("staminaCost",6),14,CYAN)
	_label(info,"%d 波敌人" % selected.get("waves",[]).size(),14,MUTED)
	_label(info,"首通星尘晶 %d" % selected.get("firstClearRewards",{}).get("diamonds",0),14,GOLD)
	var actions:=_hbox(pv,8)
	var unlocked:bool=selected.get("unlocked",false)
	var done:bool=selected.get("completed",selected.get("cleared",false))
	var enter:=_button(actions,"再次挑战" if done else "开始探索",func():_begin_stage(str(selected.id)),true)
	enter.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	enter.disabled=not unlocked
	if done:_button(actions,"回顾剧情",func():_play_dialogue(str(selected.id)+"_pre",func():_play_dialogue(str(selected.id)+"_post",func():pass)))

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
	set_page_fixed(not compact)
	_page_title("星辰祈愿", "让群星回应你的呼唤")
	var pools:Dictionary=model.catalog.GachaPoolData.pools
	var switches:=_flow(main_body,10)
	for id in model.catalog.GachaPoolData.activePools:
		_button(switches,pools[id].name,func():selected_pool=str(id);_render_screen(),selected_pool==id)
	var pool:Dictionary=pools[selected_pool]
	var row:=_responsive_box(main_body,compact,16)
	row.size_flags_vertical=Control.SIZE_EXPAND_FILL
	var hero:=_scene_panel(row,"res://assets/characters/kaldi.png" if selected_pool=="limited_kaldi" else "res://assets/characters/ayla.png",280)
	hero.size_flags_vertical=Control.SIZE_EXPAND_FILL
	var panel:=_panel(row,LINE,12)
	var v:=_vbox(panel,6)
	_label(v,pool.subtitle,13,GOLD)
	_label(v,pool.name,26,TEXT)
	_label(v,"★★★★★",15,GOLD)
	var pity:Dictionary=model.state.get("pityCounters",{}).get(selected_pool,{})
	var count:int=int(pity.get("count",0))
	var info:=_vbox(_panel(v,GOLD.darkened(0.7),8),5)
	_label(info,"五星保底  %d / %d" % [count,pool.pity.hard],18,GOLD)
	_progress(info,count,pool.pity.hard,GOLD,7)
	_label(info,"下次五星必为限定角色" if pity.get("guaranteedFeatured",false) else "每十次至少获得四星旅者",14,MUTED,true)
	var spacer:=Control.new();spacer.size_flags_vertical=Control.SIZE_EXPAND_FILL;v.add_child(spacer)
	_button(v,"概率与规则",_pool_details)
	var actions:=_responsive_box(v,compact,8)
	var balance:int=int(model.state.resources.get(pool.currency,0))
	for amount in [1,10]:
		var cost:int=int(pool.costPerPull)*amount
		var action:=_button(actions,"祈愿%d次 · %d 星尘晶" % [amount,cost],func():_pull(amount),amount==10)
		action.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		action.disabled=balance<cost

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
	set_page_fixed(not compact)
	_page_title("冒险编队","点击旅者加入或移出队伍")
	var row:=_responsive_box(main_body,compact,14)
	row.size_flags_vertical=Control.SIZE_EXPAND_FILL
	var formation_panel:=_panel(row,GOLD.darkened(0.6),10)
	formation_panel.size_flags_horizontal=Control.SIZE_FILL
	formation_panel.custom_minimum_size.x=260
	var formation:=_vbox(formation_panel,8)
	_label(formation,"当前阵容 · %d / 3" % draft_team.size(),19,GOLD)
	var seats:=_scroll_column(formation,8)
	for i in range(3):
		var cell:=_panel(seats,LINE,7)
		var cv:=_hbox(cell,10)
		if i<draft_team.size():
			var id:String=draft_team[i]
			var art:=_portrait(cv,id,73);art.custom_minimum_size.x=60
			var labels:=_vbox(cv,4);labels.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			_label(labels,_char_name(id),16,TEXT,true)
			_label(labels,"等级 %d" % model.state.ownedCharacters.get(id,{}).get("level",1),13,MUTED)
			_bind_card_tap(cell,func():_toggle_team(id));_ignore_children(cv)
		else:
			cell.custom_minimum_size.y=80
			_center_label(cv,"待命席位 %d" % (i+1),16,MUTED)
	var run_locked:bool=model.abyss_run_active()
	var save_team:=_button(formation,"保存出战队伍",func():
		if _check(model.set_team(draft_team)):_toast("出战队伍已保存",CYAN);_render_screen(),true)
	save_team.disabled=run_locked
	if run_locked:_label(formation,"远征结束后可调整阵容",12,CYAN,true)
	var roster:=_vbox(row,8);roster.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var filters:=_flow(roster,8)
	for el in ["全部","fire","water","wind","thunder"]:
		_button(filters,_element_name(el),func():character_filter=el;_render_screen(),character_filter==el)
	_label(filters,"已拥有 %d / %d" % [model.state.ownedCharacters.size(),model.catalog.CharacterData.size()],12,MUTED)
	var listing:=_scroll_column(roster,8)
	listing.get_parent().name="PartyRosterScroll"
	var grid:=_grid(listing,2 if compact else (3 if content_width()<1050 else 4))
	if compact: listing.get_parent().custom_minimum_size.y=520
	for id in model.catalog.CharacterData:
		var data:Dictionary=model.catalog.CharacterData[id]
		if character_filter!="全部" and data.element!=character_filter:continue
		var v:=_vbox(grid,5);v.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		var card:=_character_card(v,id,110,func():_toggle_team(id))
		card.name="PartyCard_"+str(id)
		if id in draft_team:card.add_theme_stylebox_override("panel",_box(Color("173039"),CYAN,8))
		var owned:bool=model.state.ownedCharacters.has(id)
		var actions:=_hbox(v,5)
		var b:=_button(actions,"移出" if id in draft_team else ("加入" if owned else "未获得"),func():_toggle_team(id),id in draft_team)
		b.size_flags_horizontal=Control.SIZE_EXPAND_FILL;b.disabled=not owned or run_locked
		_button(actions,"详情",func():selected_character=id;navigate("growth"))

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
	set_page_fixed(not compact)
	_page_title("角色养成","选择旅者，点亮新的星座")
	var row:=_responsive_box(main_body,compact,14)
	row.size_flags_vertical=Control.SIZE_EXPAND_FILL
	var roster_panel:=_panel(row,LINE,8)
	roster_panel.size_flags_horizontal=Control.SIZE_FILL
	roster_panel.custom_minimum_size.x=165
	var roster:=_scroll_column(roster_panel,6)
	for id in model.catalog.CharacterData:
		var b:=_button(roster,_char_name(str(id)),func():selected_character=str(id);_render_screen(),selected_character==str(id))
		b.custom_minimum_size.x=145
	var data:Dictionary=model.catalog.CharacterData.get(selected_character,{})
	if data.is_empty():return
	var owned:bool=model.state.ownedCharacters.has(selected_character)
	var progress:Dictionary=model.state.ownedCharacters.get(selected_character,{})
	var profile:=_panel(row,_rarity_color(int(data.rarity)).darkened(0.5),12)
	profile.size_flags_stretch_ratio=0.8
	var pv:=_vbox(profile,6)
	var art:=_portrait(pv,selected_character,150)
	art.size_flags_vertical=Control.SIZE_EXPAND_FILL
	_center_label(pv,str(data.name),24,TEXT)
	_center_label(pv,"★".repeat(int(data.rarity)),16,_rarity_color(int(data.rarity)))
	_center_label(pv,str(data.get("title","")),13,MUTED)
	_center_label(pv,_element_name(str(data.element))+" · "+str(model.catalog.RoleNames.get(data.role,data.role)),14,CYAN)
	var details:=_vbox(row,8)
	details.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	details.size_flags_stretch_ratio=1.55
	var tabs:=_hbox(details,5)
	for tab in [["stats","属性"],["skills","技能"],["constellation","命座"],["gear","遗物"]]:
		var b:=_button(tabs,tab[1],func():growth_panel=tab[0];_render_screen(),growth_panel==tab[0]);b.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var panel:=_panel(details,LINE,12)
	panel.size_flags_vertical=Control.SIZE_EXPAND_FILL
	var body:=_scroll_column(panel,10)
	match growth_panel:
		"stats":
			_label(body,"等级 %d / 10" % progress.get("level",1) if owned else "旅者档案 · 尚未获得",23,GOLD)
			if owned:
				var needed:int=model.exp_to_next_level(int(progress.get("level",1)))
				_progress(body,progress.get("exp",0),maxi(1,needed),CYAN,7)
				_label(body,"经验 %d / %d" % [progress.get("exp",0),needed] if needed>0 else "已达最高等级",12,MUTED)
			var stats:Dictionary=model.computed_stats(selected_character) if owned else data.baseStats
			var grid:=_grid(body,3)
			for attribute in [["生命","hp"],["攻击","atk"],["防御","def"],["速度","spd"],["暴击率","cri"],["暴击伤害","criDmg"]]:
				var cell:=_panel(grid,LINE,8);var cv:=_vbox(cell,3)
				_label(cv,attribute[0],12,MUTED)
				var value:float=float(stats.get(attribute[1],0))
				_label(cv,"%.1f%%" % (value*100) if attribute[1] in ["cri","criDmg"] else str(int(value)),21,TEXT)
			var passive:=_panel(body,CYAN.darkened(0.6),10);var passbody:=_vbox(passive,4)
			_label(passbody,"天赋被动",14,CYAN)
			_label(passbody,str(data.get("passiveDesc","")),14,TEXT,true)
			_label(body,str(data.get("description","")),14,MUTED,true)
		"skills":
			for sid in data.skills:
				var skill:Dictionary=model.catalog.SkillData[sid]
				var cell:=_panel(body,_element_color(data.element).darkened(0.5),10);var cv:=_vbox(cell,5)
				var heading:=_hbox(cv,8)
				_label(heading,skill.name,20,TEXT)
				_label(heading,{"normal":"普通攻击","skill":"战技","ultimate":"终结技"}.get(skill.type,"技能"),12,CYAN)
				_label(cv,skill.description,14,MUTED,true)
				_label(cv,"冷却 %d 回合 · %s" % [skill.get("cooldown",0),"消耗 %d 能量" % skill.get("energyCost",100) if skill.type=="ultimate" else "获得 %d 能量" % skill.get("energyGain",0)],12,GOLD)
		"constellation":
			var current:int=int(progress.get("constellation",progress.get("awakening",0)))
			_label(body,"命座 %d / 6 · 碎片 %d" % [current,progress.get("shards",0)],18,GOLD)
			var infos:Array=model.constellation_info(selected_character)
			for i in range(6):
				var info:Dictionary=infos[i] if i<infos.size() else {}
				var cell:=_panel(body,GOLD.darkened(0.4) if i<current else LINE,10);var cv:=_vbox(cell,5)
				_label(cv,"%02d  %s" % [i+1,info.get("label",info.get("name","命座"))],18,GOLD if i<current else TEXT)
				_label(cv,info.get("desc",info.get("description","")),14,MUTED,true)
				if i==current and owned:
					_button(cv,"解锁 · %d 碎片" % info.get("cost",model.catalog.ConstellationCost[str(int(data.rarity))][i]),func():
						if _check(model.unlock_constellation(selected_character)):_toast("命座已点亮",GOLD);_render_screen(),true)
				elif i<current:_label(cv,"已点亮",12,GOLD)
		"gear":
			for slot in model.catalog.RelicSlots:
				var cell:=_panel(body,LINE,10);var line:=_hbox(cell,10)
				var cv:=_vbox(line,3);cv.size_flags_horizontal=Control.SIZE_EXPAND_FILL
				_label(cv,slot.name,17,GOLD)
				var uid=progress.get("equippedRelics",{}).get(slot.id,null)
				var relic:=_find_relic(str(uid))
				_label(cv,("+%d · %s" % [relic.get("level",0),_relic_main(relic)]) if not relic.is_empty() else "空置",14,MUTED,true)
				if not relic.is_empty():_button(line,"卸下",func():_check(model.unequip_relic(selected_character,slot.id));_render_screen())
				else:_button(line,"选择遗物",func():navigate("relics"))
	var footer:=_hbox(details,8)
	if owned:
		var train:=_button(footer,"训练一次 · 500 金币",func():
			if _check(model.train_character(selected_character)):_toast("训练完成",CYAN);_render_screen(),true)
		train.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		train.disabled=int(progress.get("level",1))>=10
		_button(footer,"冒险编队",func():navigate("party"))
	else:
		_button(footer,"前往星辰祈愿",func():navigate("summon"),true)

func _relics() -> void:
	set_page_fixed(not compact)
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
		var empty:=_vbox(_panel(main_body,LINE,20),12)
		_label(empty,"尚未获得遗物",24,GOLD)
		_label(empty,"完成章节与深渊挑战，收集旅途中的遗物。",15,MUTED,true)
		_button(empty,"开始探索",func():navigate("story"),true)
		return
	var row := _responsive_box(main_body, compact, 20)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var list_column := _scroll_column(row)
	list_column.get_parent().size_flags_stretch_ratio = 1.6
	var listing := _grid(list_column, 2 if compact else 3)
	if compact: list_column.get_parent().custom_minimum_size.y=350
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
		var card := _panel(listing, color if str(relic.uid) == selected_relic else LINE, 10)
		card.custom_minimum_size.x=150
		var v := _vbox(card, 9)
		_center_label(v, {"helmet": "◇", "chest": "⬡", "belt": "◈", "boots": "◇", "necklace": "✦"}.get(relic.slotId, "◇"), 42, color)
		_center_label(v, "%s  +%d" % [_slot_name(relic.slotId), relic.level], 18, TEXT)
		_center_label(v, "★".repeat(int(relic.rarity)), 13, color)
		_label(v, _relic_main(relic), 13, MUTED, true)
		_center_label(v, "已装备" if relic.get("equippedBy") != null else "背包", 12, CYAN if relic.get("equippedBy") != null else MUTED)
		_button(v, "查看遗物", func(): selected_relic = str(relic.uid); _save_preferences(); _render_screen(), str(relic.uid) == selected_relic)
	var selected := _find_relic(selected_relic)
	if selected.is_empty():
		return
	var detail:=_panel(row,_rarity_color(int(selected.rarity)).darkened(0.4),12)
	detail.custom_minimum_size.x=330 if not compact else 0
	if compact:detail.custom_minimum_size.y=400
	var dv:=_vbox(detail,8)
	var title:=_hbox(dv,10)
	_label(title,"%s +%d" % [_slot_name(selected.slotId),selected.level],24,TEXT)
	_label(title,"★".repeat(int(selected.rarity)),15,_rarity_color(int(selected.rarity)))
	var stats:=_scroll_column(dv,8)
	_label(stats,"主属性  "+_relic_main(selected),18,GOLD)
	for stat in selected.get("subStats",[]):
		_label(stats,"%s  +%s" % [stat.name,_stat_value(stat.stat,stat.value)],15,MUTED)
	var upgrades:=_hbox(dv,6)
	var upgrade:=_button(upgrades,"强化 +1 · %d 金币" % model.relic_upgrade_cost(int(selected.level)),func():
		if _check(model.upgrade_relic(selected_relic)):_ui_sound("equip");_render_screen(),true)
	upgrade.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	upgrade.disabled=int(selected.level)>=25
	var max_cost:int=int(model.relic_upgrade_cost_to_max(selected_relic))
	var maxup:=_button(upgrades,"升满",func():
		_confirm("强化至 +25","消耗 %d 金币" % max_cost,func():
			if _check(model.upgrade_relic_to_max(selected_relic)):_render_screen()))
	maxup.disabled=int(selected.level)>=25
	var actions:=_hbox(dv,6)
	_button(actions,"装备给角色",func():_equip_dialog(selected_relic)).size_flags_horizontal=Control.SIZE_EXPAND_FILL
	if selected.get("equippedBy")!=null:
		_button(actions,"卸下",func():_check(model.unequip_relic(selected.equippedBy,selected.slotId));_render_screen())
	else:
		_button(actions,"出售",func():
			_confirm("出售遗物？","出售后获得金币。",func():
				if _check(model.sell_relic(selected_relic)):
					selected_relic="";_ui_sound("coin");_render_screen()))

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
	set_page_fixed(not compact)
	_page_title("补给商店", "整备物资，再次出发")
	var row:=_responsive_box(main_body,compact,14)
	row.size_flags_vertical=Control.SIZE_EXPAND_FILL
	for category in ["item","recharge"]:
		var column:=_vbox(_panel(row,LINE,12),10)
		_label(column,"旅途补给" if category=="item" else "免费体验礼包",22,GOLD)
		var list:=_scroll_column(column,10)
		if compact:list.get_parent().custom_minimum_size.y=380
		var entries=model.catalog.ShopData.itemShop if category=="item" else model.catalog.ShopData.rechargeItems
		for item in entries:
			var card:=_vbox(_panel(list,LINE,12),8)
			_label(card,item.name,20,TEXT)
			_label(card,_reward_text(item.rewards),14,MUTED,true)
			var action:=_button(card,"%d 金币 · 兑换" % item.price if category=="item" else "免费领取",func():
				if _check(model.purchase(category,item.id)):
					_ui_sound("coin");_toast("补给已发放",GOLD);_render_screen(),true)
			action.size_flags_horizontal=Control.SIZE_EXPAND_FILL

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
	_label(v, "备份进度，或从文件恢复。导入会替换所选档案。", 16, MUTED, true)
	var row := _flow(v, 14)
	_button(row, "导出当前档案", _export_dialog, true)
	_button(row, "导入存档文件", _import_dialog)
	_button(row, "立即保存", func(): _toast("旅程已保存" if model.save_game() else "保存失败，请检查目录权限", CYAN))

	_update_panel()

func _show_updates() -> void:
	navigate("save")
	await get_tree().process_frame
	await get_tree().process_frame
	if current_screen == "save":
		var panel := main_body.get_node_or_null("UpdatePanel")
		if panel != null:
			(main_body.get_parent() as ScrollContainer).scroll_vertical = int(panel.position.y)

func _update_panel() -> void:
	var panel := _panel(main_body, LINE, 24)
	panel.name = "UpdatePanel"
	var content := _vbox(panel, 14)
	_label(content, "版本与更新", 24, TEXT)
	var local: Dictionary = updater.local_version
	_label(content, "当前版本 %s · 构建 %s" % [str(local.get("version_name", "未知")), str(local.get("version_code", "未知"))], 16, MUTED, true)
	_label(content, "启动后检查正式版本，Android 可在 Wi-Fi 下自动下载并校验更新。下载完成后点击安装，由系统确认覆盖升级，保留本机存档。首次从旧测试包迁移时请先导出存档。", 14, MUTED, true)
	var auto_check := CheckBox.new()
	auto_check.name = "AutoCheckUpdates"
	auto_check.text = "启动时自动检查更新"
	auto_check.custom_minimum_size.y = 48
	auto_check.button_pressed = updater.auto_check_enabled
	content.add_child(auto_check)
	auto_check.toggled.connect(func(enabled: bool):
		updater.auto_check_enabled = enabled
		_save_preferences())
	var auto_download := CheckBox.new()
	auto_download.name = "AutoDownloadUpdates"
	auto_download.text = "Wi-Fi 下自动下载更新（Android）"
	auto_download.custom_minimum_size.y = 48
	auto_download.button_pressed = updater.auto_download_enabled
	content.add_child(auto_download)
	auto_download.toggled.connect(func(enabled: bool):
		updater.auto_download_enabled = enabled
		_save_preferences())
	var status: Dictionary = updater.state
	_label(content, str(status.get("message", "尚未检查更新")), 16, GOLD if status.get("status") == "available" else TEXT, true).name = "UpdateStatus"
	var actions := _responsive_box(content, compact, 10)
	var check_button := _button(actions, "检查更新", updater.check_for_updates, true)
	check_button.name = "CheckForUpdates"
	check_button.disabled = updater.busy or not updater.android_updater.record.is_empty()
	_button(actions, "GitHub 发布页", func():
		if updater.open_releases() != OK:
			_toast("无法打开浏览器，请稍后重试。", RED)).name = "OpenReleases"
	if status.get("status") == "available":
		_button(content, "下载更新" if OS.has_feature("android") else "在浏览器下载 APK", func():
			if updater.open_download() != OK:
				_toast("下载暂未开始，请查看更新状态或发布页。", RED), true).name = "DownloadUpdate"
		# Untrusted release prose is plain Label text, never rich text or code.
		_label(content, "发布说明", 18, GOLD)
		_label(content, str(status.get("release_notes", "")), 15, MUTED, true).name = "UpdateReleaseNotes"

	if status.get("status") == "downloading":
		_progress(content, float(status.get("progress", 0)) * 100.0, 100.0, CYAN, 10)
		_button(content, "取消下载", updater.cancel_download).name = "CancelUpdateDownload"
	elif status.get("status") in ["downloaded", "install_permission", "installing"]:
		_button(content, "安装更新 · 保留存档", func():
			var result: Error = updater.install_update()
			if result != OK and result != ERR_UNAUTHORIZED:
				_toast("暂时无法启动系统安装，请查看更新状态。", RED), true).name = "InstallUpdate"
		if status.get("status") == "install_permission":
			_button(content, "打开 Android 安装授权设置", func(): updater.open_install_settings()).name = "AllowUpdateInstall"
	elif status.get("status") == "download_error":
		_button(content, "清除失败下载并重新检查", func(): updater.cancel_download(); updater.check_for_updates()).name = "RetryUpdateDownload"

func _refresh_update_notice() -> void:
	if is_instance_valid(update_notice):
		update_notice.visible = updater.state.get("status") in ["available", "downloading", "downloaded", "install_permission", "installing", "download_error"] and current_screen != "battle" and current_screen != "save"
		update_notice.text = {"available":"有更新","downloading":"下载中","downloaded":"安装更新","install_permission":"安装更新","installing":"安装中","download_error":"重试更新"}.get(str(updater.state.get("status","")),"检查更新")
		update_notice.tooltip_text = str(updater.state.get("message", "发现新版本"))

func _on_update_state_changed(_state: Dictionary) -> void:
	_refresh_update_notice()
	if _ready_done and current_screen == "save" and overlay.get_child_count() == 0:
		_render_screen()

func _export_dialog(slot: int = -1) -> void:
	if slot == -1: slot = model.active_slot
	var d := FileDialog.new()
	d.use_native_dialog = OS.has_feature("android")
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
	d.use_native_dialog = OS.has_feature("android")
	d.title = "导入旅程档案"
	d.access = FileDialog.ACCESS_FILESYSTEM
	d.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	d.filters = PackedStringArray(["*.json ; 旅程存档"])
	d.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	add_child(d)
	d.file_selected.connect(func(path):
		d.queue_free()
		_confirm("导入并替换所选档案？", "替换档案 %d？当前版本备份会保留进行中的行动。\n%s" % [slot, path.get_file()], func():
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
	if config.get("isExtraction", false):
		var started: Dictionary = model.extraction.start_battle(battle)
		if not _check(started):
			battle_settled = true
			return
	else:
		battle.start(config, model.battle_party(is_abyss), model.rogue_effects() if is_abyss else [])
	current_screen = "battle"
	_render_screen()
	_show_combat_events(battle.state.get("events", []))

func _render_battle() -> void:
	_clear(main_body)
	set_page_fixed(true)
	unit_cards.clear()
	var state: Dictionary = battle.state
	if state.is_empty(): return
	var head := _hbox(main_body, 10)
	var names := _vbox(head, 1)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(names, str(battle_config.get("name", "裂隙战斗")), 21, TEXT)
	var caption := "第 %d 回合 · 第 %d 波" % [state.get("turn",1), state.get("wave",1)]
	if battle_config.get("isExtraction", false): caption += " · 封锁剩余 %d 回合" % maxi(0, 41-int(state.get("turn",1)))
	_label(names, caption, 11, GOLD)
	_button(head, "自动" if battle_auto else "手动", func(): battle_auto = not battle_auto; abyss_auto_continue = abyss_auto_continue and battle_auto; _render_battle(), battle_auto)
	_button(head, "%d 倍速" % battle_speed, func(): battle_speed = 2.0 if battle_speed == 1.0 else (4.0 if battle_speed == 2.0 else 1.0); _render_battle())
	_button(head, "记录", _show_battle_log)
	if battle_config.get("isAbyss", false): _button(head, "回响", _show_battle_echoes)
	_button(head, "撤退", func(): navigate(_battle_return_screen()))
	_button(head,"菜单",_show_navigation)
	var active: Dictionary = battle.current_actor()
	var active_uid: String = active.get("uid", "")
	if state.phase == "player_turn" and not active.is_empty():
		var available: Array = battle.available_actions()
		if selected_skill not in available: selected_skill = str(available[0]) if not available.is_empty() else ""
		var legal: Array = battle.legal_targets(selected_skill) if selected_skill != "" else []
		if selected_target not in legal: selected_target = str(legal[0]) if not legal.is_empty() else ""
	var order := _hbox(main_body, 5)
	_label(order, "行动", 10, MUTED)
	for uid in state.get("turnOrder", []):
		var unit := _battle_unit(str(uid))
		if unit.is_empty() or float(unit.get("currentHp",0)) <= 0: continue
		var chip := _panel(order, GOLD if uid == active_uid else LINE, 2)
		chip.size_flags_horizontal=Control.SIZE_FILL
		chip.tooltip_text=str(unit.name)
		var avatar:=_portrait(chip,str(unit.id),24)
		avatar.custom_minimum_size.x=32
	var arena := _panel(main_body, Color(0,0,0,0), 8)
	arena.add_theme_stylebox_override("panel", _box(Color(0.035,0.055,0.09,0.12),Color(0,0,0,0),8))
	arena.name = "BattleArena"
	arena.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var field := _hbox(arena, 14)
	for side in ["allies", "enemies"]:
		var group := _vbox(field, 4)
		group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		group.size_flags_stretch_ratio = 1.0
		var grid := _hbox(group, 8)
		grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
		for unit in state.get(side, []): _battle_unit_card(grid, unit, active_uid)
		if side == "allies":
			var divider := VSeparator.new()
			divider.modulate = GOLD.darkened(0.5)
			field.add_child(divider)
	var controls := _panel(main_body, CYAN.darkened(0.65), 8)
	controls.name = "BattleActions"
	if state.phase == "player_turn" and not active.is_empty():
		var available: Array = battle.available_actions()
		var cv := _vbox(controls, 5)
		var upper := _hbox(cv, 12)
		var actor_label := _label(upper, str(active.name), 14, CYAN)
		actor_label.custom_minimum_size.x = 125
		var skills := _hbox(upper, 8)
		skills.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for sid in active.get("skills", []):
			var skill: Dictionary = model.catalog.SkillData.get(sid, {})
			var cd: int = int(active.get("cooldowns", {}).get(sid,0))
			var cost: int = int(skill.get("energyCost",0))
			var b := _button(skills, "", func(): selected_skill = str(sid); selected_target = ""; _render_battle(), selected_skill == sid)
			b.name = "BattleSkill_"+str(sid)
			b.custom_minimum_size=Vector2(160,60)
			b.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			b.disabled=sid not in available or battle_auto
			b.tooltip_text=str(skill.get("description",""))
			var inner:=_hbox(b,7)
			inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			inner.offset_left=9;inner.offset_right=-9;inner.offset_top=6;inner.offset_bottom=-6
			var icon:=TextureRect.new()
			icon.texture=load("res://assets/ui/skill_"+str(skill.get("type","normal"))+".svg")
			icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.custom_minimum_size=Vector2(34,34)
			inner.add_child(icon)
			var copy:=_vbox(inner,1);copy.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			_label(copy,str(skill.get("name",sid)),15,INK if selected_skill==sid else TEXT,true)
			_label(copy,"冷却 %d" % cd if cd>0 else ("%d 能量" % cost if cost>0 else "普攻" if skill.get("type","")=="normal" else "战技"),11,INK.lightened(.25) if selected_skill==sid else GOLD)
			_ignore_children(inner)
			if b.disabled:inner.modulate.a=.45
		var chosen: Dictionary = model.catalog.SkillData.get(selected_skill,{})
		var cast := _button(upper, "施放", func(): _do_battle_action(selected_skill,selected_target), true)
		cast.custom_minimum_size.x = 110
		cast.name = "CastSkill"
		cast.disabled = battle_auto or selected_skill == "" or selected_target == ""
		var lower := _hbox(cv,12)
		var description := _label(lower,str(chosen.get("description","选择技能")),14,MUTED,true)
		description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		description.max_lines_visible = 2
		_label(lower,"目标 · "+str(_battle_unit(selected_target).get("name","点击选择")),12,GOLD)
	else:
		_center_label(controls,"敌方正在行动…" if state.phase == "enemy_turn" else "战斗结算中…",18,MUTED)

func _show_battle_log() -> void:
	var box := _modal("战斗记录",760,440)
	for entry in battle_log:
		_label(box,str(entry),14,MUTED,true)
	if battle_log.is_empty(): _label(box,"战斗即将开始",16,MUTED)
	_button(_modal_footer(box),"返回战场",_clear_overlay,true)

func _battle_unit_card(parent: Node, unit: Dictionary, active_uid: String) -> void:
	var alive: bool = float(unit.get("currentHp",0)) > 0
	var ally: bool = unit.get("isAlly",true)
	var color := _element_color(unit.get("element","fire"))
	var selected: bool = str(unit.uid) == selected_target
	var p := _panel(parent,GOLD if selected else (CYAN if unit.uid == active_uid else LINE),7)
	p.name = "Unit_"+str(unit.uid)
	p.add_theme_stylebox_override("panel",_box(Color(0,0,0,0),Color(0,0,0,0),7))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.custom_minimum_size.x = 115
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	_bind_card_tap(p,func():
		if battle.state.phase == "player_turn" and str(unit.uid) in battle.legal_targets(selected_skill):
			selected_target = str(unit.uid)
			_render_battle())
	unit_cards[unit.uid] = p
	var v := _vbox(p,3)
	var badge := _hbox(v,4)
	var name_label := _label(badge,str(unit.name),14,TEXT,true)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.max_lines_visible = 1
	_label(badge,_element_name(unit.get("element","")),10,color)
	var art := _portrait(v,unit.id,150,false,not ally)
	var ground=load("res://scripts/ui/unit_ground.gd").new()
	ground.accent=GOLD if selected else CYAN
	ground.selected=selected;ground.active=unit.uid==active_uid
	ground.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.add_child(ground);art.move_child(ground,0)
	art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_progress(v,unit.get("currentHp",0),maxi(1,int(unit.get("maxHp",1))),CYAN if ally else RED,7)
	_center_label(v,"%d / %d" % [unit.get("currentHp",0),unit.get("maxHp",1)],14,MUTED)
	if ally:
		_progress(v,unit.get("energy",0),unit.get("maxEnergy",100),GOLD,3)
	var statuses: Array = []
	if float(unit.get("shield",0)) > 0: statuses.append("盾 %d" % int(unit.shield))
	for status in unit.get("statuses",[]): statuses.append(str(STATUS_NAMES.get(status.get("id",""),status.get("id",""))))
	var status_text := " · ".join(statuses) if not statuses.is_empty() else ("行动中" if unit.uid == active_uid else ("选中目标" if selected else ""))
	var status_label := _center_label(v,status_text,10,color)
	status_label.max_lines_visible = 1
	p.tooltip_text = "\n".join(statuses)
	_ignore_children(v)
	var info:=_button(art,"i",func():_show_unit_details(unit))
	info.mouse_filter=Control.MOUSE_FILTER_STOP
	info.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	info.offset_left=-44;info.offset_right=0;info.offset_top=0;info.offset_bottom=44
	info.add_theme_stylebox_override("normal",_box(Color(0.02,0.04,0.08,0.45),Color(LINE,0.4),3))
	if not alive: p.modulate = Color(0.5,0.5,0.55,0.55)

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
			var source_unit := _battle_unit(str(e.get("actor", "")))
			var source_card = unit_cards.get(str(e.get("actor", "")))
			var destination_card = unit_cards.get(str(e.get("target", "")))
			var origin: Vector2 = source_card.get_global_rect().get_center() if is_instance_valid(source_card) else size * Vector2(0.25,0.5)
			var destination: Vector2 = destination_card.get_global_rect().get_center() if is_instance_valid(destination_card) else size * Vector2(0.75,0.5)
			fx.ultimate(str(source_unit.get("id","")),str(e.get("element","fire")),origin,destination)
		var target = unit_cards.get(str(e.get("target", "")))
		var actor = unit_cards.get(str(e.get("actor", "")))
		if not is_instance_valid(target):
			continue
		var pos: Vector2 = target.global_position + target.size * Vector2(0.5, 0.42)
		var type: String = e.get("type", "")
		var color := CYAN if type == "heal" else (GOLD if e.get("isCrit", false) else RED)
		if type == "heal": fx.heal_ring(pos)
		if type == "shield": fx.shield_ring(pos)
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
				if not extraction_reduced_motion and not actor.has_meta("lunging"):
					actor.set_meta("lunging",true)
					var home:Vector2=actor.position
					var lunge:Tween=actor.create_tween()
					lunge.tween_property(actor,"position",home+Vector2(14 if pos.x>actor.global_position.x else -14,0),0.07)
					lunge.tween_property(actor,"position",home,0.17).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
					lunge.tween_callback(func():if is_instance_valid(actor):actor.remove_meta("lunging"))
			var original: Color = target.modulate
			if type == "damage" and not extraction_reduced_motion:
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
	if battle_config.get("isExtraction", false):
		var extraction_box := _modal("遭遇胜利" if victory else "远征失利", 680, 420)
		if not victory and not str(battle.state.get("reason", "")).is_empty():
			_center_label(extraction_box, str(battle.state.reason), 22, RED)
		_center_label(extraction_box, "继续搜索，或在首领出口安全撤离" if victory else "本局物资遗失，旅者与仓库安然无恙", 22, GOLD if victory else RED)
		_label(extraction_box, "战利品仍在局内，成功撤离后才进入仓库。" if victory else "可免费重新出发，调整路线与补给后再战。", 16, MUTED, true)
		_button(extraction_box, "返回搜打撤", func(): navigate("extraction"), true)
		return
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
	art.texture = load(_background_path())
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
	style.set_corner_radius_all(6)
	style.shadow_color = Color(0, 0, 0, 0.18)
	style.shadow_size = 3
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
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(l)
	return l

func _center_label(parent: Node, text: String, font_size: int = 17, color: Color = TEXT) -> Label:
	var l := _label(parent, text, font_size, color, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

func _end_ui_input_dispatch() -> void:
	_ui_input_dispatch = false

func _dispatch_ui_action(source: Control, action: Callable) -> void:
	if _touch_dragging: return
	if source.get_meta("ui_action_pending", false):
		return
	if not _ui_input_dispatch:
		action.call()
		return
	# One pending action per control also protects purchases from duplicate
	# release events before the deferred action has had a chance to run.
	source.set_meta("ui_action_pending", true)
	_complete_ui_action.call_deferred(weakref(source), action)

func _complete_ui_action(source_ref: WeakRef, action: Callable) -> void:
	var source = source_ref.get_ref()
	if not is_instance_valid(source) or not source.is_inside_tree() or source.is_queued_for_deletion():
		return
	if action.is_valid():
		action.call()
	if is_instance_valid(source):
		source.remove_meta("ui_action_pending")

func _button(parent: Node, text: String, action: Callable, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = 44
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
	for state_name in ["normal","hover","pressed","focus","disabled"]:
		var style:StyleBoxFlat=b.get_theme_stylebox(state_name).duplicate()
		style.content_margin_top=8
		style.content_margin_bottom=8
		b.add_theme_stylebox_override(state_name,style)
	if action.is_valid():
		b.pressed.connect(func():
			if not _touch_dragging: _ui_sound("back" if "返回" in text else "tap")
			_dispatch_ui_action(b, action))
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
	var row := _hbox(main_body, 14)
	_label(row, title, 24, TEXT)
	var hint := _label(row, subtitle, 12, MUTED, true)
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER

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
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED if path.contains("/characters/") else TextureRect.STRETCH_KEEP_ASPECT_COVERED
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
	var path := ("res://assets/enemies/%s.png" if enemy else "res://assets/characters/%s.png") % id
	if id=="kaldi" and not enemy and ResourceLoader.exists("res://assets/characters/kaldi-battle.png"):
		path="res://assets/characters/kaldi-battle.png"
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
	p.custom_minimum_size.x = 160
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
					_dispatch_ui_action(card, action)
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
	_extraction_stop_search_audio()
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
	updater.auto_check_enabled = bool(config.get_value("updates", "auto_check", true))
	updater.auto_download_enabled = bool(config.get_value("updates", "auto_download", true))
	relic_filter = str(config.get_value("relics", "rarity_filter", "全部"))
	relic_slot_filter = str(config.get_value("relics", "slot_filter", "全部"))
	selected_relic = str(config.get_value("relics", "selection", ""))
	music_volume_db = clampf(float(config.get_value("audio","music_volume_db",-8.0)),-48.0,0.0)
	effects_volume_db = clampf(float(config.get_value("audio","effects_volume_db",-10.0)),-40.0,0.0)
	music_enabled = bool(config.get_value("audio", "music", true))
	sound_enabled = bool(config.get_value("audio", "sound", true))
	extraction_sound = bool(config.get_value("extraction", "sound", true))
	extraction_reduced_motion = bool(config.get_value("extraction", "reduced_motion", false))
	extraction_auto_pick = bool(config.get_value("extraction", "auto_pick", true))
	for key in salvage_options:
		salvage_options[key] = bool(config.get_value("salvage", key, false))

func _save_preferences() -> void:
	if test_session: return
	var config := ConfigFile.new()
	config.set_value("updates", "auto_check", updater.auto_check_enabled)
	config.set_value("updates", "auto_download", updater.auto_download_enabled)
	config.set_value("relics", "rarity_filter", relic_filter)
	config.set_value("relics", "slot_filter", relic_slot_filter)
	config.set_value("relics", "selection", selected_relic)
	config.set_value("audio","music_volume_db",music_volume_db)
	config.set_value("audio","effects_volume_db",effects_volume_db)
	config.set_value("audio", "music", music_enabled)
	config.set_value("audio", "sound", sound_enabled)
	config.set_value("extraction", "sound", extraction_sound)
	config.set_value("extraction", "reduced_motion", extraction_reduced_motion)
	config.set_value("extraction", "auto_pick", extraction_auto_pick)
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

func _battle_return_screen() -> String:
	if battle_config.get("isExtraction", false): return "extraction"
	return "abyss" if battle_config.get("isAbyss", false) else "story"

func _extraction_operation(result: Dictionary, message: String = "") -> void:
	if not _check(result): return
	extraction_selected = ""
	if not message.is_empty(): _toast(message, CYAN)
	_render_screen()

func _begin_extraction_battle() -> void:
	var prepared: Dictionary = model.extraction.prepare_battle()
	if _check(prepared): _start_battle(prepared.config)

func _extraction_play(clip: String) -> void:
	if not extraction_sound or not sound_enabled: return
	if clip == "search": return

	var path := "res://assets/audio/extraction/" + clip + ".mp3"
	if not ResourceLoader.exists(path): return
	var priority:int={"common":0,"purple":1,"gold":2,"red":3}.get(clip,0)
	var voices:=get_tree().get_nodes_in_group("transient_audio")
	for playing in voices:
		if priority==0 and playing.playing and int(playing.get_meta("priority",0))>=2:return
	if voices.size()>=3:
		voices.sort_custom(func(a,b):return int(a.get_meta("priority",0))<int(b.get_meta("priority",0)))
		if int(voices[0].get_meta("priority",0))>priority:return
		voices[0].stop();voices[0].stream=null;voices[0].remove_from_group("transient_audio");voices[0].queue_free()
	var voice := AudioStreamPlayer.new()
	voice.add_to_group("transient_audio")
	voice.set_meta("priority",priority)
	voice.volume_db = effects_volume_db
	voice.stream = load(path)
	voice.finished.connect(voice.queue_free)
	add_child(voice)
	voice.play()
	if is_instance_valid(music_audio) and music_audio.playing:
		var old_duck=music_audio.get_meta("duck_tween") if music_audio.has_meta("duck_tween") else null
		if old_duck is Tween and old_duck.is_valid():old_duck.kill()
		var duck:=music_audio.create_tween()
		music_audio.set_meta("duck_tween",duck)
		duck.tween_property(music_audio,"volume_db",music_volume_db-6,0.08)
		duck.tween_interval(0.35)
		duck.tween_property(music_audio,"volume_db",music_volume_db,0.5)

func _extraction_stop_search_audio() -> void:
	if is_instance_valid(extraction_search_audio): extraction_search_audio.stop()
	if is_instance_valid(music_audio): music_audio.volume_db = music_volume_db-2.0 if current_screen == "battle" else music_volume_db


func content_height() -> float:
	return maxf(240.0, _usable_rect().size.y - (20.0 if current_screen=="battle" else (126.0 if compact else 72.0)))

func content_width() -> float:
	return maxf(300.0, _usable_rect().size.x - (206.0 if size.x >= 1500 else 24.0))

func set_page_fixed(fixed: bool) -> void:
	_page_fixed = fixed
	if not is_instance_valid(page_scroll): return
	page_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED if fixed else ScrollContainer.SCROLL_MODE_AUTO
	main_body.size_flags_vertical = Control.SIZE_EXPAND_FILL if fixed else Control.SIZE_FILL
	if fixed: page_scroll.scroll_vertical = 0

func _sync_music() -> void:
	var track := "determined_pursuit" if current_screen == "battle" else ("sunset_walk" if current_screen in ["extraction","abyss","story"] else "medieval_exploration")
	if not music_enabled:
		for player in get_children():
			if player is AudioStreamPlayer and player.has_meta("track"):player.stop()
		return
	if is_instance_valid(music_audio) and music_audio.get_meta("track", "") == track:
		if not music_audio.playing: music_audio.play()
		return
	var path := "res://assets/audio/music/licensed/" + track + ".ogg"
	if not ResourceLoader.exists(path): return
	var old := music_audio
	music_audio = AudioStreamPlayer.new()
	music_audio.set_meta("track",track)
	var stream: AudioStreamOggVorbis = load(path).duplicate()
	stream.loop = true
	music_audio.stream = stream
	music_audio.volume_db = -48
	add_child(music_audio)
	music_audio.play()
	music_audio.create_tween().tween_property(music_audio,"volume_db",music_volume_db-2.0 if current_screen == "battle" else music_volume_db,0.5)
	if is_instance_valid(old):
		var fade := old.create_tween()
		fade.tween_property(old,"volume_db",-60.0,0.5)
		fade.tween_callback(func():
			if is_instance_valid(old):
				old.stop()
				old.stream=null
				old.queue_free())

func _ui_sound(clip: String = "tap") -> void:
	if not sound_enabled or Time.get_ticks_msec()-_last_ui_sound_msec < 65: return
	_last_ui_sound_msec=Time.get_ticks_msec()
	var path := "res://assets/audio/ui/"+clip+".ogg"
	if not ResourceLoader.exists(path): return
	if not is_instance_valid(ui_audio):
		ui_audio = AudioStreamPlayer.new()
		ui_audio.volume_db = effects_volume_db-13
		add_child(ui_audio)
	ui_audio.volume_db = effects_volume_db-13
	ui_audio.stream = load(path)
	ui_audio.play()

func _show_audio_settings() -> void:
	var content := _modal("声音与动画",600,460)
	for setting in [["music","背景音乐",music_enabled],["sound","音效",sound_enabled],["loot","物品揭晓音",extraction_sound],["motion","减弱动画",extraction_reduced_motion]]:
		var check := CheckButton.new()
		check.text = str(setting[1])
		check.button_pressed = bool(setting[2])
		check.custom_minimum_size.y = 44
		content.add_child(check)
		check.toggled.connect(func(enabled):
			match str(setting[0]):
				"music": music_enabled = enabled; _sync_music()
				"sound":
					sound_enabled = enabled
					if not enabled:
						_stop_reveal_voices()
						if is_instance_valid(ui_audio):ui_audio.stop()
				"loot":
					extraction_sound = enabled; _extraction_stop_search_audio()
					if not enabled:_stop_reveal_voices()
				"motion": extraction_reduced_motion = enabled; fx.reduced_motion = enabled
			_save_preferences())
	for setting in [["music","音乐音量",music_volume_db,-48.0,0.0],["effects","音效音量",effects_volume_db,-40.0,0.0]]:
		var row:=_hbox(content,12)
		_label(row,str(setting[1]),14,MUTED)
		var slider:=HSlider.new()
		slider.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		slider.custom_minimum_size=Vector2(200,44)
		slider.min_value=setting[3];slider.max_value=setting[4];slider.value=setting[2]
		row.add_child(slider)
		slider.value_changed.connect(func(value):
			if str(setting[0])=="music":
				music_volume_db=value
				if is_instance_valid(music_audio):
					var duck=music_audio.get_meta("duck_tween") if music_audio.has_meta("duck_tween") else null
					if duck is Tween and duck.is_valid():duck.kill()
					music_audio.volume_db=value
			else:effects_volume_db=value
			_save_preferences())
	_button(content,"音乐鸣谢",_show_music_credits)
	_button(_modal_footer(content),"完成",_clear_overlay,true)

func _scroll_column(parent: Node, gap: int = 10) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var content:=_vbox(scroll,gap)
	content.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	return content

func _show_unit_details(unit: Dictionary) -> void:
	var box:=_modal(str(unit.get("name","旅者")),620,420)
	var stats:=_grid(box,3)
	for value in [["生命","%d / %d" % [unit.get("currentHp",0),unit.get("maxHp",0)]],["攻击",unit.get("atk",0)],["防御",unit.get("def",0)]]:
		var tile:=_panel(stats,LINE,10);var v:=_vbox(tile,5)
		_label(v,str(value[0]),13,MUTED)
		_label(v,str(value[1]),20,TEXT)
	if float(unit.get("shield",0))>0:_label(box,"护盾 %d" % int(unit.shield),15,CYAN)
	for status in unit.get("statuses",[]):
		var row:=_panel(box,LINE,10)
		_label(row,"%s · 剩余 %d 回合 · %d 层" % [STATUS_NAMES.get(status.get("id",""),status.get("id","")),int(status.get("duration",0)),int(status.get("stacks",1))],15,GOLD,true)
	if unit.get("statuses",[]).is_empty():_label(box,"当前没有持续状态",15,MUTED)
	_button(_modal_footer(box),"返回战场",_clear_overlay,true)

func _show_music_credits() -> void:
	var box:=_modal("音乐鸣谢",620,380)
	for entry in [["Medieval Exploration","RandomMind"],["Sunset Walk","KiluaBoy"],["Determined Pursuit","Emma_MA"]]:
		var card:=_vbox(_panel(box,LINE,12),4)
		_label(card,entry[0],18,GOLD)
		_label(card,entry[1]+" · CC0",14,MUTED)
	_button(_modal_footer(box),"返回",_show_audio_settings)

func _stop_reveal_voices() -> void:
	for voice in get_tree().get_nodes_in_group("transient_audio"):
		voice.stop();voice.stream=null;voice.remove_from_group("transient_audio");voice.queue_free()
