extends RefCounted
const Grid = preload("res://scripts/ui/inventory_grid.gd")
const MapGraph = preload("res://scripts/ui/extraction_map.gd")
const RoomScene = preload("res://scripts/ui/extraction_room.gd")
const COLORS := [Color("9ca7b5"), Color("74bc9a"), Color("68ade8"), Color("bc8be8"), Color("efc774"), Color("ed7884")]
const RARITIES := ["普通", "优良", "稀有", "史诗", "传说", "至臻"]
const ROOM_NAMES := {"entry":"入口", "battle":"交战", "elite":"精英", "cache":"物资", "rest":"营地", "event":"奇遇", "boss":"首领", "vault":"藏宝室", "shrine":"祭坛", "hospital":"药房", "workshop":"工坊"}

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
		app._button(nav,tab[1],func():_switch_panel(app,id),app.extraction_panel==id).name="ExtractionTab_"+id
	var spacer=Control.new();spacer.size_flags_horizontal=Control.SIZE_EXPAND_FILL;nav.add_child(spacer)
	if not run.is_empty():app._label(nav,"第 %d 幕 · 危险 %d" % [int(run.act),int(run.difficulty)],15,app.CYAN)
	app._button(nav,"?",func():_help(app)).name="ExtractionHelp"
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
	var workspace=_workspace(app,app.main_body,12);workspace.size_flags_vertical=Control.SIZE_EXPAND_FILL
	var left=app._vbox(workspace,6);left.size_flags_horizontal=Control.SIZE_EXPAND_FILL;left.size_flags_stretch_ratio=1.65
	var right=app._vbox(workspace,8);right.size_flags_horizontal=Control.SIZE_EXPAND_FILL;right.size_flags_stretch_ratio=1.0
	right.custom_minimum_size.x=280
	if app.model.extraction.has_method("growth_choices") and not app.model.extraction.growth_choices().is_empty():_show_growth(app,left)
	elif str(run.get("phase","route"))=="route":_routes(app,left,right)
	else:_scene(app,left,run)
	_party_status(app,right,run)
	_equipment_slots(app,right,run)
	var bag_panel=_section(app,right,"背包  %d 件 · %s 金币" % [run.get("bag",[]).size(),_money(_value(app,run.get("bag",[])))])
	var grid=_grid_widget(app,bag_panel,"bag",run.get("bag",[]),6,5,34)
	grid.item_selected.connect(func(uid):app.extraction_selected=uid;app.extraction_scope="bag";_switch_panel(app,"bag",false))
	var actions=app._hbox(right,6)
	app._button(actions,"整理",func():_operate(app,app.model.extraction.sort_grid("bag"))).name="ExtractionSort_bag"
	app._button(actions,"更多",func():_run_menu(app))

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
		var b=app._button(risk,"危险 %d" % level,func():app.extraction_difficulty=d;app._render_screen(),app.extraction_difficulty==level)
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
	app._button(actions,"出发",func():_operate(app,app.model.extraction.start_run(app.extraction_difficulty)),true).name="ExtractionStart"
	app._button(actions,"编队",func():app.navigate("party"))
	var summary: Dictionary=state.get("lastRun",{})
	if not summary.is_empty():app._label(actions,"上次带出 %s" % _money(int(summary.get("value",0))) if summary.get("outcome","")=="extracted" else "准备再次出发",14,app.MUTED)
	var right=_section(app,row,"出战整备",app.GOLD);right.get_parent().size_flags_stretch_ratio=1
	_loadout(app,right,state)
	app._button(right,"前往补给站",func():_switch_panel(app,"shop"))
	app._button(right,"打开仓库",func():_switch_panel(app,"stash"))

