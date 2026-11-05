extends Control
## Presentation consumes an immutable copy of an already committed pull.
## No timers/tweens own the state: a visible-frame clock and epoch drive every stage.
const Avatars = preload("res://scripts/ui/character_avatar.gd")
const CharacterBust = preload("res://scripts/ui/character_bust.gd")
const OPENING := 0.85
const CONSTELLATION := 1.05
const SEAL := 0.52
const UNSEAL := 0.72
const LEGENDARY := 0.9
const PORTRAIT := 0.62
const SUMMARY_STAGGER := 0.075
var app
var results: Array = []
var pool_id := ""
var reduced_motion := false
var stage := "preparing"
var stage_epoch := 0
var stage_time := 0.0
var sequence_time := 0.0
var index := 0
var stage_history: Array = []
var _ready_frames := 0
var _focus_paused := false
var _gesture_serial := 0
var _consumed_serial := 0
var _gesture_epoch := -1
var _last_touch_msec := -10000
var _cooldown_until := 0.0
var _committed_slot := 0
var _voice: AudioStreamPlayer
var _audio_history: Array = []
var _art: Array[Texture2D] = []
var _background: Texture2D
var _portrait: CharacterBust
var _copy: VBoxContainer
var _title: Label
var _subtitle: Label
var _counter: Label
var _hint: Label
var _skip: Button
var _next: Button
var _details: Button
var _accept: Button
var _again: Button
var _wallet: HBoxContainer
var _balance: Label
var _repeat_cost: Label
var _cards: Array[Control] = []
var _summary: Control
var _preview: Control
var _safe := Rect2()
var _art_rect := Rect2()
var _copy_rect := Rect2()

func setup(owner_app, committed_results: Array, selected_pool: String, gentle: bool) -> void:
	app = owner_app
	results = committed_results.duplicate(true)
	pool_id = selected_pool
	_committed_slot = int(app.model.active_slot)
	reduced_motion = gentle
	name = "SummonSequence"
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var fallback := "res://assets/content_v270/banner/selin_banner.png" if selected_pool == "limited_selin" else "res://assets/backgrounds/summon_sanctum.png"
	var selected: Dictionary = app.model.catalog.GachaPoolData.pools.get(selected_pool, {})
	var background_path: String = str(selected.get("bannerPath", fallback))
	_background = load(background_path if ResourceLoader.exists(background_path) else fallback)
	for result in results:
		var bust: Texture2D = Avatars.get_texture(str(result.charId), "bust")
		_art.append(bust if bust != null else load(Avatars.source_path(str(result.charId))))

func _ready() -> void:
	_build()
	resized.connect(_layout)
	_layout()
	# Texture uploads and layout are observed before any sequence time is spent.
	_wait_for_visible_frames.call_deferred(stage_epoch)

func _wait_for_visible_frames(epoch: int) -> void:
	for frame in 2:
		await get_tree().process_frame
		if not is_inside_tree() or stage_epoch != epoch: return
		queue_redraw()
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			if not is_inside_tree() or stage_epoch != epoch: return
		_ready_frames += 1
	_enter("opening")

func _exit_tree() -> void:
	stage_epoch += 1
	set_process(false)
	set_process_input(false)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_focus_paused = true
		if is_instance_valid(_voice): _voice.stop()
	elif what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_focus_paused = false

func _input(event: InputEvent) -> void:
	if not visible: return
	if event is InputEventScreenTouch and event.pressed:
		_last_touch_msec = Time.get_ticks_msec()
		_gesture_serial += 1
		_gesture_epoch = stage_epoch
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# A touch and its emulated mouse press share one gesture identity.
		if event.device != InputEvent.DEVICE_ID_EMULATION or Time.get_ticks_msec() - _last_touch_msec > 120:
			_gesture_serial += 1
			_gesture_epoch = stage_epoch
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ENTER, KEY_SPACE]:
		_gesture_serial += 1
		_gesture_epoch = stage_epoch

