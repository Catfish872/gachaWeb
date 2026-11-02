extends RefCounted
const RewardGain=preload("res://scripts/ui/rogue_reward_gain.gd")
const RewardRarity = preload("res://scripts/ui/reward_rarity.gd")
const RouteTrack=preload("res://scripts/ui/abyss_route_track.gd")
const RuneTheme=preload("res://scripts/ui/rune_theme.gd")
const Sigil=preload("res://scripts/ui/abyss_sigil.gd")
const VIOLET:=Color("c4a4e8")
const GREEN:=Color("a9cdb0")
const PHASE_NAMES:={"none":"准备出战","reward":"选择祝福","route":"选择路线","event":"遗境奇遇","shop":"旅途商店","rest":"篝火休整"}

static func render(app)->void:
	var abyss:Dictionary=app.model.state.abyss
	var rogue:Dictionary=abyss.rogue
	var meta:Dictionary=abyss.meta
	var active:bool=app.model.abyss_run_active()
	var phase:=str(rogue.get("nextStep",{}).get("type","none"))
	var floor_number:=int(abyss.get("currentFloor",1))
	var wide:bool=app.size.x>=850
	app.set_page_fixed(wide)
	var nav=app._hbox(app.main_body,8) if wide else app._flow(app.main_body,8)
	app._label(nav,"深渊远征",22,VIOLET)
	app._tab_button(nav,"远征地图",func():app.abyss_panel="expedition";app._render_screen(),app.abyss_panel=="expedition")
	app._tab_button(nav,"永久成长",func():app.abyss_panel="meta";app._render_screen(),app.abyss_panel=="meta")
	_spacer(nav)
	app._rune_icon(nav,"rift_coin",20).tooltip_text="裂隙币 · 本轮补给"
	app._label(nav,"裂隙币 %d · 本轮"%int(rogue.get("temporaryCurrency",0)),14,app.GOLD)
	app._rune_icon(nav,"memory_shard",20).tooltip_text="记忆碎片 · 永久成长"
	app._label(nav,"记忆 %d · 永久"%int(meta.get("currency",0)),14,VIOLET)
	app._tool_button(nav,"book","远征规则",func():_help(app))
	var body=app._hbox(app.main_body,12) if wide else app._vbox(app.main_body,12)
	body.size_flags_vertical=Control.SIZE_EXPAND_FILL
	if app.abyss_panel=="meta":
		_meta(app,body,meta,active,wide)
		return
	var trail=_pane(app,body,"裂隙之路",VIOLET)
	trail.get_parent().size_flags_horizontal=Control.SIZE_FILL
	trail.get_parent().custom_minimum_size.x=158 if wide else 0
	var track=RouteTrack.new();track.name="AbyssRouteTrack";track.floor_number=floor_number;track.active=active;track.floor_cap=app.model.abyss_floor_cap();track.route=app.model.abyss_route_preview();trail.add_child(track)
	app._center_label(trail,("第 %d / 50 层"%floor_number) if app.model.abyss_floor_cap()>0 else ("无尽 · 第 %d 层"%floor_number),17,app.GOLD).name="AbyssFloorCaption"
	app._center_label(trail,"最高 %d 层"%int(abyss.maxFloor),12,app.MUTED)
	_daily_card(app,trail)
	var center=_pane(app,body,PHASE_NAMES.get(phase,"远征途中"),app.GOLD if phase=="shop" else VIOLET)
	center.get_parent().size_flags_horizontal=Control.SIZE_EXPAND_FILL
	if active:
		# Share the existing heading row instead of increasing the route pane's
		# minimum height: fixed run actions must fit even at 539 logical pixels.
		var phase_title:Node=center.get_child(0)
		var header=app._hbox(center,8);phase_title.reparent(header);center.move_child(header,0)
		_spacer(header)
		var target_info:Dictionary=app.model.abyss_relic_drop_info()
		var target_id:String=str(target_info.get("targetSetId",""))
		var target:Dictionary=app.model.catalog.get("RelicSets",{}).get(target_id,{})
		var target_row=app._hbox(header,5)
		var target_icon=app._relic_art(target_row,"helmet",25,target_id);target_icon.custom_minimum_size.x=25;target_icon.size_flags_horizontal=Control.SIZE_FILL
		app._label(target_row,str(target.get("name","散件")),12,VIOLET).name="AbyssRunTargetName"
		app._label(target_row,"已锁定",11,app.MUTED)
	if not rogue.get("pendingChoices",[]).is_empty() or phase=="reward":_blessings(app,center,rogue)
	elif phase=="shop":_shop(app,center)
	elif phase in ["route","event","rest"]:_node(app,center,phase)
	else:_departure(app,center,floor_number,active,abyss)
	var footer=app._hbox(center,8)
	var auto=app._button(footer,"连续挑战",Callable(),app.abyss_auto_continue);auto.toggle_mode=true;auto.button_pressed=app.abyss_auto_continue;auto.text="连续挑战 · 开" if app.abyss_auto_continue else "连续挑战 · 关";auto.tooltip_text="自动衔接战斗；遇到祝福和事件时停下选择"
	auto.toggled.connect(func(on):app.abyss_auto_continue=on;app.battle_auto=true if on else app.battle_auto;auto.text="连续挑战 · 开" if on else "连续挑战 · 关")
	_spacer(footer)
	app._button_icon(app._tab_button(footer,"队伍",func():_party_modal(app,abyss)),"party")
	app._button_icon(app._tab_button(footer,"构筑 %d"%rogue.get("selectedRewards",[]).size(),func():_build_modal(app,rogue)),"star")
	if active:
		app._button(footer,"归营",func():app._confirm("结束本轮？","回到营地，保留已获得的永久资源。",func():app.abyss_auto_continue=false;app._abyss_operation(app.model.reset_abyss(),"已返回营地")))

