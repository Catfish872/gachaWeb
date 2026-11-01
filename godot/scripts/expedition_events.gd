extends RefCounted
## Optional expedition decisions. Effects use the extraction model's atomic API.
## No rolling after the player sees a choice; the selected set persists in room state.
const EVENTS := [
	{"name":"残存修复台", "icon":"gear", "description":"灵力只够启动一处装置。", "choices":[
		{"id":"mend", "label":"修复护盾", "description":"恢复装备护盾45%容量", "effect":{"repair":0.45}},
		{"id":"inscribe", "label":"刻印回响", "description":"花费90金币，选择蓝色回响", "cost":90, "effect":{"blessing":"blue"}},
		{"id":"salvage", "label":"拆取物资", "description":"开启一箱遗留补给", "effect":{"cache":true}}
	]},
	{"name":"碎星熔炉", "icon":"fire", "description":"熔炉能将护盾灵力凝成回响。", "choices":[
		{"id":"transmute", "label":"熔铸星辉", "description":"消耗装备护盾35%容量，选择金色回响", "effect":{"shieldCost":0.35,"blessing":"gold"}},
		{"id":"attune", "label":"静心共鸣", "description":"获得40能量，冷却减少1", "effect":{"energy":40,"cooldown":1}},
		{"id":"scrap", "label":"收集余材", "description":"开启一箱遗留物资", "effect":{"cache":true}}
	]},
	{"name":"守卫遗契", "icon":"sword", "description":"留下的契印通向不同收获。", "choices":[
		{"id":"challenge", "label":"唤醒守卫", "description":"挑战精英，胜利后搜寻珍藏并选择回响", "effect":{"battle":"elite"}},
		{"id":"key", "label":"取走密钥", "description":"获得一把本区域密室钥匙", "effect":{"key":true}},
		{"id":"depart", "label":"平息契印", "description":"获得25能量，安全离开", "effect":{"energy":25}}
	]}
]
static func event_data(index:int)->Dictionary:
	return EVENTS[posmod(index,EVENTS.size())].duplicate(true)
static func event_choices(index:int)->Array:
	return event_data(index).choices