func _process(delta: float) -> void:
	if int(app.model.active_slot) != _committed_slot:
		app._clear_overlay()
		return
	if stage == "preparing" or _focus_paused or bool(app.get_meta("application_paused", false)) or is_instance_valid(_preview): return
	# A stalled/resumed renderer never consumes unseen animation in one frame.
	var visible_delta := minf(delta, 0.05)
	stage_time += visible_delta
	sequence_time += visible_delta
	match stage:
		"opening":
			if stage_time >= OPENING: _enter("constellation")
		"constellation":
			if stage_time >= (0.8 if reduced_motion else CONSTELLATION): _enter("seal")
		"seal":
			if stage_time >= SEAL: _enter("unseal")
		"unseal":
			if stage_time >= UNSEAL: _enter("legendary" if rarity() == 5 else "portrait")
		"legendary":
			if stage_time >= LEGENDARY: _enter("portrait")
		"portrait":
			if stage_time >= PORTRAIT: _enter("result")
		"result":
			if results.size() > 1 and stage_time >= (2.25 if rarity() == 5 else 1.7): _advance()
	_update_visuals()
	queue_redraw()

func rarity() -> int:
	return int(app.model.catalog.CharacterData[results[index].charId].rarity)

func tint() -> Color:
	return Color("efbf72") if rarity() == 5 else (Color("be9bec") if rarity() == 4 else Color("80cbdc"))

func debug_state() -> Dictionary:
	var durations := {"preparing":1.0,"opening":OPENING,"constellation":0.8 if reduced_motion else CONSTELLATION,"seal":SEAL,"unseal":UNSEAL,"legendary":LEGENDARY,"portrait":PORTRAIT,"result":2.25 if rarity()==5 else 1.7,"summary":(results.size()-1)*SUMMARY_STAGGER+.45}
	return {"stage":stage,"epoch":stage_epoch,"stage_time":stage_time,"progress":clampf(stage_time/float(durations[stage]),0,1),"sequence_time":sequence_time,"index":index,"ready_frames":_ready_frames,"rarity":rarity(),"reduced_motion":reduced_motion,"paused":_focus_paused or bool(app.get_meta("application_paused",false)),"visible_cards":_cards.filter(func(card):return card.modulate.a > 0.98).size()}

func _enter(next_stage: String) -> void:
	stage_epoch += 1
	stage = next_stage
	stage_time = 0.0
	stage_history.append({"stage":stage,"time":sequence_time,"epoch":stage_epoch,"index":index})
	app.summon_index = index
	app.summon_flipped = stage in ["portrait", "result", "summary"]
	if stage == "legendary": _play_reveal(5)
	if stage == "portrait" and rarity() < 5: _play_reveal(rarity())
	if stage == "summary":
		if is_instance_valid(_voice): _voice.stop()
		var highest := 3
		for result in results: highest = maxi(highest,int(result.rarity))
		_play_reveal(highest)
		_build_summary()
	_update_copy()
	_update_visuals()

func _play_reveal(quality: int) -> void:
	if not app.sound_enabled: return
	if not is_instance_valid(_voice):
		_voice = AudioStreamPlayer.new()
		_voice.name = "SummonRevealVoice"
		add_child(_voice)
	_voice.stop()
	_voice.stream = load("res://assets/audio/extraction/%s.mp3" % ("gold" if quality == 5 else ("purple" if quality == 4 else "common")))
	_voice.volume_db = app.effects_volume_db - 8
	_voice.play()
	_audio_history.append({"stage":stage,"epoch":stage_epoch,"index":index,"rarity":quality,"time":sequence_time})

func _advance() -> void:
	if index + 1 >= results.size():
		show_summary()
	else:
		index += 1
		_portrait.configure(str(results[index].charId))
		_enter("seal")

func show_summary() -> void:
	if stage == "summary": return
	_enter("summary")