static func _pane(app,parent:Node,title:String,color:Color)->VBoxContainer:
	var p=app._panel(parent,color.darkened(0.65),12);p.size_flags_vertical=Control.SIZE_EXPAND_FILL
	var v=app._vbox(p,9);v.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	app._label(v,title,18,color)
	return v

static func _spacer(parent:Node)->void:
	var s:=Control.new();s.size_flags_horizontal=Control.SIZE_EXPAND_FILL;parent.add_child(s)

static func _scroll(app,parent:Node)->VBoxContainer:
	var sc:=ScrollContainer.new();sc.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;sc.size_flags_horizontal=Control.SIZE_EXPAND_FILL;sc.size_flags_vertical=Control.SIZE_EXPAND_FILL
	if app.size.x<850:sc.custom_minimum_size.y=300
	parent.add_child(sc)
	var v=app._vbox(sc,10);v.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	return v

static func _icon(parent:Node,color:Color,seed_value:int,edge:int=58)->void:
	var icon=Sigil.new();icon.color=color;icon.symbol=seed_value;icon.edge=edge;parent.add_child(icon)

static func _departure(app,parent:Node,floor_number:int,active:bool,abyss:Dictionary)->void:
	var content=_scroll(app,parent)
	content.get_parent().name="AbyssDepartureScroll"
	app._restore_character_list(content.get_parent(),"abyss_departure")
	_difficulty(app,content,active)
	_target_set(app,content,active)
	var hero=app._scene_panel(content,"res://assets/backgrounds/abyss.png",95 if app.size.x>=850 else 140)
	hero.size_flags_vertical=Control.SIZE_EXPAND_FILL
	var shade:=ColorRect.new();shade.color=Color(0.025,0.035,0.08,0.28);shade.mouse_filter=Control.MOUSE_FILTER_IGNORE;shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);hero.add_child(shade)
	var inset:=MarginContainer.new();inset.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]:inset.add_theme_constant_override("margin_"+side,18)
	hero.add_child(inset)
	var v=app._vbox(inset,5)
	app._label(v,"终幕首领" if app.model.abyss_floor_cap()>0 and floor_number==50 else ("首领战将至" if floor_number%10==0 else "向裂隙深处"),24,app.TEXT)
	var gap:=Control.new();gap.size_flags_vertical=Control.SIZE_EXPAND_FILL;v.add_child(gap)
	app._label(v,"每十层迎战首领，通关五十层完成远征。" if app.model.abyss_floor_cap()>0 else "祝福交织成力量，挑战更深的无尽裂隙。",14,app.TEXT,true)
	if not active and not abyss.get("lastRun",{}).is_empty():
		var summary:Dictionary=abyss.lastRun
		app._label(v,"旧远征已结算 · 已获资源保留" if summary.get("outcome","")=="legacy_completion" else ("上一轮通关 %d 层 · 收获 %d 记忆碎片"%[int(summary.get("floorsCleared",0)),int(summary.get("metaEarned",0))]),13,VIOLET,true)
	var row=app._hbox(parent,8)
	var begin=app._button(row,"挑战第 %d 层"%floor_number,func():app._begin_abyss(),true);app._button_icon(begin,"sword",true);begin.name="AbyssBegin";begin.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	app._button(row,"调整编队",func():app.navigate("party"))