static func _routes(app,parent: Node,side: Node) -> void:
	var graph: Dictionary=app.model.extraction.map_state()
	var status=app._hbox(parent,8)
	app._label(status,"首领通道已开启" if graph.get("bossUnlocked",false) else "探索 %d / %d" % [int(graph.get("explored",0)),int(graph.get("requiredExploration",4))],14,app.GOLD)
	var map=MapGraph.new();map.name="ExtractionMap";map.configure(graph)
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
			app._button(preview,"前往",func():_map_choice(app,id),true))

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
	var room_actions: Array=app.model.extraction.room_actions() if app.model.extraction.has_method("room_actions") else []
	var room_done:=not room_actions.is_empty()
	for action in room_actions:
		if not action.get("used",false):room_done=false
	var top=app._hbox(parent,8)
	app._label(top,str(room.get("name","遗境")),19,app.GOLD)
	var spacer=Control.new();spacer.size_flags_horizontal=Control.SIZE_EXPAND_FILL;top.add_child(spacer)
	app._button(top,"地图",func():_return_map(app)).name="ExtractionAdvance"
	var scene=RoomScene.new();scene.name="ExtractionRoomScene"
	scene.configure(room,app.model.extraction.containers(),str(room.get("selectedContainer","")))
	scene.custom_minimum_size.y=maxf(150,_height(app)-(250 if room_done else 290 if not room_actions.is_empty() else 215));scene.size_flags_vertical=Control.SIZE_EXPAND_FILL;parent.add_child(scene)
	scene.container_selected.connect(func(id):
		if run.get("phase","")=="battle":app._toast("击败守卫后搜寻",app.RED);return
		if app._check(app.model.extraction.choose_container(id)):_open_container(app,id))
	var actions=app._hbox(parent,6)
	var phase:=str(run.get("phase",""))
	if phase=="battle":app._button(actions,"迎战",app._begin_extraction_battle,true).name="ExtractionBattle"
	elif phase=="boss_exit":
		app._button(actions,"撤离",func():_confirm_departure(app,true),true).name="ExtractionExit"
		if int(run.get("act",1))<3:app._button(actions,"继续深入",func():_operate(app,app.model.extraction.continue_act())).name="ExtractionNextAct"
	for box in app.model.extraction.containers():
		var id:=str(box.id)
		var button=app._button(actions,str(box.get("name","容器")),func():
			if app._check(app.model.extraction.choose_container(id)):_open_container(app,id))
		button.name="ExtractionOpenContainer_"+id;button.disabled=phase=="battle"
	if room_done:
		var result=app._panel(parent,app.CYAN.darkened(0.6),8)
		var result_row=app._hbox(result,8)
		var chosen: Dictionary={}
		for action in room_actions:
			if action.get("selected",false):chosen=action;break
		app._label(result_row,str(chosen.get("label","休整完成")),16,app.CYAN)
		app._label(result_row,str(chosen.get("description","继续探索，寻找下一处据点")),12,app.MUTED,true)
	elif not room_actions.is_empty():
		var choices=app._hbox(parent,6)
		for action in room_actions:
			var id:=str(action.get("id",action.get("actionId","")))
			var choice=_section(app,choices,str(action.get("label","互动")),app.CYAN)
			app._label(choice,str(action.get("description","")),12,app.TEXT,true)
			var cost:=int(action.get("cost",0))
			var caption:="已选择" if action.get("used",false) else "%d 金币" % cost if cost>0 else "选择"
			var b=app._button(choice,caption,func():_operate(app,app.model.extraction.choose_room_action(id)),true)
			b.disabled=not bool(action.get("enabled",true))

static func _show_growth(app,parent: Node) -> void:
	if not app.model.extraction.has_method("growth_choices"):return
	var choices: Array=app.model.extraction.growth_choices()
	if choices.is_empty():return
	var panel=_section(app,parent,"选择本局祝福",app.GOLD)
	var row=app._hbox(panel,8)
	for choice in choices:
		var id:=str(choice.get("choiceId",choice.get("id","")))
		var col=_section(app,row,str(choice.get("name","祝福")),app.CYAN)
		app._label(col,str(choice.get("description",choice.get("desc",""))),13,app.TEXT,true)
		app._button(col,"选择",func():_operate(app,app.model.extraction.choose_growth(id)),true)

static func _party_status(app,parent: Node,run: Dictionary) -> void:
	var row=app._hbox(parent,6)
	for unit in run.get("party",[]):
		var id:=str(unit.get("id",""));var hp:=int(unit.get("currentHp",unit.get("hp",0)));var maximum:=int(unit.get("maxHp",unit.get("hp",1)))
		var panel=app._panel(row,app.LINE,5);var content=app._hbox(panel,5)
		var portrait=app._portrait(content,id,45);portrait.custom_minimum_size.x=34
		var stats=app._vbox(content,2);stats.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		var name_label=app._label(stats,app._char_name(id),12,app.TEXT);name_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
		app._progress(stats,hp,maximum,app.CYAN if hp>0 else app.RED,5)
		var hp_label=app._label(stats,"%d / %d" % [hp,maximum],10,app.MUTED)
		hp_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;hp_label.tooltip_text="%d / %d" % [hp,maximum]

