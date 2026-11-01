extends SceneTree
const Battle = preload("res://scripts/battle_model.gd")
const Game = preload("res://scripts/game_model.gd")
const Sets = preload("res://scripts/relic_sets.gd")
const Parity = preload("res://tests/relic_parity_fixture.gd")
var catalog: Dictionary
var checks := 0
var failures: Array = []

func _init() -> void:
	catalog = JSON.parse_string(FileAccess.get_file_as_string("res://data/catalog.json"))
	test_legacy_parity()
	test_thresholds_and_stat_ownership()
	test_conditional_damage()
	test_action_energy()
	test_active_healing()
	test_skill_shields()
	test_damage_reduction()
	test_future_scaling_and_prediction()
	test_input_isolation_and_manual_auto()
	print("BATTLE RELIC SETS V250: %d checks, %d failures" % [checks, failures.size()])
	for label in failures: printerr("FAIL: ", label)
	quit(0 if failures.is_empty() else 1)

func ck(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func near(actual: float, expected: float, label: String) -> void:
	ck(absf(actual - expected) < 0.00001, "%s actual=%s expected=%s" % [label,actual,expected])

func pieces(set_id: String, count: int) -> Array:
	var result: Array = []
	for index in count:
		result.append({"uid":"test_%s_%d" % [set_id,index],"slotId":catalog.RelicSlots[index].id,"setId":set_id,"level":0,"mainStat":{"stat":"atk_flat","base":0.0,"perLevel":0.0},"subStats":[]})
	return result

func effects(set_id: String, count: int = 4) -> Array:
	return Sets.evaluate(catalog,pieces(set_id,count)).ownerEffects

func arena(owner_effects: Array = [], rogue_effects: Array = [], special: Dictionary = {}):
	var data := catalog.duplicate(true)
	data.SkillData.merge(special,true)
	var b = Battle.new(data)
	b.start({"enemies":["wolf","wolf","wolf"],"seed":250101,"isAbyss":true,"floor":1},[
		{"id":"kaldi","passiveId":"","stats":{"hp":10000,"atk":100,"def":0,"spd":200,"cri":0.0,"criDmg":2.0},"element":"wind","ownerEffects":owner_effects},
		{"id":"ayla","passiveId":"","stats":{"hp":20000,"atk":100,"def":0,"spd":150,"cri":0.0,"criDmg":2.0},"element":"wind"}],rogue_effects)
	for target in b.state.enemies:
		target.maxHp = 1000000; target.currentHp = target.maxHp; target.stats.maxHp = target.maxHp
		target.element = "wind"; target.stats.def = 0; target.stats.atk = 1000; target.stats.cri = 0; target.stats.spd = 100
	return b

func hit(b, source: Dictionary, target: Dictionary, effect: Dictionary = {}, critical: bool = false, follow_up: bool = false) -> int:
	source.stats.cri = 1.0 if critical else 0.0
	return b._damage(source,target,{"type":"normal","element":"wind"},"test_hit",effect,float(effect.get("multiplier",1.0)),follow_up)

func healing_skill() -> Dictionary:
	return {"type":"skill","energyGain":20,"effects":[{"type":"heal","target":"all_allies","multiplier":1.0},{"type":"heal","target":"all_allies","multiplier":1.0}]}

func shield_skill(value: float = 0.2) -> Dictionary:
	return {"type":"skill","energyGain":0,"effects":[{"type":"status","target":"all_allies","statusId":"shield","chance":1.0,"duration":2,"value":value}]}

func test_legacy_parity() -> void:
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/battle-pre-relic-v250.json"))
	var actual := Parity.fingerprints(catalog)
	ck(actual.size() == 60 and actual.size() == expected.size(),"legacy fixtures cover ten characters, C0/C6 and three seeds")
	for key in expected: ck(actual.get(key) == expected[key],"exact original output and RNG parity " + key)

func test_thresholds_and_stat_ownership() -> void:
	var g = Game.new("")
	g.state.ownedCharacters.kaldi = g.default_character()
	for set_id in catalog.RelicSets:
		for count in range(6):
			var items := pieces(set_id,count)
			var evaluated := Sets.evaluate(catalog,items)
			ck(evaluated.activeBonuses.size() == (2 if count >= 4 else (1 if count >= 2 else 0)),"piece threshold %s/%d" % [set_id,count])
			var snapshot: Dictionary = g.relic_loadout_snapshot("kaldi",items)
			var base: Dictionary = g.computed_stats_for_relic_loadout("kaldi",[])
			var b = Battle.new(catalog)
			b.start({"enemies":["wolf"],"seed":20},[{"id":"kaldi","stats":snapshot.stats,"ownerEffects":snapshot.ownerEffects},{"id":"kaldi","stats":base}])
			for stat in ["maxHp","atk","def","spd","cri","criDmg"]:
				near(b.state.allies[0].stats[stat],snapshot.stats[stat],"static stat applies once %s/%d/%s" % [set_id,count,stat])
				near(b.state.allies[1].stats[stat],base[stat],"static stat stays on wearer %s/%d/%s" % [set_id,count,stat])
			ck(b.state.allies[1].ownerEffects.is_empty(),"active set effects stay on wearer %s/%d" % [set_id,count])
		var four := pieces(set_id,4)
		four.append(four[0].duplicate(true))
		ck(Sets.evaluate(catalog,four) == Sets.evaluate(catalog,pieces(set_id,4)),"duplicate physical relic adds no second effect "+set_id)

func test_conditional_damage() -> void:
	var b = arena(effects("flame_oath"))
	var a: Dictionary = b.state.allies[0]
	var target: Dictionary = b.state.enemies[0]
	ck(hit(b,a,target) == 100,"flame requires burning target")
	b.apply_status(target,"burn",2)
	ck(hit(b,a,target) == 120,"flame wearer damage on burning target")
	ck(hit(b,b.state.allies[1],target) == 100,"flame stays off second ally")
	ck(hit(b,a,target,{},false,true) == 120,"flame direct follow-up damage retains owner bonus")
	b = arena(effects("wind_voyager"))
	a = b.state.allies[0]; target = b.state.enemies[0]
	ck(hit(b,a,target) == 120,"wind strictly faster target bonus")
	a.stats.spd = 100
	ck(hit(b,a,target) == 100,"wind equal speed gives base damage")
	a.stats.spd = 120; b.apply_status(a,"spd_down",2,0.3)
	ck(hit(b,a,target) == 100,"wind compares effective status-modified speed")
	b.apply_status(target,"spd_down",2,0.3)
	ck(hit(b,a,target) == 120,"wind target slowdown crosses true speed condition")
	ck(hit(b,b.state.allies[1],target) == 100,"wind stays off second ally")

func test_action_energy() -> void:
	var double_hit := {"type":"skill","energyGain":15,"effects":[{"type":"damage","target":"all","multiplier":1.0},{"type":"damage","target":"all","multiplier":1.0}]}
	var b = arena(effects("thunder_hunt"),[],{"test_multi":double_hit})
	var a: Dictionary = b.state.allies[0]
	a.stats.cri = 1.0
	b._events = []; b._execute_skill(a,"test_multi")
	ck(b._events.filter(func(e):return e.type == "damage").size() == 6,"critical energy fixture has six direct critical hits")
	ck(a.energy == 19,"six critical hits grant one four-energy set trigger")
	b._execute_skill(a,"test_multi")
	ck(a.energy == 38,"next accepted action resets critical trigger")
	b.state.allies[1].stats.cri = 1.0
	b._execute_skill(b.state.allies[1],"test_multi")
	ck(b.state.allies[1].energy == 15,"critical energy stays on wearer")
	a.energy = 99; b._execute_skill(a,"test_multi")
	ck(a.energy == 100,"critical energy respects natural maximum")
	a.energy = 0; a.stats.cri = 0; b._execute_skill(a,"test_multi")
	ck(a.energy == 15,"critical energy requires actual critical hit")
	for target in b.state.enemies: b.apply_status(target,"shield",10,10.0)
	a.energy = 0; a.stats.cri = 1.0; b._execute_skill(a,"test_multi")
	ck(a.energy == 19,"absorbed critical hit still counts once per action")
	a.energy = 0; b._extra_flags = {}; b._extra_damage(a,b.state.enemies[0],1.0,"wind","test_follow_up")
	ck(a.energy == 0,"follow-up does not create recursive critical energy")

func test_active_healing() -> void:
	for count in [1,2,3,4,5]:
		var b = arena(effects("aurora_prayer",count),[],{"test_heal":healing_skill()})
		var a: Dictionary = b.state.allies[0]
		b._events = []; b._execute_skill(a,"test_heal")
		var expected := int(100 * (1.3 if count >= 4 else (1.15 if count >= 2 else 1.0)))
		var heals: Array = b._events.filter(func(e):return e.type == "heal")
		ck(heals.size() == 4 and heals.all(func(e):return e.requestedAmount == expected and e.amount == 0),"active heal full-HP requests correct threshold %d" % count)
		ck(a.energy == (25 if count >= 4 else 20),"full-HP healing grants one action energy at four pieces %d" % count)
		b._events = []; b._execute_skill(b.state.allies[1],"test_heal")
		ck(b._events.filter(func(e):return e.type == "heal").all(func(e):return e.requestedAmount == 100),"active healing enhancement stays on caster %d" % count)
	var b = arena(effects("aurora_prayer"),[{"type":"healMult","value":0.5}],{"test_heal":healing_skill()})
	var a: Dictionary = b.state.allies[0]
	b._events = []; b._execute_skill(a,"test_heal")
	ck(b._events.filter(func(e):return e.type == "heal").all(func(e):return e.requestedAmount == 195),"active healing source multiplies existing rogue healing")
	a.currentHp = 100; a.energy = 0; b._events = []; b._heal(a,a,40,"test_passive",false,"passive")
	ck(a.currentHp == 140 and a.energy == 0 and b._events[0].requestedAmount == 40,"passive healing retains supplied amount and energy path")
	b.apply_status(a,"regen",2); b._events = []; b._end_round()
	ck(b._events.any(func(e):return e.type == "heal" and e.get("skill_id","") == "regen" and e.requestedAmount == int(a.maxHp * 0.08)),"regeneration preserves original maximum-HP coefficient")
	var ult := healing_skill(); ult.type = "ultimate"
	b = arena(effects("aurora_prayer"),[],{"test_heal_ult":ult})
	a = b.state.allies[0]; a.energy = 100; b._execute_skill(a,"test_heal_ult")
	ck(a.energy == 5,"active healing ultimate spends full energy then receives one defined set trigger")

func test_skill_shields() -> void:
	var b = arena(effects("star_watch"),[],{"test_shield":shield_skill()})
	var a: Dictionary = b.state.allies[0]
	var friend: Dictionary = b.state.allies[1]
	b._execute_skill(a,"test_shield")
	ck(a.shield == 2500 and friend.shield == 5000,"wearer creates 20-percent recipient-HP skill shield with 25-percent boost")
	a.statuses = []; friend.statuses = []; b._sync_shield(a); b._sync_shield(friend)
	b._execute_skill(friend,"test_shield")
	ck(a.shield == 2000 and friend.shield == 4000,"recipient set boosts caster skills only")
	a.statuses = []; b._sync_shield(a); b.apply_status(a,"shield",2,0.2,a)
	ck(a.shield == 2000,"utility shield keeps original value even when source wears set")
	b = arena(effects("star_watch"),[{"type":"battleStartStatus","statusId":"shield","duration":2,"value":0.2}])
	ck(b.state.allies[0].shield == 2000 and b.state.allies[1].shield == 4000,"battle-start blessing shield remains independent")
	b = arena(effects("star_watch"),[{"type":"statusAfterHeal","statusId":"shield","duration":2,"value":0.2}],{"test_heal":healing_skill()})
	b._execute_skill(b.state.allies[0],"test_heal")
	ck(b.state.allies[0].shield == 4000 and b.state.allies[1].shield == 8000,"heal-trigger utility shields retain two original additions")
	var gear = Battle.new(catalog)
	gear.start({"isExtraction":true,"enemies":["wolf"],"equipmentShields":{"kaldi":500},"seed":5},[{"id":"kaldi","ownerEffects":effects("star_watch")}])
	ck(gear.state.allies[0].shield == 500 and gear.state.equipmentShieldRemaining == 500,"equipment condition capacity remains independent of skill shield bonus")
	b = arena(effects("star_watch"),[],{"test_shield":shield_skill()})
	b.state.allies[0].id = "shana"; b.state.allies[0].constellation = 6
	b._heal(b.state.allies[0],b.state.allies[1],100,"test_overflow",true,"skill")
	ck(b.state.allies[1].shield == 100,"passive overflow shield retains original conversion formula")

func test_damage_reduction() -> void:
	var b = arena(effects("stone_bastion"))
	var enemy: Dictionary = b.state.enemies[0]
	var a: Dictionary = b.state.allies[0]
	ck(hit(b,enemy,a) == 880,"stone direct incoming damage reduces twelve percent")
	ck(hit(b,enemy,b.state.allies[1]) == 1000,"stone incoming reduction stays on wearer")
	var previous := int(a.currentHp); b._status_damage(a,500,"poison")
	ck(a.currentHp == previous - 500,"stone direct reduction leaves status damage formula unchanged")
	var rogue: Array = []
	for i in 10: rogue.append({"type":"damageTakenMult","value":-0.1})
	b = arena(effects("stone_bastion"),rogue); a = b.state.allies[0]; enemy = b.state.enemies[0]
	ck(hit(b,enemy,a) == 100,"stone plus rogue total reduction has ninety-percent ceiling")
	a.passiveId = "lorin_passive"
	var observed := false
	for seed_value in 20:
		a.currentHp = a.maxHp; b.rng.seed = seed_value; b._events = []
		var damage := hit(b,enemy,a)
		if b._events.any(func(e):return e.type == "block"):
			observed = true; ck(damage == 100,"Lorin block shares final ninety-percent ceiling with set and blessings")
	ck(observed,"Lorin deterministic seeds exercise block with set")
	b.apply_status(a,"shield",2,1.0); previous = int(a.currentHp)
	ck(hit(b,enemy,a) == 0 and a.currentHp == previous,"shield completely absorbs reduced hit")

func test_future_scaling_and_prediction() -> void:
	var b = arena()
	var a: Dictionary = b.state.allies[0]
	var target: Dictionary = b.state.enemies[0]
	a.stats.atk = 200; a.stats.def = 500; a.maxHp = 1000; a.stats.maxHp = 1000
	for pair in [["atk",1.0,200],["maxHp",0.2,200],["def",0.4,200]]:
		var effect := {"type":"damage","scalingStat":pair[0],"multiplier":pair[1]}
		ck(hit(b,a,target,effect) == pair[2],"future %s actor uses declared damage source" % pair[0])
		ck(b.skill_effect_amount(a,{"type":"heal","scalingStat":pair[0],"multiplier":pair[1]},a) == pair[2],"future %s actor uses declared healing source" % pair[0])
	ck(hit(b,a,target,{"multiplier":1.0}) == 200,"undeclared damage retains legacy ATK source")
	b.apply_status(a,"def_up",2,0.2)
	ck(hit(b,a,target,{"scalingStat":"def","multiplier":0.4}) == 240,"defense scaling follows effective defense buffs")
	ck(hit(b,a,target,{"scalingStat":"maxHp","multiplier":0.2}) == 200,"HP scaling remains independent of defense buff")
	var future_shield := shield_skill()
	future_shield.effects[0].scalingStat = "def"; future_shield.effects[0].multiplier = 0.5
	b.catalog.SkillData.test_def_shield = future_shield
	a.ownerEffects = effects("star_watch"); b._execute_skill(a,"test_def_shield")
	ck(a.shield == 375 and b.state.allies[1].shield == 375,"future defense skill shields scale from caster and reach every recipient")
	a.ownerEffects = effects("flame_oath"); b.apply_status(target,"burn",3)
	for scaling in ["atk","maxHp","def"]:
		for defense in [0,100,333]:
			for critical in [false,true]:
				target.stats.def = defense
				var effect := {"type":"damage","scalingStat":scaling,"multiplier":0.73,"defPierce":0.4}
				var before := JSON.stringify(b.state); var random_before: int = b.rng.state
				var predicted: int = b.predict_effect_damage(a,target,{"type":"normal","element":"wind"},effect,critical)
				ck(JSON.stringify(b.state) == before and b.rng.state == random_before,"damage prediction stays pure")
				ck(hit(b,a,target,effect,critical) == predicted,"prediction matches actual %s defense %d critical %s" % [scaling,defense,critical])
	a.stats.cri = 0.35
	var effect := {"type":"damage","scalingStat":"def","multiplier":1.23}
	var skill := {"type":"normal","element":"wind"}
	near(b.expected_effect_damage(a,target,skill,effect),0.65 * b.predict_effect_damage(a,target,skill,effect,false) + 0.35 * b.predict_effect_damage(a,target,skill,effect,true),"expected damage weighs exact integer outcomes")
	ck(catalog.CharacterData.size() == 10,"future test actors stay out of playable catalog")
	for scaling in ["maxHp","def"]:
		var virtual_skill := {"type":"skill","energyGain":0,"effects":[{"type":"damage","target":"single","scalingStat":scaling,"multiplier":0.25},{"type":"heal","target":"self","scalingStat":scaling,"multiplier":0.1}]}
		var actual = arena([],[],{"test_virtual":virtual_skill})
		var wearer: Dictionary = actual.state.allies[0]
		wearer.id = "test_future_"+scaling; wearer.stats.def = 500; wearer.currentHp = 1
		wearer.skills = ["test_virtual"]
		var source: int = actual.effect_source_value(wearer,virtual_skill.effects[0])
		var result: Dictionary = actual.act("test_virtual")
		ck(result.success and result.events.any(func(e):return e.type == "damage" and e.amount == int(source * 0.25)),"future %s source runs through accepted action" % scaling)
		ck(result.events.any(func(e):return e.type == "heal" and e.requestedAmount == int(source * 0.1)),"future %s healing runs through accepted action" % scaling)
	var before: int = b.rng.state
	ck(b.predict_effect_damage(a,target,skill,effect,true,true) == b.predict_effect_damage(a,target,skill,effect,false,true),"follow-up predictor follows real noncritical branch")
	ck(b.rng.state == before,"follow-up prediction retains RNG state")

func test_input_isolation_and_manual_auto() -> void:
	var input := {"id":"kaldi","stats":{"hp":10000,"atk":100,"def":50,"spd":200,"cri":1.5,"criDmg":2.0},"ownerEffects":effects("thunder_hunt"),"skills":["kaldi_normal"]}
	var b = Battle.new(catalog)
	b.start({"enemies":["boss_flame_lord"],"seed":250},[input])
	input.ownerEffects[0].value = 99; input.stats.atk = 9999
	ck(b.state.allies[0].ownerEffects[0].value == 4 and b.state.allies[0].stats.atk == 100,"battle owns deep copy of active effects and computed stats")
	ck(b.state.allies[0].stats.cri == 1.0,"critical probability stays naturally bounded")
	var first = arena(effects("thunder_hunt")); var second = arena(effects("thunder_hunt"))
	for instance in [first,second]:
		instance.state.allies[0].skills = ["kaldi_normal"]
		instance.state.allies[0].stats.cri = 1.0
	var original: Dictionary = first.state.allies[0].stats.duplicate(true)
	var manual: Dictionary = first.act("kaldi_normal")
	var automatic: Dictionary = second.auto_step()
	ck(manual.events == automatic.events,"manual and auto invoke identical set battle pipeline")
	ck(first.state.allies[0].stats == original and second.state.allies[0].stats == original,"manual and auto leave permanent stats unchanged")