static func _difficulty(app,parent:Node,active:bool)->void:
	var selected:Dictionary={}
	for option in app.model.abyss_difficulty_options():
		if option.selected:selected=option
	if active:
		app._label(parent,"本轮难度：%s · 已锁定"%str(selected.get("name","初探")),13,VIOLET,true);return
	var row=app._grid(parent,2 if app.size.x<850 else 4)
	for option in app.model.abyss_difficulty_options():
		var b=app._tab_button(row,str(option.name),func():app._abyss_operation(app.model.set_abyss_difficulty(int(option.id)),""),bool(option.selected))
		b.name="AbyssDifficulty_"+str(option.id);b.disabled=not bool(option.enabled);b.tooltip_text=str(option.description)
	app._label(parent,str(selected.get("description","")),12,app.MUTED,true)

static func _target_set(app,parent:Node,active:bool)->void:
	var info:Dictionary=app.model.abyss_relic_drop_info()
	var set_id:String=str(info.get("targetSetId",""))
	var definition:Dictionary=app.model.catalog.get("RelicSets",{}).get(set_id,{})
	var color:Color=Color(str(definition.get("color","c4a4e8")))
	var panel=app._panel(parent,color.darkened(.55),8);panel.name="AbyssTargetSet"
	var row=app._hbox(panel,9)
	var icon=app._relic_art(row,"helmet",46,set_id);icon.custom_minimum_size.x=46;icon.size_flags_horizontal=Control.SIZE_FILL
	var copy=app._vbox(row,3);copy.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var title:String=str(definition.get("name","散件"))
	app._label(copy,title+(" · 本轮已锁定" if active else " · 目标套装"),16,color,true).name="AbyssTargetSetName"
	app._label(copy,"普通层 %.0f%% · 每 50 层预计 %.0f 件"%[float(info.get("normalChance",0))*100.0,float(info.get("expectedPer50",10))],12,app.MUTED,true).name="AbyssRelicDropRate"
	var choose=app._button(row,"详情" if active else "选择套装",func():_target_set_picker(app));choose.name="AbyssChooseRelicSet"
	choose.tooltip_text="本轮获得的套装遗物来自所选目标；部位与属性随机"