func _action(button: Button, action: String) -> void:
	if button.disabled: return
	if is_instance_valid(_preview) and action != "preview_close": return
	var armed: Dictionary = button.get_meta("summon_gesture", {})
	if armed.is_empty() or int(armed.epoch) != stage_epoch or int(armed.serial) <= _consumed_serial: return
	# Preview pauses sequence_time, so its close action must not wait on that clock.
	# Epoch and gesture checks above still reject stale or duplicate input.
	if (action != "preview_close" and sequence_time < _cooldown_until) or stage == "preparing": return
	if stage == "opening" and stage_time < 0.55: return
	if stage == "summary" and stage_time < 0.35: return
	_consumed_serial = int(armed.serial)
	_cooldown_until = sequence_time + 0.32
	match action:
		"skip": show_summary()
		"next":
			if stage == "result": _advance()
		"details": _show_preview(str(results[index].charId))
		"accept":
			app._clear_overlay()
			app._render_screen()
		"again":
			# Recheck the current wallet before dismissing this committed result.
			var pool: Dictionary = app.model.catalog.GachaPoolData.pools[pool_id]
			if int(app.model.state.resources.get(pool.currency, 0)) < int(pool.costPerPull) * results.size():
				_update_visuals()
				return
			var amount := results.size()
			app._clear_overlay()
			app._pull(amount)
		"preview_close":
			_preview.queue_free()
			_preview = null
			stage_epoch += 1
			_update_visuals()

func _button(parent: Node, title: String, node_name: String, action: String, icon: String, primary := false) -> Button:
	var button: Button = app._button(parent, title, Callable(), primary)
	# Own callbacks use the shared deferred GUI dispatcher and stage-bound gestures.
	for connection in button.pressed.get_connections(): button.pressed.disconnect(connection.callable)
	button.name = node_name
	app._button_icon(button, icon, primary)
	button.button_down.connect(func():
		button.set_meta("summon_gesture", {"epoch":_gesture_epoch,"serial":_gesture_serial}))
	button.pressed.connect(func(): app._dispatch_ui_action(button, func(): _action(button, action)))
	return button

func _build() -> void:
	_title = app._label(self, "星辰之约", 25, app.GOLD)
	_subtitle = app._label(self, "群星循着你的呼唤，缓缓汇聚", 13, app.MUTED)
	_counter = app._label(self, "", 14, app.GOLD)
	_hint = app._center_label(self, "让星光指引相遇", 14, app.MUTED)
	_portrait = CharacterBust.new()
	_portrait.name = "SummonRevealPortrait"
	_portrait.enable_bottom_fade(30.0)
	_portrait.configure(str(results[index].charId))
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_portrait)
	_copy = app._vbox(self, 9)
	_copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skip = _button(self, "跳过 · 查看结果", "SummonSkip", "skip", "next")
	_next = _button(self, "下一位", "SummonNext", "next", "next", true)
	_details = _button(self, "旅者档案", "SummonDetails", "details", "book")
	_accept = _button(self, "收下星辰的赠礼", "SummonAccept", "accept", "check", true)
	_again = _button(self, "再祈愿 %d 次" % results.size(), "SummonAgain", "again", "star")
	_wallet = app._hbox(self, 6)
	_wallet.name = "SummonWallet"
	app._rune_icon(_wallet, "gem", 22).name = "SummonBalanceIcon"
	_balance = app._label(_wallet, "", 14, app.CYAN)
	_balance.name = "SummonBalance"
	_balance.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_balance.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	app._rune_icon(_wallet, "gem", 18).name = "SummonCostIcon"
	_repeat_cost = app._label(_wallet, "", 14, app.MUTED)
	_repeat_cost.name = "SummonRepeatCost"
	app._ignore_children(_wallet)
	_update_copy()
	_update_visuals()

