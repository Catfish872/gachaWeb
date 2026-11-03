extends RefCounted
const EventChoice=preload("res://scripts/ui/event_choice.gd")
const Grid = preload("res://scripts/ui/inventory_grid.gd")
const MapGraph = preload("res://scripts/ui/extraction_map.gd")
const RoomScene = preload("res://scripts/ui/extraction_room.gd")
const RewardRarity = preload("res://scripts/ui/reward_rarity.gd")
const COLORS := [Color("9ca7b5"), Color("74bc9a"), Color("68ade8"), Color("bc8be8"), Color("efc774"), Color("ed7884")]
const RARITIES := ["普通", "优良", "稀有", "史诗", "传说", "至臻"]
const SEARCH_SECONDS := [0.45, 0.65, 0.95, 1.35, 2.0, 2.8]
const ROOM_NAMES := {"entry":"入口", "battle":"交战", "elite":"精英", "cache":"物资", "rest":"营地", "event":"奇遇", "boss":"首领", "vault":"藏宝室", "shrine":"祭坛", "hospital":"药房", "workshop":"工坊", "relay":"寄存站", "key_vault":"钥匙密室"}

static func _button(app,parent: Node,text: String,action: Callable,primary: bool=false) -> Button:
	var button: Button=app._button(parent,text,action,primary)
	if not app.has_method("_button_icon"):return button
	var key:=""
	if text in ["地图","探索","出发","前往","继续深入","继续探索"]:key="path"
	elif text in ["背包","仓库","打开仓库","收下","收下全部","一键换入","确认换入","携带","整理","自动整理"]:key="bag"
	elif text in ["构筑","查看本局构筑"]:key="star"
	elif text in ["编队"]:key="party"
	elif text in ["更多","菜单"]:key="menu"
	elif text=="自动挑选" or text.begins_with("出售") or text.contains("购买"):key="coin"
	elif text in ["装备","直接装备","卸回背包","更换背包","卸下"]:key="gear"
	elif text in ["使用","直接使用","补给"]:key="heart"
	elif text.contains("收藏") or text=="藏品":key="book"
	elif text.begins_with("修复") or text.begins_with("装配护盾装备"):key="shield"
	elif text in ["返回","放回","撤离","放弃","确认放弃"]:key="back"
	elif text in ["选择","多选","确认寄存","确认寄送"]:key="check"
	if not key.is_empty():app._button_icon(button,key,primary)
	return button

static func _used_cells(app,items: Array) -> int:
	var total:=0
	for item in items:
		var d:Dictionary=app.model.extraction.item_def(str(item.get("itemId","")))
		total+=int(d.get("width",1))*int(d.get("height",1))
	return total

static func _bag_cells(app) -> int:
	var dims:Vector2i=app.model.extraction.dimensions("bag")
	return dims.x*dims.y

static func _height(app) -> float:
	return app.content_height() if app.has_method("content_height") else maxf(400,app.size.y-100)

static func _workspace(app,parent: Node,gap: int=12) -> BoxContainer:
	return app._vbox(parent,gap) if app.size.x<900 else app._hbox(parent,gap)

static func _section(app,parent: Node,title: String,color: Color=Color("9bc5c4")) -> VBoxContainer:
	var panel=app._panel(parent,color.darkened(0.7),10)
	panel.size_flags_vertical=Control.SIZE_EXPAND_FILL
	var col=app._vbox(panel,8);col.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var heading=app._label(col,title,16,color)
	heading.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	return col

static func _scroll(app,parent: Node,height: float=0) -> VBoxContainer:
	var scroll=ScrollContainer.new();scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	if height>0:scroll.custom_minimum_size.y=height
	elif app.size.x<900:scroll.custom_minimum_size.y=300
	parent.add_child(scroll)
	var col=app._vbox(scroll,8);col.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	return col

static func render(app) -> void:
	if app.has_method("set_page_fixed"):app.set_page_fixed(app.size.x>=900)
	var state: Dictionary=app.model.state.extraction
	var run: Dictionary=state.get("run",{})
	app.extraction_difficulty=mini(app.extraction_difficulty,int(state.get("unlockedDifficulty",0)))
	var nav=app._flow(app.main_body,6) if app.size.x<900 else app._hbox(app.main_body,8)
	app._label(nav,"遗境",20,app.GOLD)
	var tabs: Array=[["expedition","探索"],["stash","仓库"],["shop","补给站"],["collection","藏品"]] if run.is_empty() else [["expedition","探索"],["bag","背包"],["build","构筑"]]
	for tab in tabs:
		var id: String=tab[0]
		var tab_button=app._tab_button(nav,tab[1],func():_switch_panel(app,id),app.extraction_panel==id)
		tab_button.name="ExtractionTab_"+id
		app._button_icon(tab_button,{"expedition":"path","stash":"bag","bag":"bag","build":"star","shop":"coin","collection":"book"}.get(id,"star"))
	var spacer=Control.new();spacer.size_flags_horizontal=Control.SIZE_EXPAND_FILL;nav.add_child(spacer)
	if not run.is_empty():
		var earned=app._hbox(nav,4);app._rune_icon(earned,"coin",22,app.GOLD)
		app._label(earned,"携出价值 %s" % _money(_value(app,run.get("bag",[])+run.get("equipped",[]))),16,app.GOLD).name="ExtractionRunValue"
		app._bind_card_tap(earned,func():_show_run_value(app))
		app._label(nav,"第 %d 幕 · 危险 %d" % [int(run.act),int(run.difficulty)],13,app.CYAN)
	if app.model.extraction.has_method("keyring"):
		var key_button=app._tool_button(nav,"gear","钥匙串",func():_keyring(app));key_button.name="ExtractionKeyring"
		key_button.icon=load("res://assets/items/expedition_v230/key_ruins.png")
	app._tool_button(nav,"book","遗境指引",func():_help(app)).name="ExtractionHelp"
	match app.extraction_panel:
		"stash":_stash(app,state);return
		"shop":_shop(app,state);return
		"collection":_collection(app,state);return
		"build":_build(app,run);return
		"bag":
			if not run.is_empty():_bag(app,run)
			else:_stash(app,state)
			return
	if run.is_empty():_departure(app,state);return
	var workspace=_workspace(app,app.main_body,12);workspace.size_flags_vertical=Control.SIZE_EXPAND_FILL;workspace.name="ExtractionWorkspace"
	var left=app._vbox(workspace,6);left.size_flags_horizontal=Control.SIZE_EXPAND_FILL;left.size_flags_stretch_ratio=1.65
	var right=app._vbox(workspace,8);right.size_flags_horizontal=Control.SIZE_EXPAND_FILL;right.size_flags_stretch_ratio=1.0
	right.custom_minimum_size.x=280
	if app.model.extraction.has_method("growth_choices") and not app.model.extraction.growth_choices().is_empty():_show_growth(app,left,true)
	elif str(run.get("phase","route"))=="route":_routes(app,left,right)
	else:_scene(app,left,run)
	_party_status(app,right,run)
	_equipment_slots(app,right,run)
	_utility_slots(app,right,true)
	var bag_panel=_section(app,right,"背包 %d / %d 格 · %s 金币" % [_used_cells(app,run.get("bag",[])),_bag_cells(app),_money(_value(app,run.get("bag",[])))])
	var bag_scroll=_scroll(app,bag_panel)
	var grid=_grid_widget(app,bag_scroll,"bag",run.get("bag",[]),6,5,28)
	grid.item_selected.connect(func(uid):app.extraction_selected=uid;app.extraction_scope="bag";_switch_panel(app,"bag",false))
	var actions=app._hbox(right,4);actions.name="ExtractionPersistentActions"
	_button(app,actions,"整理",func():_sort_animated(app,"bag")).name="ExtractionSort_bag"
	_button(app,actions,"补给",func():_quick_supplies(app)).name="ExtractionQuickSupplies"
	_button(app,actions,"构筑",func():_switch_panel(app,"build")).name="ExtractionBuild"
	_button(app,actions,"放弃",func():_confirm_abandon(app)).name="ExtractionAbandon"

static func _departure(app,state: Dictionary) -> void:
	var row=_workspace(app,app.main_body,12);row.size_flags_vertical=Control.SIZE_EXPAND_FILL
	var left=app._vbox(row,10);left.size_flags_horizontal=Control.SIZE_EXPAND_FILL;left.size_flags_stretch_ratio=1.45
	var hero=app._scene_panel(left,"res://assets/backgrounds/abyss.png",130)
	var content=app._vbox(hero,6);content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);content.offset_left=18;content.offset_top=18
	app._label(content,"深入遗境",27,app.GOLD)
	app._label(content,"寻找珍宝，击败首领，满载归来",15,app.TEXT)
	var risk=app._hbox(left,6)
	for level in range(app.model.extraction.max_difficulty()+1):
		var d:=level
		var b=_button(app,risk,"危险 %d" % level,func():app.extraction_difficulty=d;app._render_screen(),app.extraction_difficulty==level)
		b.disabled=level>int(state.get("unlockedDifficulty",0))
	var team=app._hbox(left,8)
	for unit in app.model.extraction.departure_party():
		var col=_section(app,team,app._char_name(str(unit.id)))
		var r=app._hbox(col,8)
		var portrait=app._portrait(r,str(unit.id),74);portrait.custom_minimum_size.x=58
		var stats=app._vbox(r,3)
		app._label(stats,"生命 %d" % int(unit.stats.maxHp),13,app.TEXT)
		app._label(stats,"攻击 %d" % int(unit.stats.atk),12,app.MUTED)
		app._label(stats,"防御 %d" % int(unit.stats.def),12,app.MUTED)
		stats.name="ExtractionPartyStats_"+str(unit.id)
	var actions=app._hbox(left,8)
	_button(app,actions,"出发",func():_operate(app,app.model.extraction.start_run(app.extraction_difficulty)),true).name="ExtractionStart"
	_button(app,actions,"编队",func():app.navigate("party"))
	var summary: Dictionary=state.get("lastRun",{})
	if not summary.is_empty():
		var secured_value: int = app.model.extraction.secured_summary_value(summary)
		app._label(actions,"上次带出 %s" % _money(secured_value) if secured_value > 0 or summary.get("outcome","")=="extracted" else "准备再次出发",14,app.MUTED)
	var right=_section(app,row,"出战整备",app.GOLD);right.get_parent().size_flags_stretch_ratio=1
	var preparation=_scroll(app,right)
	preparation.get_parent().name="ExtractionPreparationScroll"
	_utility_slots(app,preparation)
	_loadout(app,preparation,state)
	var links=app._hbox(right,6)
	links.name="ExtractionPreparationActions"
	_button(app,links,"补给站",func():_switch_panel(app,"shop"))
	_button(app,links,"打开仓库",func():_switch_panel(app,"stash"))

static func _routes(app,parent: Node,side: Node) -> void:
	var graph: Dictionary=app.model.extraction.map_state()
	var status=app._hbox(parent,8)
	if not str(graph.get("name","")).is_empty():
		app._label(status,str(graph.name),16,app.GOLD)
		var space=Control.new();space.size_flags_horizontal=Control.SIZE_EXPAND_FILL;status.add_child(space)
	app._label(status,"首领通道已开启" if graph.get("bossUnlocked",false) else "探索 %d / %d" % [int(graph.get("explored",0)),int(graph.get("requiredExploration",4))],14,app.GOLD)
	var map=MapGraph.new();map.name="ExtractionMap";map.configure(graph,app.extraction_reduced_motion)
	map.custom_minimum_size.y=maxf(235,_height(app)-195);map.size_flags_vertical=Control.SIZE_EXPAND_FILL;parent.add_child(map)
	map.room_selected.connect(func(id):_map_choice(app,id))
	if map.has_signal("room_previewed"):
		var preview=app._hbox(parent,8);preview.name="ExtractionRoomPreview";preview.custom_minimum_size.y=44
		app._label(preview,"点选据点查看，再次点击前往",13,app.MUTED,true)
		map.room_previewed.connect(func(id):
			app._clear(preview)
			var room: Dictionary={}
			for candidate in app.model.extraction.map_state().get("rooms",[]):
				if str(candidate.get("id",""))==str(id):room=candidate;break
			app._label(preview,str(room.get("name",ROOM_NAMES.get(str(room.get("type","")),"据点"))),16,app.GOLD,true)
			_button(app,preview,"前往",func():_map_choice(app,id),true))

static func _map_choice(app,id: String) -> void:
	var graph: Dictionary=app.model.extraction.map_state()
	if id==str(graph.get("currentRoomId","")):
		if app.model.state.extraction.run.get("room",{}).get("type","")!="entry":_operate(app,app.model.extraction.view_current_room())
		return
	for option in app.model.extraction.route_options():
		if str(option.id)==id:_operate(app,app.model.extraction.enter_room(id));return
	app._toast("沿连线前往相邻据点",app.CYAN)