static func _equipment_slots(app,parent: Node,run: Dictionary) -> void:
	var row=app._hbox(parent,6)
	var equipped: Array=run.get("equipped",[])
	for i in 3:
		var panel=app._panel(row,app.GOLD.darkened(0.65),4)
		var col=app._vbox(panel,1)
		if i<equipped.size():
			var item: Dictionary=equipped[i];var d: Dictionary=app.model.extraction.item_def(str(item.itemId))
			panel.add_theme_stylebox_override("panel",app._box(app.PANEL,Color.WHITE if app.extraction_scope=="equipment" and app.extraction_selected==str(item.uid) else _rarity(d).darkened(0.25),4))
			_icon(col,d,30)
			app._center_label(col,str(d.get("name","装备")),10,_rarity(d))
			app._bind_card_tap(panel,func():app.extraction_selected=str(item.uid);app.extraction_scope="equipment";_switch_panel(app,"bag",false))
		else:
			var icon_def: Dictionary=app.model.extraction.item_def(["vest","blade","scope"][i])
			if icon_def.is_empty():icon_def={"icon":"res://assets/items/extraction/"+["vest","blade","scope"][i]+".png"}
			var ghost=_icon(col,icon_def,30);ghost.modulate=Color(0.5,0.65,0.7,0.22)
			app._center_label(col,"战术装备",10,app.MUTED)

static func _grid_widget(app,parent: Node,scope: String,items: Array,columns: int,rows: int,cell_size: float=42) -> Control:
	var defs: Dictionary={}
	var displayed: Array=items.duplicate(true)
	for item in displayed:
		defs[str(item.itemId)]=app.model.extraction.item_def(str(item.itemId))
		if app.model.extraction.has_method("item_value"):item.displayValue=app.model.extraction.item_value(item)
	var grid=Grid.new();grid.name="ExtractionGrid_"+scope;grid.preferred_cell=cell_size
	grid.configure(columns,rows,displayed,defs,app.extraction_selected if app.extraction_scope==scope else "")
	parent.add_child(grid)
	grid.size_flags_horizontal=Control.SIZE_SHRINK_CENTER;grid.custom_minimum_size.x=columns*cell_size
	return grid

static func _bag(app,run: Dictionary) -> void:
	var row=_workspace(app,app.main_body,12);row.size_flags_vertical=Control.SIZE_EXPAND_FILL
	var left=_section(app,row,"随身背包",app.CYAN)
	_party_status(app,left,run)
	var grid=_grid_widget(app,left,"bag",run.get("bag",[]),6,5,42)
	var right=_section(app,row,"角色与装备",app.GOLD)
	_equipment_slots(app,right,run)
	var detail=app._vbox(right,6);detail.name="ExtractionItemDetail"
	_render_inventory_detail(app,detail,"bag",run.get("bag",[]))
	grid.item_selected.connect(func(uid):app.extraction_scope="bag";app.extraction_selected=uid;app._clear(detail);_render_inventory_detail(app,detail,"bag",run.get("bag",[])))
	app._button(left,"自动整理",func():_operate(app,app.model.extraction.sort_grid("bag"))).name="ExtractionSort_bag"
	_show_growth(app,right)

static func _render_inventory_detail(app,parent: Node,scope: String,items: Array) -> void:
	if app.extraction_scope=="equipment":
		for item in app.model.state.extraction.run.get("equipped",[]):
			if str(item.uid)==app.extraction_selected:
				_item_title(app,parent,app.model.extraction.item_def(str(item.itemId)))
				app._button(parent,"卸回背包",func():_operate_sound(app,app.model.extraction.unequip_item(str(item.uid)),"equip"))
				return
	for item in items:
		if app.extraction_scope==scope and str(item.uid)==app.extraction_selected:_selected(app,parent,scope,item);return
	app._label(parent,"点选物品查看详情",15,app.MUTED,true)

