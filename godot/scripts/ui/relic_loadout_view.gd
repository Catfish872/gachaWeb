extends RefCounted
## A cancellable, read-only search followed by one model-owned atomic transaction.
## Each open dialog owns its search; closing or replacing it invalidates the work.

static func show_for(app, char_id:String="", restored_scroll:int=0, show_details:bool=false) -> void:
	if not app.model.state.ownedCharacters.has(char_id):
		char_id=str(app.selected_character)
	if not app.model.state.ownedCharacters.has(char_id):
		char_id=str(app.model.state.ownedCharacters.keys()[0]) if not app.model.state.ownedCharacters.is_empty() else ""
	if char_id.is_empty():return
	var box=app._modal("自动搭配",1000,620)
	box.name="RelicLoadoutContent"
	box.add_theme_constant_override("separation",8)
	var panel:Control=box.get_parent().get_parent()
	panel.set_meta("relic_loadout",true)
	var heading=app._hbox(box,12)
	var portrait=app._portrait(heading,char_id,44);portrait.custom_minimum_size.x=36;portrait.size_flags_horizontal=Control.SIZE_FILL
	var identity=app._vbox(heading,3);identity.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var role=app._label(identity,"正在读取角色定位…",14,app.CYAN,true);role.name="RelicLoadoutRole"
	var chooser:=OptionButton.new();chooser.name="RelicLoadoutCharacter";chooser.custom_minimum_size=Vector2(130,44)
	var ids:Array=app.model.state.ownedCharacters.keys()
	for id in ids:chooser.add_item(app._char_name(str(id)))
	chooser.selected=ids.find(char_id);heading.add_child(chooser)
	chooser.item_selected.connect(func(index):show_for(app,str(ids[index])))
	var progress=app._label(box,"正在整理遗物…",13,app.GOLD,true);progress.name="RelicLoadoutProgress"
	var comparison=app._vbox(box,8);comparison.name="RelicLoadoutComparison"
	var footer=app._modal_footer(box)
	var actions=app._hbox(footer,9)
	var cancel=app._button(actions,"取消",app._clear_overlay);cancel.name="RelicLoadoutCancel"
	var apply=app._button(actions,"正在搭配…",Callable(),true);apply.name="RelicLoadoutApply";apply.disabled=true;apply.size_flags_horizontal=Control.SIZE_EXPAND_FILL;app._button_icon(apply,"check",true)
	var ui:Dictionary={"panel":panel,"box":box,"role":role,"progress":progress,"comparison":comparison,"apply":apply,"chooser":chooser,"charId":char_id,"plan":{},"lastKey":"","applying":false,"restoreScroll":restored_scroll,"detailsOpen":show_details}
	apply.pressed.connect(func():_apply(app,ui))
	if not app.model.has_method("begin_best_relic_loadout"):
		progress.text="搭配功能准备中";return
	var optimizer=app.model.begin_best_relic_loadout(char_id,{})
	if optimizer==null:
		progress.text="搭配暂时无法启动，请返回后重试";return
	ui.optimizer=optimizer
	panel.tree_exiting.connect(func():optimizer.cancel())
	_search(app,ui,optimizer)

static func _restore_scroll(app,scroll:ScrollContainer,offset:int)->void:
	await app.get_tree().process_frame
	await app.get_tree().process_frame
	if is_instance_valid(scroll) and scroll.is_inside_tree():scroll.scroll_vertical=offset

static func _search(app,ui:Dictionary,optimizer)->void:
	var next_draw:int=0
	while is_instance_valid(app) and is_instance_valid(ui.panel) and ui.panel.is_inside_tree():
		var plan:Dictionary=optimizer.advance(4000)
		var complete:bool=bool(plan.get("done",false))
		if Time.get_ticks_msec()>=next_draw or complete:
			_update(app,ui,plan)
			next_draw=Time.get_ticks_msec()+150
		if complete:return
		await app.get_tree().process_frame
	optimizer.cancel()