static func _scene(app,parent: Node,run: Dictionary) -> void:
	var room: Dictionary=app.model.extraction.room_scene()
	var phase:=str(run.get("phase",""))
	room.servicesLocked=phase=="battle"
	var room_actions: Array=app.model.extraction.room_actions() if phase!="battle" and app.model.extraction.has_method("room_actions") else []
	var is_relay:bool=app.model.extraction.can_deposit()
	var room_done:=not room_actions.is_empty()
	for action in room_actions:
		if not action.get("used",false):room_done=false
	var top=app._hbox(parent,8)
	if room.has("eventIcon") and app.has_method("_rune_icon"):app._rune_icon(top,str(room.eventIcon),24,app.GOLD)
	app._label(top,str(room.get("eventTitle",room.get("name","遗境"))),19,app.GOLD)
	if not str(room.get("districtName","")).is_empty():app._label(top,str(room.districtName),12,app.MUTED)
	var spacer=Control.new();spacer.size_flags_horizontal=Control.SIZE_EXPAND_FILL;top.add_child(spacer)
	_button(app,top,"地图",func():_return_map(app)).name="ExtractionAdvance"
	var scene=RoomScene.new();scene.name="ExtractionRoomScene"
	var guards: Array=[]
	if str(run.get("phase",""))=="battle":
		for enemy_id in run.get("activeEncounter",{}).get("enemies",[]):
			guards.append({"id":str(enemy_id),"name":str(app.model.catalog.get("EnemyData",{}).get(str(enemy_id),{}).get("name",enemy_id)),"portrait":str(app.model.catalog.get("EnemyData",{}).get(str(enemy_id),{}).get("portrait","res://assets/enemies/"+str(enemy_id)+".png"))})
	scene.configure(room,app.model.extraction.containers() if phase!="battle" else [],str(room.get("selectedContainer","")),guards,app.extraction_reduced_motion)
	scene.battle_requested.connect(app._begin_extraction_battle)
	scene.service_requested.connect(func(service):
		if phase=="battle":return
		if service=="relay":_deposit_preview(app)
		elif service=="unlock":_room_action(app,"unlock","key"))
	var choosing:bool=not room_actions.is_empty() and not room_done
	scene.custom_minimum_size.y=96 if choosing else 150 if is_relay else 200
	scene.size_flags_vertical=Control.SIZE_FILL if choosing else Control.SIZE_EXPAND_FILL
	scene.size_flags_stretch_ratio=1.5;parent.add_child(scene)
	scene.container_selected.connect(func(id):
		if run.get("phase","")=="battle":app._toast("击败守卫后搜寻",app.RED);return
		if app._check(app.model.extraction.choose_container(id)):_open_container(app,id))
	var actions=app._hbox(parent,6)
	if phase=="battle":_button(app,actions,"迎战",app._begin_extraction_battle,true).name="ExtractionBattle"
	elif phase=="boss_exit":
		_button(app,actions,"撤离",func():_confirm_departure(app,true),true).name="ExtractionExit"
		if int(run.get("act",1))<app.model.extraction.max_acts():_button(app,actions,"继续深入",func():_operate(app,app.model.extraction.continue_act())).name="ExtractionNextAct"
	for box in ([] if phase=="battle" else app.model.extraction.containers()):
		var id:=str(box.id)
		var button=_button(app,actions,str(box.get("name","容器")),func():
			if app._check(app.model.extraction.choose_container(id)):_open_container(app,id))
		button.name="ExtractionOpenContainer_"+id;button.disabled=phase=="battle"
		if ResourceLoader.exists(str(box.get("sprite",""))):
			button.icon=load(str(box.sprite));button.expand_icon=true;button.add_theme_constant_override("icon_max_width",24)
	var services:Node=parent
	if not room_actions.is_empty() and not room_done:
		services=_scroll(app,parent)
		services.get_parent().name="ExtractionServiceScroll"
		services.get_parent().custom_minimum_size.y=88
		services.size_flags_vertical=Control.SIZE_EXPAND_FILL
	if is_relay:
		var panel=app._panel(services,app.GOLD.darkened(0.55),8)
		var relay=app._hbox(panel,10)
		_icon(relay,{"icon":"res://assets/items/expedition_v230/relay_chest.png"},44)
		var text=app._vbox(relay,3);text.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		var used:bool=run.get("room",{}).get("depositUsed",false)
		app._label(text,"物资已送回" if used else "远征信使",17,app.GOLD)
		var parcel:Vector2i=app.model.extraction.parcel_dimensions()
		app._label(text,"本次寄送完成" if used else "%d × %d 格 · 物资提前送回" % [parcel.x,parcel.y],12,app.TEXT,true)
		var send=_button(app,relay,"查看寄送",func():_deposit_preview(app),true)
		send.name="ExtractionDepositPreview";send.disabled=used
	if room_done:
		var result=app._panel(parent,app.CYAN.darkened(0.6),8)
		var result_row=app._hbox(result,8)
		var chosen: Dictionary={}
		for action in room_actions:
			if action.get("selected",false):chosen=action;break
		app._label(result_row,str(chosen.get("label","休整完成")),16,app.CYAN)
		app._label(result_row,str(chosen.get("description","继续探索，寻找下一处据点")),12,app.MUTED,true)
	elif not room_actions.is_empty():
		var choices=app._grid(services,1 if app.size.x<900 else mini(3,room_actions.size()))
		choices.add_theme_constant_override("h_separation",6)
		choices.size_flags_vertical=Control.SIZE_EXPAND_FILL
		for action in room_actions:
			var id:=str(action.get("id",action.get("actionId","")))
			var color:Color=EventChoice.color_for(action,app.CYAN)
			var card=app._panel(choices,color.darkened(0.6),8)
			card.name="ExtractionEventCard_"+id
			card.size_flags_vertical=Control.SIZE_EXPAND_FILL
			var choice=app._vbox(card,6)
			EventChoice.heading(app,choice,action,"coin",color)
			var preview: Dictionary=action.get("encounterPreview",{})
			if not preview.is_empty():
				var guards_row=app._hbox(choice,4);guards_row.name="ExtractionEncounterPreview_"+id
				for enemy_id in preview.get("enemies",[]):_icon(guards_row,{"icon":str(app.model.catalog.get("EnemyData",{}).get(str(enemy_id),{}).get("portrait","res://assets/enemies/"+str(enemy_id)+".png"))},32)
				app._label(guards_row,"精英战" if preview.get("isElite",false) or str(preview.get("kind",""))=="elite" else "交战",11,app.RED)
			var copy=EventChoice.body(app,choice)
			EventChoice.benefits(app,copy,action,"coin",color)
			EventChoice.costs(app,copy,action,"coin")
			var caption:="已选择" if action.get("used",false) else "选择"
			var b=_button(app,choice,caption,func():
				if id in ["deposit","send","relay"] and app.model.extraction.has_method("preview_deposit"):_deposit_preview(app)
				else:_room_action(app,id,"key" if id=="unlock" else "use"),true)
			b.name="ExtractionRoomAction_"+id
			b.disabled=not bool(action.get("enabled",true))
			if b.disabled and not str(action.get("disabledReason","")).is_empty():
				b.text=EventChoice.disabled_caption(str(action.disabledReason));b.tooltip_text=str(action.disabledReason)

static func _deposit_preview(app) -> void:
	var plan: Dictionary=app.model.extraction.preview_deposit()
	if not app._check(plan):return
	var box=app._modal("信使寄送",900,480)
	app.overlay.set_meta("deposit_selection",[])
	var row=app._hbox(box,12)
	var source=_section(app,row,"随身背包",app.CYAN)
	var source_scroll=_scroll(app,source,210)
	var bag=_grid_widget(app,source_scroll,"deposit_bag",app.model.state.extraction.run.get("bag",[]),6,5,38)
	bag.name="ExtractionDepositBag"
	bag.item_selected.connect(func(uid):
		var selected: Array=app.overlay.get_meta("deposit_selection",[]).duplicate()
		if selected.has(uid):selected.erase(uid)
		else:selected.append(uid)
		app.overlay.set_meta("deposit_selection",selected)
		bag.selected_uid="";bag.selected_uids=selected;bag.queue_redraw()
		_refresh_deposit(app))
	var dest=_section(app,row,"寄送格 · %d × %d" % [int(plan.get("width",3)),int(plan.get("height",4))],app.GOLD)
	var preview=app._vbox(dest,8);preview.name="ExtractionDepositPlan"
	var actions=app._hbox(app._modal_footer(box),8)
	_button(app,actions,"自动挑选",func():
		app.overlay.set_meta("deposit_selection",[]);bag.selected_uid="";bag.selected_uids.clear();bag.queue_redraw();_refresh_deposit(app)).name="ExtractionDepositAuto"
	var confirm=_button(app,actions,"确认寄送",func():
		var current: Dictionary=app.overlay.get_meta("deposit_plan",{})
		_complete_deposit(app,current,app.overlay.get_meta("deposit_selection",[])),true)
	confirm.name="ExtractionDepositConfirm"
	_button(app,actions,"返回",app._clear_overlay).name="ExtractionDepositCancel"
	_refresh_deposit(app,plan)

static func _complete_deposit(app,plan: Dictionary,selected: Array) -> void:
	var context:=_room_context(app)
	var result: Dictionary=app.model.extraction.deposit_items(str(plan.get("planHash","")),selected)
	if not app._check(result):return
	if app.has_method("_ui_sound"):app._ui_sound("relay")
	app._clear_overlay();app._render_screen();app._toast("物资已送回仓库",app.CYAN)
	_after_deposit_feedback(app,context,app.toast_layer.find_child("FeedbackToast",true,false))

static func _refresh_deposit(app,prepared_plan: Dictionary={}) -> void:
	var selected: Array=app.overlay.get_meta("deposit_selection",[])
	var plan: Dictionary=prepared_plan if not prepared_plan.is_empty() else app.model.extraction.preview_deposit(selected)
	app.overlay.set_meta("deposit_plan",plan)
	var parent=app.overlay.find_child("ExtractionDepositPlan",true,false)
	app._clear(parent)
	var confirm=app.overlay.find_child("ExtractionDepositConfirm",true,false)
	confirm.disabled=not bool(plan.get("success",false)) or not bool(plan.get("enabled",true))
	if not plan.get("success",false):
		app._label(parent,str(plan.get("message",plan.get("error","这些物品装不下，请减少选择"))),15,app.GOLD,true)
		app._label(parent,"点选背包物品取消选择",13,app.MUTED,true)
		return
	var parcel_height:=int(plan.get("height",4))
	var grid=_grid_widget(app,parent,"deposit",plan.get("items",[]),int(plan.get("width",3)),parcel_height,minf(46,152.0/maxi(1,parcel_height)))
	grid.mouse_filter=Control.MOUSE_FILTER_IGNORE
	app._label(parent,"已优先挑选高价值物资" if selected.is_empty() else "已手选 %d 件" % selected.size(),13,app.CYAN)
	app._label(parent,"%d 件 · %s 金币" % [plan.get("uids",[]).size(),_money(int(plan.get("value",0)))],16,app.GOLD)
	app._label(parent,"寄送费 %d 金币 · 安全送回仓库" % int(plan.get("fee",0)),12,app.MUTED,true)

static func _show_growth(app,parent: Node,constrained: bool=false) -> void:
	if not app.model.extraction.has_method("growth_choices"):return
	var choices: Array=app.model.extraction.growth_choices()
	if choices.is_empty():return
	var panel=_section(app,parent,"选择本局祝福",app.GOLD)
	var content=_scroll(app,panel) if constrained else panel
	if constrained:content.get_parent().name="ExtractionGrowthScroll"
	var row=app._grid(content,1)
	# The same cards also appear in the narrower bag sidebar; use their actual width.
	row.resized.connect(func():row.columns=clampi(int((row.size.x+14.0)/210.0),1,3))
	for raw_choice in choices:
		var choice:Dictionary=app._present_abyss_reward(raw_choice) if app.has_method("_present_abyss_reward") else raw_choice
		var id:=str(raw_choice.get("choiceId",raw_choice.get("id","")))
		var col=app._vbox(app._panel(row,app.LINE,12),8)
		RewardRarity.decorate(app,col.get_parent(),col,str(choice.get("rarity","white")))
		app._reward_choice_header(col,choice,app._owned_reward_count(app.model.extraction.run().get("blessings",[]),str(choice.get("id",""))))
		app._label(col,str(choice.get("name","祝福")),16,app.CYAN,true)
		app._label(col,str(choice.get("description",choice.get("desc",""))),13,app.TEXT,true)
		var spacer=Control.new();spacer.size_flags_vertical=Control.SIZE_EXPAND_FILL;col.add_child(spacer)
		_button(app,col,"选择",func():
			var context:=_room_context(app)
			_complete_room_operation(app,app.model.extraction.choose_growth(id),context),true).name="ExtractionGrowth_"+id