static func _selected(app,parent: Node,scope: String,item: Dictionary) -> void:
	var d: Dictionary=app.model.extraction.item_def(str(item.itemId)).duplicate(true);var uid:=str(item.uid)
	if app.model.extraction.has_method("item_value"):d.value=app.model.extraction.item_value(item)
	_item_title(app,parent,d)
	var actions=app._flow(parent,6)
	if scope=="bag":
		if d.get("kind","")=="equipment":app._button(actions,"装备",func():_operate_sound(app,app.model.extraction.equip_item(uid),"equip"),true)
		if d.get("kind","")=="consumable":
			var use_button=app._button(actions,"使用",func():_operate_sound(app,app.model.extraction.use_item(uid),"use"),true)
			use_button.disabled=not app.model.extraction.can_use_consumable(str(item.itemId))
		app._button(actions,"丢弃",func():app._confirm("丢弃物资？",str(d.get("name","物资")),func():_operate(app,app.model.extraction.discard_item(uid))))
	else:
		app._button(actions,"出售",func():_operate_sound(app,app.model.extraction.sell_item(uid),"coin"))
		app._button(actions,"收藏",func():_operate(app,app.model.extraction.collect_item(uid)))
		app._button(actions,"携带",func():_operate(app,app.model.extraction.bring_item(uid)),true)

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
			if uids.has(str(item.uid)):value+=app.model.extraction.item_value(item) if app.model.extraction.has_method("item_value") else int(app.model.extraction.item_def(str(item.itemId)).get("value",0))
		app._label(detail,"出售可得 %s 金币" % _money(value),18,app.GOLD)
		app._clear(batch)
		app._button(batch,"出售所选",func():_batch_operation(app,"sell_items",grid.selected_uids),true).disabled=uids.is_empty()
		app._button(batch,"收藏所选",func():_batch_operation(app,"collect_items",grid.selected_uids)).disabled=uids.is_empty()
		app._button(batch,"取消选择",func():grid.multi_select=false;grid.set_meta("inventory_selection",false);grid.selected_uids.clear();grid.queue_redraw();app._clear(batch);app._clear(detail);_render_inventory_detail(app,detail,"stash",state.get("stash",[]))))
	app._button(actions,"多选",func():grid.multi_select=not grid.multi_select;grid.set_meta("inventory_selection",grid.multi_select);selection_label.text="划过物品连续选择" if grid.multi_select else "点选查看详情")
	app._button(actions,"整理",func():_operate(app,app.model.extraction.sort_grid("stash"))).name="ExtractionSort_stash"
	if not state.get("mailbox",[]).is_empty():app._button(right,"领取待收物资",func():_operate(app,app.model.extraction.claim_mail()),true)
	if state.get("run",{}).is_empty():
		app._label(right,"已携带 %d / 3 件" % state.get("loadout",[]).size(),14,app.GOLD)
		app._button(right,"查看出战整备",func():_switch_panel(app,"expedition"))

static func _batch_operation(app,method: String,uids: Array) -> void:
	if app.model.extraction.has_method(method):_operate_sound(app,app.model.extraction.call(method,uids.duplicate()),"coin" if method=="sell_items" else "tap")

static func _shop(app,state: Dictionary) -> void:
	var row=_workspace(app,app.main_body,12);row.size_flags_vertical=Control.SIZE_EXPAND_FILL
	var left=_section(app,row,"补给站",app.GOLD);left.get_parent().size_flags_stretch_ratio=1.6
	var list=_scroll(app,left)
	var cards=app._grid(list,2 if app.size.x<900 else 3);cards.add_theme_constant_override("h_separation",8);cards.add_theme_constant_override("v_separation",8)
	for id in app.model.extraction.data.get("items",{}):
		var d: Dictionary=app.model.extraction.item_def(str(id))
		if int(d.get("buyPrice",0))<=0:continue
		var item_id:=str(id);var required:=int(d.get("buyMinRisk",0));var locked:=int(state.get("unlockedDifficulty",0))<required
		var p=app._panel(cards,_rarity(d).darkened(0.65),8);p.custom_minimum_size.x=135
		var col=app._vbox(p,5);var line=app._hbox(col,4);_icon(line,d,42)
		app._label(line,str(d.get("name",id)),13,_rarity(d),true)
		var b=app._button(col,"危险 %d 解锁" % required if locked else "%d 金币 · 购买" % int(d.buyPrice),func():_operate_sound(app,app.model.extraction.buy_supply(item_id),"coin"),not locked)
		b.name="ExtractionBuy_"+item_id;b.disabled=locked
	var right=_section(app,row,"携带与储备",app.CYAN);right.get_parent().size_flags_stretch_ratio=1
	_loadout(app,right,state)
	app._button(right,"打开仓库",func():_switch_panel(app,"stash"))

static func _loadout(app,parent: Node,state: Dictionary) -> void:
	if not state.get("run",{}).is_empty():app._label(parent,"行动中，补给存入仓库",14,app.MUTED,true);return
	var loadout: Array=state.get("loadout",[])
	app._label(parent,"携带 %d / 3" % loadout.size(),16,app.GOLD)
	for i in 3:
		var panel=app._panel(parent,app.LINE,6);var row=app._hbox(panel,6)
		if i<loadout.size():
			var item: Dictionary=loadout[i];var d: Dictionary=app.model.extraction.item_def(str(item.itemId))
			_icon(row,d,36);app._label(row,str(d.get("name","物资")),13,_rarity(d),true)
			app._button(row,"放回",func():_operate(app,app.model.extraction.store_item(str(item.uid))))
		else:app._label(row,"空位 · 从仓库携带",13,app.MUTED)

