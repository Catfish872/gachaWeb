extends RefCounted
const Grid = preload("res://scripts/ui/inventory_grid.gd")
const MapGraph = preload("res://scripts/ui/extraction_map.gd")
const RoomScene = preload("res://scripts/ui/extraction_room.gd")
const COLORS := [Color("9ca7b5"), Color("74bc9a"), Color("68ade8"), Color("bc8be8"), Color("efc774"), Color("ed7884")]
const RARITIES := ["普通", "优良", "稀有", "史诗", "传说", "至臻"]
const ROOM_NAMES := {"entry":"入口", "battle":"交战", "elite":"精英", "cache":"物资", "rest":"营地", "event":"奇遇", "boss":"首领", "vault":"藏宝室", "shrine":"祭坛", "hospital":"药房", "workshop":"工坊"}

static func render(app) -> void:
	var state: Dictionary = app.model.state.extraction
	var run: Dictionary = state.get("run", {})
	app.extraction_difficulty = mini(app.extraction_difficulty, int(state.get("unlockedDifficulty",0)))
	app._page_title("遗境搜打撤", "搜寻珍宝，满载归来")
	var header = app._flow(app.main_body,8)
	app._label(header,"贸易币 %s" % _money(int(state.get("credits",0))),22,app.GOLD)
	app._button(header,"帮助",func(): _help(app)).name="ExtractionHelp"
	var tabs=app._flow(app.main_body,8)
	var tab_list: Array=[["expedition","探索"],["stash","仓库"],["collection","收藏"]]
	if not run.is_empty(): tab_list.insert(1,["bag","背包"])
	for tab in tab_list:
		var id: String=tab[0]
		app._button(tabs,tab[1],func(): _switch_panel(app,id),app.extraction_panel==id).name="ExtractionTab_"+id
	match app.extraction_panel:
		"stash": _stash(app,state);return
		"collection": _collection(app,state);return
		"bag":
			if not run.is_empty(): _bag(app,run)
			else: _stash(app,state)
			return
	if run.is_empty(): _departure(app,state);return
	var act:=int(run.get("act",1))
	var phase:=str(run.get("phase","route"))
	var bar=app._flow(app.main_body,8)
	app._label(bar,"第 %d 幕 · 危险 %d" % [act,int(run.get("difficulty",0))],20,app.CYAN)
	app._label(bar,"背包 %s" % _money(_value(app,run.get("bag",[]))),17,app.GOLD)
	if phase=="route":
		_routes(app)
	else:
		_scene(app)
		var actions=app._flow(app.main_body,8)
		if phase=="battle":
			app._label(app.main_body,str(run.get("activeEncounter",{}).get("name","前方有敌人")),19,app.RED,true)
			app._button(actions,"迎战",app._begin_extraction_battle,true).name="ExtractionBattle"
		elif phase=="boss_exit":
			app._button(actions,"撤离",func(): _confirm_departure(app,true),true).name="ExtractionExit"
			if act<3:
				app._button(actions,"继续深入",func(): app._confirm("进入下一幕？","敌人更强，珍宝更多。当前出口将关闭。",func(): _operate(app,app.model.extraction.continue_act()))).name="ExtractionNextAct"
			app._button(actions,"查看地图",func(): _return_map(app)).name="ExtractionAdvance"
		else:
			app._button(actions,"查看地图",func(): _return_map(app),true).name="ExtractionAdvance"
		app._button(actions,"背包",func(): _switch_panel(app,"bag")).name="ExtractionOpenBag"
	_party_status(app,app.main_body,run)
	app._button(app.main_body,"结束行动",func(): app._confirm("放弃本轮？","放弃会丢失本局物资。",func(): _operate(app,app.model.extraction.retreat())))

