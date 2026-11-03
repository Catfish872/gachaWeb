extends RefCounted
## Optional expedition decisions. Effects use the extraction model's atomic API.
## No rolling after the player sees a choice; the selected set persists in room state.
const EVENTS := [
	{"name":"残存修复台", "icon":"gear", "description":"灵力只够启动一处装置。", "choices":[
		{"id":"mend", "label":"修复护盾", "description":"恢复装备护盾45%容量", "effect":{"repair":0.45}},
		{"id":"inscribe", "label":"刻印回响", "description":"花费90金币，选择蓝色回响", "cost":90, "effect":{"blessing":"blue"}},
		{"id":"salvage", "label":"拆取物资", "description":"开启一箱遗留补给", "effect":{"cache":true}},
		{"id":"tools", "label":"收起维修工具", "description":"取得2份便携补给，搜索后装包", "effect":{"items":["repair_patch","cleanse_salt"]}}
	]},
	{"name":"碎星熔炉", "icon":"fire", "description":"熔炉能将护盾灵力凝成回响。", "choices":[
		{"id":"transmute", "label":"熔铸星辉", "description":"消耗装备护盾35%容量，选择金色回响", "effect":{"shieldCost":0.35,"blessing":"gold"}},
		{"id":"attune", "label":"静心共鸣", "description":"获得40能量，冷却减少1", "effect":{"energy":40,"cooldown":1}},
		{"id":"scrap", "label":"收集余材", "description":"开启一箱遗留物资", "effect":{"cache":true}},
		{"id":"bottle", "label":"封存炉火", "description":"取得1份能量补给，搜索后装包", "effect":{"items":["energy_flask"]}}
	]},
	{"name":"守卫遗契", "icon":"sword", "description":"留下的契印通向不同收获。", "choices":[
		{"id":"challenge", "label":"唤醒守卫", "description":"挑战精英，胜利后搜寻珍藏并选择回响", "effect":{"battle":"elite"}},
		{"id":"key", "label":"取走密钥", "description":"获得一把本区域密室钥匙", "effect":{"key":true}},
		{"id":"depart", "label":"平息契印", "description":"获得25能量，安全离开", "effect":{"energy":25}},
		{"id":"study", "label":"研读守卫誓词", "description":"选择一项回响", "effect":{"blessing":""}}
	]},
	{"name":"坍塌货梯", "icon":"chest", "description":"货梯卡在半空，散落的货物只来得及搬走一批。", "choices":[
		{"id":"rescue_cargo", "label":"攀索抢救货箱", "description":"消耗15%生命，找到精良物资", "effect":{"hpCost":0.15,"cache":true,"quality":1}},
		{"id":"operate", "label":"投币启动货梯", "description":"花费65金币，取下精良货箱", "cost":65, "effect":{"cache":true,"quality":1}},
		{"id":"dismantle", "label":"拆取维修工具", "description":"取得1份修理物资，搜索后装包", "effect":{"items":["repair_kit"]}},
		{"id":"ground_cargo", "label":"收集落地货物", "description":"开启一箱普通遗留物资", "effect":{"cache":true}}
	]},
	{"name":"过载蓄能器", "icon":"star", "description":"晶环仍在放电，调整导流方向便能利用余能。", "choices":[
		{"id":"discharge", "label":"引导余能", "description":"获得40能量，冷却减少2", "effect":{"energy":40,"cooldown":2}},
		{"id":"conduct", "label":"以护盾导流", "description":"消耗装备护盾20%容量，获得70能量并清空冷却", "effect":{"shieldCost":0.2,"energy":70,"cooldown":99}},
		{"id":"bottle_charge", "label":"封装残余灵力", "description":"取得2份便携补给，搜索后装包", "effect":{"items":["energy_tonic","cleanse_salt"]}},
		{"id":"stabilize", "label":"稳定晶环", "description":"花费55金币，修复护盾35%并获得30能量", "cost":55, "effect":{"repair":0.35,"energy":30}}
	]},
	{"name":"封存检疫帐", "icon":"heart", "description":"隔离帘后还留着药品，药柜旁的净化灯仅够再亮一次。", "choices":[
		{"id":"sterilize", "label":"点亮净化灯", "description":"全队恢复30%生命，倒下角色复苏", "effect":{"heal":0.3,"revive":true}},
		{"id":"recover_medicine", "label":"穿过污染区取药", "description":"消耗10%生命，取得2份医疗补给，搜索后装包", "effect":{"hpCost":0.1,"items":["revival_incense","saline"]}},
		{"id":"medical_pack", "label":"购买封存药囊", "description":"花费45金币，取得2份医疗补给，搜索后装包", "cost":45, "effect":{"items":["medkit","tourniquet"]}},
		{"id":"gather_dressings", "label":"收集备用敷料", "description":"取得2份便携补给，搜索后装包", "effect":{"items":["bandage","repair_patch"]}}
	]},
	{"name":"替巡路者整理行囊", "icon":"chest", "environmentTheme":"windpass", "description":"巡路者将行囊摊在避风棚里，邀请你一同分拣受潮的补给。", "choices":[
		{"id":"share_meal", "label":"围坐吃些热食", "description":"全队即刻恢复20%生命", "effect":{"heal":0.2}},
		{"id":"pack_rations", "label":"收好便携口粮", "description":"取得2份便携补给，搜索后装包", "effect":{"items":["ration_1","bandage"]}},
		{"id":"sort_tools", "label":"换取修理材料", "description":"花费45金币，取得2份便携补给，搜索后装包", "cost":45, "effect":{"items":["repair_kit","cleanse_salt"]}},
		{"id":"read_route", "label":"核对巡路记号", "description":"即刻获得35能量，冷却减少1", "effect":{"energy":35,"cooldown":1}}
	]},
	{"name":"协助固定导风帆", "icon":"gear", "environmentTheme":"windpass", "description":"帆索已经磨松，桥匠正等人稳住一端，好把新的绳结系牢。", "choices":[
		{"id":"brace_sail", "label":"共同稳住帆索", "description":"消耗12%生命，选择蓝色祝福", "effect":{"hpCost":0.12,"blessing":"blue"}},
		{"id":"mend_armor", "label":"借工具修整护甲", "description":"即刻恢复装备护盾45%容量", "effect":{"repair":0.45}},
		{"id":"collect_patches", "label":"收下备用补片", "description":"取得2份修理物资，搜索后装包", "effect":{"items":["repair_patch","repair_patch"]}},
		{"id":"replace_rope", "label":"购入新绳索", "description":"花费65金币，开启一箱精良遗留物资", "cost":65, "effect":{"cache":true,"quality":1}}
	]},
	{"name":"查看封存运单", "icon":"star", "environmentTheme":"windpass", "description":"图室旁的运单仍有完整封蜡，一枚备用钥匙压在交接簿下。", "choices":[
		{"id":"take_chart_key", "label":"领取图室钥匙", "description":"取得1枚区域钥匙，搜索后收入钥匙串", "effect":{"key":true}},
		{"id":"study_routes", "label":"研读旧运输路线", "description":"选择一项祝福", "effect":{"blessing":""}},
		{"id":"recover_parcel", "label":"取出封存货箱", "description":"花费65金币，开启一箱精良遗留物资", "cost":65, "effect":{"cache":true,"quality":1}},
		{"id":"pack_tonic", "label":"收下值守补给", "description":"取得2份便携补给，搜索后装包", "effect":{"items":["energy_tonic","saline"]}}
	]}
]

static func event_ids(theme: String) -> Array:
	var result: Array = [0,1,2]
	for index in range(EVENTS.size()):
		var event_theme := str(EVENTS[index].get("environmentTheme",""))
		if event_theme.is_empty() or event_theme == theme: result.append(index+3)
	return result

static func event_data(index:int)->Dictionary:
	return EVENTS[posmod(index,EVENTS.size())].duplicate(true)
static func event_choices(index:int)->Array:
	return event_data(index).choices