static func _target_set_picker(app)->void:
	var info:Dictionary=app.model.abyss_relic_drop_info()
	var locked:bool=bool(info.get("locked",false))
	var box=app._modal("本轮目标套装" if locked else "选择目标套装",990,620)
	box.name="AbyssSetPickerContent"
	box.add_theme_constant_override("separation",12)
	app._label(box,"本轮已锁定，远征结束后可重新选择。" if locked else "本轮套装遗物均来自目标套装，部位与属性随机。",14,app.MUTED,true)
	var rates=app._vbox(app._panel(box,VIOLET.darkened(.6),9),4)
	app._label(rates,"每 %d 层四星保底 · 每 %d 层五星保底"%[int(info.get("milestoneEvery",5)),int(info.get("fiveStarEvery",10))],14,app.TEXT,true)
	app._label(rates,"普通层额外掉落 %.0f%% · 额外品质：四星 %.0f%% / 五星 %.0f%%"%[float(info.get("normalChance",0))*100.0,float(info.get("extraRarity4Chance",.8))*100.0,float(info.get("extraRarity5Chance",.2))*100.0],12,app.MUTED,true)
	app._label(rates,"每 50 层预计 %.0f 件"%float(info.get("expectedPer50",10)),12,app.MUTED,true)
	var grid=app._grid(box,1 if app.size.x<760 else 2)
	for option in app.model.relic_set_options():
		var set_id:String=str(option.id)
		var selected:bool=bool(option.get("selected",false))
		var color:Color=Color(str(option.get("color","c4a4e8")))
		var panel=app._panel(grid,color if selected else app.LINE,10);panel.name="AbyssRelicSetCard_"+set_id
		var card=app._vbox(panel,7)
		var heading=app._hbox(card,8)
		var icon=app._relic_art(heading,"helmet",58,set_id);icon.custom_minimum_size.x=58;icon.size_flags_horizontal=Control.SIZE_FILL
		var identity=app._vbox(heading,4);identity.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		app._label(identity,str(option.name),21,color,true)
		var pieces=app._hbox(identity,3)
		for slot in app.model.catalog.RelicSlots:
			var thumb=app._relic_art(pieces,str(slot.id),22,set_id);thumb.custom_minimum_size.x=22;thumb.size_flags_horizontal=Control.SIZE_FILL
		app._relic_set_details(card,set_id)
		var choice=app._button(card,"本轮目标" if locked and selected else ("已选择" if selected else "选择此套装"),func():_choose_target_set(app,set_id),selected)
		choice.name="AbyssRelicSet_"+set_id;choice.disabled=locked or selected
	box.move_child(rates.get_parent(),box.get_child_count()-1)
	var footer=app._hbox(app._modal_footer(box),8)
	app._restore_character_list(box.get_parent(),"abyss_set_picker")
	app._label(footer,"本轮已锁定" if locked else "出发时锁定本轮目标",12,app.MUTED,true).size_flags_horizontal=Control.SIZE_EXPAND_FILL
	app._button(footer,"返回",app._clear_overlay).name="AbyssSetPickerClose"

static func _choose_target_set(app,set_id:String)->void:
	var result:Dictionary=app.model.set_abyss_relic_set(set_id)
	if not app._check(result):return
	app._clear_overlay();app._render_screen()
	var definition:Dictionary=app.model.catalog.get("RelicSets",{}).get(set_id,{})
	app._toast("目标套装 · "+str(definition.get("name","")),VIOLET)

static func _card(app,parent:Node,title:String,desc:String,color:Color,symbol:int,semantic:String="",reward:Dictionary={})->VBoxContainer:
	var p=app._panel(parent,color.darkened(0.5),12);p.custom_minimum_size.x=160
	var v=app._vbox(p,8)
	if not reward.is_empty():app._reward_art_icon(v,reward,44)
	elif semantic.is_empty():_icon(v,color,symbol)
	else:app._rune_icon(v,semantic,44,color)
	var name=app._label(v,title,18,color,true);name.max_lines_visible=2
	var text=app._label(v,desc,14,app.TEXT,true);text.size_flags_vertical=Control.SIZE_EXPAND_FILL
	return v

static func _reward_operation(app,result:Dictionary,message:String="",continue_auto:bool=false)->void:
	var reward:Dictionary=result.get("reward",result.get("outcome",{}).get("reward",{}))
	if not result.get("success",false) or reward.is_empty():
		app._abyss_operation(result,message,continue_auto)
		return
	var presentation:Dictionary=result.duplicate(true)
	presentation.message=""
	app._abyss_operation(presentation,"",false)
	var count:=0
	for raw in app.model.state.abyss.rogue.get("selectedRewards",[]):
		var id:String=str(raw.get("id","")) if raw is Dictionary else str(raw)
		if id==str(reward.get("id","")):count+=1
	var run_id:=str(app.model.state.abyss.rogue.get("runId",""))
	var panel_id:=str(app.abyss_panel)
	var generation:=int(app.get_meta("rogue_gain_generation",0))+1
	var resume:Callable=func():
		if continue_auto and is_instance_valid(app) and app.current_screen=="abyss" and str(app.abyss_panel)==panel_id and app.overlay.get_child_count()==0 and str(app.model.state.abyss.rogue.get("runId",""))==run_id and int(app.get_meta("rogue_gain_generation",0))==generation:app._maybe_continue_abyss()
	RewardGain.show_gain(app,reward,maxi(1,count),resume)