static func _departure(app,state: Dictionary) -> void:
	var hero=app._scene_panel(app.main_body,"res://assets/backgrounds/abyss.png",160)
	var shade:=ColorRect.new();shade.color=Color(0.02,0.06,0.11,0.65);shade.mouse_filter=Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);hero.add_child(shade)
	var text=app._vbox(hero,10);text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	text.offset_left=18;text.offset_top=20;text.offset_right=-18;text.offset_bottom=-18
	app._label(text,"深入遗境",29,app.GOLD)
	app._label(text,"探索地图，击败首领，带着珍宝撤离。",17,app.TEXT,true)
	var risk=app._flow(app.main_body,8)
	for level in range(app.model.extraction.max_difficulty()+1):
		var d:=level
		var unlocked:=level<=int(state.get("unlockedDifficulty",0))
		var b=app._button(risk,"危险 %d%s" % [level,"" if unlocked else " · 锁定"],func(): app.extraction_difficulty=d;app._render_screen(),app.extraction_difficulty==level)
		b.disabled=not unlocked
	app._label(app.main_body,"危险越高，珍品越多。通关三幕后解锁下一档。",14,app.MUTED,true)
	for unit in app.model.extraction.departure_party():
		app._label(app.main_body,"%s · 生命 %d · 攻击 %d · 防御 %d" % [app._char_name(str(unit.id)),int(unit.stats.maxHp),int(unit.stats.atk),int(unit.stats.def)],14,app.CYAN,true).name="ExtractionPartyStats_"+str(unit.id)
	var actions=app._flow(app.main_body,8)
	app._button(actions,"出发",func(): _operate(app,app.model.extraction.start_run(app.extraction_difficulty)),true).name="ExtractionStart"
	app._button(actions,"编队",func(): app.navigate("party"))
	_loadout(app,app.main_body,state)
	var summary: Dictionary=state.get("lastRun",{})
	if not summary.is_empty():
		app._label(app.main_body,("上次带出 %s" if summary.get("outcome","")=="extracted" else "上次遗失 %s") % _money(int(summary.get("value",0))),16,app.GOLD,true)

static func _routes(app) -> void:
	var graph: Dictionary=app.model.extraction.map_state()
	var explored:=int(graph.get("explored",0))
	app._label(app.main_body,"首领通道已开启" if graph.get("bossUnlocked",false) else "探索 %d / %d 处，解除首领封印" % [explored,int(graph.get("requiredExploration",4))],16,app.GOLD,true)
	var map=MapGraph.new();map.name="ExtractionMap";map.configure(graph)
	var map_frame:=MarginContainer.new();map_frame.add_theme_constant_override("margin_right",16);app.main_body.add_child(map_frame);map_frame.add_child(map)
	map.room_selected.connect(func(id): _map_choice(app,id))
	var map_controls=app._flow(app.main_body,8)
	app._button(map_controls,"全图",func():map.fit_view()).name="ExtractionMapOverview"
	app._button(map_controls,"定位",func():map.focus_current()).name="ExtractionMapFocus"
	app._label(app.main_body,"滑动地图 · 点击相邻房间进入",14,app.MUTED,true)
	# Adjacent-room shortcuts remain useful for accessibility and compact screens.
	var options=app._flow(app.main_body,8)
	var names: Dictionary={}
	for route in app.model.extraction.route_options():
		var id:=str(route.id);var kind:=str(route.get("type",""))
		var label:=str(route.get("name",ROOM_NAMES.get(kind,"房间")))
		if kind=="vault" and not route.get("cleared",false):label+=" · 有守卫"
		if route.get("visited",false):label+=" · 已到访"
		if route.get("locked",false):label+=" · 封印"
		var b=app._button(options,label,func(): _map_choice(app,id))
		b.name="ExtractionRoute_"+kind+("_"+id if names.has(kind) else "")
		names[kind]=true;b.disabled=bool(route.get("locked",false))

static func _map_choice(app,id: String) -> void:
	var graph: Dictionary=app.model.extraction.map_state()
	if id==str(graph.get("currentRoomId","")):
		if app.model.state.extraction.run.get("room",{}).get("type","")!="entry":
			_operate(app,app.model.extraction.view_current_room())
		return
	var adjacent:=false
	for route in app.model.extraction.route_options():
		if str(route.id)==id:adjacent=true
	if not adjacent:
		app._toast("沿连线前往相邻房间",app.CYAN);return
	_operate(app,app.model.extraction.enter_room(id))