static func _run_menu(app) -> void:
	var box=app._modal("行动选项",420,230)
	app._button(box,"查看本局构筑",func():app._clear_overlay();_switch_panel(app,"build"))
	app._button(box,"放弃本次行动",func():app._confirm("结束行动？","随身物资将遗失。",func():_operate(app,app.model.extraction.retreat())))
	app._button(box,"返回",app._clear_overlay,true)

static func _build(app,run: Dictionary) -> void:
	var col=_scroll(app,app.main_body)
	app._label(col,"本局构筑",22,app.GOLD)
	if app.model.extraction.has_method("growth_summary"):
		var blessings: Array=app.model.extraction.growth_summary()
		if blessings.is_empty():app._label(col,"探索据点、击败敌人，获得本局祝福",15,app.MUTED,true)
		var cards=app._grid(col,3 if app.size.x>=900 else 2)
		for blessing in blessings:
			var card=_section(app,cards,str(blessing.get("name","祝福")),app.GOLD)
			app._label(card,str(blessing.get("description","")),14,app.TEXT,true)
			if int(blessing.get("stacks",1))>1:app._label(card,"叠加 %d 层" % int(blessing.stacks),13,app.CYAN)
	_equipment_slots(app,col,run)
	_show_growth(app,col)

static func _collection(app,state: Dictionary) -> void:
	var col=_scroll(app,app.main_body)
	var collected: Array=state.get("collection",[]);var catalog: Dictionary=app.model.extraction.data.get("items",{})
	app._label(col,"遗境藏品  %d / %d" % [collected.size(),catalog.size()],22,app.GOLD)
	var cards=app._grid(col,maxi(2,mini(6,int((app.size.x-40)/145))))
	for id in catalog:
		var d: Dictionary=app.model.extraction.item_def(str(id));var owned:=collected.has(str(id))
		var p=app._panel(cards,_rarity(d).darkened(0.6),8);p.custom_minimum_size.x=115
		var card=app._vbox(p,5);_icon(card,d,55)
		app._label(card,str(d.get("name","物资")),13,_rarity(d),true)
		app._label(card,"已收藏" if owned else "待收集",11,app.GOLD if owned else app.MUTED)
		if not owned:p.modulate=Color(0.7,0.75,0.8)

static func _icon(parent: Node,d: Dictionary,side: float=48) -> TextureRect:
	var image=TextureRect.new();image.custom_minimum_size=Vector2(side,side)
	image.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;image.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;image.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var path:=str(d.get("icon",""))
	if ResourceLoader.exists(path):image.texture=load(path)
	parent.add_child(image);return image

static func _rarity(d: Dictionary) -> Color:
	return COLORS[clampi(int(d.get("rarity",0)),0,5)]