static func _update(app,ui:Dictionary,plan:Dictionary)->void:
	# The apply action always owns exactly the snapshot shown on screen. Search
	# steps between presentation frames cannot silently replace the clicked plan.
	ui.plan=plan.duplicate(true)
	ui.panel.set_meta("relic_displayed_plan",ui.plan)
	ui.role.text=str(plan.get("roleLabel","当前角色"))
	var proven:bool=bool(plan.get("provenOptimal",false))
	var done:bool=bool(plan.get("done",false))
	var phase:String=str(plan.get("phase","scan"))
	if not bool(plan.get("success",true)) or phase=="error":
		ui.progress.text=str(plan.get("error","暂时无法完成搭配"))
	elif proven:
		ui.progress.text="搭配完成"
	elif phase=="scan":
		ui.progress.text="整理遗物 %d / %d"%[int(plan.get("scanned",0)),int(plan.get("total",0))]
	elif phase=="prune":ui.progress.text="正在比较遗物与套装…"
	else:
		ui.progress.text="继续比较中"
	var gap:float=float(plan.get("gap",INF))
	ui.progress.tooltip_text="参考条件下的收益差距上界：%.2f%%"%(gap*100.0) if is_finite(gap) else "正在核对完整候选范围"
	if is_instance_valid(ui.get("bounds")):ui.bounds.text=_bound_description(plan)
	ui.apply.disabled=not _valid_display_plan(app,plan) or ui.applying
	ui.apply.text=("应用搭配" if proven else "采用当前推荐") if not ui.apply.disabled else ("当前搭配已合适" if proven else ("搭配已取消" if phase=="cancelled" else "正在搭配…"))
	if done and phase=="error":ui.apply.text="暂时无法应用"
	var before:Dictionary=plan.get("before",{})
	var after:Dictionary=plan.get("after",before)
	if not before.has("objective"):return
	var key:String=JSON.stringify(after.get("relicUids",{}))+str(proven)+str(phase=="error")
	if key==str(ui.lastKey):return
	ui.lastKey=key
	var scroll:ScrollContainer=ui.box.get_parent()
	var offset:int=int(ui.restoreScroll) if int(ui.restoreScroll)>=0 else scroll.scroll_vertical
	ui.restoreScroll=-1
	app._clear(ui.comparison)
	var metric=app._hbox(app._panel(ui.comparison,app.CYAN.darkened(.65),10),8)
	var metric_copy=app._vbox(metric,3);metric_copy.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	app._label(metric_copy,str(plan.get("objectiveShortLabel","角色收益")),13,app.MUTED,true)
	app._label(metric_copy,"%.1f  →  %.1f"%[float(before.get("objective",0)),float(after.get("objective",0))],24,app.TEXT)
	var start:float=float(before.get("objective",0))
	var gain:float=float(after.get("objective",0))-start
	app._label(metric,"+%.1f%%"%(100.0*gain/maxf(.00001,absf(start))) if start>0 else "+%.1f"%gain,25,app.CYAN)
	var attributes=app._grid(ui.comparison,3)
	for stat in [["hp","生命"],["atk","攻击"],["def","防御"],["spd","速度"],["cri","暴击率"],["criDmg","暴击伤害"],["energyRate","能量恢复"]]:
		var old:float=float(before.get("stats",{}).get(stat[0],0))
		var value:float=float(after.get("stats",{}).get(stat[0],0))
		var percentage:bool=stat[0] in ["cri","criDmg","energyRate"]
		var text:String=("%.1f%% → %.1f%%"%[old*100.0,value*100.0]) if percentage else ("%d → %d"%[roundi(old),roundi(value)])
		app._label(attributes,str(stat[1])+"　"+text,12,app.CYAN if value>old else app.MUTED,true)
	var labels=app._grid(ui.comparison,2)
	app._label(labels,"当前装备",13,app.MUTED).size_flags_horizontal=Control.SIZE_EXPAND_FILL
	app._label(labels,"推荐搭配" if proven else "当前最佳",13,app.CYAN).size_flags_horizontal=Control.SIZE_EXPAND_FILL
	for slot in app.model.catalog.RelicSlots:
		var pair=app._grid(ui.comparison,2)
		pair.name="RelicLoadoutSlot_"+str(slot.id)
		var current:Dictionary=_find(before,str(slot.id))
		var recommended:Dictionary=_find(after,str(slot.id))
		var changed:bool=str(current.get("uid",""))!=str(recommended.get("uid",""))
		_item(app,pair,current,str(slot.id),false)
		_item(app,pair,recommended,str(slot.id),changed)
	ui.comparison.move_child(attributes,ui.comparison.get_child_count()-1)
	var effects=app._grid(ui.comparison,2)
	_effects(app,effects,before,"当前套装")
	_effects(app,effects,after,"推荐套装")
	var notes=app._vbox(app._panel(ui.comparison,app.LINE,9),4)
	var details=app._vbox(notes,5);details.visible=bool(ui.detailsOpen)
	app._label(details,str(plan.get("objectiveLabel","角色收益")),12,app.GOLD,true)
	ui.bounds=app._label(details,_bound_description(plan),12,app.CYAN,true)
	for note in plan.get("assumptions",[]):app._label(details,app._localized_combat_text(str(note)),12,app.MUTED,true)
	var toggle=app._button(notes,"评价条件与差距",func():ui.detailsOpen=not bool(ui.detailsOpen);details.visible=bool(ui.detailsOpen))
	toggle.name="RelicLoadoutDetails";app._button_icon(toggle,"book");notes.move_child(toggle,0)
	_restore_scroll(app,scroll,offset)