static func _party_status(app,parent: Node,run: Dictionary) -> void:
	var row=app._hbox(parent,6)
	for unit in run.get("party",[]):
		var id:=str(unit.get("id",""));var hp:=int(unit.get("currentHp",unit.get("hp",0)));var maximum:=int(unit.get("maxHp",unit.get("hp",1)))
		var panel=app._panel(row,app.LINE,5);var content=app._hbox(panel,5)
		var portrait=app._portrait(content,id,45);portrait.custom_minimum_size.x=34
		var stats=app._vbox(content,2);stats.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		var name_label=app._label(stats,app._char_name(id),12,app.TEXT);name_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
		app._progress(stats,hp,maximum,app.CYAN if hp>0 else app.RED,5)
		var hp_label=app._label(stats,"%s/%s" % [app._battle_number(hp),app._battle_number(maximum)],10,app.MUTED)
		hp_label.name="ExtractionPartyHP_"+id
		hp_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;hp_label.tooltip_text="%d / %d" % [hp,maximum]

static func _equipment_slots(app,parent: Node,_run: Dictionary) -> void:
	if app.model.state.extraction.has("equipmentNotice"):app._label(parent,"重复装备已收回",11,app.MUTED)
	var row=app._hbox(parent,6)
	row.name="ExtractionTacticalSlots"
	row.tooltip_text=str(app.model.state.extraction.get("equipmentNotice", "同类装备限一件"))
	var equipped: Array=app.model.extraction.equipped_items()
	for i in 3:
		var panel=app._panel(row,app.GOLD.darkened(0.65),4)
		panel.name="ExtractionTacticalSlot_%d" % i
		panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		var col=app._vbox(panel,1)
		if i<equipped.size():
			var item: Dictionary=equipped[i];var d: Dictionary=app.model.extraction.item_def(str(item.itemId))
			panel.add_theme_stylebox_override("panel",app._box(app.PANEL,Color.WHITE if app.extraction_scope=="equipment" and app.extraction_selected==str(item.uid) else _rarity(d).darkened(0.25),4))
			_icon(col,d,30)
			app._center_label(col,str(d.get("name","装备")),10,_rarity(d))
			app._bind_card_tap(panel,func():app.extraction_selected=str(item.uid);app.extraction_scope="equipment";_switch_panel(app,"bag" if app.model.extraction.active() else "stash",false))
		else:
			var icon_def: Dictionary=app.model.extraction.item_def(["vest","blade","scope"][i])
			if icon_def.is_empty():icon_def={"icon":"res://assets/items/extraction/"+["vest","blade","scope"][i]+".png"}
			var ghost=_icon(col,icon_def,30);ghost.modulate=Color(0.7,0.8,0.9,0.5)
			app._center_label(col,"战术装备",10,app.MUTED)

static func _utility_slots(app,parent: Node,compact: bool=false) -> void:
	if not app.model.extraction.has_method("equipment_status"):return
	var status: Dictionary=app.model.extraction.equipment_status()
	var row=app._hbox(parent,6);row.name="ExtractionUtilitySlots"
	for slot in ["armor","backpack"]:
		var info: Dictionary=status.get(slot,{})
		var item: Dictionary=info.get("item",{})
		var panel=app._panel(row,app.CYAN.darkened(0.65),5)
		var line=app._hbox(panel,6)
		var icon_name:="shield" if slot=="armor" else "bag"
		if not item.is_empty():
			_icon(line,app.model.extraction.item_def(str(item.get("itemId",""))),32 if compact else 42)
		else:_icon(line,{"icon":"res://assets/ui/runes/"+icon_name+".svg"},24)
		var col=app._vbox(line,2);col.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		if slot=="armor":
			var maximum:=float(info.get("max",0));var current:=float(info.get("current",0))
			app._label(col,"护盾 %d%%" % roundi(100.0*current/maximum) if maximum>0 else "未装护盾",12,app.CYAN)
			if maximum>0:
				app._progress(col,current,maximum,app.CYAN,3)
				if not compact:
					var d:Dictionary=app.model.extraction.item_def(str(item.get("itemId","")))
					app._label(col,str(d.get("name","护盾装备")),11,_rarity(d))
					app._label(col,"吸收 %d / %d" % [int(current),int(maximum)],11,app.MUTED)
		else:
			app._label(col,"背包 %d 格" % int(info.get("cells",30)),12,app.GOLD)
			if not compact:app._label(col,str(app.model.extraction.item_def(str(item.get("itemId",""))).get("name","旅人背包")),11,app.MUTED)
		if not compact and not item.is_empty():
			var slot_id:=str(slot)
			_button(app,col,"卸下",func():_operate_sound(app,app.model.extraction.remove_utility_slot(slot_id),"equip")).name="ExtractionRemoveUtility_"+slot_id
	if not compact and app.model.state.extraction.get("run",{}).is_empty() and app.model.extraction.has_method("repair_quote"):
		var quote: Dictionary=app.model.extraction.repair_quote()
		if int(quote.get("missing",0))>0:
			var repair=_button(app,parent,"修复护盾装备 · %d 金币" % int(quote.get("cost",0)),func():_operate_sound(app,app.model.extraction.repair_equipment(),"repair"))
			repair.name="ExtractionRepair";repair.disabled=not bool(quote.get("enabled",false))

static func _grid_widget(app,parent: Node,scope: String,items: Array,columns: int,rows: int,cell_size: float=42) -> Control:
	if scope in ["bag","search_bag","deposit_bag"]:
		var dims: Vector2i=app.model.extraction.dimensions("bag")
		columns=dims.x;rows=dims.y
	var defs: Dictionary={}
	var displayed: Array=items.duplicate(true)
	for item in displayed:
		defs[str(item.itemId)]=app.model.extraction.item_def(str(item.itemId))
		if app.model.extraction.has_method("item_value"):item.displayValue=app.model.extraction.item_value(item)
	var grid=Grid.new();grid.name="ExtractionGrid_"+scope;grid.preferred_cell=cell_size;grid.reduced_motion=app.extraction_reduced_motion
	grid.configure(columns,rows,displayed,defs,app.extraction_selected if app.extraction_scope==scope else "")
	parent.add_child(grid)
	grid.size_flags_horizontal=Control.SIZE_SHRINK_CENTER;grid.custom_minimum_size.x=columns*cell_size
	return grid

static func _bag(app,run: Dictionary) -> void:
	var row=_workspace(app,app.main_body,12);row.size_flags_vertical=Control.SIZE_EXPAND_FILL
	var left=_section(app,row,"随身背包 · %d / %d 格" % [_used_cells(app,run.get("bag",[])),_bag_cells(app)],app.CYAN)
	_party_status(app,left,run)
	var bag_scroll=_scroll(app,left)
	var grid=_grid_widget(app,bag_scroll,"bag",run.get("bag",[]),6,5,42)
	var right_panel=_section(app,row,"角色与装备",app.GOLD)
	var right=_scroll(app,right_panel)
	_equipment_slots(app,right,run)
	_utility_slots(app,right)
	var detail=app._vbox(right,6);detail.name="ExtractionItemDetail"
	_render_inventory_detail(app,detail,"bag",run.get("bag",[]))
	grid.item_selected.connect(func(uid):app.extraction_scope="bag";app.extraction_selected=uid;app._clear(detail);_render_inventory_detail(app,detail,"bag",run.get("bag",[])))
	var tools=app._hbox(left,6)
	_button(app,tools,"自动整理",func():_sort_animated(app,"bag")).name="ExtractionSort_bag"
	_button(app,tools,"补给",func():_quick_supplies(app)).name="ExtractionQuickSupplies"
	_show_growth(app,right)

static func _render_inventory_detail(app,parent: Node,scope: String,items: Array) -> void:
	if app.extraction_scope=="equipment":
		for item in app.model.extraction.equipped_items():
			if str(item.uid)==app.extraction_selected:
				_item_title(app,parent,_item_display_def(app,item))
				app._label(parent,"已穿戴 · 同类限一件",12,app.CYAN)
				_button(app,parent,"卸回背包" if app.model.extraction.active() else "卸回仓库",func():_operate_sound(app,app.model.extraction.unequip_item(str(item.uid)),"equip"))
				return
	for item in items:
		if app.extraction_scope==scope and str(item.uid)==app.extraction_selected:_selected(app,parent,scope,item);return
	app._label(parent,"点选物品查看详情",15,app.MUTED,true)

static func _selected(app,parent: Node,scope: String,item: Dictionary) -> void:
	var d: Dictionary=app.model.extraction.item_def(str(item.itemId)).duplicate(true);var uid:=str(item.uid)
	if app.model.extraction.has_method("item_value"):d.value=app.model.extraction.item_value(item);d.originAct=int(item.get("originAct",1))
	_item_title(app,parent,d)
	_manual_controls(app,parent,scope,item)
	var actions=app._flow(parent,6)
	var utility_slot:=str(d.get("slot",""))
	if utility_slot in ["armor","backpack"] and app.model.extraction.has_method("set_utility_slot"):
		_button(app,actions,"装配护盾装备" if utility_slot=="armor" else "更换背包",func():_operate_sound(app,app.model.extraction.set_utility_slot(utility_slot,uid),"equip"),true)
	if scope=="bag":
		if d.get("kind","")=="equipment" and utility_slot.is_empty():_button(app,actions,"装备",func():_equip_bag(app,parent,uid),true).name="ExtractionEquip_"+uid
		if d.get("kind","")=="consumable":
			var use_button=_button(app,actions,"使用",func():_operate_sound(app,app.model.extraction.use_item(uid),"use"),true)
			use_button.name="ExtractionUse_"+uid
			use_button.disabled=not app.model.extraction.can_use_consumable(str(item.itemId))
		_button(app,actions,"丢弃",func():app._confirm("丢弃物资？",str(d.get("name","物资")),func():_operate(app,app.model.extraction.discard_item(uid))))
	else:
		if d.get("kind","")=="equipment":_button(app,actions,"装备",func():_equip_bag(app,parent,uid),true).name="ExtractionEquip_"+uid
		_button(app,actions,"出售",func():_operate_sound(app,app.model.extraction.sell_item(uid),"coin"))
		
		if int(d.get("rarity",0))>=4:_button(app,actions,"收藏",func():_operate_sound(app,app.model.extraction.collect_item(uid),"pickup"))
		if utility_slot.is_empty():_button(app,actions,"携带",func():_operate(app,app.model.extraction.bring_item(uid)),true).name="ExtractionBring_"+uid

static func _cancel_pending_placement(app,id: String,resume_search: bool=true) -> void:
	var grid=app.overlay.find_child("ExtractionGrid_search_bag",true,false)
	if not is_instance_valid(grid):return
	var was_active:bool=grid.placement_mode or grid.has_meta("exchange_callback")
	grid.placement_mode=false
	if grid.has_meta("exchange_callback"):
		var callback:Callable=grid.get_meta("exchange_callback")
		if grid.selection_changed.is_connected(callback):grid.selection_changed.disconnect(callback)
		grid.remove_meta("exchange_callback");grid.multi_select=false;grid.set_meta("inventory_selection",false);grid.selected_uids=[]
	grid.queue_redraw()
	if was_active and resume_search:_queue_search(app,id)

static func _manual_controls(app,parent: Node,scope: String,item: Dictionary,container_id: String="") -> void:
	var uid:=str(item.uid)
	var actions=app._hbox(parent,4)
	_button(app,actions,"指定位置收下" if scope=="container" else "移动 / 旋转",func():_begin_placement(app,parent,scope,item,container_id)).name="ExtractionMove_"+uid