func _update_copy() -> void:
	app._clear(_copy)
	var result: Dictionary = results[index]
	var data: Dictionary = app.model.catalog.CharacterData[result.charId]
	_counter.text = "%02d  /  %02d" % [index + 1, results.size()]
	if stage in ["preparing", "opening", "constellation", "seal", "unseal", "legendary"]:
		app._label(_copy, "星门正在开启" if stage in ["seal", "unseal", "legendary"] else "群星回应", 30, app.TEXT)
		app._label(_copy, "命运的轨迹，正在此刻交汇", 15, app.MUTED, true)
		app._label(_copy, "✦   星辰祈愿   ✦", 16, tint())
	else:
		app._label(_copy, "初次相遇" if result.get("isNew", false) else "命运重逢", 15, app.CYAN)
		app._label(_copy, str(data.name), 36, tint(), true)
		app._label(_copy, "★".repeat(int(data.rarity)), 22, tint())
		var row: HBoxContainer = app._hbox(_copy, 8)
		app._rune_icon(row, {"fire":"fire","water":"ice","wind":"leaf","thunder":"energy"}.get(str(data.element),"star"), 24, tint())
		app._label(row, app._element_name(str(data.element)) + " · " + str(app.model.catalog.RoleNames.get(data.get("role", ""), "")), 16, app.MUTED)
		app._label(_copy, "已加入旅者收藏" if result.get("isNew", false) else "角色碎片 +%d" % result.get("shards", 0), 17, app.TEXT, true)
	_layout()

func _layout() -> void:
	if not is_instance_valid(_title): return
	_safe = app._usable_rect()
	var margin := 24.0 if _safe.size.x < 760 else 40.0
	var left := _safe.position.x + margin
	var right := _safe.end.x - margin
	_title.position = Vector2(left, _safe.position.y + 20)
	_subtitle.position = Vector2(left, _safe.position.y + 53)
	_skip.position = Vector2(right - 200, _safe.position.y + 24)
	_skip.size = Vector2(200, 44)
	_counter.position = Vector2(right - 284, _safe.position.y + 36)
	var content := Rect2(Vector2(left, _safe.position.y + 92), Vector2(right-left, maxf(170, _safe.size.y-180)))
	if _safe.size.x < 680:
		_art_rect = Rect2(content.position, Vector2(content.size.x * 0.52, content.size.y))
		_copy_rect = Rect2(content.position + Vector2(content.size.x * 0.56, 24), Vector2(content.size.x * 0.44, content.size.y-24))
	else:
		_art_rect = Rect2(content.position + Vector2(12, -8), Vector2(content.size.x * 0.53, content.size.y + 16))
		_copy_rect = Rect2(content.position + Vector2(content.size.x * 0.60, 40), Vector2(content.size.x * 0.37, content.size.y-40))
	_portrait.position = _art_rect.position
	_portrait.size = _art_rect.size
	_portrait.pivot_offset = _portrait.size / 2
	_copy.position = _copy_rect.position
	_copy.size = _copy_rect.size
	var bottom := _safe.end.y - 68
	_next.position = Vector2(right-180, bottom)
	_next.size = Vector2(180, 48)
	_details.position = Vector2(left, bottom)
	_details.size = Vector2(156, 48)
	_accept.position = Vector2(right-220, bottom)
	_accept.size = Vector2(220, 48)
	_again.position = Vector2(left, bottom)
	_again.size = Vector2(180, 48)
	_wallet.position = Vector2(left, bottom - 34)
	_wallet.size = Vector2(right-left, 26)
	_hint.position = Vector2(left+190, bottom+12)
	_hint.size = Vector2(maxf(0,right-left-420), 26)
	_hint.visible = _safe.size.x >= 820
	if is_instance_valid(_summary):
		content.size.y = maxf(0, _wallet.position.y - 10 - content.position.y)
		_layout_summary(content)
	if is_instance_valid(_preview): _layout_preview()
	queue_redraw()