static func _blessings(app,parent:Node,rogue:Dictionary)->void:
	app._label(parent,"选择一项回响，本轮持续生效",14,app.MUTED,true)
	var content=_scroll(app,parent)
	var grid=app._grid(content,1 if app.size.x<850 else 3)
	for raw in rogue.get("pendingChoices",[]):
		var choice:Dictionary=app._present_abyss_reward(raw)
		var color:Color={"gold":app.GOLD,"blue":app.CYAN,"white":app.TEXT}.get(str(choice.get("rarity","white")),app.TEXT)
		var v=_card(app,grid,str(choice.get("name","裂隙回响")),str(choice.get("description","")),color,str(choice.get("id","")).hash(),RuneTheme.effect_key(choice),choice)
		RewardRarity.decorate(app,v.get_parent(),v,str(choice.get("rarity","white")))
		app._label(v.find_child("RewardRarityBadge",true,false),str(choice.get("target","全队")),12,app.MUTED,true)
		var b=app._button(v,"融入构筑",func():_reward_operation(app,app.model.choose_abyss_reward(str(choice.get("choiceId",choice.get("id","")))),"回响已融入本轮构筑",true),true)
		app._button_icon(b,"check",true)
		b.name="Blessing_"+str(choice.get("choiceId",choice.get("id","")))

static func _node(app,parent:Node,phase:String)->void:
	var node:Dictionary=app.model.node_options()
	app._label(parent,str(node.get("title","旅途抉择")),23,app.TEXT,true)
	if phase!="route":app._label(parent,str(node.get("description","")),14,app.MUTED,true)
	var content=_scroll(app,parent)
	var options:Array=node.get("options",[])
	var grid=app._grid(content,1 if app.size.x<850 else mini(3,maxi(1,options.size())))
	var color:Color=GREEN if phase=="rest" else VIOLET
	for option in options:
		var panel=app._panel(grid,color.darkened(0.5),10)
		var v=app._vbox(panel,6)
		var heading=app._hbox(v,8);app._rune_icon(heading,RuneTheme.effect_key(option),32,color)
		app._label(heading,str(option.get("label","继续探索")),17,color,true).size_flags_horizontal=Control.SIZE_EXPAND_FILL
		if not str(option.get("reward","")).is_empty():app._label(v,str(option.reward),13,GREEN,true)
		var risk:String=str(option.get("risk",""))
		if not risk.is_empty() and risk!="进入后再选择具体代价":app._label(v,risk,12,app.RED,true)
		if str(option.get("reward","")).is_empty() and str(option.get("risk","")).is_empty():app._label(v,str(option.get("description","")),13,app.TEXT,true)
		var action_gap:=Control.new();action_gap.size_flags_vertical=Control.SIZE_EXPAND_FILL;v.add_child(action_gap)
		var actions=app._hbox(v,6)
		app._button(actions,"详情",func():_detail(app,str(option.get("label","旅途抉择")),str(option.get("description",""))))
		var cost:=int(option.get("cost",0))
		var b=app._button(actions,("选择 · %d 裂隙币"%cost) if cost>0 else "选择",func():_reward_operation(app,app.model.choose_abyss_node(str(option.id)),"",true),true)
		app._button_icon(b,"rift_coin" if cost>0 else "check",true)
		b.size_flags_horizontal=Control.SIZE_EXPAND_FILL;b.name="NodeChoice_"+str(option.id);b.disabled=not bool(option.get("enabled",true))
		if b.disabled:app._label(v,str(option.get("disabledReason","暂不可用")),12,app.RED,true)