static func _begin_placement(app,parent: Node,scope: String,item: Dictionary,container_id: String="") -> void:
	var grid=app.overlay.find_child("ExtractionGrid_search_bag",true,false) if not container_id.is_empty() else app.main_body.find_child("ExtractionGrid_"+scope,true,false)
	if not is_instance_valid(grid):return
	var d:Dictionary=_item_display_def(app,item)
	var uid:=str(item.uid)
	if not container_id.is_empty():_stop_search(app,false)
	grid.placement_mode=true;grid.placement_uid=uid;grid.multi_select=false;grid.set_meta("inventory_selection",false)
	grid.set_meta("placement_rotated",bool(item.get("rotated",false)))
	grid.placement_size=Vector2i(int(d.get("height",1)),int(d.get("width",1))) if item.get("rotated",false) else Vector2i(int(d.get("width",1)),int(d.get("height",1)))
	grid.placement_cell=Vector2i(int(item.get("x",0)),int(item.get("y",0)));grid.queue_redraw()
	app._clear(parent)
	_item_title(app,parent,d)
	app._label(parent,"点选目标格放置",14,app.CYAN)
	var actions=app._flow(parent,4)
	_button(app,actions,"旋转",func():
		grid.set_meta("placement_rotated",not bool(grid.get_meta("placement_rotated",false)))
		grid.placement_size=Vector2i(grid.placement_size.y,grid.placement_size.x);grid.queue_redraw()).name="ExtractionRotate_"+uid
	_button(app,actions,"取消移动",func():
		grid.placement_mode=false;grid.queue_redraw()
		if not container_id.is_empty():
			_queue_search(app,container_id)
			if scope=="container":_select_container_item(app,container_id,uid)
			else:_select_search_bag_item(app,container_id,uid)
		else:app._clear(parent);_selected(app,parent,scope,item)).name="ExtractionCancelMove"
	# Replace the previous pending placement callback, leaving scrolling and selection intact.
	if grid.has_meta("placement_callback"):
		var previous:Callable=grid.get_meta("placement_callback")
		if grid.cell_selected.is_connected(previous):grid.cell_selected.disconnect(previous)
	var callback=func(x:int,y:int):
		if not grid.placement_mode:return
		var rotated:=bool(grid.get_meta("placement_rotated",false))
		var result:Dictionary
		if scope=="container":result=app.model.extraction.take_item_at(container_id,uid,x,y,rotated)
		else:result=app.model.extraction.move_item(scope,uid,x,y,rotated)
		if not app._check(result):return
		app._ui_sound("pickup" if scope=="container" else "tap")
		grid.placement_mode=false;grid.queue_redraw()
		if not container_id.is_empty():
			_queue_search(app,container_id)
			if scope=="container":_fly_to_bag(app,container_id,item,d)
			_refresh_search_grids(app,container_id)
			_select_search_bag_item(app,container_id,uid)
		else:
			var contents:Array=app.model.state.extraction.stash if scope=="stash" else app.model.state.extraction.run.bag
			var dims:Vector2i=app.model.extraction.dimensions(scope)
			grid.configure(dims.x,dims.y,contents,grid.definitions,uid)
			app._clear(parent)
			for moved in contents:
				if str(moved.uid)==uid:_selected(app,parent,scope,moved);break
	grid.set_meta("placement_callback",callback);grid.cell_selected.connect(callback)

static func _stash(app,state: Dictionary) -> void:
	var row=_workspace(app,app.main_body,12);row.size_flags_vertical=Control.SIZE_EXPAND_FILL
	var left=_section(app,row,"营地仓库",app.CYAN);left.get_parent().size_flags_stretch_ratio=1.5
	var actions=app._hbox(left,6);actions.name="ExtractionStashToolbar"
	var selection_label=app._label(actions,"长按物品，划过批量选择",13,app.MUTED)
	var contents=_scroll(app,left)
	var grid=_grid_widget(app,contents,"stash",state.get("stash",[]),10,12,50)
	grid.size_flags_horizontal=Control.SIZE_SHRINK_CENTER;grid.custom_minimum_size.x=minf(500,app.size.x-70);grid.allow_multi_select=true
	var right=_section(app,row,"物资详情",app.GOLD);right.get_parent().size_flags_stretch_ratio=1
	var detail=app._vbox(right,8);detail.size_flags_vertical=Control.SIZE_EXPAND_FILL
	_render_inventory_detail(app,detail,"stash",state.get("stash",[]))
	grid.item_selected.connect(func(uid):app.extraction_scope="stash";app.extraction_selected=uid;app._clear(detail);_render_inventory_detail(app,detail,"stash",state.get("stash",[])))
	var batch=app._vbox(right,6);batch.name="ExtractionStashActions"
	grid.selection_changed.connect(func(uids):
		selection_label.text="已选 %d 件" % uids.size()
		app._clear(detail);app._label(detail,"批量管理",20,app.GOLD)
		app._label(detail,"继续划过物品即可选中",14,app.MUTED,true)
		var value:=0
		for item in state.get("stash",[]):
			if uids.has(str(item.uid)) and not app.model.extraction.protected_item(str(item.uid)):value+=app.model.extraction.item_value(item) if app.model.extraction.has_method("item_value") else int(app.model.extraction.item_def(str(item.itemId)).get("value",0))
		app._label(detail,"出售可得 %s 金币" % _money(value),18,app.GOLD)
		app._clear(batch)
		_button(app,batch,"出售所选",func():_batch_operation(app,"sell_items",grid.selected_uids),true).disabled=uids.is_empty()
		_button(app,batch,"收藏所选",func():_batch_operation(app,"collect_items",_collectible_uids(app,grid.selected_uids))).disabled=uids.is_empty() or _collectible_uids(app,uids).is_empty()
		_button(app,batch,"取消选择",func():grid.multi_select=false;grid.set_meta("inventory_selection",false);grid.selected_uids.clear();grid.queue_redraw();app._clear(batch);app._clear(detail);_render_inventory_detail(app,detail,"stash",state.get("stash",[]))))
	_button(app,actions,"多选",func():
		grid.multi_select=not grid.multi_select;grid.selected_uid="";grid.selected_uids.clear();grid.queue_redraw();grid.set_meta("inventory_selection",grid.multi_select)
		selection_label.text="划过物品连续选择" if grid.multi_select else "点选查看详情"
		if grid.multi_select:grid.selection_changed.emit([])
		else:app._clear(batch);app._clear(detail);_render_inventory_detail(app,detail,"stash",state.get("stash",[]))).name="ExtractionStashMulti"
	_button(app,actions,"整理",func():_sort_animated(app,"stash")).name="ExtractionSort_stash"
	var bulk=app._hbox(left,6)
	_button(app,bulk,"一键收藏",func():_stash_bulk_preview(app,true)).name="ExtractionCollectAll"
	_button(app,bulk,"出售全部",func():_stash_bulk_preview(app,false)).name="ExtractionSellAll"
	if not state.get("mailbox",[]).is_empty():_button(app,right,"领取待收物资",func():_operate(app,app.model.extraction.claim_mail()),true)
	if state.get("run",{}).is_empty():
		app._label(right,"已携带 %d / 3 件" % state.get("loadout",[]).size(),14,app.GOLD)
		_button(app,right,"查看出战整备",func():_switch_panel(app,"expedition"))

static func _collectible_uids(app,selection: Array=[]) -> Array:
	var choices:Dictionary={}
	for item in app.model.state.extraction.stash:
		if not selection.is_empty() and not selection.has(str(item.uid)):continue
		var id:=str(item.itemId);var d:Dictionary=app.model.extraction.item_def(id)
		if app.model.extraction.protected_item(str(item.uid)) or int(d.get("rarity",0))<4 or app.model.state.extraction.collection.has(id):continue
		if not choices.has(id) or app.model.extraction.item_value(item)<app.model.extraction.item_value(choices[id]):choices[id]=item
	var result:Array=[]
	for item in choices.values():result.append(str(item.uid))
	return result

static func _stash_bulk_preview(app,collect: bool) -> void:
	var uids:Array=_collectible_uids(app) if collect else []
	if not collect:
		for item in app.model.state.extraction.stash:
			if not app.model.extraction.protected_item(str(item.uid)):uids.append(str(item.uid))
	var value:=0
	for item in app.model.state.extraction.stash:
		if uids.has(str(item.uid)) and not app.model.extraction.protected_item(str(item.uid)):value+=app.model.extraction.item_value(item)
	var box=app._modal("收藏金红珍品" if collect else "出售仓库全部物资",650,420)
	app._rune_icon(box,"book" if collect else "coin",40,app.GOLD)
	app._label(box,"收藏 %d 种新珍品" % uids.size() if collect else "%d 件 · %s 金币" % [uids.size(),_money(value)],23,app.GOLD)
	app._label(box,"每种取一件，重复珍品留在仓库" if collect else "出售仓库闲置物资；已穿戴装备保留。",14,app.TEXT,true)
	var icons=app._flow(box,5);var count:=0
	for item in app.model.state.extraction.stash:
		if uids.has(str(item.uid)) and count<12:_icon(icons,app.model.extraction.item_def(str(item.itemId)),36);count+=1
	var actions=app._hbox(app._modal_footer(box),8)
	var confirm=_button(app,actions,"确认收藏" if collect else "确认出售全部",func():
		var result:Dictionary=app.model.extraction.collect_items(uids) if collect else app.model.extraction.sell_items(uids)
		if app._check(result):
			app._ui_sound("pickup" if collect else "coin");app._clear_overlay();app.extraction_selected="";app._render_screen(),true)
	confirm.name="ExtractionCollectAllConfirm" if collect else "ExtractionSellAllConfirm";confirm.disabled=uids.is_empty()
	_button(app,actions,"返回",func():app._clear_overlay()).name="ExtractionBulkCancel"

static func _batch_operation(app,method: String,uids: Array) -> void:
	if app.model.extraction.has_method(method):_operate_sound(app,app.model.extraction.call(method,uids.duplicate()),"coin" if method=="sell_items" else "pickup")

static func _supply_category(d: Dictionary) -> String:
	var slot:=str(d.get("slot",""))
	if slot in ["armor","backpack"]:return slot
	return str(d.get("kind","loot"))

static func _shop(app,state: Dictionary) -> void:
	var row=_workspace(app,app.main_body,12);row.size_flags_vertical=Control.SIZE_EXPAND_FILL
	var left=_section(app,row,"补给站",app.GOLD);left.get_parent().size_flags_stretch_ratio=1.6
	var filters=app._flow(left,4)
	var filter:=str(app.get_meta("extraction_shop_filter","all"))
	for entry in [["all","全部"],["armor","护盾"],["backpack","背包"],["equipment","装备"],["consumable","消耗品"],["key","钥匙"]]:
		var key:=str(entry[0])
		app._tab_button(filters,str(entry[1]),func():app.set_meta("extraction_shop_filter",key);app._render_screen(),filter==key).name="ExtractionShopFilter_"+key
	var list=_scroll(app,left)
	list.get_parent().name="ExtractionSupplyScroll"
	app._restore_shop_list(list.get_parent(),"extraction/shop/"+filter)
	var cards=app._grid(list,2 if app.size.x<900 else 3);cards.add_theme_constant_override("h_separation",8);cards.add_theme_constant_override("v_separation",8)
	for id in app.model.extraction.data.get("items",{}):
		var d: Dictionary=app.model.extraction.item_def(str(id))
		if int(d.get("buyPrice",0))<=0:continue
		if filter!="all" and _supply_category(d)!=filter:continue
		var item_id:=str(id);var required:=int(d.get("buyMinRisk",0));var locked:=int(state.get("unlockedDifficulty",0))<required
		var p=app._panel(cards,_rarity(d).darkened(0.65),8);p.custom_minimum_size.x=135
		var col=app._vbox(p,5);var line=app._hbox(col,4);_icon(line,d,42)
		app._label(line,str(d.get("name",id)),13,_rarity(d),true)
		var effect=app._label(col,str(d.get("description","")),12,app.TEXT,true)
		effect.name="ExtractionSupplyEffect_"+item_id
		app._label(col,"钥匙串 · 独立堆叠" if d.get("kind","")=="key" else "%d × %d 格" % [int(d.get("width",1)),int(d.get("height",1))],11,app.MUTED)
		var b=_button(app,col,"危险 %d 解锁" % required if locked else "%d 金币 · 购买" % int(d.buyPrice),func():_operate_sound(app,app.model.extraction.buy_supply(item_id),"coin"),not locked)
		b.name="ExtractionBuy_"+item_id;b.disabled=locked
	var right=_section(app,row,"携带与储备",app.CYAN);right.get_parent().size_flags_stretch_ratio=1
	var preparation=_scroll(app,right)
	preparation.get_parent().name="ExtractionPreparationScroll"
	app._restore_shop_list(preparation.get_parent(),"extraction/shop/preparation/"+filter)
	_utility_slots(app,preparation)
	_loadout(app,preparation,state)
	_button(app,right,"打开仓库",func():_switch_panel(app,"stash"))

static func _loadout(app,parent: Node,state: Dictionary) -> void:
	if not state.get("run",{}).is_empty():app._label(parent,"行动中，补给存入仓库",14,app.MUTED,true);return
	app._label(parent,"战术装备 · 同类限一件",14,app.GOLD)
	_equipment_slots(app,parent,{})
	var loadout: Array=state.get("loadout",[])
	app._label(parent,"携带 %d / 3" % loadout.size(),16,app.GOLD)
	for i in 3:
		var panel=app._panel(parent,app.LINE,6);var row=app._hbox(panel,6)
		if i<loadout.size():
			var item: Dictionary=loadout[i];var d: Dictionary=app.model.extraction.item_def(str(item.itemId))
			_icon(row,d,36);app._label(row,str(d.get("name","物资")),13,_rarity(d),true)
			_button(app,row,"放回",func():_operate(app,app.model.extraction.store_item(str(item.uid))))
		else:app._label(row,"空位 · 从仓库携带",13,app.MUTED)