static func _scene(app) -> void:
	var room: Dictionary=app.model.extraction.room_scene()
	app._label(app.main_body,str(room.get("name","遗境")),22,app.TEXT,true)
	var scene=RoomScene.new();scene.name="ExtractionRoomScene"
	scene.configure(room,app.model.extraction.containers(),str(room.get("selectedContainer","")))
	var scene_frame:=MarginContainer.new();scene_frame.add_theme_constant_override("margin_right",16);app.main_body.add_child(scene_frame);scene_frame.add_child(scene)
	scene.container_selected.connect(func(id):
		if app.model.state.extraction.run.get("phase","")=="battle":app._toast("先解决守卫",app.RED);return
		if app._check(app.model.extraction.choose_container(id)): _open_container(app,id))
	app._label(app.main_body,"滑动查看 · 点击容器搜索" if not app.model.extraction.containers().is_empty() else str(room.get("description","这里暂时安静")),14,app.MUTED,true)
	# These concise names are also keyboard/screen-reader accessible alternatives.
	var shortcuts=app._flow(app.main_body,8)
	for box in app.model.extraction.containers():
		var id:=str(box.id)
		app._button(shortcuts,str(box.get("name","容器")),func():
			if app._check(app.model.extraction.choose_container(id)): _open_container(app,id)).name="ExtractionOpenContainer_"+id

static func _return_map(app) -> void:
	_stop_search(app,false)
	_operate(app,app.model.extraction.advance_room())

static func _container(app,id: String) -> Dictionary:
	for box in app.model.extraction.containers():
		if str(box.id)==id:return box
	return {}

static func _open_container(app,id: String) -> void:
	var container:=_container(app,id)
	if container.is_empty():return
	app.extraction_search_container=id
	var box=app._modal(str(container.get("name","搜索")),660,660)
	app.overlay.set_meta("extraction_container",id)
	var items: Array=container.get("items",[])
	var unknown:=0
	for item in items:
		if not item.get("revealed",false):unknown+=1
	var controls=app._flow(box,8)
	if app.extraction_searching:
		app._button(controls,"停止",func(): _stop_search(app,true)).name="ExtractionStopSearch"
	elif unknown>0:
		app._button(controls,"搜索",func(): _search(app,id),true).name="ExtractionSearch"
	app._button(controls,"收下全部",func(): _take_all(app,id)).name="ExtractionTakeAll"
	if app.model.extraction.has_method("plan_smart_loot") and app.model.extraction.plan_smart_loot(id).get("success",false):
		app._button(controls,"一键换入",func(): _smart_loot(app,id),true).name="ExtractionSmartLoot"
	app._button(controls,"返回",func(): _close_container(app)).name="ExtractionCloseContainer"
	var progress=app._progress(box,items.size()-unknown,maxi(1,items.size()),app.CYAN,7)
	progress.name="SearchProgress_"+id
	if items.is_empty():app._label(box,"已搜空",19,app.MUTED)
	else:_container_grid(app,box,id,items)
	if not app.extraction_recent.is_empty():
		var recent: Dictionary=app.extraction_recent
		var definition: Dictionary=app.model.extraction.item_def(str(recent.get("itemId","")))
		app._label(box,("已收下 · " if recent.get("taken",false) else "发现 · ")+str(definition.get("name","物资")),18,COLORS[clampi(int(definition.get("rarity",0)),0,5)],true)
	app._label(box,"背包 %d 件 · %s" % [app.model.state.extraction.run.get("bag",[]).size(),_money(_value(app,app.model.state.extraction.run.get("bag",[])))],15,app.GOLD,true)
	app._button(box,"自动收下：开" if app.extraction_auto_pick else "自动收下：关",func(): app.extraction_auto_pick=not app.extraction_auto_pick;app._save_preferences();_open_container(app,id)).name="ExtractionAutoPick"
	for item in items:
		if not item.get("revealed",false):continue
		var uid:=str(item.uid);var d: Dictionary=app.model.extraction.item_def(str(item.itemId))
		var row=app._vbox(box,5);_item_title(app,row,d)
		app._button(row,"收下",func(): _take_one(app,id,uid)).name="ExtractionPickup_"+uid

static func _take_one(app,id: String,uid: String) -> void:
	if app._check(app.model.extraction.take_item(id,uid)):
		app.model.extraction.sort_grid("bag")
	_open_container(app,id)

static func _take_all(app,id: String) -> void:
	var result: Dictionary=app.model.extraction.take_all_revealed(id)
	if app._check(result) and not result.get("left",[]).is_empty():app._toast("背包已满，剩余物资留在这里",app.GOLD)
	_open_container(app,id)