static func _item_title(app,parent: Node,d: Dictionary) -> void:
	var row=app._hbox(parent,8);_icon(row,d,48)
	var text=app._vbox(row,3);text.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var title_row=app._hbox(text,6)
	app._label(title_row,str(d.get("name","遗境物资")),18,_rarity(d),true)
	var item_id:=str(d.get("icon","")).get_file().get_basename()
	if not item_id.is_empty():
		var chip=app._panel(title_row,app.GOLD.darkened(0.6),3);chip.size_flags_horizontal=Control.SIZE_SHRINK_END
		app._label(chip,"已收藏" if app.model.state.extraction.get("collection",[]).has(item_id) else "新藏品",10,app.GOLD)
	app._label(text,"%s   %d × %d 格   %s 金币" % [RARITIES[clampi(int(d.get("rarity",0)),0,5)],int(d.get("width",1)),int(d.get("height",1)),_money(int(d.get("value",0)))],12,app.MUTED,true)
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
	app.extraction_search_container=id
	var box=app._modal("",1150,520)
	box.add_theme_constant_override("separation",8)
	var modal=app.overlay.find_child("ModalPanel",true,false)
	modal.add_theme_stylebox_override("panel",app._box(app.PANEL,app.GOLD.darkened(0.55),12))
	if box.get_child_count()>0:var old=box.get_child(0);box.remove_child(old);old.queue_free()
	app.overlay.set_meta("extraction_container",id);app.overlay.set_meta("loot_history",[]);app.overlay.set_meta("manual_loot_selection","");app.overlay.set_meta("pending_loot",0)
	var heading=app._hbox(box,8)
	app._label(heading,str(container.get("name","搜寻物资")),22,app.GOLD)
	var spacer=Control.new();spacer.size_flags_horizontal=Control.SIZE_EXPAND_FILL;heading.add_child(spacer)
	app._button(heading,"×",func():_close_container(app)).name="ExtractionCloseContainer"
	var controls=app._hbox(box,8);controls.name="ExtractionSearchToolbar"
	var primary=app._button(controls,"搜索",func():
		if app.extraction_searching:_stop_search(app,true)
		else:_search(app,id),true)
	primary.name="ExtractionSearch"
	var toggle=CheckButton.new();toggle.text="自动收下";toggle.button_pressed=app.extraction_auto_pick;toggle.custom_minimum_size.y=40
	controls.add_child(toggle);toggle.name="ExtractionAutoPick"
	toggle.toggled.connect(func(on):app.extraction_auto_pick=on;app._save_preferences())
	var status=app._label(controls,"逐件发现物资",13,app.MUTED,true);status.name="ExtractionSearchStatus";status.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var split=app._hbox(box,10);split.name="ExtractionLootSplit"
	var source=_section(app,split,"容器",app.CYAN)
	var dest=_section(app,split,"随身背包",app.GOLD)
	var information=_section(app,split,"物资详情",app.CYAN)
	var preferred:=minf(52,floorf((app.size.x-144)/18))
	app.overlay.set_meta("loot_cell",preferred)
	var source_scroll=_scroll(app,source,preferred*5)
	source_scroll.get_parent().name="ExtractionContainerScroll"
	var container_grid=Grid.new();container_grid.name="ExtractionContainer_"+id;container_grid.preferred_cell=preferred
	source_scroll.add_child(container_grid)
	container_grid.item_selected.connect(func(uid):_select_container_item(app,id,uid))
	var bottom=app._hbox(source,6);bottom.name="ExtractionContainerActions"
	app._button(bottom,"收下全部",func():_take_all(app,id),true).name="ExtractionTakeAll"
	app._button(bottom,"一键换入",func():_smart_loot(app,id)).name="ExtractionSmartLoot"
	var progress=app._progress(source,0,1,app.CYAN,3);progress.name="SearchProgress_"+id
	var bag_grid=_grid_widget(app,dest,"search_bag",app.model.state.extraction.run.get("bag",[]),6,5,preferred)
	bag_grid.item_selected.connect(func(uid):
		app.overlay.set_meta("manual_loot_selection","bag:"+str(uid))
		var detail=app.overlay.find_child("ExtractionSearchDetail",true,false);app._clear(detail)
		for item in app.model.state.extraction.run.get("bag",[]):
			if str(item.uid)!=uid:continue
			var d: Dictionary=app.model.extraction.item_def(str(item.itemId)).duplicate(true)
			if app.model.extraction.has_method("item_value"):d.value=app.model.extraction.item_value(item)
			_item_title(app,detail,d)
			if d.get("kind","")=="consumable":app._button(detail,"使用",func():app._check(app.model.extraction.use_item(uid));_refresh_search_grids(app,id))
			if d.get("kind","")=="equipment":app._button(detail,"装备",func():app._check(app.model.extraction.equip_item(uid));_refresh_search_grids(app,id)))
	var history=app._hbox(dest,5);history.name="ExtractionLootHistory"
	var detail=app._vbox(information,8);detail.name="ExtractionSearchDetail"
	_party_status(app,detail,app.model.state.extraction.run)
	app._label(detail,"点选物资查看详情",14,app.MUTED,true)
	app._label(detail,"背包满时，也可直接使用补给或替换装备。",13,app.MUTED,true)
	_refresh_search_grids(app,id);_refresh_search_controls(app,id)

static func _refresh_search_controls(app,id: String) -> void:
	var primary=app.overlay.find_child("ExtractionSearch",true,false)
	if not is_instance_valid(primary):primary=app.overlay.find_child("ExtractionStopSearch",true,false)
	if not is_instance_valid(primary):return
	var unknown:=false
	for item in _container(app,id).get("items",[]):
		if not item.get("revealed",false):unknown=true
	primary.name="ExtractionStopSearch" if app.extraction_searching else "ExtractionSearch"
	primary.text="暂停搜索" if app.extraction_searching else "搜索" if unknown else "已搜完"
	primary.disabled=not app.extraction_searching and not unknown

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
	bag.configure(6,5,bag_items,bag_defs)
	bag.size_flags_horizontal=Control.SIZE_SHRINK_CENTER;bag.custom_minimum_size.x=float(app.overlay.get_meta("loot_cell",44))*6