static func _show_run_value(app) -> void:
	var run:Dictionary=app.model.state.extraction.run
	var box=app._modal("本局收获",500,390)
	for entry in [["bag","随身物资",_value(app,run.get("bag",[])+run.get("equipped",[]))],["check","已寄存",int(run.get("securedValue",0))]]:
		var card=app._panel(box,app.GOLD.darkened(.7),10)
		var line=app._hbox(card,10);app._rune_icon(line,str(entry[0]),28,app.GOLD)
		app._label(line,str(entry[1]),16,app.TEXT)
		var spacer=Control.new();spacer.size_flags_horizontal=Control.SIZE_EXPAND_FILL;line.add_child(spacer)
		app._label(line,_money(int(entry[2])),20,app.GOLD)
	_button(app,app._modal_footer(box),"返回",func():app._clear_overlay()).name="ExtractionValueClose"

static func _keyring(app) -> void:
	var box=app._modal("钥匙串",620,450)
	var list=app._vbox(box,8)
	app._label(list,"独立保管 · 随身开锁",14,app.CYAN)
	var owned:Dictionary={}
	for key in app.model.extraction.keyring():owned[str(key.itemId)]=key
	for item_id in app.model.extraction.data.items:
		var d:Dictionary=app.model.extraction.item_def(str(item_id))
		if d.get("kind","")!="key":continue
		var id:=str(item_id)
		var card=app._panel(list,_rarity(d).darkened(.65),8)
		var line=app._hbox(card,8);_icon(line,d,48)
		var info=app._vbox(line,4);info.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		app._label(info,str(d.get("name",id)),15,_rarity(d),true)
		app._label(info,str(d.get("description","")),12,app.TEXT,true)
		app._label(line,"× %d" % int(owned.get(id,{}).get("count",0)),22,app.GOLD).name="ExtractionKeyCount_"+id
		if app.model.state.extraction.run.is_empty() or app.model.extraction.can_trade_keys():
			_button(app,info,"购买 · %d 金币" % int(d.get("buyPrice",0)),func():
				if app._check(app.model.extraction.buy_keys(id,1)):
					app._ui_sound("coin");app._render_screen();_keyring(app)).name="ExtractionBuyKey_"+id
	_button(app,app._modal_footer(box),"返回",func():app._clear_overlay()).name="ExtractionSupplyClose"
	box.get_parent().name="ExtractionKeyringScroll"
	app._restore_shop_list(box.get_parent(),"extraction/keyring")

static func _quick_supplies(app) -> void:
	var box=app._modal("随身补给",580,420)
	app._label(box,"锁定仅防自动换出，仍可直接使用",12,app.MUTED,true)
	var list=app._vbox(box,8)
	var count:=0
	for item in app.model.state.extraction.run.get("bag",[]):
		var d:Dictionary=app.model.extraction.item_def(str(item.itemId))
		if d.get("kind","")!="consumable":continue
		count+=1
		var card=app._panel(list,_rarity(d).darkened(.65),6)
		var line=app._hbox(card,8);_icon(line,d,42)
		var info=app._vbox(line,3);info.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		app._label(info,str(d.get("name","补给")),15,_rarity(d),true)
		app._label(info,str(d.get("description","")),12,app.TEXT,true)
		var uid:=str(item.uid)
		var actions=app._hbox(line,4)
		actions.size_flags_vertical=Control.SIZE_SHRINK_CENTER
		var lock_button=_button(app,actions,"未锁",func():_toggle_supply_lock(app,uid))
		lock_button.name="ExtractionSupplyLock_"+uid
		_supply_lock_style(app,lock_button,bool(item.get("exchangeLocked",false)))
		var button=_button(app,actions,"使用",func():
			if app._check(app.model.extraction.use_item(uid)):
				app._ui_sound("use");app._render_screen();_quick_supplies(app),true)
		button.name="ExtractionQuickUse_"+uid;button.disabled=not app.model.extraction.can_use_consumable(str(item.itemId))
	if count==0:app._label(list,"背包暂无消耗品",16,app.MUTED)
	_button(app,app._modal_footer(box),"返回",func():app._clear_overlay()).name="ExtractionSupplyClose"
	box.get_parent().name="ExtractionKeyringScroll"
	app._restore_shop_list(box.get_parent(),"extraction/keyring")

static func _supply_lock_style(app,button: Button,locked: bool) -> void:
	button.set_meta("exchange_locked",locked)
	button.text="已锁" if locked else "未锁"
	button.tooltip_text="已保护：自动换入会保留此物品" if locked else "自动换入可替换此物品"
	app._button_icon(button,"lock_closed" if locked else "lock_open")
	button.add_theme_color_override("font_color",app.GOLD if locked else app.MUTED)
	button.add_theme_color_override("icon_normal_color",app.GOLD if locked else app.MUTED)

static func _toggle_supply_lock(app,uid: String) -> void:
	var button=app.overlay.find_child("ExtractionSupplyLock_"+uid,true,false)
	if not is_instance_valid(button):return
	var locked:=not bool(button.get_meta("exchange_locked",false))
	if app._check(app.model.extraction.set_consumable_exchange_lock(uid,locked)):
		_supply_lock_style(app,button,locked)
		app._ui_sound("equip")

static func _confirm_abandon(app) -> void:
	var box=app._modal("放弃本次行动？",580,340)
	var notice=app._panel(box,app.RED.darkened(.65),12)
	var summary=app._hbox(notice,12);app._rune_icon(summary,"bag",32,app.RED)
	var copy=app._vbox(summary,6)
	copy.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	copy.name="ExtractionAbandonSummary"
	var run:Dictionary=app.model.extraction.run()
	var items:Array=run.get("bag",[])+run.get("equipped",[])
	var value:=0
	for item in items:value+=int(app.model.extraction.item_value(item))
	app._label(copy,"随身物资将遗失",17,app.TEXT,true)
	app._label(copy,"背包与战术装备共 %d 件 · 价值 %s 金币" % [items.size(),_money(value)],14,app.MUTED,true)
	app._label(copy,"本局祝福随行动结束清空",13,app.MUTED,true)
	app._label(copy,"已寄送物资保留",13,app.CYAN,true)
	var actions=app._hbox(app._modal_footer(box),12)
	var cancel=_button(app,actions,"继续探索",app._clear_overlay,true)
	cancel.name="ExtractionAbandonCancel"
	cancel.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var confirm=_button(app,actions,"确认放弃",func():
		app._clear_overlay();_stop_search(app,false);_operate(app,app.model.extraction.retreat()))
	confirm.name="ExtractionAbandonConfirm"
	confirm.size_flags_horizontal=Control.SIZE_EXPAND_FILL

static func _build(app,run: Dictionary) -> void:
	var col=_scroll(app,app.main_body)
	app._label(col,"本局构筑",22,app.GOLD)
	if app.model.extraction.has_method("growth_summary"):
		var blessings: Array=app.model.extraction.growth_summary()
		if blessings.is_empty():app._label(col,"探索据点、击败敌人，获得本局祝福",15,app.MUTED,true)
		var cards=app._grid(col,3 if app.size.x>=900 else 2)
		for blessing in blessings:
			var card=_section(app,cards,str(blessing.get("name","祝福")),app.GOLD)
			RewardRarity.decorate(app,card.get_parent(),card,str(blessing.get("rarity","white")))
			if app.has_method("_rune_icon"):app._reward_art_icon(card,blessing,30)
			app._label(card,str(blessing.get("description","")),14,app.TEXT,true)
			if int(blessing.get("stacks",1))>1:app._label(card,"叠加 %d 层" % int(blessing.stacks),13,app.CYAN)
	_equipment_slots(app,col,run)
	_show_growth(app,col)

static func _collection(app,state: Dictionary) -> void:
	var col=_scroll(app,app.main_body)
	var collected: Array=state.get("collection",[]);var catalog: Dictionary=app.model.extraction.data.get("items",{})
	var treasures:Array=[];var owned_count:=0
	for id in catalog:
		if int(app.model.extraction.item_def(str(id)).get("rarity",0))<4:continue
		treasures.append(str(id))
		if collected.has(str(id)):owned_count+=1
	var heading=app._hbox(col,10);app._rune_icon(heading,"book",30,app.GOLD)
	app._label(heading,"金红珍藏  %d / %d" % [owned_count,treasures.size()],22,app.GOLD).name="ExtractionCollectionProgress"
	app._progress(col,owned_count,maxi(1,treasures.size()),app.GOLD,5)
	var cards=app._grid(col,maxi(2,mini(6,int((app.size.x-40)/160))))
	for id in treasures:
		var d: Dictionary=app.model.extraction.item_def(id);var owned:=collected.has(id)
		var p=app._panel(cards,_rarity(d).darkened(.25) if owned else app.LINE,10);p.custom_minimum_size.x=125;p.name="ExtractionCollection_"+id
		var card=app._vbox(p,6)
		var art=_icon(card,d,70);art.name="CollectionArt";art.modulate=Color.WHITE if owned else Color(.08,.10,.13,1)
		app._label(card,str(d.get("name","珍品")),13,_rarity(d) if owned else app.MUTED,true)
		var badge=app._hbox(card,5)
		_icon(badge,{"icon":"res://assets/ui/runes/check.svg" if owned else "res://assets/ui/runes/lock.svg"},20)
		app._label(badge,"已收藏" if owned else "未发现",12,app.GOLD if owned else app.MUTED)

static func _icon(parent: Node,d: Dictionary,side: float=48) -> TextureRect:
	var image=TextureRect.new();image.custom_minimum_size=Vector2(side,side)
	image.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;image.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;image.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var path:=str(d.get("icon",""))
	if ResourceLoader.exists(path):image.texture=load(path)
	parent.add_child(image);return image

static func _rarity(d: Dictionary) -> Color:
	return COLORS[clampi(int(d.get("rarity",0)),0,5)]

static func _item_display_def(app,item: Dictionary) -> Dictionary:
	var definition:Dictionary=app.model.extraction.item_def(str(item.get("itemId",""))).duplicate(true)
	definition.value=app.model.extraction.item_value(item)
	definition.originAct=int(item.get("originAct",1))
	return definition

static func _item_title(app,parent: Node,d: Dictionary) -> void:
	var row=app._hbox(parent,8);_icon(row,d,48)
	var text=app._vbox(row,3);text.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var title_row=app._hbox(text,6)
	app._label(title_row,str(d.get("name","遗境物资")),18,_rarity(d),true)
	var item_id:=str(d.get("icon","")).get_file().get_basename()
	if not item_id.is_empty() and int(d.get("rarity",0))>=4:
		var chip=app._panel(title_row,app.GOLD.darkened(0.6),3);chip.size_flags_horizontal=Control.SIZE_SHRINK_END
		app._label(chip,"已收藏" if app.model.state.extraction.get("collection",[]).has(item_id) else "新藏品",10,app.GOLD)
	if d.get("kind","")=="key":app._label(text,"钥匙串 · 独立堆叠",12,app.CYAN)
	else:app._label(text,"%s   %d × %d 格   %s 金币" % [RARITIES[clampi(int(d.get("rarity",0)),0,5)],int(d.get("width",1)),int(d.get("height",1)),_money(int(d.get("value",0)))],12,app.MUTED,true)
	if d.get("kind","")=="loot" and int(d.get("originAct",1))>1:
		var provenance=app._panel(parent,app.GOLD.darkened(.6),5)
		app._label(provenance,"深层珍藏 · 第 %d 幕" % int(d.originAct),12,app.GOLD)
	var description:=str(d.get("description",""))
	if not description.is_empty() and d.get("kind","")!="loot":app._label(parent,description,13,app.TEXT,true)
	if description.is_empty() and float(d.get("heal",0))>0:app._label(parent,"全队恢复 %d%% 生命" % roundi(float(d.heal)*100),13,app.CYAN,true)

static func _container(app,id: String) -> Dictionary:
	for box in app.model.extraction.containers():
		if str(box.id)==id:return box
	return {}