static func _smart_loot(app,id: String) -> void:
	_stop_search(app,false)
	var plan: Dictionary=app.model.extraction.plan_smart_loot(id)
	if not plan.get("success",false):
		app._toast(str(plan.get("message",plan.get("error","没有更合适的物资"))),app.GOLD)
		_open_container(app,id);return
	var box=app._modal("一键换入",620,520)
	app.overlay.set_meta("extraction_container",id)
	app._label(box,"换入 %d 件 · 价值 +%s" % [plan.get("added",[]).size(),_money(int(plan.get("gain",0)))],21,app.GOLD,true)
	for group in ["removed","added"]:
		var items: Array=plan.get(group,[])
		app._label(box,("换出 · " if group=="removed" else "换入 · ")+_money(_value(app,items)),17,app.MUTED,true)
		for item in items:
			var d: Dictionary=app.model.extraction.item_def(str(item.itemId))
			app._label(box,str(d.get("name","物资")),16,COLORS[clampi(int(d.get("rarity",0)),0,5)],true)
	app._label(box,"换出的物资留在这个容器中。",14,app.MUTED,true)
	var actions=app._flow(box,8)
	app._button(actions,"确认换入",func():
		app._check(app.model.extraction.apply_smart_loot(id,str(plan.get("planHash",""))))
		_open_container(app,id),true).name="ExtractionSmartConfirm"
	app._button(actions,"取消",func():_open_container(app,id)).name="ExtractionSmartCancel"

static func _search_alive(app,generation: int,id: String) -> bool:
	return is_instance_valid(app) and app.current_screen=="extraction" and app.extraction_search_generation==generation and app.overlay.get_child_count()>0 and str(app.overlay.get_meta("extraction_container",""))==id

static func _search(app,id: String) -> void:
	if app.extraction_searching:return
	app.extraction_searching=true;app.extraction_search_generation+=1
	var generation: int=app.extraction_search_generation
	_open_container(app,id)
	while _search_alive(app,generation,id):
		var unknown:=false
		for item in _container(app,id).get("items",[]):
			if not item.get("revealed",false):unknown=true;break
		if not unknown:break
		app._extraction_play("search")
		var duration:=0.08 if app.extraction_reduced_motion else 1.05
		var start:=Time.get_ticks_msec()
		while float(Time.get_ticks_msec()-start)/1000.0<duration:
			if not _search_alive(app,generation,id):return
			var progress=app.overlay.find_child("SearchProgress_"+id,true,false)
			if is_instance_valid(progress):progress.max_value=1.0;progress.value=float(Time.get_ticks_msec()-start)/(duration*1000)
			await app.get_tree().process_frame
		if not _search_alive(app,generation,id):return
		var result: Dictionary=app.model.extraction.reveal_next(id)
		if not app._check(result):break
		var latest: Dictionary=result.get("item",{})
		app.extraction_recent=latest.duplicate(true)
		var d: Dictionary=app.model.extraction.item_def(str(latest.get("itemId","")))
		var rarity:=clampi(int(d.get("rarity",0)),0,5)
		if app.extraction_auto_pick:
			var take: Dictionary=app.model.extraction.take_all_revealed(id)
			if take.get("success",false):
				app.extraction_recent.taken=str(latest.get("uid","")) in take.get("taken",[])
			else:
				app._check(take)
				break
		app._extraction_play("red" if rarity==5 else "gold" if rarity==4 else "purple" if rarity==3 else "common")
		_open_container(app,id)
		var pause:=0.04 if app.extraction_reduced_motion else (1.8 if rarity>=4 else 0.7 if rarity==3 else 0.28)
		await app.get_tree().create_timer(pause).timeout
	if not _search_alive(app,generation,id):return
	app.extraction_searching=false
	if is_instance_valid(app.extraction_audio):app.extraction_audio.stop()
	_open_container(app,id)
	app._render_screen()

static func _stop_search(app,refresh: bool=true) -> void:
	app.extraction_search_generation+=1;app.extraction_searching=false
	if is_instance_valid(app.extraction_audio):app.extraction_audio.stop()
	if refresh and not app.extraction_search_container.is_empty():_open_container(app,app.extraction_search_container)

static func _close_container(app) -> void:
	_stop_search(app,false);app._clear_overlay();app._render_screen()