static func _shop(app,parent:Node)->void:
	var content=_scroll(app,parent)
	content.get_parent().name="AbyssShopScroll"
	var grid=app._grid(content,1 if app.size.x<850 else 3)
	for item in app.model.abyss_shop_items():
		var sold:=bool(item.get("sold",false))
		var blessing:bool=str(item.get("kind",""))=="blessing"
		var rarity:String=str(item.get("rarity","white"))
		var tier:Dictionary=RewardRarity.tier(rarity)
		var color:Color=tier.color if blessing else GREEN
		var definition:Dictionary=app._abyss_reward(str(item.get("rewardId",""))) if blessing else item
		var v=_card(app,grid,str(item.get("name","旅行补给")),str(item.get("description","")),color,str(item.id).hash(),RuneTheme.effect_key(definition),definition)
		v.get_parent().name="RunShopCard_"+str(item.id)
		if blessing:
			RewardRarity.decorate(app,v.get_parent(),v,rarity)
		else:
			var category=app._hbox(v,6);v.move_child(category,0)
			app._rune_icon(category,"bag",16,GREEN)
			app._label(category,"补给",12,GREEN).name="RunShopSupplyLabel"
		var title:String="已购入" if sold else ((str(tier.label)+" · 购买 %d")%int(item.get("cost",0)) if blessing else "购买 · %d"%int(item.get("cost",0)))
		var b=app._button(v,title,func():_purchase_shop(app,str(item.id)),false)
		app._button_icon(b,"rift_coin",false)
		b.add_theme_color_override("font_color",color)
		b.add_theme_color_override("font_hover_color",color.lightened(.2))
		b.tooltip_text="%s · %d 裂隙币"%[str(item.get("name","补给")),int(item.get("cost",0))]
		if sold:v.modulate=Color(.7,.7,.7,1)
		b.name="RunShop_"+str(item.id);b.disabled=sold or not bool(item.get("enabled",true))
		if b.disabled and not sold:app._label(v,str(item.get("disabledReason","裂隙币不足")),12,app.RED,true)
	var leave=app._button(parent,"离开商店",func():app._abyss_operation(app.model.leave_abyss_shop(),"已离开旅途商店",true));leave.name="RunShopLeave"

static func _purchase_shop(app,item_id:String)->void:
	var scroll=app.main_body.find_child("AbyssShopScroll",true,false)
	var offset:int=int(scroll.scroll_vertical) if is_instance_valid(scroll) else 0
	var rogue:Dictionary=app.model.state.abyss.rogue
	var run_id:=str(rogue.get("runId",""))
	var node_id:=str(rogue.get("pendingNode",{}).get("id",""))
	var result:Dictionary=app.model.purchase_abyss_item(item_id)
	_reward_operation(app,result,"补给已收入行囊")
	if result.get("success",false):_restore_shop_scroll(app,run_id,node_id,offset)

static func _restore_shop_scroll(app,run_id:String,node_id:String,offset:int)->void:
	var tree:SceneTree=app.get_tree()
	await tree.process_frame
	await tree.process_frame
	if not is_instance_valid(app) or app.current_screen!="abyss" or app.abyss_panel!="expedition":return
	var rogue:Dictionary=app.model.state.abyss.rogue
	if str(rogue.get("runId",""))!=run_id or str(rogue.get("nextStep",{}).get("type",""))!="shop" or str(rogue.get("pendingNode",{}).get("id",""))!=node_id:return
	var scroll=app.main_body.find_child("AbyssShopScroll",true,false)
	if is_instance_valid(scroll):scroll.scroll_vertical=offset