static func _select_container_item(app,id: String,uid: String,automatic: bool=false) -> void:
	if automatic and not str(app.overlay.get_meta("manual_loot_selection","")).is_empty():return
	if not automatic:app.overlay.set_meta("manual_loot_selection",uid)
	for item in _container(app,id).get("items",[]):
		if str(item.uid)!=uid or not item.get("revealed",false):continue
		var detail=app.overlay.find_child("ExtractionSearchDetail",true,false)
		if not is_instance_valid(detail):return
		app._clear(detail)
		var d: Dictionary=app.model.extraction.item_def(str(item.itemId)).duplicate(true)
		if app.model.extraction.has_method("item_value"):d.value=app.model.extraction.item_value(item)
		var description=app._vbox(detail,3);description.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		_item_title(app,description,d)
		var actions=app._flow(detail,5);actions.size_flags_stretch_ratio=0.7
		app._button(actions,"收下",func():_take_one(app,id,uid),true).name="ExtractionPickup_"+uid
		if d.get("kind","")=="consumable" and app.model.extraction.has_method("use_container_item"):
			var use_button=app._button(actions,"直接使用",func():_container_action(app,id,"use_container_item",uid),true)
			use_button.disabled=not app.model.extraction.can_use_consumable(str(item.itemId))
		if d.get("kind","")=="equipment" and app.model.extraction.has_method("equip_container_item"):
			app._button(actions,"直接装备",func():_container_equip(app,id,uid),true)
		return

static func _container_action(app,id: String,method: String,uid: String) -> void:
	if app._check(app.model.extraction.call(method,id,uid)):
		if app.has_method("_ui_sound"):app._ui_sound("equip" if method=="equip_container_item" else "use")
		_refresh_search_grids(app,id)
		var detail=app.overlay.find_child("ExtractionSearchDetail",true,false);app._clear(detail)
		app._label(detail,"已装备" if method=="equip_container_item" else "已使用",16,app.CYAN)

static func _container_equip(app,id: String,uid: String) -> void:
	var equipped: Array=app.model.state.extraction.run.get("equipped",[])
	if equipped.size()<3:_container_action(app,id,"equip_container_item",uid);return
	var detail=app.overlay.find_child("ExtractionSearchDetail",true,false);app._clear(detail)
	app._label(detail,"选择替换装备",15,app.GOLD)
	for old in equipped:
		var old_uid:=str(old.uid);var d: Dictionary=app.model.extraction.item_def(str(old.itemId))
		app._button(detail,str(d.get("name","装备")),func():
			if app._check(app.model.extraction.equip_container_item(id,uid,old_uid)):_refresh_search_grids(app,id);app._clear(detail);app._label(detail,"已装备，旧装备留在容器中",14,app.CYAN))

static func _take_one(app,id: String,uid: String) -> void:
	if app._check(app.model.extraction.take_item(id,uid)):
		if app.has_method("_ui_sound"):app._ui_sound("tap")
		app.model.extraction.sort_grid("bag");_refresh_search_grids(app,id)
		var detail=app.overlay.find_child("ExtractionSearchDetail",true,false);app._clear(detail);app._label(detail,"已收入背包",16,app.CYAN)

static func _take_all(app,id: String) -> void:
	var result: Dictionary=app.model.extraction.take_all_revealed(id)
	if app._check(result):
		if not result.get("left",[]).is_empty():app._toast("背包已满，可直接使用补给或更换装备",app.GOLD)
		var detail=app.overlay.find_child("ExtractionSearchDetail",true,false)
		if is_instance_valid(detail):app._clear(detail);app._label(detail,"已收入 %d 件物资" % result.get("taken",[]).size(),16,app.CYAN,true)
	_refresh_search_grids(app,id);_refresh_search_controls(app,id)

static func _smart_loot(app,id: String) -> void:
	_stop_search(app,true)
	var plan: Dictionary=app.model.extraction.plan_smart_loot(id)
	if not plan.get("success",false):app._toast("当前背包已保留更合适的物资",app.CYAN);return
	var detail=app.overlay.find_child("ExtractionSearchDetail",true,false);app._clear(detail)
	app._label(detail,"换入 %d 件 · 价值 +%s" % [plan.get("added",[]).size(),_money(int(plan.get("gain",0)))],17,app.GOLD,true)
	app._button(detail,"确认换入",func():
		if app._check(app.model.extraction.apply_smart_loot(id,str(plan.get("planHash","")))):_refresh_search_grids(app,id);app._clear(detail);app._label(detail,"已换入，替换物资留在容器中",14,app.CYAN),true).name="ExtractionSmartConfirm"
	app._button(detail,"取消",func():app._clear(detail)).name="ExtractionSmartCancel"

