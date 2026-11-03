extends RefCounted
# Presentation only: callers keep the persisted option id and own the action.
const RuneTheme = preload("res://scripts/ui/rune_theme.gd")
const RewardRarity = preload("res://scripts/ui/reward_rarity.gd")
const GREEN := Color("a9cdb0")

static func effect(option:Dictionary)->Dictionary:
	return option.get("presentationEffect",option.get("effect",{}))

static func icon_key(option:Dictionary,currency:String)->String:
	var data:=effect(option)
	if data.has("blessing"):return "star"
	if data.has("items") or data.has("cache"):return "bag"
	if data.has("heal") or data.has("revive"):return "heart"
	if data.has("repair"):return "shield"
	if data.has("energy") or data.has("cooldown"):return "energy"
	if data.has("meta"):return "memory_shard"
	if data.has("coins") or data.has("gamble"):return currency
	if data.has("battle"):return "sword"
	if data.has("key") or data.has("unlock"):return "gear"
	var id:=str(option.get("id",""))
	if id=="rest":return "camp"
	if id=="shop":return "rift_coin"
	if id=="event":return "path"
	return RuneTheme.effect_key(option)

static func color_for(option:Dictionary,fallback:Color)->Color:
	var rarity:=str(effect(option).get("blessing",""))
	if rarity in ["blue","gold"]:return RewardRarity.tier(rarity).color
	if effect(option).has("heal"):return GREEN
	return fallback

static func heading(app,parent:Node,option:Dictionary,currency:String,color:Color,details:Callable=Callable())->void:
	var row=app._hbox(parent,5)
	var icon=app._rune_icon(row,icon_key(option,currency),28,color)
	var data:=effect(option)
	if data.has("items") and not data.items.is_empty():
		var item:Dictionary=app.model.extraction.item_def(str(data.items[0]))
		var path:=str(item.get("icon",""))
		if ResourceLoader.exists(path):icon.texture=load(path);icon.modulate=Color.WHITE
	var label=app._label(row,str(option.get("label","继续探索")),16,color,true)
	label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	label.tooltip_text=str(option.get("description",""))
	if details.is_valid():
		var info=app._tool_button(row,"book","查看详情",details)
		info.custom_minimum_size=Vector2(30,30)
		info.size_flags_vertical=Control.SIZE_SHRINK_CENTER

static func body(app,parent:Node)->VBoxContainer:
	var scroll:=ScrollContainer.new()
	scroll.name="EventChoiceBody"
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y=38
	parent.add_child(scroll)
	var column=app._vbox(scroll,4)
	column.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	return column


static func strip(app,parent:Node,key:String,text:String,color:Color)->void:
	var panel=app._panel(parent,color.darkened(.72),4)
	var row=app._hbox(panel,5)
	app._rune_icon(row,key,17,color)
	app._label(row,text,12,color,true).size_flags_horizontal=Control.SIZE_EXPAND_FILL

static func costs(app,parent:Node,option:Dictionary,currency:String)->void:
	var data:=effect(option)
	var cost:=int(option.get("cost",0))
	if cost>0:strip(app,parent,currency,"支付 %d %s"%[cost,"裂隙币" if currency=="rift_coin" else "金币"],app.GOLD)
	var risk:=str(option.get("risk",""))
	if not risk.is_empty() and risk!="进入后再选择具体代价":
		strip(app,parent,"heart" if data.has("hpCost") else currency,risk,app.RED)
	else:
		if data.has("hpCost"):strip(app,parent,"heart","最大生命 −%d%%"%roundi(float(data.hpCost)*100),app.RED)
		if data.has("shieldCost"):strip(app,parent,"shield","装备护盾 −%d%%"%roundi(float(data.shieldCost)*100),app.RED)

static func benefits(app,parent:Node,option:Dictionary,currency:String,color:Color)->void:
	var data:=effect(option)
	var reward:=str(option.get("reward",""))
	if not reward.is_empty():
		strip(app,parent,icon_key(option,currency),reward,color)
		return
	if data.is_empty():
		app._label(parent,str(option.get("description","")),13,app.TEXT,true)
		return
	if data.has("heal"):
		strip(app,parent,"heart","%s恢复 %d%%%s"%["全队" if data.get("revive",false) else "存活队员",roundi(float(data.heal)*100)," · 复苏" if data.get("revive",false) else ""],GREEN)
	if data.has("repair"):strip(app,parent,"shield","装备护盾 +%d%%"%roundi(float(data.repair)*100),app.CYAN)
	if data.has("energy") or data.has("cooldown"):
		var parts:Array[String]=[]
		if data.has("energy"):parts.append("能量 +%d"%int(data.energy))
		if data.has("cooldown"):parts.append("清空冷却" if int(data.cooldown)>=99 else "冷却 −%d"%int(data.cooldown))
		strip(app,parent,"energy"," · ".join(parts),app.CYAN)
	if data.has("blessing"):
		var rarity:=str(data.blessing)
		strip(app,parent,"star","选择%s祝福"%({"blue":"蓝色","gold":"金色"}.get(rarity,"一项")),color)
	if data.has("cache"):strip(app,parent,"bag","搜寻精良物资" if int(data.get("quality",0))>0 else "搜寻遗留物资",GREEN)
	if data.has("items"):
		var names:Array[String]=[]
		for item_id in data.items:
			var item:Dictionary=app.model.extraction.item_def(str(item_id))
			names.append(str(item.get("name",item_id)))
		strip(app,parent,"bag","、".join(names)+"\n搜索后装包",GREEN)
	if data.has("battle"):strip(app,parent,"sword",str(option.get("description","挑战守卫")),app.TEXT)
	if data.has("key"):strip(app,parent,"gear","本区域密室钥匙 ×1",app.GOLD)
	if data.has("unlock"):strip(app,parent,"gear","使用本区域钥匙",app.GOLD)

static func disabled_caption(reason:String)->String:
	if reason.contains("生命") or reason.contains("复苏"):return "生命不足"
	if reason.contains("裂隙币"):return "裂隙币不足"
	if reason.contains("金币"):return "金币不足"
	if reason.contains("祝福"):return "暂无适用祝福"
	return "暂不可选"