static func _help(app) -> void:
	var box=app._modal("探索指南",660,640)
	for line in ["沿地图连线探索，发现物资、营地和珍贵据点。", "探索四处不同房间后，首领封印解除。击败首领可撤离或深入下一幕。", "点击场景中的箱柜，搜索会逐件揭示并自动收下。背包满时，物品留在容器里。", "角色成长完整保留。每场战斗最多40回合，封锁前击败敌人。", "撤离带回物资；失败或放弃会失去本局背包和装备。"]:
		app._label(box,line,16,app.TEXT,true)
	app._button(box,"音效：开" if app.extraction_sound else "音效：关",func():app.extraction_sound=not app.extraction_sound;app._save_preferences();_help(app))
	app._button(box,"快速搜索：开" if app.extraction_reduced_motion else "快速搜索：关",func():app.extraction_reduced_motion=not app.extraction_reduced_motion;app._save_preferences();_help(app))
	app._button(box,"返回",app._clear_overlay,true)

static func _bag(app, run: Dictionary) -> void:
	app._label(app.main_body, "随身背包 · 6 × 5", 23, app.CYAN)
	_inventory(app, app.main_body, "bag", run.get("bag", []), 6, 5)
	app._label(app.main_body, "装备槽 · %d / 3" % run.get("equipped", []).size(), 19, app.GOLD)
	for item in run.get("equipped", []):
		var d: Dictionary = app.model.extraction.item_def(str(item.itemId))
		var card = app._panel(app.main_body, COLORS[clampi(int(d.get("rarity", 0)), 0, 5)].darkened(0.5), 12)
		var row = app._responsive_box(card, app.compact, 8)
		_item_title(app, row, d)
		var uid := str(item.uid)
		app._button(row, "卸回背包", func(): _operate(app, app.model.extraction.unequip_item(uid)))

static func _inventory(app, parent: Node, scope: String, items: Array, columns: int, rows: int) -> void:
	var defs := {}
	for item in items: defs[str(item.itemId)] = app.model.extraction.item_def(str(item.itemId))
	var grid = Grid.new()
	grid.name = "ExtractionGrid_" + scope
	grid.configure(columns, rows, items, defs, app.extraction_selected if app.extraction_scope == scope else "")
	grid.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	grid.custom_minimum_size.x = minf(columns * 64.0, maxf(240, app.main_body.size.x - 32))
	parent.add_child(grid)
	grid.item_selected.connect(func(uid): app.extraction_scope = scope; app.extraction_selected = uid; app._render_screen())
	grid.cell_selected.connect(func(x, y):
		if app.extraction_scope != scope or app.extraction_selected.is_empty(): return
		for item in items:
			if str(item.uid) == app.extraction_selected:
				_operate(app, app.model.extraction.move_item(scope, str(item.uid), x, y, bool(item.get("rotated", false)))))
	app._label(parent, "点选物品查看 · 自动整理腾出空间", 14, app.MUTED, true)
	app._button(parent, "自动整理", func(): _operate(app, app.model.extraction.sort_grid(scope))).name = "ExtractionSort_" + scope
	for item in items:
		if app.extraction_scope != scope or str(item.uid) != app.extraction_selected: continue
		_selected(app, parent, scope, item)

static func _selected(app, parent: Node, scope: String, item: Dictionary) -> void:
	var d: Dictionary = app.model.extraction.item_def(str(item.itemId))
	var uid := str(item.uid)
	var card = app._panel(parent, COLORS[clampi(int(d.get("rarity", 0)), 0, 5)], 14)
	var col = app._vbox(card, 8)
	_item_title(app, col, d)
	app._label(col, str(d.get("description", "可出售的遗境物资。")), 15, app.MUTED, true)
	var actions = app._flow(col, 8)
	app._button(actions, "旋转", func(): _operate(app, app.model.extraction.move_item(scope, uid, int(item.x), int(item.y), not bool(item.get("rotated", false))))).name = "ExtractionRotate"
	if scope == "bag":
		if d.get("kind", "loot") == "equipment": app._button(actions, "装备", func(): _operate(app, app.model.extraction.equip_item(uid)), true)
		if d.get("kind", "loot") == "consumable" and app.model.extraction.has_method("use_item"): app._button(actions, "使用补给", func(): _operate(app, app.model.extraction.use_item(uid)), true)
		app._button(actions, "丢弃", func(): app._confirm("丢弃物资？", "丢弃后无法取回。", func(): _operate(app, app.model.extraction.discard_item(uid))))
	else:
		app._button(actions, "出售 · " + _money(int(d.get("value", 0))), func(): _operate(app, app.model.extraction.sell_item(uid)))
		app._button(actions, "收入收藏", func(): app._confirm("收藏此物品？", "收入收藏后无法出售。", func(): _operate(app, app.model.extraction.collect_item(uid))))
		if app.model.extraction.has_method("bring_item"):
			app._button(actions, "携带出战", func(): _operate(app, app.model.extraction.bring_item(uid)))