static func _search_alive(app,generation: int,id: String) -> bool:
	return is_instance_valid(app) and app.current_screen=="extraction" and app.extraction_search_generation==generation and app.overlay.get_child_count()>0 and str(app.overlay.get_meta("extraction_container",""))==id

static func _search(app,id: String) -> void:
	if app.extraction_searching:return
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
		status.text="搜索中…"
		var duration:=0.09 if app.extraction_reduced_motion else 0.65
		var start:=Time.get_ticks_msec()
		var source_scroll=app.overlay.find_child("ExtractionContainerScroll",true,false)
		if is_instance_valid(source_scroll):
			var target_rect: Rect2=grid.item_rect(next)
			if target_rect.end.y>source_scroll.scroll_vertical+source_scroll.size.y:source_scroll.scroll_vertical=ceili(target_rect.end.y-source_scroll.size.y)
		while float(Time.get_ticks_msec()-start)/1000.0<duration:
			if not _search_alive(app,generation,id):return
			var ratio:=float(Time.get_ticks_msec()-start)/(duration*1000)
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
	if is_instance_valid(status):status.text="搜索完成"

static func _auto_collect_after(app,generation: int,id: String,latest: Dictionary,d: Dictionary) -> void:
	var duration:=0.04 if app.extraction_reduced_motion else 0.38
	var start:=Time.get_ticks_msec()
	while float(Time.get_ticks_msec()-start)/1000.0<duration:
		if not _search_alive(app,generation,id):return
		await app.get_tree().process_frame
	if not _search_alive(app,generation,id):return
	if app.extraction_auto_pick:
		var take: Dictionary=app.model.extraction.take_item(id,str(latest.uid))
		if take.get("success",false):
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
					_item_title(app,detail,d);app._label(detail,"已收入背包",13,app.CYAN))
		else:
			var status=app.overlay.find_child("ExtractionSearchStatus",true,false)
			if is_instance_valid(status):status.text="背包已满 · 可直接使用或装备"

	if _search_alive(app,generation,id):app.overlay.set_meta("pending_loot",maxi(0,int(app.overlay.get_meta("pending_loot",0))-1))

static func _fly_to_bag(app,id: String,item: Dictionary,d: Dictionary) -> void:
	if app.extraction_reduced_motion:return
	var source=app.overlay.find_child("ExtractionContainer_"+id,true,false);var bag=app.overlay.find_child("ExtractionGrid_search_bag",true,false)
	if not is_instance_valid(source) or not is_instance_valid(bag):return
	var icon=_icon(app.overlay,d,38);icon.size=Vector2(38,38)
	icon.global_position=source.global_position+source.item_rect(item).get_center()-Vector2(19,19)
	var tween=app.create_tween();tween.set_parallel(true)
	tween.tween_property(icon,"global_position",bag.global_position+Vector2(25,25),0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(icon,"modulate:a",0.0,0.3)
	var icon_ref: WeakRef=weakref(icon)
	tween.chain().tween_callback(func():
		var target=icon_ref.get_ref()
		if target!=null:target.queue_free())

static func _stop_search(app,refresh: bool=true) -> void:
	app.extraction_search_generation+=1;app.extraction_searching=false
	app.overlay.set_meta("pending_loot",0)
	if app.has_method("_extraction_stop_search_audio"):app._extraction_stop_search_audio()
	elif is_instance_valid(app.extraction_audio):app.extraction_audio.stop()
	if refresh:
		_refresh_search_controls(app,app.extraction_search_container)
		var grid=app.overlay.find_child("ExtractionContainer_"+app.extraction_search_container,true,false)
		if is_instance_valid(grid):grid.set_scan("",0)

static func _close_container(app) -> void:
	_stop_search(app,false);app._clear_overlay();app._render_screen()
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
	app._button(actions,"音效：开" if app.extraction_sound else "音效：关",func():app.extraction_sound=not app.extraction_sound;app._save_preferences();_help(app))
	app._button(actions,"快速搜索：开" if app.extraction_reduced_motion else "快速搜索：关",func():app.extraction_reduced_motion=not app.extraction_reduced_motion;app._save_preferences();_help(app))
	app._button(actions,"返回",app._clear_overlay,true)
static func _confirm_departure(app,extraction: bool) -> void:
	var left:=0
	for box in app.model.extraction.containers():left+=box.get("items",[]).size()
	var action:=func():_stop_search(app,false);_operate(app,app.model.extraction.extract() if extraction else app.model.extraction.advance_room(),"撤离成功" if extraction else "")
	if left>0:app._confirm("准备撤离？","还有 %d 件物资留在据点。" % left,action)
	else:action.call()
