extends Control

const CharacterAvatars = preload("res://scripts/ui/character_avatar.gd")
const RuneTheme = preload("res://scripts/ui/rune_theme.gd")
const SummonSequence = preload("res://scripts/ui/summon_sequence.gd")

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
var story_list_positions: Dictionary = {}
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
var _music_pool: Dictionary = {}
var _music_context_id := "hub"
var ui_audio: AudioStreamPlayer
var music_enabled := true
var sound_enabled := true
var music_volume_db := -8.0
var effects_volume_db := -10.0
var _last_ui_sound_msec := 0
var _last_ui_sound_clip := ""
var _last_battle_sound_msec: int = -10000
var _battle_audio_history: Array = []
var battle_log: Array = []
var last_reward: Dictionary = {}
var summon_results: Array = []
var summon_index := 0
var summon_flipped := false
var summon_sequence: Control
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
	if current_screen == "battle" and not bool(get_meta("application_paused", false)) and not battle_settled and not battle.state.is_empty() and overlay.get_child_count() == 0:
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
				_cancel_scroll_child_gestures(_touch_scroll, event.index)
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

func _cancel_scroll_child_gestures(node: Node, touch_index: int) -> void:
	# Scrolling consumes subsequent drag/release events; release the original
	# child's pointer ownership immediately, without clicking or placing items.
	if node.has_method("cancel_pointer_gesture"):
		node.cancel_pointer_gesture(touch_index)
	for child in node.get_children():
		_cancel_scroll_child_gestures(child, touch_index)

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
		set_meta("application_paused",true)
		_extraction_stop_search_audio()
		if is_inside_tree():
			for voice in get_tree().get_nodes_in_group("transient_audio"):
				voice.stop();voice.queue_free()
		if is_instance_valid(ui_audio):ui_audio.stop()
		for player in get_children():
			if player is AudioStreamPlayer and player.has_meta("track"):player.stream_paused=true
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		set_meta("application_paused",false)
		for player in get_children():
			if player is AudioStreamPlayer and player.has_meta("track"):player.stream_paused=player!=music_audio or not music_enabled
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
		if current_screen == "extraction" and ExtractionView.handle_modal_back(self):
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
	var menu := _modal("前往", 600, 500)
	var icons := {"home":"camp","story":"map","summon":"star","party":"party","growth":"upgrade","relics":"gear","abyss":"void","extraction":"bag","shop":"coin","save":"book"}
	for section in [["探索与冒险",["home","story","summon","abyss","extraction"]],["旅者整备",["party","growth","relics","shop","save"]]]:
		_label(menu,section[0],13,MUTED)
		var grid := _grid(menu, 3 if size.x >= 600 else 2)
		for tab in TABS:
			if not tab[0] in section[1]:continue
			var destination := _tab_button(grid, tab[1], func(): navigate(tab[0]), tab[0] == current_screen)
			_button_icon(destination, icons[tab[0]])
			destination.name = "MenuNav_" + tab[0]
			destination.custom_minimum_size.y=48
			destination.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var footer:=_hbox(_modal_footer(menu),10)
	var settings:=_button(footer, "声音与动画", _show_audio_settings)
	_button_icon(settings,"gear")
	settings.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var back:=_button(footer, "返回游戏", _clear_overlay,true)
	_button_icon(back,"back",true)
	back.size_flags_horizontal=Control.SIZE_EXPAND_FILL

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
		_confirm("离开战斗？", ("未寄存的物资与战术装备会遗失。护盾装备、背包扩容保留。" if battle_config.get("isExtraction", false) else "撤退将结束当前战斗，已消耗的体力保留。深渊撤退会结束本轮构筑。"), func():
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
		_clear(fx)
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
	for item in [["星尘晶",r.get("diamonds",0),CYAN,"gem"],["金币",r.get("gold",0),GOLD,"coin"],["体力","%s / %s" % [r.get("stamina",0),r.get("maxStamina",100)],Color("a6c9a5"),"energy"]]:
		var p:=_panel(header_resources,item[2].darkened(0.7),5)
		p.tooltip_text=item[0]
		var row:=_hbox(p,5)
		_rune_icon(row,item[3],22)
		var value:=_label(row,"%s %s" % [item[0],str(item[1])],12,item[2])
		value.size_flags_vertical=Control.SIZE_SHRINK_CENTER

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
		var chapter_button:=_button(tabs,str(chapters[i].name),func():_select_story_chapter(i),selected_chapter==i)
		chapter_button.name="StoryChapter_"+str(i)
		var chapter_open:bool=bool(chapters[i].get("unlocked",false)) or bool(model.state.stageProgress.get(chapters[i].get("unlockCondition",""),{}).get("cleared",false))
		_button_icon(chapter_button,("fire" if i==0 else "ice") if chapter_open else "lock",selected_chapter==i)
	var row := _responsive_box(main_body,compact,16)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var stages_panel := _panel(row,LINE,10)
	stages_panel.size_flags_stretch_ratio = 0.85
	var stage_list := _scroll_column(stages_panel)
	stage_list.get_parent().name="StoryStageScroll"
	_restore_story_list(stage_list.get_parent(),selected_chapter)
	var stage_map: Dictionary = {}
	for stage in model.stage_list(): stage_map[stage.id]=stage
	var chapter: Dictionary=chapters[selected_chapter]
	if selected_stage_id.is_empty() or not stage_map.has(selected_stage_id): selected_stage_id=str(chapter.stages[0].id)
	for index in chapter.stages.size():
		var data: Dictionary=stage_map.get(chapter.stages[index].id,chapter.stages[index])
		var card := _panel(stage_list,GOLD if str(data.id)==selected_stage_id else LINE,10)
		card.name="StageCard_"+str(data.id)
		var line := _hbox(card,10)
		var cleared:bool=data.get("completed",data.get("cleared",false))
		var open:bool=data.get("unlocked",false)
		_rune_icon(line,"check" if cleared else ("map" if open else "lock"),28,CYAN if cleared else GOLD if open else MUTED)
		var labels:=_vbox(line,4);labels.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		_label(labels,str(data.name),17,TEXT,true)
		var state_row:=_hbox(labels,8)
		var stage_kind:String="首领" if data.get("isBoss",false) else ("精英" if data.get("isElite",false) else "普通")
		var tint:Color=RED if data.get("isBoss",false) else GOLD if data.get("isElite",false) else MUTED
		_rune_icon(state_row,"crown" if data.get("isBoss",false) else "sword",15,tint)
		_label(state_row,stage_kind,12,tint)
		_rune_icon(state_row,"energy",15)
		_label(state_row,str(int(data.get("staminaCost",6))),12,MUTED)
		_label(state_row,"已通关" if cleared else ("可探索" if open else "未解锁"),12,CYAN if open else MUTED)
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
	var info:=_hbox(pv,8)
	_story_chip(info,"energy","体力",str(int(selected.get("staminaCost",6))),CYAN)
	_story_chip(info,"sword","敌群","%d 波" % selected.get("waves",[]).size(),MUTED)
	_story_chip(info,"gem","首通",str(int(selected.get("firstClearRewards",{}).get("diamonds",0))),GOLD)
	var actions:=_hbox(pv,8)
	var unlocked:bool=selected.get("unlocked",false)
	var done:bool=selected.get("completed",selected.get("cleared",false))
	var enter:=_button(actions,"再次挑战" if done else "开始探索",func():_begin_stage(str(selected.id)),true)
	enter.name="StoryEnter"
	enter.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	enter.disabled=not unlocked
	if done:
		var replay:=_button(actions,"回顾剧情",func():_play_dialogue(str(selected.id)+"_pre",func():_play_dialogue(str(selected.id)+"_post",func():pass)))
		replay.name="StoryReplay"
		_button_icon(replay,"book")

func _select_story_chapter(index:int) -> void:
	if selected_chapter==index:return
	selected_chapter=index
	selected_stage_id=""
	story_list_positions[index]=0
	_render_screen()

func _restore_story_list(scroll:ScrollContainer,chapter_index:int) -> void:
	var desired:int=int(story_list_positions.get(chapter_index,0))
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(scroll) or not scroll.is_inside_tree():return
	scroll.scroll_vertical=desired
	story_list_positions[chapter_index]=scroll.scroll_vertical
	scroll.get_v_scroll_bar().value_changed.connect(func(value:float):
		if is_instance_valid(scroll) and scroll.is_inside_tree():story_list_positions[chapter_index]=int(value))

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
	var pools:Dictionary=model.catalog.GachaPoolData.pools
	var nav:=_flow(main_body,10)
	_label(nav,"星辰祈愿",22,GOLD)
	for id in model.catalog.GachaPoolData.activePools:
		var tab:=_tab_button(nav,pools[id].name,func():selected_pool=str(id);_render_screen(),selected_pool==id)
		tab.name="SummonPool_"+str(id)
	_tool_button(nav,"book","概率与规则",_pool_details).name="SummonRules"
	var pool:Dictionary=pools[selected_pool]
	var featured:String="kaldi" if selected_pool=="limited_kaldi" else "ayla"
	var row:=_responsive_box(main_body,compact,16)
	row.size_flags_vertical=Control.SIZE_EXPAND_FILL
	var background:="res://assets/backgrounds/summon_sanctum.png"
	if not ResourceLoader.exists(background):background=""
	var stage:=_portrait_environment(row,featured,330,background)
	stage.size_flags_stretch_ratio=1.6
	stage.name="SummonStage"
	var banner:=_vbox(stage,8);banner.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	banner.offset_left=22;banner.offset_top=20;banner.offset_right=-22
	_label(banner,"UP · 限定旅者" if selected_pool=="limited_kaldi" else "常驻祈愿 · 群星相逢",13,GOLD)
	_label(banner,_char_name(featured),25,TEXT)
	_label(banner,"★★★★★",16,GOLD)
	_ignore_children(banner)
	var preview:=_button(stage,"旅者档案",func():_summon_character_preview(featured))
	preview.name="SummonPreview";preview.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	preview.offset_left=20;preview.offset_right=152;preview.offset_top=-64;preview.offset_bottom=-20
	_button_icon(preview,"book")
	var side:=_vbox(row,10);side.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_label(side,pool.name,30,TEXT)
	_label(side,pool.subtitle,14,GOLD,true)
	var pity:Dictionary=model.state.get("pityCounters",{}).get(selected_pool,{})
	var count:int=int(pity.get("count",0))
	var info:=_vbox(_panel(side,GOLD.darkened(.7),10),6)
	var pity_row:=_hbox(info,8);_rune_icon(pity_row,"star",24,GOLD)
	_label(pity_row,"五星保底",14,MUTED)
	_label(pity_row,"%d / %d" % [count,pool.pity.hard],20,GOLD)
	_progress(info,count,pool.pity.hard,GOLD,6)
	_label(info,"当前五星概率 %.2f%%" % (float(model.pity_info(selected_pool).get("rate5",.016))*100.0),12,CYAN)
	_label(info,"下次五星必为限定角色" if pity.get("guaranteedFeatured",false) else "每十次至少获得四星旅者",13,MUTED,true)
	var gap:=Control.new();gap.size_flags_vertical=Control.SIZE_EXPAND_FILL;side.add_child(gap)
	var current:=_hbox(side,6);_rune_icon(current,"gem",21)
	_label(current,"持有 %d" % int(model.state.resources.get(pool.currency,0)),14,CYAN)
	var actions:=_responsive_box(side,compact,10)
	var balance:int=int(model.state.resources.get(pool.currency,0))
	for amount in [1,10]:
		var cost:int=int(pool.costPerPull)*amount
		var action:=_summon_cta(actions,amount,cost,func():_pull(amount))
		action.disabled=balance<cost
		if action.disabled:action.modulate=Color(.6,.65,.7)

func _pool_details() -> void:
	var pool: Dictionary = model.catalog.GachaPoolData.pools[selected_pool]
	var box := _modal("祈愿规则", 680)
	_label(box, "五星 1.6%% · 四星 15%% · 三星 83.4%%\n每十次至少出现四星及以上角色。五星软保底从第 %d 次开始，硬保底为第 %d 次。\n重复角色转化为对应角色碎片，可用于解锁命座。\n限定池五星有 75%% 概率为当期角色；若未获得，下次五星必为限定角色。" % [int(pool.pity.soft) + 1, pool.pity.hard], 17, TEXT, true)
	_label(box, "五星角色  " + _char_names(pool.pool5) + "\n四星角色  " + _char_names(pool.pool4) + "\n三星角色  " + _char_names(pool.pool3), 15, MUTED, true)
	_button(box, "我知道了", _clear_overlay, true).name="SummonRulesClose"

func _pull(count: int) -> void:
	# A committed sequence owns the presentation until explicitly closed.
	if is_instance_valid(summon_sequence) and summon_sequence.is_inside_tree():
		return
	var r: Dictionary = model.pull(selected_pool, count)
	if not _check(r):
		return
	summon_results = r.results
	summon_index = 0
	summon_flipped = false
	_update_resources()
	_reveal_summon()

func _reveal_summon() -> void:
	if summon_results.is_empty(): return
	_clear_overlay()
	summon_sequence = SummonSequence.new()
	summon_sequence.setup(self, summon_results, selected_pool, extraction_reduced_motion)
	overlay.add_child(summon_sequence)

func _summon_summary() -> void:
	if not is_instance_valid(summon_sequence) or not summon_sequence.is_inside_tree():
		_reveal_summon()
	if is_instance_valid(summon_sequence): summon_sequence.show_summary()

func _summon_character_preview(id:String,back:Callable=Callable()) -> void:
	var data:Dictionary=model.catalog.CharacterData[id]
	var box:=_modal("旅者档案",1040,500)
	var row:=_responsive_box(box,compact,16)
	_portrait_environment(row,id,270)
	var copy:=_vbox(row,8);copy.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_label(copy,str(data.name),26,_rarity_color(int(data.rarity)),true)
	_label(copy,"★".repeat(int(data.rarity)),16,GOLD)
	_label(copy,"已加入收藏" if model.state.ownedCharacters.has(id) else "尚未获得",14,CYAN)
	for sid in data.get("skills",[]):
		var skill:Dictionary=model.catalog.SkillData.get(sid,{})
		var heading:=_hbox(copy,6);_rune_icon(heading,RuneTheme.effect_key(skill),22)
		_label(heading,str(skill.get("name",sid)),16,TEXT)
		_label(copy,str(skill.get("description","")),12,MUTED,true)
	var close:=_button(_modal_footer(box),"返回",func():
		if back.is_valid():back.call()
		else:_clear_overlay())
	close.name="SummonPreviewClose"

var character_filter := "全部"
var character_list_positions: Dictionary = {}
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
		_tab_button(filters,_element_name(el),func():character_filter=el;_render_screen(),character_filter==el)
	_label(filters,"已拥有 %d / %d" % [model.state.ownedCharacters.size(),model.catalog.CharacterData.size()],12,MUTED)
	var listing:=_scroll_column(roster,8)
	listing.get_parent().name="PartyRosterScroll"
	_restore_character_list(listing.get_parent(), "party")
	var grid:=_grid(listing,2 if compact else (3 if content_width()<1050 else 4))
	if compact: listing.get_parent().custom_minimum_size.y=520
	for id in model.catalog.CharacterData:
		var data:Dictionary=model.catalog.CharacterData[id]
		if character_filter!="全部" and data.element!=character_filter:continue
		var v:=_vbox(grid,5);v.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		var card:=_character_card(v,id,110,func():_toggle_team(id))
		card.name="PartyCard_"+str(id)
		if id in draft_team:card.add_theme_stylebox_override("panel",_box(Color("173039"),CYAN,10))
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
	roster.get_parent().name="GrowthRosterScroll"
	_restore_character_list(roster.get_parent(), "growth")
	for id in model.catalog.CharacterData:
		var entry:Dictionary=model.catalog.CharacterData[id]
		var obtained:bool=model.state.ownedCharacters.has(id)
		var b:=_button(roster,"",func():selected_character=str(id);_render_screen(),selected_character==str(id))
		b.name="GrowthSelect_"+str(id)
		b.custom_minimum_size=Vector2(145,64)
		b.tooltip_text=_char_name(str(id))+" · "+("已拥有" if obtained else "未获得")
		var contents:=HBoxContainer.new()
		contents.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		contents.offset_left=9;contents.offset_right=-9;contents.offset_top=6;contents.offset_bottom=-6
		contents.add_theme_constant_override("separation",6)
		b.add_child(contents)
		var avatar:=_portrait(contents,str(id),38);avatar.custom_minimum_size.x=32;avatar.size_flags_horizontal=Control.SIZE_FILL
		var labels:=_vbox(contents,3);labels.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		var title:=_label(labels,_char_name(str(id)),13,INK if selected_character==str(id) else (TEXT if obtained else MUTED))
		title.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
		_character_ownership_badge(labels,str(id),true)
		_ignore_children(contents)
	var data:Dictionary=model.catalog.CharacterData.get(selected_character,{})
	if data.is_empty():return
	var owned:bool=model.state.ownedCharacters.has(selected_character)
	var progress:Dictionary=model.state.ownedCharacters.get(selected_character,{})
	var profile:=_panel(row,_rarity_color(int(data.rarity)).darkened(0.5),12)
	profile.size_flags_stretch_ratio=0.8
	var pv:=_vbox(profile,6)
	var art:=_portrait_environment(pv,selected_character,150)
	art.size_flags_vertical=Control.SIZE_EXPAND_FILL
	_character_ownership_badge(pv,selected_character)
	_center_label(pv,str(data.name),24,TEXT)
	_center_label(pv,"★".repeat(int(data.rarity)),16,_rarity_color(int(data.rarity)))
	_center_label(pv,str(data.get("title","")),13,MUTED)
	_center_label(pv,_element_name(str(data.element))+" · "+str(model.catalog.RoleNames.get(data.role,data.role)),14,CYAN)
	var details:=_vbox(row,8)
	details.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	details.size_flags_stretch_ratio=1.55
	var tabs:=_hbox(details,5)
	for tab in [["stats","属性"],["skills","技能"],["constellation","命座"],["gear","遗物"]]:
		var b:=_tab_button(tabs,tab[1],func():growth_panel=tab[0];_render_screen(),growth_panel==tab[0]);b.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	if model.has_method("relic_set_recommendations"):
		var recommendations:Array=model.relic_set_recommendations(selected_character)
		if not recommendations.is_empty():
			var recommendation:Dictionary=recommendations[0]
			var recommended:=_button(details,"推荐套装 · "+str(recommendation.name)+(" 等 %d 套"%recommendations.size() if recommendations.size()>1 else ""),func():load("res://scripts/ui/relic_recommendations_view.gd").show_for(self,selected_character))
			recommended.name="CharacterRecommendedRelics";recommended.icon=_relic_texture("helmet",str(recommendation.get("setId",recommendation.get("id",""))));recommended.add_theme_constant_override("icon_max_width",32);recommended.expand_icon=true;recommended.clip_text=true
	var panel:=_panel(details,LINE,12)
	panel.size_flags_vertical=Control.SIZE_EXPAND_FILL
	var body:=_scroll_column(panel,10)
	match growth_panel:
		"stats":
			_label(body,"等级 %d / 10" % progress.get("level",1) if owned else "旅者档案 · 尚未获得",23,GOLD)
			if owned:
				var needed:int=model.exp_to_next_level(int(progress.get("level",1)))
				_progress(body,progress.get("exp",0),maxi(1,needed),CYAN,7)
				var experience:=_hbox(body,5)
				var essence:=_relic_art(experience,"essence",20);essence.size_flags_horizontal=Control.SIZE_FILL
				_label(experience,"经验 %d / %d" % [progress.get("exp",0),needed] if needed>0 else "已达最高等级",12,MUTED)
			var stats:Dictionary=model.computed_stats(selected_character) if owned else data.baseStats
			var grid:=_grid(body,3)
			for attribute in [["生命","hp"],["攻击","atk"],["防御","def"],["速度","spd"],["暴击率","cri"],["暴击伤害","criDmg"]]:
				var cell:=_panel(grid,LINE,8);var cv:=_vbox(cell,3)
				var heading:=_hbox(cv,6)
				_rune_icon(heading,{"hp":"heart","atk":"sword","def":"shield","spd":"wind","cri":"crit","criDmg":"burst"}.get(attribute[1],"star"),18,CYAN)
				_label(heading,attribute[0],12,MUTED)
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
				_rune_icon(heading,{"normal":"sword","skill":"energy" if data.element=="thunder" else str(data.element),"ultimate":"burst"}.get(skill.type,"star"),26,_element_color(data.element))
				_label(heading,skill.name,20,TEXT)
				_label(heading,{"normal":"普通攻击","skill":"战技","ultimate":"终结技"}.get(skill.type,"技能"),12,CYAN)
				_label(cv,skill.description,14,MUTED,true)
				_label(cv,"冷却 %d 回合 · %s" % [skill.get("cooldown",0),"消耗 %d 能量" % skill.get("energyCost",100) if skill.type=="ultimate" else "获得 %d 能量" % skill.get("energyGain",0)],12,GOLD)
		"constellation":
			var current:int=int(progress.get("constellation",progress.get("awakening",0)))
			var balance:=_hbox(body,8)
			_rune_icon(balance,"star",24,GOLD)
			_label(balance,"命座 %d / 6" % current,18,GOLD)
			_rune_icon(balance,"gem",20)
			_label(balance,"碎片 %d" % progress.get("shards",0),14,CYAN)
			var infos:Array=model.constellation_info(selected_character)
			for i in range(6):
				var info:Dictionary=infos[i] if i<infos.size() else {}
				var cell:=_panel(body,GOLD.darkened(0.4) if i<current else LINE,10);var cv:=_vbox(cell,5)
				var heading:=_hbox(cv,8)
				_rune_icon(heading,"star" if i<current else "lock",24,GOLD if i<current else MUTED)
				_label(heading,"%02d  %s" % [i+1,info.get("label",info.get("name","命座"))],18,GOLD if i<current else TEXT)
				_label(cv,info.get("desc",info.get("description","")),14,MUTED,true)
				if i==current and owned:
					_button(cv,"解锁 · %d 碎片" % info.get("cost",model.catalog.ConstellationCost[str(int(data.rarity))][i]),func():
						if _check(model.unlock_constellation(selected_character)):_toast("命座已点亮",GOLD);_render_screen(),true)
				elif i<current:_label(cv,"已点亮",12,GOLD)
		"gear":
			if owned:
				var loadout:Dictionary=model.relic_loadout_snapshot(selected_character)
				for bonus in loadout.get("activeBonuses",[]):
					_label(body,"%s · %d 件　%s"%[str(bonus.name),int(bonus.pieces),str(bonus.description)],12,CYAN,true)
			for slot in model.catalog.RelicSlots:
				var cell:=_panel(body,LINE,10);var line:=_hbox(cell,10)
				var uid=progress.get("equippedRelics",{}).get(slot.id,null)
				var relic:=_find_relic(str(uid))
				var slot_art:=_relic_art(line,str(slot.id),42,str(relic.get("setId","")));slot_art.custom_minimum_size.x=42;slot_art.size_flags_horizontal=Control.SIZE_FILL
				var cv:=_vbox(line,3);cv.size_flags_horizontal=Control.SIZE_EXPAND_FILL
				_label(cv,str(slot.name)+(" · "+_relic_set_name(relic) if not relic.is_empty() else ""),15,GOLD,true)
				_label(cv,("+%d · %s" % [relic.get("level",0),_relic_main(relic)]) if not relic.is_empty() else "空置",14,MUTED,true)
				if not relic.is_empty():_button(line,"卸下",func():_check(model.unequip_relic(selected_character,slot.id));_render_screen())
				elif owned:_button(line,"选择遗物",func():navigate("relics"))
	var footer:=_hbox(details,8)
	if owned:
		if growth_panel=="gear":
			var auto_equip:=_button(footer,"自动搭配",func():_auto_relic_loadout(selected_character),true)
			auto_equip.name="GrowthAutoRelics";auto_equip.size_flags_horizontal=Control.SIZE_EXPAND_FILL;_button_icon(auto_equip,"gear",true)
		else:
			var train:=_button(footer,"训练一次 · 500 金币",func():
				if _check(model.train_character(selected_character)):_toast("训练完成",CYAN);_render_screen(),true)
			_button_icon(train,"coin",true)
			train.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			train.disabled=int(progress.get("level",1))>=10
		_button(footer,"冒险编队",func():navigate("party"))
	else:
		_button(footer,"前往星辰祈愿",func():navigate("summon"),true)

func _relics() -> void:
	set_page_fixed(not compact)
	var row := _responsive_box(main_body, compact, 16)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var collection:=_vbox(row,8)
	collection.name="RelicCollectionColumn"
	collection.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	collection.size_flags_stretch_ratio=1.5
	var collection_title:=_hbox(collection,10)
	collection_title.custom_minimum_size.y=42
	_label(collection_title,"遗物工坊",24,TEXT)
	var headline_gap:=Control.new();headline_gap.size_flags_horizontal=Control.SIZE_EXPAND_FILL;collection_title.add_child(headline_gap)
	var auto_equip:=_button(collection_title,"自动搭配",func():_auto_relic_loadout(),true)
	auto_equip.name="RelicAutoEquip";_button_icon(auto_equip,"gear",true)
	var controls := _flow(collection, 6)
	for f in ["全部", "背包", "已装备", "三星", "四星", "五星"]:
		_tab_button(controls, f, func(): relic_filter = f; _save_preferences(); _render_screen(), relic_filter == f)
	_button_icon(_tab_button(controls, "批量出售", _batch_salvage),"coin")
	var slots := HFlowContainer.new()
	slots.add_theme_constant_override("h_separation", 8)
	slots.add_theme_constant_override("v_separation", 8)
	collection.add_child(slots)
	_tab_button(slots, "全部部位", func(): relic_slot_filter = "全部"; _save_preferences(); _render_screen(), relic_slot_filter == "全部")
	for slot in model.catalog.RelicSlots:
		var filter_button:=_tab_button(slots, slot.name, func(): relic_slot_filter = slot.id; _save_preferences(); _render_screen(), relic_slot_filter == slot.id)
		filter_button.icon=_relic_texture(str(slot.id));filter_button.add_theme_constant_override("icon_max_width",24);filter_button.expand_icon=false
		for style_name in ["normal","hover","pressed","disabled"]:
			var style:StyleBox=filter_button.get_theme_stylebox(style_name).duplicate()
			style.content_margin_left=8;style.content_margin_right=8
			filter_button.add_theme_stylebox_override(style_name,style)
	var inventory: Array = model.state.get("relics", [])
	if inventory.is_empty():
		var empty:=_vbox(_panel(collection,LINE,20),12)
		_label(empty,"尚未获得遗物",24,GOLD)
		_label(empty,"完成章节与深渊挑战，收集旅途中的遗物。",15,MUTED,true)
		_button(empty,"开始探索",func():navigate("story"),true)
		return
	var list_column := _scroll_column(collection)
	list_column.get_parent().name="RelicRosterScroll"
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
		selected_relic=""
		_label(listing, "当前筛选下没有遗物", 18, MUTED)
	if not visible.any(func(relic):return str(relic.uid)==selected_relic) and not visible.is_empty():
		selected_relic = str(visible[0].uid)
	# Keep the full filtered inventory addressable while bounding native controls.
	# Pages remember their own scroll; changing a page preserves the selected UID.
	var page_key:String=relic_filter+"|"+relic_slot_filter
	var page_size:int=60
	var page_count:int=maxi(1,ceili(float(visible.size())/page_size))
	var pages:Dictionary=get_meta("relic_inventory_pages",{})
	var page:int=clampi(int(pages.get(page_key,0)),0,page_count-1)
	pages[page_key]=page;set_meta("relic_inventory_pages",pages)
	_restore_character_list(list_column.get_parent(),"relics" if page_count==1 else "relics|"+page_key+"|"+str(page))
	for relic in visible.slice(page*page_size,mini(visible.size(),(page+1)*page_size)):
		var color := _rarity_color(int(relic.rarity))
		var card := _panel(listing, color if str(relic.uid) == selected_relic else LINE, 10)
		card.custom_minimum_size.x=150
		card.name="RelicCard_"+str(relic.uid)
		var v := _vbox(card, 6)
		var art:=_relic_item_art(v,relic,70)
		art.modulate=Color.WHITE
		var badge:=_hbox(v,4)
		_rune_icon(badge,"check" if relic.get("equippedBy")!=null else "bag",14,CYAN if relic.get("equippedBy")!=null else MUTED)
		_label(badge,_char_name(str(relic.equippedBy)) if relic.get("equippedBy")!=null else "待装备",11,CYAN if relic.get("equippedBy")!=null else MUTED)
		_center_label(v,_relic_set_name(relic),14,GOLD)
		_center_label(v, "%s  +%d" % [_slot_name(relic.slotId), relic.level], 16, TEXT)
		_center_label(v, "★".repeat(int(relic.rarity)), 13, color)
		_label(v, _relic_main(relic), 13, MUTED, true)
		_bind_card_tap(card,func():selected_relic=str(relic.uid);_save_preferences();_render_screen())
		_ignore_children(v)
	if page_count>1:
		var paging:=_hbox(collection,8);paging.name="RelicPagination"
		var previous:=_button(paging,"上一页",func():_set_relic_inventory_page(page_key,page-1));previous.name="RelicPreviousPage";previous.disabled=page==0
		var count:=_label(paging,"%d 件"%visible.size(),12,MUTED,true);count.size_flags_horizontal=Control.SIZE_EXPAND_FILL;count.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		var jump:=SpinBox.new();jump.name="RelicPageNumber";jump.min_value=1;jump.max_value=page_count;jump.step=1;jump.value=page+1;jump.custom_minimum_size=Vector2(82,44);jump.tooltip_text="输入页码，查看全部遗物";paging.add_child(jump)
		_label(paging,"/ %d"%page_count,12,MUTED)
		jump.value_changed.connect(func(value):_set_relic_inventory_page(page_key,int(value)-1))
		var next:=_button(paging,"下一页",func():_set_relic_inventory_page(page_key,page+1));next.name="RelicNextPage";next.disabled=page>=page_count-1
	var selected := _find_relic(selected_relic)
	if selected.is_empty():
		return
	var detail:=_panel(row,_rarity_color(int(selected.rarity)).darkened(0.4),12)
	detail.name="RelicDetailPanel"
	detail.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	detail.size_flags_stretch_ratio=1.0
	detail.custom_minimum_size.x=350 if not compact else 0
	if compact:detail.custom_minimum_size.y=400
	var dv:=_vbox(detail,8)
	var title:=_hbox(dv,10)
	var hero:=_relic_item_art(title,selected,60);hero.custom_minimum_size.x=60;hero.size_flags_horizontal=Control.SIZE_FILL
	var identity:=_vbox(title,4);identity.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_label(identity,_relic_set_name(selected),19,GOLD)
	_label(identity,"%s +%d" % [_slot_name(selected.slotId),selected.level],18,TEXT)
	_label(identity,"★".repeat(int(selected.rarity)),15,_rarity_color(int(selected.rarity)))
	_progress(identity,int(selected.level),25,GOLD,4)
	var stats:=_scroll_column(dv,6)
	stats.get_parent().name="RelicStatsScroll"
	_restore_character_list(stats.get_parent(),"relic_detail_"+selected_relic)
	var main_tile:=_hbox(_panel(stats,GOLD.darkened(0.6),9),8)
	_rune_icon(main_tile,_stat_icon(str(selected.mainStat.stat)),24,GOLD)
	_label(main_tile,_relic_main(selected),18,GOLD).tooltip_text="主属性"
	var substats:=_vbox(_panel(stats,LINE,8),7)
	_label(substats,"附加属性",11,MUTED)
	for stat in selected.get("subStats",[]):
		var line:=_hbox(substats,8)
		line.name="RelicSubstat_"+str(stat.stat)
		line.custom_minimum_size.y=22
		_rune_icon(line,_stat_icon(str(stat.stat)),18,CYAN)
		_label(line,_stat_label(str(stat.stat),str(stat.name)),13,MUTED).size_flags_horizontal=Control.SIZE_EXPAND_FILL
		_label(line,"+"+_stat_value(stat.stat,stat.value),15,TEXT)
	var set_count:int=-1
	if selected.get("equippedBy")!=null:
		set_count=int(model.relic_loadout_snapshot(str(selected.equippedBy)).get("counts",{}).get(str(selected.get("setId","")),0))
	_label(stats,"套装效果"+(" · 已装备 %d 件"%set_count if set_count>=0 else ""),12,GOLD,true)
	_relic_set_details(stats,str(selected.get("setId","")),set_count)
	var upgrades:=_hbox(dv,6)
	var upgrade:=_button(upgrades,"强化 +1 · %d 金币" % model.relic_upgrade_cost(int(selected.level)),func():
		if _check(model.upgrade_relic(selected_relic)):_ui_sound("equip");_render_screen(),true)
	upgrade.name="RelicUpgrade"
	_button_icon(upgrade,"upgrade",true)
	upgrade.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	upgrade.disabled=int(selected.level)>=25
	var max_cost:int=int(model.relic_upgrade_cost_to_max(selected_relic))
	var maxup:=_tab_button(upgrades,"升满",func():
		_confirm("强化至 +25","消耗 %d 金币" % max_cost,func():
			if _check(model.upgrade_relic_to_max(selected_relic)):_render_screen()))
	maxup.disabled=int(selected.level)>=25
	var actions:=_hbox(dv,6)
	var equip:=_button(actions,"装备给角色",func():_equip_dialog(selected_relic))
	equip.name="RelicEquip";equip.size_flags_horizontal=Control.SIZE_EXPAND_FILL;_button_icon(equip,"party")
	if selected.get("equippedBy")!=null:
		_button_icon(_tab_button(actions,"卸下",func():_check(model.unequip_relic(selected.equippedBy,selected.slotId));_render_screen()),"gear")
	else:
		_tab_button(actions,"出售",func():
			_confirm("出售遗物？","出售后获得金币。",func():
				if _check(model.sell_relic(selected_relic)):
					selected_relic="";_ui_sound("coin");_render_screen()))

func _set_relic_inventory_page(key: String, page: int) -> void:
	var pages:Dictionary=get_meta("relic_inventory_pages",{})
	pages[key]=maxi(0,page);set_meta("relic_inventory_pages",pages)
	_render_screen()

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
	var box := _modal("选择装备角色", 760, 450)
	var relic:=_find_relic(uid)
	var heading:=_hbox(box,10)
	var icon:=_relic_item_art(heading,relic,50);icon.custom_minimum_size.x=50;icon.size_flags_horizontal=Control.SIZE_FILL
	var copy:=_vbox(heading,3)
	_label(copy,"%s · %s +%d" % [_relic_set_name(relic),_slot_name(str(relic.get("slotId",""))),int(relic.get("level",0))],20,GOLD,true)
	_label(copy,_relic_main(relic),14,TEXT)
	var grid := _grid(box, 2)
	for id in model.state.ownedCharacters:
		var cell:=_panel(grid,LINE,8)
		var row:=_hbox(cell,8)
		var portrait:=_portrait(row,str(id),58);portrait.custom_minimum_size.x=48;portrait.size_flags_horizontal=Control.SIZE_FILL
		var info:=_vbox(row,5);info.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		var action:=_button(info,_char_name(id),func():
			if _check(model.equip_relic(uid,id)):
				_clear_overlay();_ui_sound("equip");_toast("已装备给 "+_char_name(id),CYAN);_render_screen())
		action.name="RelicEquipFor_"+str(id)
		var previous_uid=str(model.state.ownedCharacters[id].get("equippedRelics",{}).get(relic.get("slotId",""),""))
		var previous:=_find_relic(previous_uid)
		_label(info,"空置" if previous.is_empty() else "替换 +%d %s" % [int(previous.get("level",0)),_slot_name(str(previous.get("slotId","")))],11,MUTED)
	_button(_modal_footer(box), "返回", _clear_overlay).name="RelicEquipCancel"

func _shop() -> void:
	set_page_fixed(not compact)
	_page_title("补给商店", "整备物资，再次出发")
	var row:=_responsive_box(main_body,compact,14)
	row.size_flags_vertical=Control.SIZE_EXPAND_FILL
	for category in ["item","recharge"]:
		var column:=_vbox(_panel(row,LINE,12),10)
		_label(column,"旅途补给" if category=="item" else "旅者礼遇",22,GOLD)
		var list:=_scroll_column(column,10)
		list.get_parent().name="ShopScroll_"+category
		if compact:list.get_parent().custom_minimum_size.y=380
		var entries=model.catalog.ShopData.itemShop if category=="item" else model.catalog.ShopData.rechargeItems
		for item in entries:
			var accent:Color=Color(str(item.get("color","#7dcac9")))
			var card:=_vbox(_panel(list,accent.darkened(0.6),12),9)
			var heading:=_hbox(card,10)
			_rune_icon(heading,{"recharge_traveler":"bag","recharge_monthly":"book","recharge_hero":"sword","recharge_legend":"crown","recharge_supreme":"gem"}.get(item.id,"gem") if category=="recharge" else ("energy" if item.id=="buy_stamina_60" else "gem"),32,accent)
			var titles:=_vbox(heading,3);titles.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			_label(titles,item.name,20,TEXT)
			if not str(item.get("badge","")).is_empty():
				var badge:=_panel(titles,accent.darkened(0.5),3)
				_label(badge,str(item.badge),11,accent)
			if category=="recharge":
				var price:=_label(heading,str(item.get("priceDisplay",item.get("price",""))),26,GOLD)
				price.name="ShopPrice_"+str(item.id)
			var rewards:=_flow(card,8)
			for reward in item.rewards:
				var chip:=_hbox(_panel(rewards,LINE,5),5)
				_rune_icon(chip,{"diamonds":"gem","stamina":"energy","gold":"coin"}.get(reward.type,"star"),19)
				_label(chip,str(int(reward.amount)),15,TEXT)
			var action:=_button(card,"%d 金币 · 兑换" % item.price if category=="item" else "购买",func():
				if _check(model.purchase(category,item.id)):
					_ui_sound("coin");_toast("获得 "+str(item.name),GOLD);_render_screen(),true)
			action.name="ShopPurchase_"+str(item.id)
			_button_icon(action,"coin" if category=="item" else "gift",true)
			action.size_flags_horizontal=Control.SIZE_EXPAND_FILL

func _save_screen() -> void:
	_page_title("旅程档案", "三份独立存档 · 自动保存 · 兼容网页原版存档")
	var grid := _grid(main_body, 1 if compact else 3)
	for s in model.slot_summaries():
		var slot: int = int(s.get("slot", s.get("id", 1)))
		var active: bool = slot == model.active_slot
		var p := _panel(grid, GOLD if active else LINE, 16)
		var v := _vbox(p, 10)
		var title:=_hbox(v,10)
		_rune_icon(title,"book",30,GOLD if active else MUTED)
		_label(title, "档案  %02d" % slot, 26, GOLD if active else TEXT)
		_label(v, "当前旅程" if active else ("已有存档" if s.get("hasData", false) else "新的旅程"), 14, CYAN if active else MUTED)
		for metric in [["party","旅者",s.get("ownedCount",0)],["star","累计祈愿",s.get("totalPulls",0)],["sword","战斗胜利",s.get("totalVictories",0)]]:
			var line:=_hbox(v,10)
			_rune_icon(line,metric[0],20,MUTED)
			var caption:=_label(line,metric[1],14,MUTED);caption.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			_label(line,str(metric[2]),20,TEXT).name="SaveStat_%d_%s" % [slot,metric[0]]
		var b := _button(v, "已在当前档案" if active else "切换至此档案", func():
			_confirm("切换旅程档案", "当前进度已自动保存。接下来将载入档案 %d。" % slot, func():
				if _check(model.load_slot(slot)):
					selected_relic = ""
					_clear_overlay()
					_render_screen()), active)
		_button_icon(b,"check" if active else "next",active)
		b.disabled = active
		_label(v, "最后保存：" + (Time.get_datetime_string_from_unix_time(int(s.get("lastSaved", 0)) / 1000).replace("T", " ") if int(s.get("lastSaved", 0)) > 0 else "尚未保存"), 11, MUTED, true)
		if s.get("corrupt", false): _label(v, "数据异常 · 可导入备份恢复", 13, RED, true)
		var transfer := _flow(v, 8)
		var export_button:=_tab_button(transfer, "导出", func(): _export_dialog(slot))
		_button_icon(export_button,"next")
		export_button.disabled = not s.get("hasData", false) or s.get("corrupt", false)
		_button_icon(_tab_button(transfer, "导入", func(): _import_dialog(slot)),"back")
		_tab_button(v, "重新开始", func():
			_confirm("重置档案 %d？" % slot, "该档案中的角色、资源与进度将被初始状态替换。建议先导出备份。", func():
				if _check(model.reset_slot(slot)):
					selected_relic = ""
					_clear_overlay()
					_render_screen()))
	var p := _panel(main_body, LINE, 16)
	var v := _vbox(p, 10)
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
	_label(content, "启动后自动检查并下载更新，完成后点击安装。升级保留本机存档。", 14, MUTED, true)
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
	auto_download.text = "自动下载更新（Android）"
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

func _present_abyss_reward(raw: Variant) -> Dictionary:
	# Refresh display-only copy for old ongoing runs without changing issued effects.
	var reward:Dictionary=raw.duplicate(true) if raw is Dictionary else _abyss_reward(str(raw)).duplicate(true)
	var id:String=str(reward.get("id",""))
	if id=="common_static_blue":
		reward.description=str(reward.get("description","")).split("感电期间")[0].strip_edges()
	var definition:Dictionary=_abyss_reward(id)
	if str(reward.get("icon",""))=="✦" and not definition.is_empty():reward.icon=definition.get("icon","✦")
	return reward

func _start_battle(config: Dictionary) -> void:
	_clear_overlay()
	battle_generation += 1
	battle_config = config
	battle_settled = false
	settlement_error = false
	selected_skill = ""
	selected_target = ""
	battle_clock = -0.4 if config.get("isExtraction", false) else 0.0
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
	_tab_button(head, "自动" if battle_auto else "手动", func(): battle_auto = not battle_auto; abyss_auto_continue = abyss_auto_continue and battle_auto; _render_battle(), battle_auto)
	_tab_button(head, "%d 倍速" % battle_speed, func(): battle_speed = 2.0 if battle_speed == 1.0 else (4.0 if battle_speed == 2.0 else 1.0); _render_battle())
	_tool_button(head,"book","战斗记录",_show_battle_log)
	if battle_config.get("isAbyss", false): _tool_button(head,"star","本轮回响",_show_battle_echoes)
	_tab_button(head, "撤退", func(): navigate(_battle_return_screen()))
	_tool_button(head,"menu","菜单",_show_navigation)
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
		var avatar:=_portrait(chip,str(unit.id),24,false,not bool(unit.get("isAlly",true)))
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
	controls.custom_minimum_size.y = 118
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
			icon.texture=_icon_texture(RuneTheme.effect_key(skill))
			icon.modulate=INK if selected_skill==sid else _element_color(str(active.get("element","wind")))
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

func _battle_number(value: float) -> String:
	if absf(value)>=100000000:return "%.1f亿" % (value/100000000.0)
	if absf(value)>=10000:return "%.1f万" % (value/10000.0)
	return str(int(value))

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
	var art := _portrait(v,unit.id,138,false,not ally)
	var ground=load("res://scripts/ui/unit_ground.gd").new()
	ground.accent=GOLD if selected else CYAN
	ground.selected=selected;ground.active=unit.uid==active_uid
	ground.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.add_child(ground);art.move_child(ground,0)
	art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_progress(v,unit.get("currentHp",0),maxi(1,int(unit.get("maxHp",1))),CYAN if ally else RED,7)
	var hp_label:=_center_label(v,"%s / %s" % [_battle_number(float(unit.get("currentHp",0))),_battle_number(float(unit.get("maxHp",1)))],14,MUTED)
	hp_label.clip_text=true
	hp_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	var shield_value := int(unit.get("shield", 0))
	var shield_line:=_hbox(v,4)
	shield_line.custom_minimum_size.y=16
	_rune_icon(shield_line,"shield",12,Color(0.55,0.78,1.0))
	var shield_bar := _progress(shield_line, shield_value, maxi(1,maxi(shield_value,int(unit.get("maxHp",1)))), Color(0.55,0.78,1.0), 4)
	shield_bar.name = "BattleShield_" + str(unit.uid)
	shield_bar.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	shield_bar.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	var shield_count:=_label(shield_line,_battle_number(shield_value),11,Color(0.55,0.78,1.0))
	shield_count.custom_minimum_size.x=36;shield_count.clip_text=true
	shield_count.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	shield_line.modulate.a=1.0 if shield_value>0 else 0.0
	var energy_bar:=_progress(v,unit.get("energy",0),unit.get("maxEnergy",100),GOLD,3)
	energy_bar.modulate.a=1.0 if ally else 0.0
	var statuses: Array = []
	for status in unit.get("statuses",[]):
		var status_name := "装备护盾" if status.get("source", "") == "expedition_equipment" else str(STATUS_NAMES.get(status.get("id",""),status.get("id","")))
		if status_name not in statuses: statuses.append(status_name)
	var status_strip=load("res://scripts/ui/battle_status_strip.gd").new()
	status_strip.name="BattleStatuses_"+str(unit.uid)
	status_strip.configure(unit.get("statuses",[]),extraction_reduced_motion,model.catalog)
	v.add_child(status_strip)
	p.tooltip_text = "生命 %d / %d\n护盾 %d\n" % [unit.get("currentHp",0),unit.get("maxHp",1),shield_value]+status_strip.tooltip_text
	_ignore_children(v)
	var info:=_tool_button(art,"book","角色状态",func():_show_unit_details(unit))
	info.name="BattleUnitInfo_"+str(unit.uid)
	info.mouse_filter=Control.MOUSE_FILTER_STOP
	info.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	info.offset_left=-44;info.offset_right=0;info.offset_top=0;info.offset_bottom=44
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

func _battle_event_element(event: Dictionary) -> String:
	var unit:=_battle_unit(str(event.get("actor","")))
	return str(event.get("element",unit.get("element","fire")))

func _battle_effect_kind(event: Dictionary) -> String:
	var skill:Dictionary=model.catalog.SkillData.get(event.get("skill_id",""),{})
	var animation:=str(event.get("animation",skill.get("animation",""))).to_lower()
	if "ice" in animation or "frost" in animation:return "ice"
	if "punch" in animation or "smash" in animation or "impact" in animation:return "blunt"
	if "slash" in animation or "blade" in animation:return "slash"
	return _battle_event_element(event)

func _battle_sound_clip(events: Array) -> String:
	var has_damage:=false
	var has_heal:=false
	var has_shield_hit:=false
	var has_shield_cast:=false
	var critical:=false
	var element_clip:="slash"
	for event in events:
		var type:=str(event.get("type",""))
		if type=="skill" and str(model.catalog.SkillData.get(event.get("skill_id",""),{}).get("type",""))=="ultimate":return "ultimate"
		if type=="shield":
			has_shield_hit=true
			if int(_battle_unit(str(event.get("target",""))).get("shield",0))<=0:return "shield_break"
		if type=="status" and str(event.get("statusId",event.get("status","")))=="shield":has_shield_cast=true
		if type=="heal" and int(event.get("amount",0))>0:has_heal=true
		if type=="damage" and int(event.get("amount",0))>0:
			has_damage=true;critical=critical or event.get("isCrit",false)
			element_clip=_battle_effect_kind(event)
	if critical:return "critical"
	if has_damage:return element_clip if element_clip in ["slash","blunt","fire","water","ice","thunder","wind"] else "blunt"
	if has_shield_hit:return "shield_hit"
	if has_heal:return "heal"
	if has_shield_cast:return "shield_cast"
	return ""

func _play_battle_sound(events: Array) -> void:
	if not sound_enabled or bool(get_meta("application_paused",false)):return
	var clip:=_battle_sound_clip(events)
	if clip.is_empty() or Time.get_ticks_msec()-_last_battle_sound_msec<90:return
	var path:="res://assets/audio/battle/"+clip+".ogg"
	if not ResourceLoader.exists(path):return
	_last_battle_sound_msec=Time.get_ticks_msec()
	var voices:Array=get_tree().get_nodes_in_group("battle_audio")
	while voices.size()>=2:
		var old:AudioStreamPlayer=voices.pop_front()
		old.stop();old.stream=null;old.remove_from_group("battle_audio");old.remove_from_group("transient_audio");old.queue_free()
	var voice:=AudioStreamPlayer.new();voice.stream=load(path)
	voice.volume_db=effects_volume_db-9
	voice.add_to_group("battle_audio");voice.add_to_group("transient_audio");voice.set_meta("priority",1)
	voice.set_meta("battle_clip",clip)
	add_child(voice);voice.finished.connect(voice.queue_free);voice.play()
	_battle_audio_history.append(clip)
	if _battle_audio_history.size()>32:_battle_audio_history.pop_front()

func _show_combat_events(events: Array) -> void:
	var generation := battle_generation
	await get_tree().process_frame
	if current_screen != "battle" or generation != battle_generation: return
	_play_battle_sound(events)
	for e in events:
		if e.get("type", "") == "skill" and model.catalog.SkillData.get(e.get("skill_id", ""), {}).get("type", "") == "ultimate":
			fx.flash(_element_color(_battle_event_element(e)))
			var source_unit := _battle_unit(str(e.get("actor", "")))
			var source_card = unit_cards.get(str(e.get("actor", "")))
			var target_uid:=str(e.get("target",""))
			if target_uid.is_empty():
				for follow in events:
					if follow.get("actor","")==e.get("actor","") and not str(follow.get("target","")).is_empty() and follow.get("type","") in ["damage","heal","status"]:
						target_uid=str(follow.target);break
			var destination_card = unit_cards.get(target_uid)
			var origin: Vector2 = source_card.get_global_rect().get_center() if is_instance_valid(source_card) else size * Vector2(0.25,0.5)
			var destination: Vector2 = destination_card.get_global_rect().get_center() if is_instance_valid(destination_card) else size * Vector2(0.75,0.5)
			fx.ultimate(str(source_unit.get("id","")),_battle_event_element(e),origin,destination)
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
			if type=="damage":
				var origin:Vector2=actor.global_position+actor.size*0.5 if is_instance_valid(actor) else pos+Vector2(-32,0)
				fx.impact(str(e.get("status",_battle_effect_kind(e))),origin,pos,bool(e.get("isCrit",false)))
			elif type=="shield" and int(_battle_unit(str(e.get("target",""))).get("shield",0))<=0:fx.impact("shield_break",pos,pos)
			else:fx.burst(pos,color,false)
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
			var status_id:=str(e.get("statusId",e.get("status","")))
			if status_id=="shield":fx.shield_ring(pos)
			elif not status_id.is_empty():fx.impact(status_id,pos,pos)
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
		var summary := _hbox(extraction_box, 10)
		summary.alignment = BoxContainer.ALIGNMENT_CENTER
		_extraction_result_stat(summary, "sword", "%d 回合" % int(battle.state.get("turn", 0)), "遭遇战")
		var survivors := 0
		for unit in battle.state.get("allies", []):
			if float(unit.get("currentHp", 0)) > 0: survivors += 1
		_extraction_result_stat(summary, "party", "%d / %d" % [survivors, battle.state.get("allies", []).size()], "存活旅者")
		if victory:
			var choices: Array = model.extraction.growth_choices()
			_extraction_result_stat(summary, "star" if not choices.is_empty() else "bag", "回响待选" if not choices.is_empty() else "区域解锁", "战后收获")
		else:
			_extraction_result_stat(summary, "shield", "整备再战", "旅者成长保留")
		if victory and int(result.get("rewards",{}).get("exp",0))>0:
			var experience_row:=_hbox(extraction_box,8);experience_row.alignment=BoxContainer.ALIGNMENT_CENTER
			var experience_icon:=_rune_icon(experience_row,"star",26);experience_icon.texture=_relic_texture("essence")
			_label(experience_row,"经验 +%d"%int(result.rewards.exp),18,CYAN).name="ExtractionBattleExperience"
			var gained_levels:=0
			for progress in result.get("progression",[]):gained_levels+=int(progress.get("leveledUp",0))
			if gained_levels>0:_label(experience_row,"等级提升 +%d"%gained_levels,15,GOLD)
		var exit_open: bool = victory and model.extraction.active() and model.extraction.run().get("phase", "") == "boss_exit"
		_center_label(extraction_box, "撤离点已开启" if exit_open else ("守卫已清除" if victory else "返回营地"), 20, GOLD if victory else MUTED)
		var continue_button := _button(extraction_box, "选择回响" if victory and not model.extraction.growth_choices().is_empty() else ("前往出口" if exit_open else ("继续搜索" if victory else "返回营地")), func(): navigate("extraction"), true)
		continue_button.name = "ExtractionBattleContinue"
		_button_icon(continue_button, "star" if victory and not model.extraction.growth_choices().is_empty() else "path", true)
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
	_render_battle_settlement(result,victory,run_ended)

func _render_battle_settlement(result:Dictionary,victory:bool,run_ended:bool) -> void:
	var box:=_modal("战斗结算",1080,500)
	box.add_theme_constant_override("separation",10)
	var row:=_responsive_box(box,compact,18)
	row.name="SettlementColumns"
	var left:=_vbox(row,7)
	left.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio=.9
	var color:=GOLD if victory else MUTED
	var heading:=_hbox(left,10)
	_rune_icon(heading,"crown" if victory else "shield",28,color)
	_label(heading,"远征通关" if run_ended and victory else ("远征胜利" if victory else "整装再出发"),28,color)
	var allies:Array=battle.state.get("allies",[])
	var featured:String=str(allies[0].get("id","ember")) if not allies.is_empty() else "ember"
	_portrait_environment(left,featured,210)
	var context:=_hbox(left,8)
	_rune_icon(context,"sword",20,MUTED)
	_label(context,"%d 回合" % int(battle.state.get("turn",0)),15,TEXT)
	_label(left,str(battle_config.get("name","深渊远征")),14,MUTED,true)
	var right:=_vbox(row,9)
	right.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio=1.5
	var scroll_content:=_scroll_column(right,10)
	scroll_content.get_parent().name="SettlementRewardScroll"
	scroll_content.get_parent().custom_minimum_size.y=300
	if victory:
		var rewards:Dictionary=result.get("rewards",{})
		var is_abyss:bool=bool(battle_config.get("isAbyss",false))
		var reward_grid:=_grid(scroll_content,2 if is_abyss else 3)
		var resources:Array=[["exp","essence","经验"],["diamonds","gem","星尘晶"]] if is_abyss else [["gold","coin","金币"],["exp","essence","经验"],["diamonds","gem","星尘晶"]]
		for resource in resources:
			_settlement_reward_tile(reward_grid,resource[1],resource[2],int(rewards.get(resource[0],0)),resource[0])
		var daily_award:Dictionary=result.get("dailyAward",{})
		if is_abyss and not daily_award.is_empty():
			var daily_row:=_hbox(_panel(scroll_content,GOLD.darkened(.55),8),8)
			daily_row.name="SettlementDailyAward";_rune_icon(daily_row,"gem",24)
			var award_text:String="第 %d 层 · 今日已领取"%int(daily_award.get("floor",0))
			if int(daily_award.get("amount",0))>0:
				award_text="第 %d 层 · %s +%d"%[int(daily_award.get("floor",0)),"难度补领" if int(daily_award.get("previousPaid",0))>0 else "每日首通",int(daily_award.amount)]
			_label(daily_row,award_text,15,GOLD,true).name="SettlementDailyAwardText"
		if result.get("firstClear",false):
			var first:=_hbox(scroll_content,7);_rune_icon(first,"check",18,CYAN);_label(first,"首次通关",14,CYAN)
		var relic:Dictionary=result.get("relic",{})
		if relic.is_empty() and rewards.get("relicDrop") is Dictionary:relic=rewards.relicDrop
		if not relic.is_empty():
			var loot:=_hbox(_panel(scroll_content,_rarity_color(int(relic.get("rarity",3))).darkened(.5),10),12)
			loot.name="SettlementRelic"
			var art:=_relic_item_art(loot,relic,56);art.custom_minimum_size.x=56;art.size_flags_horizontal=Control.SIZE_FILL
			var copy:=_vbox(loot,4);copy.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			_label(copy,_relic_set_name(relic)+" · "+_slot_name(str(relic.get("slotId","helmet"))),18,TEXT,true)
			_label(copy,"★".repeat(int(relic.get("rarity",3))),13,_rarity_color(int(relic.get("rarity",3))))
			_label(copy,"已收入遗物背包",12,MUTED)
		if battle_config.get("isAbyss",false):
			var run_rewards:=_grid(scroll_content,1 if run_ended else 2)
			if not run_ended:_settlement_reward_tile(run_rewards,"rift_coin","裂隙币 · 本轮",int(rewards.get("runCoins",0)),"runCoins")
			_settlement_reward_tile(run_rewards,"memory_shard","记忆 · 永久",int(rewards.get("meta",0)),"meta")
		var gift=result.get("gift")
		if gift is Dictionary and not gift.is_empty():
			var giftrow:=_hbox(_panel(scroll_content,GOLD.darkened(.5),10),10)
			_rune_icon(giftrow,"star",28,GOLD)
			_label(giftrow,"章节赠礼 · "+str(gift.get("charName",gift.get("name","五星旅者加入"))),17,GOLD,true)
		for progress in result.get("progression",[]):
			if int(progress.get("leveledUp",0))<=0:continue
			var growth:=_hbox(scroll_content,8)
			var portrait:=_portrait(growth,str(progress.get("charId","ember")),36);portrait.custom_minimum_size.x=36;portrait.size_flags_horizontal=Control.SIZE_FILL
			_label(growth,_char_name(str(progress.get("charId",""))),14,TEXT).size_flags_horizontal=Control.SIZE_EXPAND_FILL
			_rune_icon(growth,"upgrade",18,CYAN)
			_label(growth,"等级 %d" % int(progress.get("newLevel",1)),16,CYAN)
	else:
		var recovery:=_vbox(_panel(scroll_content,LINE,16),12)
		_rune_icon(recovery,"camp",48,CYAN)
		_label(recovery,"回到营地，再次出发",22,TEXT)
		_label(recovery,"训练旅者、强化遗物，带着新的准备继续挑战。",16,MUTED,true)
	if run_ended and not result.get("lastRun",{}).is_empty():
		var summary:Dictionary=result.lastRun
		var endrow:=_hbox(scroll_content,8);_rune_icon(endrow,"path",24,CYAN)
		_label(endrow,"本轮通关 %d 层 · 获得 %d 记忆碎片" % [int(summary.get("floorsCleared",0)),int(summary.get("metaEarned",0))],16,CYAN,true)
	var proceed:=_button(_modal_footer(box), "返回营地 · 继续旅程   →" if run_ended else "继续旅程   →", func():
		_clear_overlay()
		var next_screen := "abyss" if battle_config.get("isAbyss", false) else "story"
		var key: String = str(battle_config.get("id", "")) + "_post"
		if victory and not battle_config.get("isAbyss", false) and not model.state.get("dialogueSeen", {}).get(key, false):
			_play_dialogue(key, func(): navigate(next_screen))
		else:
			navigate(next_screen), true)
	proceed.name="BattleSettlementContinue"
	_button_icon(proceed,"next",true)

func _settlement_reward_tile(parent:Node,icon_key:String,caption:String,amount:int,key:String) -> void:
	var card:=_panel(parent,LINE,10)
	var row:=_hbox(card,9)
	var icon:=_rune_icon(row,icon_key,30)
	if icon_key=="essence":icon.texture=_relic_texture("essence")
	var copy:=_vbox(row,3)
	_label(copy,caption,12,MUTED)
	_label(copy,"+%d" % amount,22,TEXT).name="SettlementReward_"+key

func _extraction_result_stat(parent: Node, icon_key: String, value: String, caption: String) -> void:
	var card := _panel(parent, LINE, 12)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var contents := _vbox(card, 5)
	var image_row := _hbox(contents, 0)
	image_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_rune_icon(image_row, icon_key, 28, GOLD)
	_center_label(contents, value, 18, TEXT)
	_center_label(contents, caption, 12, MUTED)

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
	if dialogue_tween:dialogue_tween.kill()
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
	margin.offset_top = -270
	margin.offset_bottom = -20
	margin.offset_left = 36
	margin.offset_right = -36
	overlay.add_child(margin)
	var p := _panel(margin, GOLD.darkened(0.35), 20)
	p.add_theme_stylebox_override("panel", _box(Color(0.035, 0.06, 0.10, 0.96), GOLD.darkened(0.5), 20))
	var v := _vbox(p, 10)
	var speaker_name: String = line.get("speakerName", _char_name(speaker))
	if speaker == "narrator": speaker_name = "旅者纪事"
	if speaker == "traveler": speaker_name = "旅行者"
	var identity:=_hbox(v,8)
	var speaker_color:Color=_element_color(line.get("element","fire")) if speaker!="narrator" else GOLD
	_rune_icon(identity,"book" if speaker=="narrator" else {"fire":"fire","water":"ice","wind":"leaf","thunder":"energy"}.get(str(line.get("element","")),"star"),22,speaker_color)
	_label(identity,speaker_name,20,speaker_color)
	var prose := _label(v, line.get("text", ""), 20, TEXT, true)
	prose.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dialogue_prose = prose
	prose.name="DialogueProse"
	_bind_card_tap(prose,_next_dialogue)
	prose.visible_characters = 0
	dialogue_tween = create_tween()
	dialogue_tween.tween_property(prose, "visible_characters", str(line.get("text", "")).length(), minf(1.5, str(line.get("text", "")).length() * 0.023))
	var row := _hbox(v, 15)
	_label(row, "%d / %d" % [dialogue_index + 1, dialogue_lines.size()], 13, MUTED)
	var space := Control.new()
	space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(space)
	var skip:=_button(overlay,"跳过剧情",_finish_dialogue)
	skip.name="DialogueSkip"
	skip.position=Vector2(size.x-160,18)
	skip.custom_minimum_size=Vector2(124,44)
	_button_icon(skip,"skip")
	var next:=_button(row,"继续" if dialogue_index < dialogue_lines.size()-1 else "踏上旅途",_next_dialogue,true)
	next.name="DialogueNext"
	_button_icon(next,"next",true)

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
	dialogue_prose.name="DialogueProse"
	_bind_card_tap(dialogue_prose,_next_dialogue)
	dialogue_prose.visible_characters = 0
	if dialogue_tween: dialogue_tween.kill()
	dialogue_tween = create_tween()
	dialogue_tween.tween_property(dialogue_prose, "visible_characters", dialogue_prose.text.length(), minf(1.5, dialogue_prose.text.length() * 0.023))
	var footer := _modal_footer(v)
	_label(footer, "%d / %d" % [dialogue_index + 1, dialogue_lines.size()], 14, MUTED)
	var actions := _flow(footer, 8)
	_button(actions, "跳过剧情", _finish_dialogue).name="DialogueSkip"
	_button(actions, "继续 →" if dialogue_index < dialogue_lines.size() - 1 else "踏上旅途 →", _next_dialogue, true).name="DialogueNext"

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
	for state_name in ["normal","hover","pressed","disabled"]:
		b.add_theme_stylebox_override(state_name,RuneTheme.button_style(primary,state_name))
	b.add_theme_stylebox_override("focus",_box(Color(0,0,0,0),CYAN,0))
	b.add_theme_constant_override("h_separation",7)
	var rune:String={"‹ 返回":"back","菜单":"menu","继续旅程":"path","保存出战队伍":"check","开始探索":"sword","概率与规则":"book"}.get(text,"")
	if not rune.is_empty():
		_button_icon(b,rune,primary)
		if rune=="back":b.text="返回"
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

func _portrait(parent: Node, id: String, height: float, _wide: bool = false, enemy: bool = false, avatar_style: String = "") -> Control:
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
		var style:String=avatar_style if not avatar_style.is_empty() else ("face" if height>0 and height<=80 and not _wide else "")
		var avatar:Texture2D=CharacterAvatars.get_texture(id,style) if not enemy and not style.is_empty() else null
		t.texture = avatar if avatar!=null else load(path)
		c.set_meta("portrait_mode",style if avatar!=null else "full")
		c.set_meta("portrait_id",id)
		t.name="CharacterPortraitTexture"
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
	var portrait:=_portrait_environment(v, id, art_height,"","bust")
	_character_ownership_badge(v,id)
	if not owned:portrait.modulate=Color(0.64,0.68,0.76,0.8)
	_label(v, "★".repeat(rarity) + "   " + _element_name(data.get("element", "")), 11, color)
	_label(v, data.get("name", id), 18, TEXT)
	_label(v, "等级 %d   ·   %s" % [model.state.ownedCharacters.get(id, {}).get("level", 1), model.catalog.RoleNames.get(data.get("role", ""), "")] if owned else "未拥有 · 可查看完整档案", 12, MUTED)
	if action.is_valid():
		p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_bind_card_tap(p, action)
		_ignore_children(v)
	return p

func _character_ownership_badge(parent: Node, id: String, small: bool=false) -> void:
	var owned:bool=model.state.ownedCharacters.has(id)
	var color:Color=CYAN if owned else MUTED
	var badge:=_panel(parent,color.darkened(0.65),3 if small else 5)
	badge.name="CharacterOwned_"+id if owned else "CharacterLocked_"+id
	badge.add_theme_stylebox_override("panel",_box(Color("163b3d") if owned else Color("232732"),color.darkened(0.6),3))
	var row:=_hbox(badge,4)
	_rune_icon(row,"check" if owned else "lock",12 if small else 16,color)
	_label(row,"已拥有" if owned else "未获得",10 if small else 12,color)
	if owned and not small:
		_label(row,"Lv.%d" % int(model.state.ownedCharacters[id].get("level",1)),12,TEXT)

func _restore_character_list(scroll: ScrollContainer, key: String) -> void:
	# Capture state continuously, then restore only after the new list is laid out.
	# Detached old controls cannot overwrite the remembered position during teardown.
	var desired:int=int(character_list_positions.get(key,0))
	var tree:=get_tree()
	await tree.process_frame
	await tree.process_frame
	if not is_instance_valid(scroll) or not scroll.is_inside_tree():return
	scroll.scroll_vertical=desired
	character_list_positions[key]=scroll.scroll_vertical
	scroll.get_v_scroll_bar().value_changed.connect(func(value:float):
		if is_instance_valid(scroll) and scroll.is_inside_tree():character_list_positions[key]=int(value))

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
	if OS.has_feature("mobile"):
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
	_clear(toast_layer)
	var p := PanelContainer.new()
	p.name="FeedbackToast"
	p.add_theme_stylebox_override("panel", _box(Color("142235"), color.darkened(0.3), 10))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_layer.add_child(p)
	var l := _label(p, message, 15, color, true)
	var measured:=FONT.get_string_size(message,HORIZONTAL_ALIGNMENT_LEFT,-1,15).x
	l.custom_minimum_size.x = clampf(measured+8,160,minf(size.x-64,460))
	p.position = Vector2(maxf(12,(size.x-l.custom_minimum_size.x-20)/2),64)
	var tween := create_tween().bind_node(p)
	tween.tween_interval(1.8)
	tween.tween_property(p, "modulate:a", 0.0, 0.25)
	tween.tween_callback(p.queue_free)

func _float_text(at: Vector2, value: String, color: Color, font_size: int = 25) -> void:
	var l := _label(fx, value, font_size, color)
	l.add_theme_constant_override("outline_size", 5)
	l.add_theme_color_override("font_outline_color", INK)
	l.position = at - Vector2(30, 0)
	var tween := create_tween().set_parallel()
	if not extraction_reduced_motion:tween.tween_property(l, "position:y", l.position.y - 75, 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
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

func _relic_texture(slot_id: String, set_id: String = "") -> Texture2D:
	var definition:Dictionary=model.catalog.get("RelicSets",{}).get(set_id,{})
	var set_path:String=str(definition.get("slotIcons",{}).get(slot_id,""))
	if not set_path.is_empty() and ResourceLoader.exists(set_path):return load(set_path)
	var path:="res://assets/ui/relics/"+slot_id+".png"
	return load(path) if ResourceLoader.exists(path) else _icon_texture("gear")

func _relic_art(parent: Node, slot_id: String, edge: float, set_id: String = "") -> TextureRect:
	var image:=TextureRect.new();image.texture=_relic_texture(slot_id,set_id)
	image.name="RelicArt_"+slot_id
	image.set_meta("relic_set_id",set_id)
	image.custom_minimum_size=Vector2(edge,edge)
	image.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;image.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.size_flags_horizontal=Control.SIZE_EXPAND_FILL;image.mouse_filter=Control.MOUSE_FILTER_IGNORE
	parent.add_child(image);return image

func _relic_item_art(parent: Node, relic: Dictionary, edge: float) -> TextureRect:
	return _relic_art(parent,str(relic.get("slotId","helmet")),edge,str(relic.get("setId","")))

func _relic_set_name(relic: Dictionary) -> String:
	return str(model.catalog.get("RelicSets",{}).get(str(relic.get("setId","")),{}).get("name","散件"))

func _relic_set_details(parent: Node, set_id: String, active_count: int = -1) -> void:
	var definition:Dictionary=model.catalog.get("RelicSets",{}).get(set_id,{})
	if definition.is_empty():
		_label(parent,"散件 · 自由搭配",13,MUTED,true)
		return
	for bonus in definition.get("bonuses",[]):
		var pieces:int=int(bonus.get("pieces",0))
		var active:bool=active_count>=pieces
		var line:=_hbox(parent,7)
		var marker:=_label(line,"%d 件"%pieces,12,CYAN if active else GOLD)
		marker.custom_minimum_size.x=32
		_label(line,str(bonus.get("description","")),13,TEXT if active or active_count<0 else MUTED,true).size_flags_horizontal=Control.SIZE_EXPAND_FILL

func _auto_relic_loadout(char_id: String = "") -> void:
	load("res://scripts/ui/relic_loadout_view.gd").show_for(self,char_id)

func _stat_icon(stat: String) -> String:
	if stat.begins_with("hp"):return "heart"
	if stat.begins_with("atk"):return "sword"
	if stat.begins_with("def"):return "shield"
	if stat.begins_with("cri"):return "crit"
	if stat.begins_with("energy"):return "energy"
	if stat=="spd":return "wind"
	return "star"

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
	return _stat_label(str(stat.get("stat", "")),str(stat.get("name", "属性"))) + " +" + _stat_value(str(stat.get("stat", "")), value)

func _stat_label(stat: String, fallback: String="属性") -> String:
	return str({"hp_flat":"生命","hp_pct":"生命加成","atk_flat":"攻击","atk_pct":"攻击加成","def_flat":"防御","def_pct":"防御加成","spd":"速度","cri_rate":"暴击率","cri_dmg":"暴击伤害","energy_rate":"能量恢复"}.get(stat,fallback))

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
		var reward: Dictionary = _present_abyss_reward(raw)
		var card:=_panel(box,LINE,12)
		var contents:=_vbox(card,6)
		preload("res://scripts/ui/reward_rarity.gd").decorate(self,card,contents,str(reward.get("rarity","white")))
		var row:=_hbox(contents,12)
		_rune_icon(row,RuneTheme.effect_key(reward),40,GOLD)
		var copy:=_vbox(row,5);copy.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		_label(copy, str(reward.get("name", "回响")), 20, GOLD)
		_label(copy, str(reward.get("description", "")), 15, TEXT, true)
	if model.state.abyss.rogue.get("selectedRewards", []).is_empty():
		_rune_icon(box,"star",52,MUTED)
		_label(box, "继续挑战，收集新的回响。", 17, MUTED, true)
	_button_icon(_button(_modal_footer(box), "回到战斗", _clear_overlay, true),"back",true)

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
	var status_view = load("res://scripts/ui/battle_status_strip.gd")
	_label(box, "感电：" + status_view.status_description({"id":"electrify"}, model.catalog), 16, CYAN, true).name="BattleRulesElectrify"
	_label(box, "冰冻、眩晕按完整持续时间生效。中毒可以叠加，每层在回合末造成最大生命 5% 的伤害。首领战超过 20 回合后，每回合攻击提升 5%，上限为 100%。", 16, MUTED, true)
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
		duck.tween_property(music_audio,"volume_db",_music_gain(music_audio)-6,0.08)
		duck.tween_interval(0.35)
		duck.tween_property(music_audio,"volume_db",_music_gain(music_audio),0.5)

func _extraction_stop_search_audio() -> void:
	if is_instance_valid(extraction_search_audio): extraction_search_audio.stop()
	if is_instance_valid(music_audio) and music_audio.has_meta("duck_tween"):
		var duck=music_audio.get_meta("duck_tween")
		if duck is Tween and duck.is_valid():
			duck.kill();music_audio.volume_db=_music_gain(music_audio)


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

func _music_gain(player: AudioStreamPlayer) -> float:
	return music_volume_db-2.0 if str(player.get_meta("track",""))=="determined_pursuit" else music_volume_db

func _music_cancel_tween(player: AudioStreamPlayer, key: String) -> void:
	var tween=player.get_meta(key) if player.has_meta(key) else null
	if tween is Tween and tween.is_valid():tween.kill()

func _music_fade_to(player: AudioStreamPlayer, volume: float, pause_after: bool=false) -> void:
	_music_cancel_tween(player,"music_fade")
	_music_cancel_tween(player,"duck_tween")
	var fade:=player.create_tween()
	player.set_meta("music_fade",fade)
	fade.tween_property(player,"volume_db",volume,1.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if pause_after:
		fade.tween_callback(func():
			if is_instance_valid(player) and player!=music_audio:player.stream_paused=true)

func _sync_music() -> void:
	var track:=_music_track_for_context()
	if not music_enabled:
		for player in _music_pool.values():
			if is_instance_valid(player):
				_music_cancel_tween(player,"music_fade");_music_cancel_tween(player,"duck_tween")
				player.stream_paused=true
		return
	var path:="res://assets/audio/music/licensed/"+track+".ogg"
	if not ResourceLoader.exists(path):return
	var target:AudioStreamPlayer=_music_pool.get(track)
	if not is_instance_valid(target):
		target=AudioStreamPlayer.new();target.set_meta("track",track)
		var stream:AudioStreamOggVorbis=load(path).duplicate();stream.loop=true
		target.stream=stream;target.volume_db=-60
		add_child(target);_music_pool[track]=target
	if music_audio==target:
		var was_paused:bool=target.stream_paused
		if not target.playing:target.play()
		target.stream_paused=bool(get_meta("application_paused",false))
		if was_paused and not target.stream_paused:_music_fade_to(target,_music_gain(target))
		return
	var old:=music_audio
	music_audio=target
	# Reusing the player preserves the exact cursor across a boss encounter or
	# a trip to the camp. Only the two sides of the current transition may sound.
	for other in _music_pool.values():
		if other!=target and other!=old:
			_music_cancel_tween(other,"music_fade");_music_cancel_tween(other,"duck_tween")
			other.stream_paused=true
	_music_cancel_tween(target,"music_fade")
	if not target.playing:target.play()
	target.stream_paused=bool(get_meta("application_paused",false))
	_music_fade_to(target,_music_gain(target))
	if is_instance_valid(old):_music_fade_to(old,-60.0,true)

func _ui_sound(clip: String = "tap") -> void:
	if not sound_enabled:return
	var now:=Time.get_ticks_msec()
	if now-_last_ui_sound_msec<65 and (clip==_last_ui_sound_clip or clip=="tap"):return
	_last_ui_sound_msec=now
	_last_ui_sound_clip=clip
	var path := "res://assets/audio/ui/"+clip+".ogg"
	if not ResourceLoader.exists(path): return
	if not is_instance_valid(ui_audio):
		ui_audio = AudioStreamPlayer.new()
		ui_audio.volume_db = effects_volume_db-(13 if clip in ["tap","back"] else 8)
		add_child(ui_audio)
	ui_audio.volume_db = effects_volume_db-(13 if clip in ["tap","back"] else 8)
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
					_music_cancel_tween(music_audio,"music_fade")
					music_audio.volume_db=_music_gain(music_audio)
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
	for value in [["生命","%d / %d" % [unit.get("currentHp",0),unit.get("maxHp",0)]],["攻击",unit.get("stats",{}).get("atk",0)],["防御",unit.get("stats",{}).get("def",0)]]:
		var tile:=_panel(stats,LINE,10);var v:=_vbox(tile,5)
		_rune_icon(v,{"生命":"heart","攻击":"sword","防御":"shield"}.get(str(value[0]),"star"),24,CYAN)
		_label(v,str(value[0]),13,MUTED)
		_label(v,str(value[1]),20,TEXT).name="BattleDetail_"+str({"生命":"hp","攻击":"atk","防御":"def"}.get(str(value[0]),"stat"))
	if float(unit.get("shield",0))>0:_label(box,"护盾 %d" % int(unit.shield),15,CYAN)
	var status_view = load("res://scripts/ui/battle_status_strip.gd")
	for status in unit.get("statuses",[]):
		var row:=_panel(box,LINE,10)
		var content:=_vbox(row,4)
		var heading:=_hbox(content,7)
		var status_id:=str(status.get("id",""))
		var asset_id:="electrify" if status_id=="shock" else status_id
		var asset_path:="res://assets/ui/status/%s.svg"%asset_id
		var icon:=_rune_icon(heading,"star",22)
		icon.texture=load(asset_path if ResourceLoader.exists(asset_path) else "res://assets/ui/status/unknown.svg")
		if status.get("source","")=="expedition_equipment":
			_label(heading,"装备护盾 · 剩余 %d" % int(status.get("shieldHp",0)),15,CYAN,true)
		else:
			var title:=_label(heading,"%s · 剩余 %d 回合 · %d 层" % [STATUS_NAMES.get(status_id,status_id),int(status.get("duration",0)),int(status.get("stacks",1))],15,GOLD,true)
			title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		_label(content,status_view.status_description(status,model.catalog),13,MUTED,true).name="BattleStatusDetail_"+status_id
	if unit.get("statuses",[]).is_empty():_label(box,"当前没有持续状态",15,MUTED)
	_button(_modal_footer(box),"返回战场",_clear_overlay,true)

func _show_music_credits() -> void:
	var box:=_modal("音乐鸣谢",620,380)
	for entry in [["Medieval Exploration","RandomMind"],["Sunset Walk","KiluaBoy"],["Determined Pursuit","Emma_MA"],["Old Tower Inn","RandomMind"],["Dungeon Mystic","FazeDevWater"]]:
		var card:=_vbox(_panel(box,LINE,12),4)
		_label(card,entry[0],18,GOLD)
		_label(card,entry[1]+" · CC0",14,MUTED)
	_button(_modal_footer(box),"返回",_show_audio_settings)

func _stop_reveal_voices() -> void:
	for voice in get_tree().get_nodes_in_group("transient_audio"):
		voice.stop();voice.stream=null;voice.remove_from_group("transient_audio");voice.queue_free()

func _icon_texture(key:String)->Texture2D:
	if key in ["rift_coin","memory_shard"]:
		var currency_path:="res://assets/ui/currency/"+key+".png"
		if ResourceLoader.exists(currency_path):return load(currency_path)
	var path:="res://assets/ui/runes/"+key+".svg"
	return load(path) if ResourceLoader.exists(path) else load("res://assets/ui/runes/star.svg")

func _rune_icon(parent:Node,key:String,edge:int=24,tint:Color=Color.WHITE)->TextureRect:
	var icon:=TextureRect.new()
	icon.texture=_icon_texture(key)
	icon.custom_minimum_size=Vector2(edge,edge)
	icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	icon.modulate=tint
	icon.mouse_filter=Control.MOUSE_FILTER_IGNORE
	parent.add_child(icon)
	return icon

func _button_icon(button:Button,key:String,primary:bool=false)->void:
	button.icon=_icon_texture(key)
	button.add_theme_constant_override("icon_max_width",18)
	button.expand_icon=false
	var colored:bool=key in ["coin","gem","energy","rift_coin","memory_shard"]
	button.add_theme_color_override("icon_normal_color",Color.WHITE if colored else INK if primary else TEXT)
	button.add_theme_color_override("icon_hover_color",Color.WHITE if colored else INK if primary else Color.WHITE)
	button.add_theme_color_override("icon_pressed_color",Color.WHITE if colored else INK if primary else GOLD)

func _exploration_music_track(deep: bool) -> String:
	return "dungeon_mystic" if deep else "sunset_walk"

func _music_track_for_context() -> String:
	# Functional pages inherit the scene they were opened from. Inventory,
	# upgrades, shops, menus and previews never choose a new score themselves.
	if current_screen=="home":_music_context_id="hub"
	elif current_screen=="story":_music_context_id="story"
	elif current_screen=="extraction":_music_context_id="extraction" if model.extraction.active() else "story"
	elif current_screen=="abyss":_music_context_id="abyss"
	elif current_screen=="battle":
		_music_context_id="extraction" if battle_config.get("isExtraction",false) else "abyss" if battle_config.get("isAbyss",false) else "story"
		var boss:bool=battle_config.get("kind","")=="boss" or battle_config.get("isBoss",false)
		for enemy_id in battle_config.get("enemies",[]):
			if str(enemy_id).begins_with("boss_"):boss=true
		if boss:return "determined_pursuit"
	match _music_context_id:
		"extraction":
			if not model.extraction.active():return "medieval_exploration"
			return model.extraction.environment_music_track()
		"abyss":return _exploration_music_track(int(model.state.abyss.get("currentFloor",1))>10)
		"story":return "medieval_exploration"
	return "old_tower_inn"

func _story_chip(parent:Node,key:String,caption:String,value:String,color:Color)->void:
	var row:=_hbox(_panel(parent,color.darkened(0.65),5),5)
	_rune_icon(row,key,20)
	_label(row,caption,11,MUTED)
	_label(row,value,13,color)

func _tab_button(parent:Node,text:String,action:Callable,selected:bool=false)->Button:
	var b:=_button(parent,text,action)
	for state in ["normal","hover","pressed","disabled"]:
		var style:=StyleBoxFlat.new()
		style.bg_color=Color(.14,.21,.29,.65 if selected else .14)
		style.border_color=GOLD if selected else (CYAN if state=="hover" else Color(0,0,0,0))
		style.border_width_bottom=3 if selected else 1
		style.content_margin_left=16;style.content_margin_right=16;style.content_margin_top=8;style.content_margin_bottom=8
		b.add_theme_stylebox_override(state,style)
	b.add_theme_color_override("font_color",GOLD if selected else MUTED)
	return b

func _tool_button(parent:Node,key:String,tooltip:String,action:Callable)->Button:
	var b:=_button(parent,"",action)
	b.custom_minimum_size=Vector2(44,44)
	b.tooltip_text=tooltip
	_button_icon(b,key)
	for state in ["normal","hover","pressed"]:
		var style:=_box(Color(.08,.14,.2,.3 if state=="normal" else .8),Color(0,0,0,0) if state=="normal" else CYAN.darkened(.5),8)
		style.set_corner_radius_all(22)
		b.add_theme_stylebox_override(state,style)
	return b

func _portrait_environment(parent:Node,id:String,height:float=240,background_path:String="",avatar_style:String="")->Control:
	var element:=str(model.catalog.CharacterData.get(id,{}).get("element","water"))
	var tint:=_element_color(element)
	var stage:=Control.new()
	stage.name="PortraitEnvironment_"+id
	stage.custom_minimum_size.y=height
	stage.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	stage.size_flags_vertical=Control.SIZE_EXPAND_FILL
	stage.clip_contents=true
	stage.mouse_filter=Control.MOUSE_FILTER_IGNORE
	parent.add_child(stage)
	var path:=background_path
	if path.is_empty():path={"fire":"res://assets/wilderness.png","water":"res://assets/backgrounds/snowfield.png","wind":"res://assets/backgrounds/camp.png","thunder":"res://assets/backgrounds/abyss.png"}.get(element,"res://assets/backgrounds/abyss.png")
	var backdrop:=TextureRect.new();backdrop.texture=load(path)
	backdrop.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;backdrop.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);backdrop.modulate=Color(.53,.58,.68)
	backdrop.mouse_filter=Control.MOUSE_FILTER_IGNORE;stage.add_child(backdrop)
	var gradient:=Gradient.new();gradient.set_color(0,Color(tint,.22));gradient.set_color(1,Color(.025,.04,.09,.1))
	var glow:=GradientTexture2D.new();glow.gradient=gradient;glow.fill=GradientTexture2D.FILL_RADIAL;glow.fill_from=Vector2(.5,.45);glow.fill_to=Vector2(1,.9)
	var light:=TextureRect.new();light.texture=glow;light.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);light.mouse_filter=Control.MOUSE_FILTER_IGNORE;stage.add_child(light)
	var aura=load("res://scripts/ui/character_aura.gd").new();aura.tint=tint.lightened(.25);aura.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);stage.add_child(aura)
	var portrait:=_portrait(stage,id,0,false,false,avatar_style)
	portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	portrait.offset_top=8;portrait.offset_bottom=-8
	return stage

func _summon_cta(parent:Node,amount:int,cost:int,action:Callable)->Button:
	var b:=_button(parent,"",action,amount==10)
	b.name="SummonPull_"+str(amount)
	b.custom_minimum_size=Vector2(145,78)
	b.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var content:=_hbox(b,10);content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left=16;content.offset_right=-16;content.offset_top=8;content.offset_bottom=-8
	_rune_icon(content,"star" if amount==10 else "gem",30,INK if amount==10 else CYAN)
	var copy:=_vbox(content,2);copy.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_label(copy,"十连祈愿" if amount==10 else "单次祈愿",19,INK if amount==10 else TEXT)
	var price:=_hbox(copy,4);_rune_icon(price,"gem",16)
	_label(price,str(cost),13,INK if amount==10 else MUTED)
	_ignore_children(content)
	return b