static func _open_container(app,id: String) -> void:
	var container:=_container(app,id)
	if container.is_empty():return
	_stop_search(app,false)
	app.extraction_search_container=id
	var box=app._modal("",1150,520)
	box.add_theme_constant_override("separation",8)
	var modal=app.overlay.find_child("ModalPanel",true,false)
	var context:=_room_context(app)
	context.modalId=modal.get_instance_id()
	modal.set_meta("extraction_context",context)
	modal.add_theme_stylebox_override("panel",app._box(app.PANEL,app.GOLD.darkened(0.55),12))
	if box.get_child_count()>0:var old=box.get_child(0);box.remove_child(old);old.queue_free()
	app.overlay.set_meta("extraction_container",id);app.overlay.set_meta("loot_history",[]);app.overlay.set_meta("manual_loot_selection","");app.overlay.set_meta("pending_loot",0)
	var heading=app._hbox(box,8)
	app._label(heading,str(container.get("name","搜寻物资")),22,app.GOLD)
	var spacer=Control.new();spacer.size_flags_horizontal=Control.SIZE_EXPAND_FILL;heading.add_child(spacer)
	_button(app,heading,"×",func():_close_container(app,context)).name="ExtractionCloseContainer"
	var controls=app._hbox(box,8);controls.name="ExtractionSearchToolbar"
	var toggle=CheckButton.new();toggle.text="自动收下";toggle.button_pressed=app.extraction_auto_pick;toggle.custom_minimum_size.y=40
	controls.add_child(toggle);toggle.name="ExtractionAutoPick"
	toggle.toggled.connect(func(on):app.extraction_auto_pick=on;app._save_preferences())
	var status=app._label(controls,"逐件发现物资",13,app.MUTED,true);status.name="ExtractionSearchStatus";status.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var split=app._hbox(box,10);split.name="ExtractionLootSplit"
	var source=_section(app,split,"容器",app.CYAN)
	var bag_dimensions: Vector2i=app.model.extraction.dimensions("bag")
	var dest=_section(app,split,"背包 %d / %d 格" % [_used_cells(app,app.model.state.extraction.run.get("bag",[])),bag_dimensions.x*bag_dimensions.y],app.GOLD)
	dest.get_child(0).name="ExtractionSearchBagHeading"
	var information=_section(app,split,"物资详情",app.CYAN)
	var preferred:=minf(52,floorf((app.size.x-144)/18))
	app.overlay.set_meta("loot_cell",preferred)
	var source_scroll=_scroll(app,source,preferred*5)
	source_scroll.get_parent().name="ExtractionContainerScroll"
	var container_grid=Grid.new();container_grid.name="ExtractionContainer_"+id;container_grid.preferred_cell=preferred;container_grid.reduced_motion=app.extraction_reduced_motion
	source_scroll.add_child(container_grid)
	container_grid.item_selected.connect(func(uid):_select_container_item(app,id,uid))
	var bottom=app._hbox(source,6);bottom.name="ExtractionContainerActions"
	_button(app,bottom,"收下全部",func():_take_all(app,id),true).name="ExtractionTakeAll"
	_button(app,bottom,"一键换入",func():_smart_loot(app,id)).name="ExtractionSmartLoot"
	var progress=app._progress(source,0,1,app.CYAN,3);progress.name="SearchProgress_"+id
	var bag_scroll=_scroll(app,dest,preferred*5)
	var bag_grid=_grid_widget(app,bag_scroll,"search_bag",app.model.state.extraction.run.get("bag",[]),6,5,preferred)
	bag_grid.item_selected.connect(func(uid):_select_search_bag_item(app,id,uid))
	var history=app._hbox(dest,5);history.name="ExtractionLootHistory"
	var detail_scroll=_scroll(app,information,preferred*5+52)
	var detail=app._vbox(detail_scroll,8);detail.name="ExtractionSearchDetail"
	_party_status(app,detail,app.model.state.extraction.run)
	app._label(detail,"点选物资查看详情",14,app.MUTED,true)
	app._label(detail,"背包满时，也可直接使用补给或替换装备。",13,app.MUTED,true)
	_refresh_search_grids(app,id);_refresh_search_controls(app,id)
	_queue_search(app,id)

static func _select_search_bag_item(app,id: String,uid: String) -> void:
	_cancel_pending_placement(app,id)
	app.overlay.set_meta("manual_loot_selection","bag:"+uid)
	app.overlay.set_meta("detail_uid","bag:"+uid)
	var detail=app.overlay.find_child("ExtractionSearchDetail",true,false)
	if not is_instance_valid(detail):return
	app._clear(detail)
	for item in app.model.state.extraction.run.get("bag",[]):
		if str(item.uid)!=uid:continue
		var d: Dictionary=app.model.extraction.item_def(str(item.itemId)).duplicate(true)
		d.value=app.model.extraction.item_value(item);d.originAct=int(item.get("originAct",1))
		_item_title(app,detail,d)
		var actions=app._flow(detail,5)
		if d.get("kind","")=="consumable":
			var button=_button(app,actions,"使用",func():_search_bag_action(app,id,uid,"use"),true)
			button.name="ExtractionUse_"+uid;button.disabled=not app.model.extraction.can_use_consumable(str(item.itemId))
		if str(d.get("slot","")) in ["armor","backpack"] or d.get("kind","")=="equipment":
			_button(app,actions,"装备",func():_search_bag_action(app,id,uid,"equip"),true).name="ExtractionEquip_"+uid
		_manual_controls(app,detail,"bag",item,id)
		return
	app.overlay.set_meta("manual_loot_selection","")
	app._label(detail,"物品已移出背包",14,app.MUTED)

static func _search_bag_action(app,id: String,uid: String,action: String) -> void:
	var result: Dictionary={"success":false,"message":"物品已移出背包"}
	for item in app.model.state.extraction.run.get("bag",[]):
		if str(item.uid)!=uid:continue
		var d:Dictionary=app.model.extraction.item_def(str(item.itemId))
		if action=="use":result=app.model.extraction.use_item(uid)
		elif str(d.get("slot","")) in ["armor","backpack"]:result=app.model.extraction.set_utility_slot(str(d.slot),uid)
		else:
			_equip_bag(app,app.overlay.find_child("ExtractionSearchDetail",true,false),uid,id);return
		break
	if app._check(result):
		app.overlay.set_meta("manual_loot_selection","")
		if app.has_method("_ui_sound"):app._ui_sound("use" if action=="use" else "equip")
		var detail=app.overlay.find_child("ExtractionSearchDetail",true,false);app._clear(detail)
		app._label(detail,"已使用" if action=="use" else "已装备",16,app.CYAN)
	_refresh_search_grids(app,id)

static func _refresh_search_controls(app,id: String) -> void:
	var status=app.overlay.find_child("ExtractionSearchStatus",true,false)
	if not is_instance_valid(status):return
	var unknown:=0
	for item in _container(app,id).get("items",[]):
		if not item.get("revealed",false):unknown+=1
	status.modulate=Color.WHITE
	status.text="搜索中…" if unknown>0 else "已搜完 · 仍有物资" if not _container(app,id).get("items",[]).is_empty() else "已取空"

static func _refresh_search_grids(app,id: String) -> void:
	var grid=app.overlay.find_child("ExtractionContainer_"+id,true,false)
	if not is_instance_valid(grid):return
	var display: Array=[];var defs: Dictionary={};var bottom:=5
	for original in _container(app,id).get("items",[]):
		var item: Dictionary=original.duplicate(true);var actual: Dictionary=app.model.extraction.item_def(str(item.itemId))
		if app.model.extraction.has_method("item_value"):item.displayValue=app.model.extraction.item_value(item)
		var d: Dictionary=actual.duplicate(true) if item.get("revealed",false) else {"name":"未搜索","width":actual.get("width",1),"height":actual.get("height",1),"kind":"unknown","rarity":0}
		if not item.get("revealed",false):item.itemId="unknown_"+str(item.uid)
		defs[str(item.itemId)]=d;display.append(item)
		bottom=maxi(bottom,int(item.get("y",0))+int(d.get("width",1) if item.get("rotated",false) else d.get("height",1)))
	grid.configure(6,bottom,display,defs,grid.selected_uid)
	grid.size_flags_horizontal=Control.SIZE_SHRINK_CENTER;grid.custom_minimum_size.x=float(app.overlay.get_meta("loot_cell",44))*6
	var bag=app.overlay.find_child("ExtractionGrid_search_bag",true,false)
	var bag_items: Array=app.model.state.extraction.run.get("bag",[]).duplicate(true);var bag_defs: Dictionary={}
	for item in bag_items:
		bag_defs[str(item.itemId)]=app.model.extraction.item_def(str(item.itemId))
		if app.model.extraction.has_method("item_value"):item.displayValue=app.model.extraction.item_value(item)
	var bag_dims: Vector2i=app.model.extraction.dimensions("bag")
	bag.configure(bag_dims.x,bag_dims.y,bag_items,bag_defs,bag.selected_uid)
	var active_detail:=str(app.overlay.get_meta("detail_uid",""))
	var detail_exists:=false
	for entry in bag_items if active_detail.begins_with("bag:") else _container(app,id).get("items",[]):
		if str(entry.uid)==active_detail.trim_prefix("bag:"):detail_exists=true;break
	if not active_detail.is_empty() and not detail_exists:
		app.overlay.set_meta("detail_uid","");app.overlay.set_meta("manual_loot_selection","")
		var detail=app.overlay.find_child("ExtractionSearchDetail",true,false)
		if is_instance_valid(detail):app._clear(detail);app._label(detail,"点选物资查看详情",14,app.MUTED)
	var heading=app.overlay.find_child("ExtractionSearchBagHeading",true,false)
	if is_instance_valid(heading):heading.text="%d / %d 格 · %s 金币" % [_used_cells(app,bag_items),bag_dims.x*bag_dims.y,_money(_value(app,bag_items))]
	bag.size_flags_horizontal=Control.SIZE_SHRINK_CENTER;bag.custom_minimum_size.x=float(app.overlay.get_meta("loot_cell",44))*6

static func _select_container_item(app,id: String,uid: String,automatic: bool=false) -> void:
	if not automatic:_cancel_pending_placement(app,id)
	if automatic and not str(app.overlay.get_meta("manual_loot_selection","")).is_empty():return
	if not automatic:app.overlay.set_meta("manual_loot_selection",uid)
	app.overlay.set_meta("detail_uid",uid)
	for item in _container(app,id).get("items",[]):
		if str(item.uid)!=uid or not item.get("revealed",false):continue
		var detail=app.overlay.find_child("ExtractionSearchDetail",true,false)
		if not is_instance_valid(detail):return
		app._clear(detail)
		var d: Dictionary=app.model.extraction.item_def(str(item.itemId)).duplicate(true)
		if app.model.extraction.has_method("item_value"):d.value=app.model.extraction.item_value(item);d.originAct=int(item.get("originAct",1))
		var description=app._vbox(detail,3);description.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		_item_title(app,description,d)
		if d.get("kind","")!="key":_manual_controls(app,detail,"container",item,id)
		var actions=app._flow(detail,5);actions.size_flags_stretch_ratio=0.7
		_button(app,actions,"收下",func():_take_one(app,id,uid),true).name="ExtractionPickup_"+uid
		if d.get("kind","")!="key" and app.model.extraction.has_method("preview_exchange"):
			_button(app,actions,"手选换出",func():_manual_exchange(app,id,uid)).name="ExtractionManualExchange_"+uid
		if d.get("kind","")=="consumable" and app.model.extraction.has_method("use_container_item"):
			var use_button=_button(app,actions,"直接使用",func():_container_action(app,id,"use_container_item",uid),true)
			use_button.name="ExtractionUse_"+uid
			use_button.disabled=not app.model.extraction.can_use_consumable(str(item.itemId))
		if (d.get("kind","")=="equipment" or str(d.get("slot","")) in ["armor","backpack"]) and app.model.extraction.has_method("equip_container_item"):
			_button(app,actions,"直接装备",func():_container_equip(app,id,uid),true).name="ExtractionEquip_"+uid
		return

static func _container_action(app,id: String,method: String,uid: String) -> void:
	if app._check(app.model.extraction.call(method,id,uid)):
		if app.has_method("_ui_sound"):app._ui_sound("equip" if method=="equip_container_item" else "use")
		_refresh_search_grids(app,id)
		var detail=app.overlay.find_child("ExtractionSearchDetail",true,false);app._clear(detail)
		app._label(detail,"已装备" if method=="equip_container_item" else "已使用",16,app.CYAN)

static func _equip_bag(app,detail: Node,uid: String,container_id: String="") -> void:
	var selected: Dictionary = {}
	var source: Array = app.model.state.extraction.run.get("bag", []) if app.model.extraction.active() else app.model.state.extraction.stash
	for item in source:
		if str(item.uid)==uid: selected=item;break
	var conflict: String=app.model.extraction.equipment_conflict(selected) if not selected.is_empty() else ""
	if app.model.extraction.equipped_items().size()<3 and conflict.is_empty():
		_finish_bag_equip(app,uid,"",container_id);return
	app._clear(detail)
	app._label(detail,"选择替换装备",15,app.GOLD)
	for old in app.model.extraction.equipped_items():
		if not conflict.is_empty() and str(old.uid)!=conflict:continue
		var old_uid:=str(old.uid);var d:Dictionary=app.model.extraction.item_def(str(old.itemId))
		var card=app._panel(detail,_rarity(d).darkened(.65),6);card.name="ExtractionReplacement_"+old_uid
		var line=app._hbox(card,6);_icon(line,d,38)
		var info=app._vbox(line,3);info.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		app._label(info,str(d.get("name","装备")),14,_rarity(d),true)
		app._label(info,str(d.get("description","")),12,app.TEXT,true)
		_button(app,info,"替换",func():_finish_bag_equip(app,uid,old_uid,container_id)).name="ExtractionReplace_"+old_uid