func _update_visuals() -> void:
	var is_summary := stage == "summary"
	var is_result := stage in ["portrait", "result"]
	var amount := clampf(stage_time / PORTRAIT, 0, 1) if stage == "portrait" else 1.0
	_portrait.visible = is_result or stage == "legendary"
	_portrait.modulate = Color(1, 1, 1, amount if is_result else clampf(stage_time / LEGENDARY,0,1) * 0.34)
	_portrait.scale = Vector2.ONE * (1.0 if reduced_motion else lerpf(0.94,1.0,amount))
	_copy.visible = not is_summary
	_copy.modulate.a = amount if is_result else (0.7 if stage != "preparing" else 0.3)
	_skip.visible = not is_summary
	_skip.disabled = stage == "preparing" or (stage == "opening" and stage_time < 0.55)
	_next.visible = stage == "result"
	_next.text = "查看结果" if index + 1 == results.size() else "下一位"
	_details.visible = stage == "result"
	_accept.visible = is_summary
	_again.visible = is_summary
	_accept.disabled = is_summary and stage_time < 0.35
	var pool: Dictionary = app.model.catalog.GachaPoolData.pools[pool_id]
	var balance := int(app.model.state.resources.get(pool.currency,0))
	var cost := int(pool.costPerPull) * results.size()
	_again.disabled = stage_time < 0.35 or balance < cost
	_wallet.visible = is_summary
	_balance.text = "剩余星尘晶 %d" % balance
	_balance.set_meta("balance", balance)
	_repeat_cost.text = "花费 %d" % cost
	_repeat_cost.set_meta("cost", cost)
	_repeat_cost.modulate = app.CYAN if balance >= cost else app.GOLD
	_again.text = "再祈愿 %d 次" % results.size() if balance >= cost else "星尘晶不足"
	_counter.visible = not is_summary
	_title.text = "星辰之约 · 祈愿结果" if is_summary else "星辰之约"
	_subtitle.text = "每一次相遇，都已铭刻于旅程" if is_summary else ("传说之光 · 命运交汇" if rarity() == 5 and stage in ["legendary","portrait","result"] else "群星循着你的呼唤，缓缓汇聚")
	_hint.text = "轻触旅者，查看完整档案" if is_summary else ("已获得 · 继续与群星相遇" if is_result else "让星光指引相遇")
	if is_summary:
		for i in _cards.size():
			var card := _cards[i]
			var p := clampf((stage_time - i * SUMMARY_STAGGER) / (0.45 if reduced_motion else 0.38), 0, 1)
			card.modulate.a = p
			card.scale = Vector2.ONE if reduced_motion else Vector2.ONE * lerpf(0.94,1.0,1.0-pow(1.0-p,3))
			card.mouse_filter = Control.MOUSE_FILTER_STOP if p >= 1 else Control.MOUSE_FILTER_IGNORE

func _build_summary() -> void:
	_summary = Control.new()
	_summary.name = "SummonSummary"
	_summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_summary)
	move_child(_summary, _portrait.get_index())
	for i in results.size():
		var result: Dictionary = results[i]
		var data: Dictionary = app.model.catalog.CharacterData[result.charId]
		var color: Color = app._rarity_color(int(data.rarity))
		var card: PanelContainer = app._panel(_summary, color.darkened(0.25), 7)
		card.name = "SummonResult_%s_%d" % [result.charId, i]
		card.modulate.a = 0
		var column: VBoxContainer = app._vbox(card, 3)
		var art := CharacterBust.new()
		art.configure(str(result.charId))
		art.size_flags_vertical = Control.SIZE_EXPAND_FILL
		column.add_child(art)
		var captions := [app._center_label(column, str(data.name), 15, color), app._center_label(column, "★".repeat(int(data.rarity)), 11, color), app._center_label(column, "初次相遇" if result.get("isNew",false) else "碎片 +%d" % result.get("shards",0), 12, app.CYAN)]
		for caption in captions:
			caption.autowrap_mode = TextServer.AUTOWRAP_OFF
			caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		app._ignore_children(column)
		var character_id := str(result.charId)
		app._bind_card_tap(card, func():
			if stage == "summary" and stage_time >= 0.35 and not is_instance_valid(_preview): _show_preview(character_id))
		_cards.append(card)
	_layout()