static func _meta(app,parent:Node,meta:Dictionary,active:bool,wide:bool)->void:
	var intro=_pane(app,parent,"记忆营地",VIOLET)
	intro.get_parent().size_flags_horizontal=Control.SIZE_FILL;intro.get_parent().custom_minimum_size.x=210 if wide else 0
	app._rune_icon(intro,"memory_shard",58)
	app._label(intro,str(int(meta.get("currency",0))),36,app.GOLD)
	app._label(intro,"记忆碎片",16,VIOLET)
	app._label(intro,"跨轮保留，强化下一次远征。",14,app.MUTED,true)
	var gap:=Control.new();gap.size_flags_vertical=Control.SIZE_EXPAND_FILL;intro.add_child(gap)
	var exchange:Dictionary=app.model.memory_exchange_status()
	var exchange_button=app._button(intro,"兑换星尘晶",func():_exchange_memory(app),bool(exchange.enabled))
	exchange_button.name="MemoryExchangeOpen";app._button_icon(exchange_button,"gem",bool(exchange.enabled));exchange_button.disabled=not bool(exchange.enabled)
	app._label(intro,"1 记忆 = 1 星尘晶" if exchange.enabled else str(exchange.reason),13,app.MUTED,true)
	app._label(intro,"本轮结束后可升级" if active else "营地已开放",14,GREEN,true)
	app._button(intro,"返回远征地图",func():app.abyss_panel="expedition";app._render_screen())
	var upgrades=_pane(app,parent,"永久传承",VIOLET)
	var content=_scroll(app,upgrades)
	var grid=app._grid(content,1 if not wide else 2)
	for upgrade in app.model.meta_upgrade_list():
		var p=app._panel(grid,VIOLET.darkened(0.6),10)
		var v=app._vbox(p,6)
		var row=app._hbox(v,8);app._rune_icon(row,RuneTheme.effect_key(upgrade),38,VIOLET);var title=app._vbox(row,3);title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		app._label(title,str(upgrade.name),18,app.TEXT,true)
		var level:=int(upgrade.level);var maximum:=int(upgrade.maxLevel)
		app._label(title,"等级 %d / %d"%[level,maximum],12,VIOLET)
		var detail_row=app._hbox(v,8)
		var short_desc={"vitality":"生命 +4% / 级","offense":"攻击 +3% / 级","recovery":"战后回复 +1.5% / 级","supply":"开局裂隙币 +15 / 级"}
		app._label(detail_row,short_desc.get(str(upgrade.id),str(upgrade.description)),13,app.MUTED,true)
		_spacer(detail_row)
		app._tool_button(row,"book","成长详情",func():_detail(app,str(upgrade.name),str(upgrade.description)))
		var capped:=level>=maximum
		var b=app._button(v,"已满级" if capped else "升级 · %d 碎片"%int(upgrade.get("cost",0)),func():app._abyss_operation(app.model.purchase_meta_upgrade(str(upgrade.id)),"营地升级完成"),not capped)
		app._button_icon(b,"memory_shard",not capped)
		b.name="MetaUpgrade_"+str(upgrade.id);b.disabled=capped or not bool(upgrade.get("enabled",false))
		if b.disabled and not capped:b.text="本轮结束后可升级" if active else "记忆碎片不足 · %d"%int(upgrade.get("cost",0))

static func _daily_card(app,parent:Node)->void:
	var daily:Dictionary=app.model.abyss_daily_status()
	var card=app._panel(parent,app.GOLD.darkened(.55),8);card.name="AbyssDailyCard"
	var v=app._vbox(card,4)
	var head=app._hbox(v,5);app._rune_icon(head,"gem",18);app._label(head,"第 %d 层"%int(daily.nextMilestone),14,app.GOLD).name="AbyssDailyMilestone"
	app._label(v,"今日已领 %d"%int(daily.paidToday),13,app.TEXT).name="AbyssDailyPaid"
	app._label(v,"+%d 星尘晶"%int(daily.remaining) if int(daily.remaining)>0 else "今日已领取",16,app.GOLD).name="AbyssDailyNext"
	app._label(v,"每日 06:00 刷新",11,app.MUTED).tooltip_text="北京时间；更高难度补齐差额"
	var refresh:=Timer.new();refresh.name="AbyssDailyRefresh";refresh.wait_time=15;card.add_child(refresh)
	refresh.timeout.connect(func():
		var latest:Dictionary=app.model.abyss_daily_status()
		v.get_node("AbyssDailyPaid").text="今日已领 %d"%int(latest.paidToday)
		head.get_node("AbyssDailyMilestone").text="第 %d 层"%int(latest.nextMilestone)
		v.get_node("AbyssDailyNext").text="+%d 星尘晶"%int(latest.remaining) if int(latest.remaining)>0 else "今日已领取")
	refresh.start()