static func _finish_bag_equip(app,uid: String,replace_uid: String,container_id: String="") -> void:
	var result:Dictionary=app.model.extraction.equip_item(uid,replace_uid)
	if container_id.is_empty():_operate_sound(app,result,"equip");return
	if app._check(result):
		_refresh_search_grids(app,container_id)
		var detail=app.overlay.find_child("ExtractionSearchDetail",true,false);app._clear(detail)
		app._label(detail,"已装备，旧装备放回背包" if not replace_uid.is_empty() else "已装备",14,app.CYAN,true)
		app._ui_sound("equip")

static func _container_equip(app,id: String,uid: String) -> void:
	for item in _container(app,id).get("items",[]):
		if str(item.uid)==uid and str(app.model.extraction.item_def(str(item.itemId)).get("slot","")) in ["armor","backpack"]:
			_container_action(app,id,"equip_container_item",uid);return
	var equipped: Array=app.model.state.extraction.run.get("equipped",[])
	var selected: Dictionary={}
	for item in _container(app,id).get("items",[]):
		if str(item.uid)==uid:selected=item;break
	var conflict: String=app.model.extraction.equipment_conflict(selected) if not selected.is_empty() else ""
	if equipped.size()<3 and conflict.is_empty():_container_action(app,id,"equip_container_item",uid);return
	var detail=app.overlay.find_child("ExtractionSearchDetail",true,false);app._clear(detail)
	app._label(detail,"选择替换装备",15,app.GOLD)
	for old in equipped:
		if not conflict.is_empty() and str(old.uid)!=conflict:continue
		var old_uid:=str(old.uid);var d: Dictionary=app.model.extraction.item_def(str(old.itemId))
		var card=app._panel(detail,_rarity(d).darkened(.65),6);card.name="ExtractionReplacement_"+old_uid
		var line=app._hbox(card,6);_icon(line,d,38)
		var info=app._vbox(line,3);info.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		app._label(info,str(d.get("name","装备")),14,_rarity(d),true)
		app._label(info,str(d.get("description","")),12,app.TEXT,true)
		_button(app,info,"替换",func():
			if app._check(app.model.extraction.equip_container_item(id,uid,old_uid)):_refresh_search_grids(app,id);app._clear(detail);app._label(detail,"已装备，旧装备留在容器中",14,app.CYAN);app._ui_sound("equip")).name="ExtractionReplace_"+old_uid

static func _take_one(app,id: String,uid: String) -> void:
	var origin: Dictionary={}
	for item in _container(app,id).get("items",[]):
		if str(item.uid)==uid:origin=item.duplicate(true);break
	if app._check(app.model.extraction.take_item(id,uid)):
		if app.has_method("_ui_sound"):app._ui_sound("pickup")
		_fly_to_bag(app,id,origin,app.model.extraction.item_def(str(origin.get("itemId",""))))
		_refresh_search_grids(app,id)
		var detail=app.overlay.find_child("ExtractionSearchDetail",true,false);app._clear(detail);app._label(detail,"已放入钥匙串" if app.model.extraction.item_def(str(origin.get("itemId",""))).get("kind","")=="key" else "已收入背包",16,app.CYAN)

static func _take_all(app,id: String) -> void:
	var before: Array=_container(app,id).get("items",[]).duplicate(true)
	var result: Dictionary=app.model.extraction.take_all_revealed(id)
	if app._check(result):
		if app.has_method("_ui_sound") and not result.get("taken",[]).is_empty():app._ui_sound("pickup")
		for item in before:
			if result.get("taken",[]).has(str(item.uid)):_fly_to_bag(app,id,item,app.model.extraction.item_def(str(item.itemId)))
		if not result.get("left",[]).is_empty():app._toast("背包已满，可直接使用补给或更换装备",app.GOLD)
		var detail=app.overlay.find_child("ExtractionSearchDetail",true,false)
		if is_instance_valid(detail):app._clear(detail);app._label(detail,"已收入 %d 件物资" % result.get("taken",[]).size(),16,app.CYAN,true)
	_refresh_search_grids(app,id);_refresh_search_controls(app,id)

static func _manual_exchange(app,id: String,uid: String) -> void:
	_cancel_pending_placement(app,id,false)
	_stop_search(app,true)
	var grid=app.overlay.find_child("ExtractionGrid_search_bag",true,false)
	if not is_instance_valid(grid):return
	grid.placement_mode=false;grid.multi_select=true;grid.set_meta("inventory_selection",true);grid.selected_uids=[];grid.selected_uid="";grid.queue_redraw()
	app.overlay.set_meta("manual_loot_selection",uid)
	var detail=app.overlay.find_child("ExtractionSearchDetail",true,false);app._clear(detail)
	for item in _container(app,id).get("items",[]):
		if str(item.uid)==uid:_item_title(app,detail,_item_display_def(app,item));break
	app._label(detail,"划过背包物资，选出要交换的物品",14,app.CYAN,true)
	var preview=app._vbox(detail,5);preview.name="ExtractionManualExchangePreview"
	var callback=func(_uids):_refresh_manual_exchange(app,id,uid)
	grid.set_meta("exchange_callback",callback);grid.selection_changed.connect(callback)
	_refresh_manual_exchange(app,id,uid)

static func _refresh_manual_exchange(app,id: String,uid: String) -> void:
	var grid=app.overlay.find_child("ExtractionGrid_search_bag",true,false)
	var preview=app.overlay.find_child("ExtractionManualExchangePreview",true,false)
	if not is_instance_valid(grid) or not is_instance_valid(preview):return
	var selected:Array=grid.selected_uids.duplicate()
	var plan:Dictionary=app.model.extraction.preview_exchange(id,uid,selected)
	app._clear(preview)
	var value:=0
	for item in app.model.state.extraction.run.get("bag",[]):
		if selected.has(str(item.uid)):value+=app.model.extraction.item_value(item)
	app._label(preview,"换出 %d 件 · %s 金币" % [selected.size(),_money(value)],15,app.GOLD,true)
	app._label(preview,"换出的物品留在当前容器",12,app.MUTED,true)
	if plan.get("success",false):app._label(preview,"背包价值 %+d" % int(plan.get("gain",0)),14,app.CYAN)
	if not plan.get("success",false):app._label(preview,str(plan.get("message","请选择要换出的物资")),12,app.MUTED,true)
	var actions=app._hbox(preview,5)
	var button=_button(app,actions,"确认交换",func():
		var result:Dictionary=app.model.extraction.exchange_items(id,uid,selected,str(plan.get("planHash","")))
		if app._check(result):
			_cancel_pending_placement(app,id)
			for incoming in plan.get("added",[]):_fly_to_bag(app,id,incoming,_item_display_def(app,incoming))
			_refresh_search_grids(app,id)
			_select_search_bag_item(app,id,uid)
			app._ui_sound("pickup")
		else:_refresh_manual_exchange(app,id,uid),true)
	button.name="ExtractionManualExchangeConfirm";button.disabled=not plan.get("success",false)
	_button(app,actions,"取消",func():_cancel_pending_placement(app,id);_select_container_item(app,id,uid)).name="ExtractionManualExchangeCancel"

static func _exchange_feedback_group(app,parent: Node,title: String,items: Array,node_name: String,color: Color) -> void:
	if items.is_empty():return
	var card=app._panel(parent,color.darkened(.7),8);card.name=node_name
	var col=app._vbox(card,5)
	app._label(col,"%s · %d 件" % [title,items.size()],13,color,true)
	var icons=app._flow(col,4)
	for item in items:
		var d:Dictionary=app.model.extraction.item_def(str(item.get("itemId","")))
		var icon=_icon(icons,d,30);icon.name="ExchangeItem_"+str(item.get("uid",""));icon.tooltip_text=str(d.get("name","物资"))

static func _smart_loot(app,id: String) -> void:
	_cancel_pending_placement(app,id,false)
	_stop_search(app,true)
	var plan: Dictionary=app.model.extraction.plan_smart_loot(id)
	if not plan.get("success",false):app._toast("当前背包已保留更合适的物资",app.CYAN);_queue_search(app,id);return
	var detail=app.overlay.find_child("ExtractionSearchDetail",true,false);app._clear(detail)
	app._label(detail,"换入 %d 件 · 价值 +%s" % [plan.get("added",[]).size(),_money(int(plan.get("gain",0)))],17,app.GOLD,true)
	_exchange_feedback_group(app,detail,"换出后自动使用",plan.get("willUse",[]),"ExtractionSmartWillUse",app.CYAN)
	_exchange_feedback_group(app,detail,"留在容器",plan.get("returned",plan.get("removed",[])),"ExtractionSmartReturned",app.MUTED)
	_button(app,detail,"确认换入",func():_smart_confirm(app,id,str(plan.get("planHash",""))),true).name="ExtractionSmartConfirm"
	_button(app,detail,"取消",func():app._clear(detail);_queue_search(app,id)).name="ExtractionSmartCancel"

static func _smart_confirm(app,id: String,hash: String) -> void:
	var before: Array=_container(app,id).get("items",[]).duplicate(true)
	var result: Dictionary=app.model.extraction.apply_smart_loot(id,hash)
	if app._check(result):
		app._ui_sound("pickup")
		for item in before:_fly_to_bag(app,id,item,app.model.extraction.item_def(str(item.itemId)))
		_refresh_search_grids(app,id)
		var detail=app.overlay.find_child("ExtractionSearchDetail",true,false)
		app._clear(detail);app._label(detail,"已换入背包",16,app.CYAN)
		_exchange_feedback_group(app,detail,"已使用",result.get("used",[]),"ExtractionSmartUsed",app.CYAN)
		_exchange_feedback_group(app,detail,"留在容器",result.get("returned",result.get("removed",[])),"ExtractionSmartReturned",app.MUTED)
		if not result.get("used",[]).is_empty():app._ui_sound("use")
	_queue_search(app,id)

static func _search_alive(app,generation: int,id: String) -> bool:
	return is_instance_valid(app) and app.current_screen=="extraction" and app.extraction_search_generation==generation and _container_modal_current(app) and str(app.overlay.get_meta("extraction_container",""))==id

static func _queue_search(app,id: String) -> void:
	if not _container_modal_current(app):return
	var modal=app.overlay.find_child("ModalPanel",true,false)
	var context:=_room_context(app)
	context.modalId=modal.get_instance_id()
	_search.call_deferred(app,id,context)

static func _search(app,id: String,context: Dictionary={}) -> void:
	if not context.is_empty() and (not _room_context_current(app,context) or not _container_modal_current(app,context)):return
	if app.extraction_searching or str(app.overlay.get_meta("extraction_container",""))!=id or not _container_modal_current(app):return
	app.extraction_searching=true;app.extraction_search_generation+=1
	var generation: int=app.extraction_search_generation
	_refresh_search_controls(app,id)
	while _search_alive(app,generation,id):
		var next: Dictionary={}
		for item in _container(app,id).get("items",[]):
			if not item.get("revealed",false):next=item;break
		if next.is_empty():break
		var grid=app.overlay.find_child("ExtractionContainer_"+id,true,false)
		var status=app.overlay.find_child("ExtractionSearchStatus",true,false)
		status.text="搜索中…";status.modulate=Color.WHITE
		var rarity_before:=clampi(int(app.model.extraction.item_def(str(next.itemId)).get("rarity",0)),0,5)
		var duration:=search_duration(rarity_before,app.extraction_reduced_motion)
		var elapsed:=0.0
		var source_scroll=app.overlay.find_child("ExtractionContainerScroll",true,false)
		if is_instance_valid(source_scroll):
			var target_rect: Rect2=grid.item_rect(next)
			if target_rect.end.y>source_scroll.scroll_vertical+source_scroll.size.y:source_scroll.scroll_vertical=ceili(target_rect.end.y-source_scroll.size.y)
		while elapsed<duration:
			if not _search_alive(app,generation,id):return
			if not app.get_meta("application_paused",false):elapsed+=minf(0.05,app.get_process_delta_time())
			var ratio:=clampf(elapsed/duration,0,1)
			grid.set_scan(str(next.uid),ratio)
			var progress=app.overlay.find_child("SearchProgress_"+id,true,false);progress.value=ratio
			await app.get_tree().process_frame
		if not _search_alive(app,generation,id):return
		grid.set_scan("",0)
		var result: Dictionary=app.model.extraction.reveal_next(id)
		if not app._check(result):break
		var latest: Dictionary=result.get("item",{});app.extraction_recent=latest.duplicate(true)
		var d: Dictionary=app.model.extraction.item_def(str(latest.get("itemId",""))).duplicate(true)
		if app.model.extraction.has_method("item_value"):d.value=app.model.extraction.item_value(latest)
		var rarity:=clampi(int(d.get("rarity",0)),0,5)
		_refresh_search_grids(app,id);grid.reveal_flash(str(latest.uid))
		status.text="发现 · "+str(d.get("name","物资"));status.modulate=_rarity(d)
		app._extraction_play("red" if rarity==5 else "gold" if rarity==4 else "purple" if rarity==3 else "common")
		_select_container_item(app,id,str(latest.uid),true)
		if app.extraction_auto_pick:
			app.overlay.set_meta("pending_loot",int(app.overlay.get_meta("pending_loot",0))+1)
			_auto_collect_after(app,generation,id,latest,d)
		# The next scan overlaps the revealed item's visible dwell and transfer.

	while _search_alive(app,generation,id) and int(app.overlay.get_meta("pending_loot",0))>0:
		await app.get_tree().process_frame
	if not _search_alive(app,generation,id):return
	app.extraction_searching=false
	if app.has_method("_extraction_stop_search_audio"):app._extraction_stop_search_audio()
	elif is_instance_valid(app.extraction_audio):app.extraction_audio.stop()
	_refresh_search_controls(app,id)
	var status=app.overlay.find_child("ExtractionSearchStatus",true,false)
	if is_instance_valid(status):_refresh_search_controls(app,id)