func _layout_summary(content: Rect2) -> void:
	_summary.position = content.position
	_summary.size = content.size
	var columns := 1 if results.size() == 1 else (5 if content.size.x >= 700 else 5)
	var rows := int(ceil(float(results.size()) / columns))
	var gap := 10.0
	var width := minf(260, (content.size.x - (columns-1)*gap) / columns)
	var height := (content.size.y - (rows-1)*gap) / rows
	var start_x := (content.size.x - (width * columns + (columns-1)*gap)) / 2
	for i in _cards.size():
		_cards[i].position = Vector2(start_x + (i % columns)*(width+gap), (i / columns)*(height+gap))
		_cards[i].size = Vector2(width, height)
		_cards[i].pivot_offset = Vector2(width,height)/2

func _show_preview(id: String) -> void:
	if is_instance_valid(_preview): return
	stage_epoch += 1
	_preview = PanelContainer.new()
	_preview.name = "SummonPreviewPanel"
	_preview.add_theme_stylebox_override("panel", app._box(app.PANEL, app.GOLD.darkened(.4), 24))
	add_child(_preview)
	var content: VBoxContainer = app._vbox(_preview, 10)
	var data: Dictionary = app.model.catalog.CharacterData[id]
	app._label(content, "旅者档案 · " + str(data.name), 25, app._rarity_color(int(data.rarity)))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	var column: VBoxContainer = app._vbox(scroll, 8)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	app._label(column, "★".repeat(int(data.rarity)), 18, app.GOLD)
	for skill_id in data.get("skills",[]):
		var skill: Dictionary = app.model.catalog.SkillData.get(skill_id,{})
		app._label(column, str(skill.get("name",skill_id)), 18, app.TEXT)
		app._label(column, str(skill.get("description","")), 15, app.MUTED, true)
	_button(content, "返回祈愿结果", "SummonPreviewClose", "preview_close", "back", true)
	_layout_preview()

func _layout_preview() -> void:
	var target := Vector2(minf(760,_safe.size.x-48), minf(460,_safe.size.y-48))
	_preview.position = _safe.get_center() - target/2
	_preview.size = target