static func _exchange_memory(app)->void:
	var status:Dictionary=app.model.memory_exchange_status()
	if not status.enabled:app._toast(str(status.reason));return
	var box=app._modal("记忆兑换",620,420)
	var balance=app._hbox(box,10);app._rune_icon(balance,"memory_shard",36)
	app._label(balance,"可用记忆 %d"%int(status.available),22,app.TEXT)
	var input_row=app._hbox(box,10)
	var amount:=SpinBox.new();amount.name="MemoryExchangeAmount";amount.min_value=1;amount.max_value=int(status.available);amount.step=1;amount.value=1;amount.custom_minimum_size=Vector2(150,48);amount.size_flags_horizontal=Control.SIZE_EXPAND_FILL;input_row.add_child(amount)
	var all=app._button(input_row,"全部",func():amount.value=amount.max_value);all.name="MemoryExchangeAll"
	var output=app._hbox(box,10);app._rune_icon(output,"gem",30)
	var receive=app._label(output,"获得 1 星尘晶",22,app.GOLD);receive.name="MemoryExchangePreview"
	amount.value_changed.connect(func(value):receive.text="获得 %d 星尘晶"%int(value))
	app._label(box,"1 记忆 = 1 星尘晶",14,app.MUTED)
	var footer=app._hbox(app._modal_footer(box),10)
	app._button(footer,"取消",app._clear_overlay).name="MemoryExchangeCancel"
	var confirm=app._button(footer,"确认兑换",func():
		var result:Dictionary=app.model.exchange_memory(int(amount.value))
		if result.get("success",false):app._clear_overlay()
		app._abyss_operation(result,"兑换完成"),true)
	confirm.name="MemoryExchangeConfirm";confirm.size_flags_horizontal=Control.SIZE_EXPAND_FILL;app._button_icon(confirm,"gem",true)

static func _party_modal(app,abyss:Dictionary)->void:
	var box=app._modal("远征队伍",900,430)
	var saved=abyss.get("savedPartyState")
	var members:Array=saved if saved is Array else app.model.battle_party(true)
	var row=app._grid(box,1 if app.size.x<850 else 3)
	for unit in members:
		var p=app._panel(row,app.LINE,12);var v=app._vbox(p,6)
		app._portrait(v,str(unit.id),130,false,false,"bust")
		app._center_label(v,app._char_name(str(unit.id)),16,app.TEXT)
		var maximum:=maxi(1,int(unit.get("maxHp",unit.get("stats",{}).get("maxHp",1))))
		var hp:=int(unit.get("currentHp",maximum))
		app._progress(v,hp,maximum,GREEN,6)
		app._center_label(v,"%d / %d"%[hp,maximum],13,GREEN)
		app._center_label(v,"能量 %d"%int(unit.get("energy",0)),13,app.CYAN)
	app._button(app._modal_footer(box),"返回",app._clear_overlay)

static func _build_modal(app,rogue:Dictionary)->void:
	var box=app._modal("本轮构筑",900,460)
	var rewards:Array=rogue.get("selectedRewards",[])
	if rewards.is_empty():app._label(box,"通过战斗与奇遇获取回响。",16,app.MUTED,true)
	var grouped:Dictionary={}
	for raw in rewards:
		var reward:Dictionary=app._present_abyss_reward(raw)
		if not grouped.has(reward.id):grouped[reward.id]={"reward":reward,"count":0}
		grouped[reward.id].count+=1
	var grid=app._grid(box,1 if app.size.x<850 else 2)
	for entry in grouped.values():
		var reward:Dictionary=entry.reward
		var p=app._panel(grid,VIOLET.darkened(0.6),10);var v=app._vbox(p,6)
		RewardRarity.decorate(app,p,v,str(reward.get("rarity","white")))
		var heading=app._hbox(v,8)
		app._rune_icon(heading,RuneTheme.effect_key(reward),30,VIOLET)
		app._label(heading,"%s ×%d"%[reward.name,entry.count],18,app.GOLD,true)
		app._label(v,str(reward.description),14,app.MUTED,true)
	app._button(app._modal_footer(box),"返回",app._clear_overlay)

static func _help(app)->void:
	var box=app._modal("远征指南",660,400)
	for line in ["生命、能量与冷却跨层保留。","祝福、路线、奇遇和补给由你选择。","裂隙币用于本轮补给，记忆碎片用于永久传承。","初探、险境、绝境以第五十层为终点。","无尽难度可持续挑战，每十层迎战首领。","每十层领取每日星尘晶，北京时间早六点刷新。","提升难度补齐差额，经验与遗物持续获得。","营地传承全满后，可在局外等量兑换记忆。","归营后可重新编队与升级营地。"]:app._label(box,line,16,app.TEXT,true)
	app._button(app._modal_footer(box),"返回",app._clear_overlay)

static func _detail(app,title:String,description:String)->void:
	var box=app._modal(title,640,300)
	app._label(box,description,18,app.TEXT,true)
	app._button(app._modal_footer(box),"返回",app._clear_overlay)