static func _stash(app, state: Dictionary) -> void:
	_loadout(app, app.main_body, state)
	app._label(app.main_body, "营地仓库 · 10 × 12", 23, app.CYAN)
	if not state.get("run", {}).is_empty(): app._label(app.main_body, "行动进行中", 15, app.MUTED, true)
	if not state.get("mailbox", []).is_empty():
		app._button(app.main_body, "领取撤离物资 · %d 件" % state.mailbox.size(), func(): _operate(app, app.model.extraction.claim_mail()), true)
	_inventory(app, app.main_body, "stash", state.get("stash", []), 10, 12)
	app._label(app.main_body, "仓库满了？带出的物资会暂存待领区。", 14, app.MUTED, true)

static func _collection(app, state: Dictionary) -> void:
	var collected: Array=state.get("collection",[])
	var catalog: Dictionary=app.model.extraction.data.get("items",{})
	app._label(app.main_body,"遗境收藏 · %d / %d" % [collected.size(),catalog.size()],24,app.GOLD)
	app._label(app.main_body,"把新藏品带回仓库，收入收藏。",15,app.MUTED,true)
	var cards=app._grid(app.main_body,1 if app.compact else 3)
	for id in catalog:
		var d: Dictionary=app.model.extraction.item_def(str(id))
		var owned:=collected.has(str(id))
		var card=app._panel(cards,COLORS[clampi(int(d.get("rarity",0)),0,5)].darkened(0.5 if owned else 0.8),16)
		var col=app._vbox(card,8)
		app._label(col,str(d.get("name","物资")),18,COLORS[clampi(int(d.get("rarity",0)),0,5)],true)
		app._label(col,"已收藏" if owned else "待收集",14,app.GOLD if owned else app.MUTED,true)

static func _item_title(app, parent: Node, d: Dictionary) -> void:
	var rarity := clampi(int(d.get("rarity", 0)), 0, 5)
	var item_id=app.model.extraction.data.get("items",{}).find_key(d)
	if item_id!=null and d.get("kind","")!="unknown":
		app._label(parent,"已收藏" if app.model.state.extraction.get("collection",[]).has(str(item_id)) else "新藏品",14,app.GOLD,true)
	app._label(parent, "%s · %s" % [RARITIES[rarity], d.get("name", "遗境物资")], 18, COLORS[rarity], true)
	app._label(parent, "%d × %d 格   ·   售价 %s   ·   每格 %s" % [int(d.get("width", 1)), int(d.get("height", 1)), _money(int(d.get("value", 0))), _money(int(d.get("value", 0)) / maxi(1, int(d.get("width", 1)) * int(d.get("height", 1))))], 13, app.MUTED, true)
	if float(d.get("heal", 0)) > 0:
		app._label(parent, "使用后全队存活成员恢复 %d%% 最大生命" % roundi(float(d.heal) * 100), 14, app.CYAN, true)
	for effect in d.get("effects", []):
		var label := ""
		if effect.get("type", "") == "stat":
			var names := {"maxHpMult": "最大生命", "atkMult": "攻击", "defMult": "防御", "criAdd": "暴击率"}
			label = "全队%s +%d%%" % [names.get(str(effect.get("stat", "")), "属性"), roundi(float(effect.get("value", 0)) * 100)]
		elif effect.get("type", "") == "battleStartEnergy":
			label = "全队战斗开始时能量 +%d" % int(effect.get("value", 0))
		if not label.is_empty(): app._label(parent, label, 14, app.CYAN, true)

static func _value(app, items: Array) -> int:
	var total := 0
	for item in items: total += int(app.model.extraction.item_def(str(item.itemId)).get("value", 0))
	return total

static func _money(value: int) -> String:
	return str(value)

static func _operate(app, result: Dictionary, message: String = "") -> void:
	app._extraction_operation(result, message)