func _draw() -> void:
	if not is_instance_valid(app) or _background == null: return
	draw_rect(Rect2(Vector2.ZERO,size), Color("050b15"))
	var texture_size := _background.get_size()
	var scale_factor := maxf(size.x/texture_size.x,size.y/texture_size.y)
	var source_size := size/scale_factor
	draw_texture_rect_region(_background,Rect2(Vector2.ZERO,size),Rect2((texture_size-source_size)/2,source_size),Color(.52,.60,.73,.84))
	draw_rect(Rect2(Vector2.ZERO,size), Color(.018,.035,.075,.36))
	# Prime each full-art texture on real rendering frames, before stage zero.
	if stage == "preparing":
		for texture in _art: draw_texture_rect(texture,Rect2(1,1,1,1),false,Color(1,1,1,.001))
	var color := tint()
	var center := _art_rect.get_center()
	var radius := minf(_art_rect.size.y * .40, _art_rect.size.x * .40)
	var clock := sequence_time if not reduced_motion else 0.0
	for i in 54:
		var point := Vector2(fmod(i*173.7+43,size.x),fmod(i*i*29.3+19,size.y))
		var alpha := .12 + .18*(.5+.5*sin(clock*.8+i))
		_star(point,1.0+fmod(i,3),Color(color,alpha))
	if stage == "summary": return
	var glow := .2
	if stage == "constellation": glow = lerpf(.2,.6,clampf(stage_time/CONSTELLATION,0,1))
	if stage in ["seal","unseal","legendary","portrait","result"]: glow = .6
	for ring in range(12,0,-1):
		draw_circle(center,radius*(.35+ring*.075),Color(color,glow*.012*(13-ring)))
	var orbit_alpha := clampf(stage_time/OPENING,0,1) if stage == "opening" else 1.0
	var rotation := clock*.12
	for orbit in 3:
		var r := radius * (1.0+orbit*.13)
		draw_arc(center,r,rotation+orbit*.7,rotation+orbit*.7+TAU*.76,96,Color(color,orbit_alpha*(.36-orbit*.08)),1.2,true)
		for tick in 12:
			var angle := TAU*tick/12+rotation
			var direction := Vector2.from_angle(angle)
			draw_line(center+direction*(r-3),center+direction*(r+4),Color(color,orbit_alpha*.45),1,true)
	if stage in ["opening","constellation","preparing"]:
		var p := clampf(stage_time/CONSTELLATION,0,1) if stage == "constellation" else 0.0
		var previous := Vector2.ZERO
		for i in 8:
			var angle := TAU*i/8-.5+rotation
			var point := center+Vector2.from_angle(angle)*radius*(1.0-p*.78)
			if i > 0: draw_line(previous,point,Color(color,.12+p*.45),1.2,true)
			_star(point,4+3*p,Color(color,.6))
			if not reduced_motion and p > .02:
				for tail in 8:
					var behind := angle-tail*.035
					var tail_point := center+Vector2.from_angle(behind)*radius*(1.0-p*.78+tail*.018)
					draw_circle(tail_point,2.3-tail*.23,Color(color,(1-tail/8.0)*p*.5))
			previous = point
		_star(center,14+18*p,Color(color,.55+p*.4))
	if stage in ["seal","unseal"]:
		var p := clampf(stage_time/UNSEAL,0,1) if stage == "unseal" else 0.0
		var flip := 1.0 if reduced_motion else maxf(.035,absf(cos(p*PI)))
		var card_size := Vector2(radius*1.12*flip,radius*1.66)
		var rect := Rect2(center-card_size/2,card_size)
		draw_style_box(app._box(Color(.04,.08,.15,.96),color,5),rect)
		draw_rect(rect.grow(-7),Color(color,.4),false,1)
		if p < .5 or reduced_motion:
			_star(center,24*flip,Color(color,.9))
			if flip > .3: draw_arc(center,radius*.32*flip,0,TAU,48,Color(color,.7),1.3,true)
		else:
			var portrait_rects := CharacterBust.composition_rects(rect.grow(-10), _art[index].get_size(), Avatars.region_for(str(results[index].charId), "bust"))
			if portrait_rects.size() == 2:
				draw_texture_rect_region(_art[index], portrait_rects[0], portrait_rects[1], Color(1,1,1,(p-.5)*2))
	if stage == "legendary":
		var p := clampf(stage_time/LEGENDARY,0,1)
		if not reduced_motion:
			var beam := Rect2(center-Vector2(radius*.14,size.y),Vector2(radius*.28,size.y*2))
			draw_rect(beam,Color(color,.12*sin(p*PI)))
			draw_arc(center,radius*(.4+p*1.35),0,TAU,96,Color(color,(1-p)*.7),2.0,true)
		_star(center,34,Color(color,.65*(1-p)))
	if stage in ["legendary","portrait","result"]:
		var count := 28 if rarity() == 5 else (17 if rarity() == 4 else 9)
		for i in count:
			var angle := i*2.39996+rotation
			var distance := radius*(.5+fmod(i*.217,1.0))
			var point := center+Vector2.from_angle(angle)*distance
			point.y -= 8*sin(clock+i)
			_star(point,2+fmod(i,3),Color(color,.25+.25*sin(i+clock*.6)))
	draw_line(Vector2(_safe.position.x+30,_safe.position.y+80),Vector2(_safe.end.x-30,_safe.position.y+80),Color(color,.2),1,true)

func _star(center: Vector2, radius: float, color: Color) -> void:
	var points := PackedVector2Array([center+Vector2(0,-radius),center+Vector2(radius*.23,-radius*.23),center+Vector2(radius,0),center+Vector2(radius*.23,radius*.23),center+Vector2(0,radius),center+Vector2(-radius*.23,radius*.23),center+Vector2(-radius,0),center+Vector2(-radius*.23,-radius*.23)])
	draw_colored_polygon(points,color)