static func _bound_description(plan:Dictionary)->String:
	var upper:float=float(plan.get("upperBound",INF))
	var gap:float=float(plan.get("gap",INF))
	if not is_finite(upper) or not is_finite(gap):return "正在核对完整候选范围与收益上界"
	return "当前收益 %.1f · 收益上界 %.1f · 差距上界 %.2f%%"%[float(plan.get("lowerBound",0)),upper,gap*100.0]

static func _find(snapshot:Dictionary,slot_id:String)->Dictionary:
	for relic in snapshot.get("relics",[]):
		if str(relic.get("slotId",""))==slot_id:return relic
	return {}

static func _item(app,parent:Node,relic:Dictionary,slot_id:String,changed:bool)->void:
	var panel=app._panel(parent,app.CYAN.darkened(.4) if changed else app.LINE,8)
	panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var row=app._hbox(panel,8)
	var art=app._relic_art(row,slot_id,46,str(relic.get("setId","")));art.custom_minimum_size.x=46;art.size_flags_horizontal=Control.SIZE_FILL
	var copy=app._vbox(row,3);copy.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	app._label(copy,app._slot_name(slot_id)+" · "+(app._relic_set_name(relic) if not relic.is_empty() else "空置"),14,app.TEXT,true)
	if relic.is_empty():
		app._label(copy,"等待收集",12,app.MUTED)
	else:
		app._label(copy,"★".repeat(int(relic.get("rarity",3)))+"  +%d"%int(relic.get("level",0)),12,app._rarity_color(int(relic.get("rarity",3))))
		app._label(copy,app._relic_main(relic),12,app.CYAN if changed else app.MUTED,true)
		var secondary:Array[String]=[]
		for stat in relic.get("subStats",[]):
			secondary.append(app._stat_label(str(stat.get("stat","")),str(stat.get("name","属性")))+" +"+app._stat_value(str(stat.get("stat","")),float(stat.get("value",0))))
		if not secondary.is_empty():app._label(copy," · ".join(secondary),11,app.MUTED,true)

static func _effects(app,parent:Node,snapshot:Dictionary,title:String)->void:
	var box=app._vbox(app._panel(parent,app.LINE,9),5)
	app._label(box,title,13,app.GOLD)
	var bonuses:Array=snapshot.get("activeBonuses",[])
	if bonuses.is_empty():app._label(box,"自由搭配",12,app.MUTED)
	for bonus in bonuses:
		app._label(box,"%s · %d 件"%[str(bonus.get("name","")),int(bonus.get("pieces",0))],12,app.CYAN,true)
		app._label(box,str(bonus.get("description","")),12,app.MUTED,true)

static func _apply(app,ui:Dictionary)->void:
	if ui.applying or ui.apply.disabled:return
	ui.applying=true;ui.apply.disabled=true;ui.chooser.disabled=true
	var displayed:Dictionary=ui.plan.duplicate(true)
	if ui.has("optimizer"):ui.optimizer.cancel()
	var result:Dictionary=app.model.apply_relic_loadout(displayed,not bool(displayed.get("provenOptimal",false)))
	if bool(result.get("success",false)):
		app._clear_overlay();app._update_resources();app._ui_sound("equip")
		app._toast(app._char_name(str(ui.charId))+" · 搭配已应用",app.CYAN);app._render_screen()
		return
	ui.applying=false;ui.chooser.disabled=false
	app._toast(str(result.get("error","搭配状态已更新，正在重新比较")),app.RED)
	# Every failed application is refreshed from the actual state. The model owns
	# rollback, so the dialog never announces a commit before persistence succeeds.
	var scroll:ScrollContainer=ui.box.get_parent()
	show_for(app,str(ui.charId),scroll.scroll_vertical,bool(ui.detailsOpen))

static func _valid_display_plan(app,plan:Dictionary)->bool:
	if not bool(plan.get("canApply",false)) or bool(plan.get("cancelled",false)) or str(plan.get("fingerprint","")).length()!=64:return false
	var after:Dictionary=plan.get("after",{})
	var slots:Dictionary=after.get("relicUids",{})
	var relics:Array=after.get("relics",[])
	if slots.size()!=relics.size() or not after.has("stats"):return false
	var valid_slots:Array=[]
	for slot in app.model.catalog.RelicSlots:valid_slots.append(str(slot.id))
	var seen:Dictionary={}
	for relic in relics:
		var slot_id:String=str(relic.get("slotId",""))
		var uid:String=str(relic.get("uid",""))
		if not slot_id in valid_slots or uid.is_empty() or seen.has(uid) or str(slots.get(slot_id,""))!=uid:return false
		seen[uid]=true
	return true