static func _loadout(app, parent: Node, state: Dictionary) -> void:
	if not state.get("run", {}).is_empty(): return
	var loadout: Array = state.get("loadout", [])
	var panel = app._panel(parent, app.LINE, 14)
	var col = app._vbox(panel, 8)
	app._label(col, "出战携带 · %d / 3 件" % loadout.size(), 19, app.GOLD)
	app._label(col, "从仓库挑选装备和补给，也可空手出发。", 14, app.MUTED, true)
	for item in loadout:
		var uid := str(item.uid)
		var d: Dictionary = app.model.extraction.item_def(str(item.itemId))
		_item_title(app, col, d)
		app._button(col, "放回仓库", func(): _operate(app, app.model.extraction.store_item(uid)))
	if app.model.extraction.has_method("buy_supply"):
		var shop = app._flow(col, 8)
		for id in app.model.extraction.data.get("items", {}):
			var d: Dictionary = app.model.extraction.item_def(str(id))
			if int(d.get("buyPrice", 0)) <= 0: continue
			var item_id := str(id)
			var required:=int(d.get("buyMinRisk",0))
			var locked:=int(state.get("unlockedDifficulty",0))<required
			var caption:="%s · %d 币" % [d.get("name",id),int(d.buyPrice)]
			if locked:caption+=" · 危险%d解锁" % required
			var buy=app._button(shop,caption,func(): _operate(app,app.model.extraction.buy_supply(item_id)))
			buy.name="ExtractionBuy_"+item_id;buy.disabled=locked

static func _switch_panel(app, id: String) -> void:
	app.extraction_search_generation += 1
	app.extraction_searching = false
	if is_instance_valid(app.extraction_audio): app.extraction_audio.stop()
	app.extraction_panel = id
	app.extraction_selected = ""
	app._render_screen()

static func _party_status(app, parent: Node, run: Dictionary) -> void:
	for unit in run.get("party", []):
		var id := str(unit.get("id", ""))
		var hp := int(unit.get("currentHp", unit.get("hp", 0)))
		var maximum := int(unit.get("maxHp", unit.get("hp", 1)))
		app._label(parent, "%s  %d / %d" % [app._char_name(id), hp, maximum], 14, app.CYAN if hp > 0 else app.RED)
		app._progress(parent, hp, maximum, app.CYAN if hp > 0 else app.RED, 4)

static func _confirm_departure(app, extraction: bool) -> void:
	var left := 0
	for container in app.model.extraction.containers(): left += container.get("items", []).size()
	var action := func():
		app.extraction_search_generation += 1
		app.extraction_searching = false
		if is_instance_valid(app.extraction_audio): app.extraction_audio.stop()
		_operate(app, app.model.extraction.extract() if extraction else app.model.extraction.advance_room(), "撤离成功，物资已送回营地" if extraction else "")
	if left > 0:
		app._confirm("还有物资留在容器中", "还有 %d 件物资留在这里，确认撤离？" % left, action)
	else: action.call()

static func _container_grid(app, parent: Node, container_id: String, items: Array) -> void:
	var display: Array = []
	var defs := {}
	var bottom := 1
	for original in items:
		var item: Dictionary = original.duplicate(true)
		var known := bool(item.get("revealed", false))
		var actual: Dictionary = app.model.extraction.item_def(str(item.itemId))
		var d: Dictionary = actual.duplicate(true) if known else {"name": "未搜索", "width": int(actual.get("width",1)), "height": int(actual.get("height",1)), "rarity": 0, "value": 0, "kind": "unknown"}
		if not known: item.itemId = "unknown_" + str(item.uid)
		defs[str(item.itemId)] = d
		var w := int(d.get("width", 1))
		var h := int(d.get("height", 1))
		bottom = maxi(bottom, int(item.get("y", 0)) + (w if item.get("rotated",false) else h))
		display.append(item)
	var grid = Grid.new()
	grid.name = "ExtractionContainer_" + container_id
	grid.configure(6, bottom, display, defs)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	grid.custom_minimum_size.x = minf(384, maxf(240, app.main_body.size.x - 64))
	parent.add_child(grid)
	grid.item_selected.connect(func(uid):
		for item in items:
			if str(item.uid) == uid and item.get("revealed", false):
				_stop_search(app,false)
				var detail = app._modal("发现物资", 600, 390)
				_item_title(app, detail, app.model.extraction.item_def(str(item.itemId)))
				app._button(detail, "收入背包", func(): app._clear_overlay(); _operate(app, app.model.extraction.take_item(container_id, uid)), true)
				app._button(detail, "返回搜索", app._clear_overlay))