static func _auto_collect_after(app,generation: int,id: String,latest: Dictionary,d: Dictionary) -> void:
	var duration:=0.38
	var elapsed:=0.0
	while elapsed<duration:
		if not _search_alive(app,generation,id):return
		if not app.get_meta("application_paused",false):elapsed+=minf(0.05,app.get_process_delta_time())
		await app.get_tree().process_frame
	if not _search_alive(app,generation,id):return
	var still_present:=false
	for current in _container(app,id).get("items",[]):
		if str(current.uid)==str(latest.uid):still_present=true;break
	if app.extraction_auto_pick and still_present:
		var take: Dictionary=app.model.extraction.take_item(id,str(latest.uid))
		if take.get("success",false):
			if app.has_method("_ui_sound") and int(d.get("rarity",0))<3:app._ui_sound("pickup")
			app.extraction_recent.taken=true
			_fly_to_bag(app,id,latest,d)
			_refresh_search_grids(app,id)
			var history=app.overlay.find_child("ExtractionLootHistory",true,false)
			if is_instance_valid(history):
				if history.get_child_count()>=5:var old=history.get_child(0);history.remove_child(old);old.queue_free()
				var thumbnail=TextureButton.new();thumbnail.custom_minimum_size=Vector2(28,28);thumbnail.ignore_texture_size=true;thumbnail.stretch_mode=TextureButton.STRETCH_KEEP_ASPECT_CENTERED
				if ResourceLoader.exists(str(d.get("icon",""))):thumbnail.texture_normal=load(str(d.icon))
				thumbnail.tooltip_text=str(d.get("name","物资"))+" · 已收下";history.add_child(thumbnail)
				thumbnail.pressed.connect(func():
					app.overlay.set_meta("manual_loot_selection","history")
					var detail=app.overlay.find_child("ExtractionSearchDetail",true,false);app._clear(detail)
					_item_title(app,detail,d);app._label(detail,"已放入钥匙串" if d.get("kind","")=="key" else "已收入背包",13,app.CYAN))
		else:
			var status=app.overlay.find_child("ExtractionSearchStatus",true,false)
			if is_instance_valid(status):status.text="背包已满 · 可直接使用或装备"

	if _search_alive(app,generation,id):app.overlay.set_meta("pending_loot",maxi(0,int(app.overlay.get_meta("pending_loot",0))-1))

static func _fly_to_bag(app,id: String,item: Dictionary,d: Dictionary) -> void:
	var source=app.overlay.find_child("ExtractionContainer_"+id,true,false);var bag=app.overlay.find_child("ExtractionGrid_search_bag",true,false)
	if not is_instance_valid(source) or not is_instance_valid(bag):return
	var destination: Dictionary={}
	for current in app.model.state.extraction.run.get("bag",[]):
		if str(current.uid)==str(item.uid):destination=current;break
	if destination.is_empty():return
	if app.extraction_reduced_motion:bag.arrival_flash(str(item.uid));return
	var origin: Rect2=_transfer_rect(source,item,d)
	var target: Rect2=_transfer_rect(bag,destination,d)
	var scroll=bag.get_parent()
	while scroll!=null and not scroll is ScrollContainer:scroll=scroll.get_parent()
	if scroll is ScrollContainer:
		if target.end.y>scroll.scroll_vertical+scroll.size.y:scroll.scroll_vertical=ceili(target.end.y-scroll.size.y)
		elif target.position.y<scroll.scroll_vertical:scroll.scroll_vertical=floori(target.position.y)
	var icon=_icon(app.overlay,d,minf(52,minf(origin.size.x,origin.size.y)))
	icon.name="ExtractionTransfer_"+str(item.uid)
	icon.size=Vector2.ONE*minf(52,minf(origin.size.x,origin.size.y))
	icon.global_position=source.global_position+origin.get_center()-icon.size/2
	var tween=icon.create_tween();tween.set_parallel(true)
	tween.tween_property(icon,"global_position",bag.global_position+target.get_center()-icon.size/2,0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(icon,"scale",Vector2.ONE*0.8,0.28)
	var bag_ref: WeakRef=weakref(bag);var uid:=str(item.uid)
	tween.chain().tween_callback(func():
		var live_bag=bag_ref.get_ref()
		if live_bag!=null:live_bag.arrival_flash(uid))
	tween.tween_property(icon,"modulate:a",0.0,0.10)
	tween.chain().tween_callback(icon.queue_free)

static func _transfer_rect(grid,item: Dictionary,d: Dictionary) -> Rect2:
	var w:=int(d.get("width",1));var h:=int(d.get("height",1))
	if item.get("rotated",false):var old:=w;w=h;h=old
	return Rect2(int(item.get("x",0))*grid.cell+2,int(item.get("y",0))*grid.cell+2,w*grid.cell-4,h*grid.cell-4)

static func search_duration(rarity: int,_reduced: bool=false) -> float:
	return float(SEARCH_SECONDS[clampi(rarity,0,5)])

static func _sort_animated(app,scope: String) -> void:
	var result: Dictionary=app.model.extraction.sort_grid(scope)
	if not app._check(result):return
	var grid=app.main_body.find_child("ExtractionGrid_"+scope,true,false)
	if not is_instance_valid(grid):return
	var state: Dictionary=app.model.state.extraction
	var items: Array=(state.get("stash",[]) if scope=="stash" else state.get("run",{}).get("bag",[])).duplicate(true)
	for item in items:item.displayValue=app.model.extraction.item_value(item)
	grid.configure(grid.columns,grid.rows,items,app.model.extraction.data.items,grid.selected_uid)
	if app.has_method("_ui_sound"):app._ui_sound("tap")

static func _stop_search(app,refresh: bool=true) -> void:
	app.extraction_search_generation+=1;app.extraction_searching=false
	app.overlay.set_meta("pending_loot",0)
	if app.has_method("_extraction_stop_search_audio"):app._extraction_stop_search_audio()
	elif is_instance_valid(app.extraction_audio):app.extraction_audio.stop()
	if refresh:
		_refresh_search_controls(app,app.extraction_search_container)
		var grid=app.overlay.find_child("ExtractionContainer_"+app.extraction_search_container,true,false)
		if is_instance_valid(grid):grid.set_scan("",0)

static func _room_context(app) -> Dictionary:
	var run:Dictionary=app.model.state.extraction.get("run",{})
	return {"runId":str(run.get("id","")),"roomId":str(run.get("room",{}).get("id","")),"generation":int(app.extraction_search_generation)}

static func _room_context_current(app,context: Dictionary,check_generation: bool=true) -> bool:
	if not is_instance_valid(app) or app.current_screen!="extraction":return false
	var current:=_room_context(app)
	return not str(context.get("runId","")).is_empty() and current.runId==context.get("runId") and current.roomId==context.get("roomId") and (not check_generation or current.generation==context.get("generation"))

static func _container_modal_current(app,context: Dictionary={}) -> bool:
	var modal=app.overlay.find_child("ModalPanel",true,false)
	if not is_instance_valid(modal) or not modal.has_meta("extraction_context"):return false
	var live:Dictionary=modal.get_meta("extraction_context")
	if not context.is_empty() and live.get("modalId")!=context.get("modalId"):return false
	return _room_context_current(app,live,false) and live.get("modalId")==modal.get_instance_id()

static func _try_completed_room(app,context: Dictionary,closing_container: bool=false) -> Dictionary:
	if not _room_context_current(app,context) or app.get_meta("application_paused",false):return {"success":true,"advanced":false}
	if app.overlay.get_child_count()>0 and not closing_container:return {"success":true,"advanced":false}
	var status:Dictionary=app.model.extraction.room_interaction_status()
	if not status.get("canAutoReturn",false):return {"success":true,"advanced":false}
	var result:Dictionary=app.model.extraction.advance_room()
	if not app._check(result):return result
	app.extraction_panel="expedition";app.extraction_selected=""
	return {"success":true,"advanced":true}

static func _close_container(app,context: Dictionary={}) -> void:
	if not _container_modal_current(app,context):return
	# Invalidate scans and delayed auto-pickup before querying the actual items.
	# Keep the modal available for retry if the navigation save fails.
	_stop_search(app,false)
	if not _try_completed_room(app,_room_context(app),true).get("success",false):return
	app._clear_overlay();app._render_screen()

static func handle_modal_back(app) -> bool:
	if not _container_modal_current(app):return false
	# Inner cancel is distinct from closing the container itself.
	for name in ["ExtractionManualExchangeCancel","ExtractionSmartCancel","ExtractionCancelMove"]:
		var cancel=app.overlay.find_child(name,true,false)
		if is_instance_valid(cancel):cancel.pressed.emit();return true
	if not app.overlay.find_children("ExtractionReplacement_*","",true,false).is_empty():
		var detail=app.overlay.find_child("ExtractionSearchDetail",true,false)
		app._clear(detail);app._label(detail,"点选物资查看详情",14,app.MUTED,true)
		return true
	_close_container(app)
	return true

static func _room_action(app,id: String,clip: String) -> void:
	var context:=_room_context(app)
	_complete_room_operation(app,app.model.extraction.choose_room_action(id),context,clip)

static func _complete_room_operation(app,result: Dictionary,context: Dictionary,clip: String="") -> void:
	if not app._check(result):return
	if not clip.is_empty() and app.has_method("_ui_sound"):app._ui_sound(clip)
	app.extraction_selected=""
	_try_completed_room(app,context)
	app._render_screen()

static func _after_deposit_feedback(app,context: Dictionary,feedback: Node) -> void:
	if is_instance_valid(feedback):await feedback.tree_exited
	if not is_instance_valid(app):return
	while app.get_meta("application_paused",false):
		await app.get_tree().process_frame
		if not is_instance_valid(app) or not _room_context_current(app,context):return
	var result:=_try_completed_room(app,context)
	if result.get("advanced",false):app._render_screen()

static func _return_map(app) -> void:
	_stop_search(app,false);_operate(app,app.model.extraction.advance_room())
static func _switch_panel(app,id: String,clear_selection: bool=true) -> void:
	_stop_search(app,false);app.extraction_panel=id
	if clear_selection:app.extraction_selected=""
	app._render_screen()
static func _operate_sound(app,result: Dictionary,clip: String) -> void:
	if result.get("success",false) and app.has_method("_ui_sound"):app._ui_sound(clip)
	_operate(app,result)
static func _operate(app,result: Dictionary,message: String="") -> void:
	app._extraction_operation(result,message)
static func _value(app,items: Array) -> int:
	var value:=0
	for item in items:value+=app.model.extraction.item_value(item) if app.model.extraction.has_method("item_value") else int(app.model.extraction.item_def(str(item.itemId)).get("value",0))
	return value
static func _money(value: int) -> String:
	return str(value)
static func _help(app) -> void:
	var box=app._modal("探索指南",760,440)
	for line in ["沿连线探索据点，击败首领后可撤离。", "搜寻时，左侧是容器，右侧是背包。物资揭示后自动收下。", "背包满了，可直接使用补给、替换装备。长按仓库物品进入批量选择。", "每场战斗最多40回合。角色与遗物成长完整继承。"]:app._label(box,line,15,app.TEXT,true)
	var actions=app._hbox(box,8)
	_button(app,actions,"音效：开" if app.extraction_sound else "音效：关",func():app.extraction_sound=not app.extraction_sound;app._save_preferences();_help(app))
	_button(app,actions,"减少动效：开" if app.extraction_reduced_motion else "减少动效：关",func():app.extraction_reduced_motion=not app.extraction_reduced_motion;app._save_preferences();_help(app))
	_button(app,actions,"返回",app._clear_overlay,true)
static func _confirm_departure(app,extraction: bool) -> void:
	var left:=0
	for box in app.model.extraction.containers():left+=box.get("items",[]).size()
	var action:=func():_stop_search(app,false);_operate(app,app.model.extraction.extract() if extraction else app.model.extraction.advance_room(),"撤离成功" if extraction else "")
	if left>0:app._confirm("准备撤离？","还有 %d 件物资留在据点。" % left,action)
	else:action.call()
