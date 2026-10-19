extends SceneTree
const Battle = preload("res://scripts/battle_model.gd")
var catalog: Dictionary
var failures: Array = []
var checks = 0
var skills_executed = 0
var enemy_skills_executed = 0
var rewards_exercised = 0

func _init() -> void:
	catalog = JSON.parse_string(FileAccess.get_file_as_string("res://data/catalog.json"))
	test_all_player_skills()
	test_all_enemy_skills()
	test_turns_and_validation()
	test_statuses()
	test_passives_and_constellations()
	test_rogue_effects()
	test_battles_and_safety()
	print("BATTLE TESTS: %d checks; %d player skills; %d enemy skills; %d rogue rewards exercised; %d failures" % [checks, skills_executed, enemy_skills_executed, rewards_exercised, failures.size()])
	for failure in failures: printerr("FAIL: ", failure)
	quit(0 if failures.is_empty() else 1)

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)

func near(actual: float, expected: float, label: String, tolerance: float = 0.0001) -> void:
	check(absf(actual - expected) <= tolerance, "%s: actual %s expected %s" % [label, actual, expected])

func ally(id: String, c: int = 0, speed: float = 1000.0) -> Dictionary:
	var data = catalog.CharacterData[id]
	var stats = data.baseStats.duplicate(true)
	stats.maxHp = stats.hp
	stats.spd = speed
	stats.cri = 0.0
	return {"id": id, "stats": stats, "constellation": c}

func arena(id: String = "kaldi", c: int = 0, effects: Array = []) -> Variant:
	var b = Battle.new(catalog)
	var hero = ally(id, c)
	hero.energy = 100
	b.start({"enemies": ["wolf", "goblin", "fire_imp"], "seed": 51, "isAbyss": not effects.is_empty(), "floor": 1}, [hero, ally("tide", 0, 150), ally("ayla", 0, 140)], effects)
	for enemy in b.state.enemies:
		enemy.maxHp = 1000000
		enemy.currentHp = enemy.maxHp
		enemy.stats.maxHp = enemy.maxHp
		enemy.stats.spd = 10
		enemy.stats.cri = 0.0
	return b

func event_count(events: Array, type: String, sid: String = "") -> int:
	var count = 0
	for event in events:
		if event.type == type and (sid.is_empty() or event.get("skill_id", "") == sid): count += 1
	return count

func test_all_player_skills() -> void:
	check(catalog.SkillData.size() == 30, "catalog has 30 player skills")
	for id in catalog.CharacterData:
		for sid in catalog.CharacterData[id].skills:
			var b = arena(id)
			for unit in b.state.allies: unit.currentHp = int(unit.maxHp * 0.3)
			check(b.current_actor().id == id, sid + " actor")
			check(b.available_actions().has(sid), sid + " available")
			var result = b.act(sid)
			check(result.success, sid + " executed")
			check(event_count(result.events, "skill", sid) == 1, sid + " skill event")
			var skill = catalog.SkillData[sid]
			for effect in skill.effects:
				if effect.type == "damage": check(event_count(result.events, "damage", sid) > 0, sid + " damage effect")
				elif effect.type == "heal": check(event_count(result.events, "heal", sid) > 0, sid + " healing effect")
				elif effect.type == "status" and float(effect.get("chance", 1)) == 1:
					var found = result.events.any(func(e): return e.type == "status" and e.get("statusId", "") == effect.statusId)
					check(found, sid + " guaranteed " + effect.statusId)
			if skill.type == "ultimate": check(b.state.allies[0].energy == 0, sid + " energy consumed")
			else: check(b.state.allies[0].energy <= 100, sid + " energy capped")
			check(b.state.allies[0].cooldowns.get(sid, 0) == int(skill.get("cooldown", 0)), sid + " cooldown set")
			skills_executed += 1

func test_all_enemy_skills() -> void:
	check(catalog.EnemySkillData.size() == 23, "catalog has 23 enemy skills")
	for sid in catalog.EnemySkillData:
		var b = arena()
		var enemy = b.state.enemies[0]
		enemy.skills = [sid]
		enemy.aiPattern = "random"
		enemy.cooldowns = {}
		b.state.currentActor = enemy.uid
		b.state.phase = "enemy_turn"
		var result = b.auto_step()
		check(result.success, sid + " enemy executed")
		check(event_count(result.events, "skill", sid) == 1, sid + " enemy skill event")
		for effect in catalog.EnemySkillData[sid].effects:
			if effect.type == "damage": check(event_count(result.events, "damage", sid) > 0, sid + " enemy damage")
			elif effect.type == "status" and float(effect.get("chance", 1)) == 1:
				check(result.events.any(func(e): return e.type == "status" and e.get("statusId", "") == effect.statusId), sid + " enemy status")
		if sid == "wolf_howl":
			check(b.has_status(enemy, "atk_up"), "wolf howl buffs own team")
			check(not b.has_status(b.state.allies[0], "atk_up"), "wolf howl does not buff player")
		enemy_skills_executed += 1

func test_turns_and_validation() -> void:
	var b = arena()
	var before = JSON.stringify(b.state)
	check(not b.act("ayla_ult").success, "cannot execute another character's skill")
	check(not b.act("kaldi_normal", "missing_uid").success, "invalid target rejected")
	check(JSON.stringify(b.state) == before, "invalid action atomic")
	var target = b.state.enemies[2]
	var first_hp = b.state.enemies[0].currentHp
	var selected_hp = target.currentHp
	check(b.act("kaldi_normal", target.uid).success, "manual targeting accepted")
	check(target.currentHp < selected_hp and b.state.enemies[0].currentHp == first_hp, "manual target receives damage")
	b = arena("ayla")
	var target_id = b.state.enemies[2].uid
	var result = b.act("ayla_skill", target_id)
	var damage = result.events.filter(func(e): return e.type == "damage" and e.get("skill_id", "") == "ayla_skill")
	var freeze = result.events.filter(func(e): return e.type == "status" and e.get("statusId", "") == "freeze")
	check(damage[0].target == target_id and freeze[0].target == target_id, "damage and control remain on selected target")
	b = arena("shana")
	var friend = b.state.allies[1]
	friend.currentHp = 1
	result = b.act("shana_skill", friend.uid)
	check(b.has_status(friend, "regen"), "heal/regen stay on same ally")
	b = Battle.new(catalog)
	b.start({"enemies": ["thunder_hawk"], "seed": 1}, [ally("tide", 0, 1)])
	check(b.state.phase == "enemy_turn" and not b.current_actor().isAlly, "enemy-first start")
	check(not b.act("tide_normal").success, "player cannot act on enemy turn")
	b = arena("kaldi", 2)
	b.act("kaldi_skill")
	check(b.state.allies[0].cooldowns.kaldi_skill == 2, "C2 cooldown reduction")
	b.state.currentActor = b.state.allies[0].uid
	b.state.phase = "player_turn"
	check(not b.available_actions().has("kaldi_skill"), "cooldown unavailable")
	b._end_round()
	b._end_round()
	check(b.available_actions().has("kaldi_skill"), "cooldown round recovery")
	b.state.allies[0].energy = 99
	check(not b.available_actions().has("kaldi_ult"), "ultimate energy requirement")
	b.state.allies[0].stats.energyRate = 0.5
	b.state.allies[0].energy = 0
	b.act("kaldi_normal")
	check(b.state.allies[0].energy == 22, "relic energy rate active")
	b = arena("gus")
	for e in b.state.enemies: e.element = "water"; e.stats.def = 0
	result = b.act("gus_skill")
	var hits = result.events.filter(func(e): return e.type == "damage" and e.get("skill_id", "") == "gus_skill")
	check(hits.size() == 3 and hits[0].amount > hits[1].amount and hits[1].amount > hits[2].amount, "chain three and decay")
	near(b.element_mult("fire", "wind"), 1.5, "strong element")
	near(b.element_mult("fire", "water"), 0.75, "weak element")
	near(b.element_mult("fire", "fire"), 1.0, "neutral element")
	b = arena("bolt")
	b.state.enemies[0].stats.def = 1000
	var without = b._damage(b.state.allies[0], b.state.enemies[0], {"type":"test"}, "test", {}, 1.0)
	var with_pierce = b._damage(b.state.allies[0], b.state.enemies[0], {"type":"test"}, "test", {"defPierce":0.4}, 1.0)
	check(with_pierce > without, "defense pierce formula")
	b = arena("lorin")
	var tank = b.state.allies[0]
	b.apply_status(tank,"taunt",2)
	var enemy = b.state.enemies[0]
	b._events = []
	b._execute_skill(enemy,"wolf_bite")
	check(b._events.filter(func(e): return e.type == "damage")[0].target == tank.uid, "taunt redirects single attacks")
	b._events = []
	b._execute_skill(enemy,"boss_fireball")
	check(event_count(b._events,"damage") == 3, "AOE remains AOE despite taunt")

	b = arena()
	enemy = b.state.enemies[0]
	enemy.skills = ["wolf_howl","wolf_bite"]
	enemy.aiPattern = "aggressive"
	check(b._enemy_choice(enemy,b._available(enemy)) == "wolf_bite","aggressive AI prioritizes damage")
	enemy.skills = ["golem_slam","golem_guard"]
	enemy.aiPattern = "defensive"
	enemy.currentHp = int(enemy.maxHp * 0.2)
	check(b._enemy_choice(enemy,b._available(enemy)) == "golem_guard","defensive AI prioritizes protection at low health")
	enemy.cooldowns.golem_guard = 2
	check(not b._available(enemy).has("golem_guard"),"enemy cooldown enforced")

func test_statuses() -> void:
	var b = arena()
	var unit = b.state.enemies[0]
	for sid in Battle.STATUS_IDS:
		unit.statuses = []
		check(b.apply_status(unit, sid, 2), sid + " apply")
		check(b.has_status(unit,sid), sid + " present")
		b.apply_status(unit,sid,1)
		if sid == "poison": check(unit.statuses.size() == 2,"poison independently stacks")
		else: check(unit.statuses[0].duration == 3, sid + " duration adds")
	check(not b.apply_status(unit,"unknown",2),"unknown status rejected")
	unit.statuses = []
	unit.currentHp = unit.maxHp
	b.apply_status(unit,"burn",1)
	var before = unit.currentHp
	b._end_round()
	check(unit.currentHp == before - int(unit.baseAtk * 0.18),"burn damage exact")
	check(not b.has_status(unit,"burn"),"burn expires")
	b.apply_status(unit,"poison",1)
	b.apply_status(unit,"poison",1)
	before = unit.currentHp
	b._end_round()
	check(unit.currentHp == before - int(unit.maxHp * 0.05) * 2,"poison stacked damage")
	unit.currentHp = int(unit.maxHp * 0.5)
	b.apply_status(unit,"regen",1)
	before = unit.currentHp
	b._end_round()
	check(unit.currentHp == before + int(unit.maxHp * 0.08),"regen exact and expired")
	unit.statuses = []
	b.apply_status(unit,"atk_up",2,0.2)
	b.apply_status(unit,"def_up",2,0.4)
	b.apply_status(unit,"stun",1)
	b.apply_status(unit,"spd_down",2,0.3)
	var mods = b.modifiers(unit)
	near(mods.atkMult,1.2,"atk buff")
	near(mods.defMult,0.98,"def buff and stun multiply")
	near(mods.spdMult,0.7,"speed down")
	unit.statuses = []
	b.apply_status(unit,"shield",2,0.3)
	b.apply_status(unit,"shield",2,0.2)
	check(unit.shield == int(unit.maxHp * 0.5),"shield amounts add")
	before = unit.currentHp
	var dealt = b._damage(b.state.allies[0], unit, {"type":"test"},"test",{},1.0)
	check(dealt == 0 and unit.currentHp == before,"shield fully absorbs damage")
	unit.statuses = []
	b.apply_status(unit,"invincible",2)
	b.apply_status(unit,"burn",1)
	b.apply_status(unit,"poison",1)
	before = unit.currentHp
	dealt = b._damage(b.state.allies[0],unit,{"type":"test"},"test",{},1)
	b._end_round()
	check(dealt == 0 and unit.currentHp == before,"invincible blocks direct and DOT")
	for sid in Battle.CONTROL_STATUSES:
		b = arena()
		var actor = b.current_actor()
		b.apply_status(actor,sid,1)
		b._events = []
		b._seek_actor()
		check(b.current_actor().uid != actor.uid, sid + " first actor is skipped")
		check(not b.has_status(actor,sid), sid + " consumed by skipped action")
		check(event_count(b._events,"skip") == 1, sid + " skip event")
	b = arena()
	unit = b.state.enemies[0]
	unit.currentHp = 1
	b.apply_status(unit,"poison",1)
	b._end_round()
	b._report_deaths()
	check(unit.currentHp == 0 and event_count(b._events,"death") == 1,"DOT death event once")

func test_passives_and_constellations() -> void:
	var b = arena("kaldi")
	var a = b.state.allies[0]
	var t = b.state.enemies[0]
	b.apply_status(t,"burn",5)
	near(b._damage_multiplier(a,t,"normal"),1.2,"Kaldi burn deepen passive")
	b = arena("ayla")
	b.state.allies[1].currentHp = 1
	b._end_round()
	check(b.state.allies[1].currentHp > 1,"Ayla lowest-health heal passive")
	b = arena("gus")
	a = b.state.allies[0]
	a.energy = 0
	a.stats.cri = 1.0
	b.act("gus_normal")
	check(a.energy == 20,"Gus crit gives five energy")
	b = arena("shana")
	a = b.state.allies[0]
	a.currentHp = 500
	b.state.allies[1].currentHp = 1
	b.act("shana_skill",b.state.allies[1].uid)
	check(a.currentHp == 529,"Shana self-heal passive 15 percent")
	b = arena("lorin")
	a = b.state.allies[0]
	var blocked = false
	for i in range(50):
		a.currentHp = a.maxHp
		b._events = []
		b._damage(b.state.enemies[0],a,{"type":"test"},"test",{},1)
		blocked = blocked or event_count(b._events,"block") > 0
	check(blocked,"Lorin probabilistic block passive")
	b = arena("ember")
	var burns = 0
	for i in range(100):
		b.state.enemies[0].statuses = []
		b._execute_skill(b.state.allies[0],"ember_normal")
		if b.has_status(b.state.enemies[0],"burn"): burns += 1
	check(burns > 10 and burns < 40,"Ember 25 percent burn passive observed")
	b = arena("zeph")
	check(b._effective_atk(b.state.allies[0]) == int(120 * 1.15),"Zeph speed attack passive")
	b.state.allies[0].stats.spd = 1
	check(b._effective_atk(b.state.allies[0]) == 120,"Zeph passive only above average")
	b = arena("bolt")
	b.state.allies[0].stats.cri = 1
	b.act("bolt_normal")
	check(b.has_status(b.state.enemies[0],"electrify"),"Bolt crit electrify passive")
	b = arena("tide")
	a = b.state.allies[0]
	a.currentHp = 500
	# Remove Ayla support from this exact-heal assertion.
	b.state.allies[2].passiveId = ""
	b._end_round()
	check(a.currentHp == 533,"Tide 3 percent regen passive")
	b = arena("cinder")
	b.apply_status(b.state.enemies[0],"burn",5)
	near(b._damage_multiplier(b.state.allies[0],b.state.enemies[0],"skill"),1.4,"Cinder burn skill passive")
	b = arena("kaldi",6)
	b.apply_status(b.state.enemies[0],"burn",5)
	var result = b.act("kaldi_ult")
	check(event_count(result.events,"damage","kaldi_ult_c6") == 1,"Kaldi C6 extra damage")
	b = arena("ayla",6)
	b.act("ayla_ult")
	check(b.state.allies[1].statuses.filter(func(s): return s.id == "regen")[0].duration == 4,"Ayla C6 team regen stacks")
	b = arena("gus",6)
	a = b.state.allies[0]
	a.stats.cri = 1
	var chains = 0
	for i in range(80):
		b._events = []
		b._execute_skill(a,"gus_normal")
		chains += event_count(b._events,"damage","gus_c6")
	check(chains > 15 and chains < 55,"Gus C6 additional nonrecursive attacks")
	b = arena("shana",6)
	b.act("shana_skill",b.state.allies[1].uid)
	check(b.state.allies[1].shield == 195,"Shana C6 overheal becomes shield")
	b = arena("lorin",6)
	a = b.state.allies[0]
	t = b.state.enemies[0]
	t.stats.atk = 10000
	b.apply_status(a,"shield",2,0.5)
	var before = a.currentHp
	b._damage(t,a,{"type":"enemy"},"test",{},2.0)
	check(a.currentHp == before and a.c6Used and b.has_status(a,"invincible"),"Lorin C6 nullifies trigger hit")
	a.statuses = []
	b.apply_status(a,"shield",2,0.5)
	b._damage(t,a,{"type":"enemy"},"test",{},2.0)
	check(a.currentHp < before,"Lorin C6 limited once per battle")
	b = arena("ember",6)
	var empowered_burns = 0
	for i in range(100):
		b.state.enemies[0].statuses = []
		b.state.allies[0].energy = 0
		b._execute_skill(b.state.allies[0],"ember_normal")
		if b.has_status(b.state.enemies[0],"burn"):
			empowered_burns += 1
			check(b.state.allies[0].energy == 25,"Ember C6 proc grants 10 energy")
	check(empowered_burns > burns and empowered_burns > 40 and empowered_burns < 80,"Ember C6 60 percent burn")
	b = arena("zeph",6)
	check(b.has_status(b.state.allies[2],"atk_up"),"Zeph C6 buffs slowest teammate")
	b = arena("bolt",6)
	b.apply_status(b.state.enemies[0],"electrify",2)
	near(b._damage_multiplier(b.state.allies[0],b.state.enemies[0],"normal"),1.15 * 1.35,"Bolt C6 electrify damage")
	b = arena("tide",6)
	a = b.state.allies[0]
	a.currentHp = 500
	b.state.allies[2].passiveId = ""
	b._end_round()
	check(a.currentHp == 566,"Tide C6 doubles regen")
	b = arena("cinder",6)
	b.apply_status(b.state.enemies[0],"burn",5)
	near(b._damage_multiplier(b.state.allies[0],b.state.enemies[0],"skill"),1.2 * 1.7,"Cinder C6 burn damage")
	b = arena("kaldi",5)
	near(b._damage_multiplier(b.state.allies[0],b.state.enemies[0],"normal"),1.15,"generic C1")
	near(b._damage_multiplier(b.state.allies[0],b.state.enemies[0],"skill"),1.20,"generic C3")
	near(b._damage_multiplier(b.state.allies[0],b.state.enemies[0],"ultimate"),1.30,"generic C5")

func test_rogue_effects() -> void:
	for reward in catalog.AbyssData.rogue.rewards:
		var b = arena("kaldi",0,reward.effects)
		var a = b.state.allies[0]
		var t = b.state.enemies[0]
		for effect in reward.effects:
			match effect.type:
				"stat":
					match effect.stat:
						"atkMult": check(a.stats.atk == int(185 * (1 + effect.value)),reward.id + " atk")
						"maxHpMult": check(a.maxHp == int(1200 * (1 + effect.value)),reward.id + " maxHp")
						"defMult": check(a.stats.def == int(75 * (1 + effect.value)),reward.id + " def")
						"spdMult": check(a.stats.spd == int(1000 * (1 + effect.value)),reward.id + " speed")
						"criAdd": near(a.stats.cri,effect.value,reward.id + " crit")
						"criDmgAdd": near(a.stats.criDmg,1.65 + effect.value,reward.id + " crit dmg")
				"energyGainMult":
					a.energy = 0
					b._execute_skill(a,"kaldi_normal")
					check(a.energy == 17,reward.id + " energy multiplier")
				"battleStartStatus": check(a.shield == int(a.maxHp * effect.value),reward.id + " opening shield")
				"battleStartEnergy": check(a.energy == 100,reward.id + " opening energy cap")
				"damageTakenMult": near(b._damage_multiplier(t,a,"enemy"),0.9,reward.id + " damage taken")
				"damageTakenWhileStatus":
					b.apply_status(a,effect.statusId,3)
					near(b._damage_multiplier(t,a,"enemy"),0.85,reward.id + " regen guard")
				"damageVsStatus":
					b.apply_status(t,effect.statusId,3)
					var passive = 1.2 if effect.statusId == "burn" else 1.0
					near(b._damage_multiplier(a,t,"normal"),passive * (1+effect.value),reward.id + " status bonus")
				"applyStatusAfterDamage":
					var applied = false
					for i in range(40):
						t.statuses = []
						b._execute_skill(a,"kaldi_normal")
						applied = applied or b.has_status(t,effect.statusId)
					check(applied,reward.id + " status proc")
				"skillTypeDamage": near(b._damage_multiplier(a,t,"ultimate"),1.18,reward.id + " ult bonus")
				"skillTypeDamageVsStatus":
					b.apply_status(t,"burn",3)
					near(b._damage_multiplier(a,t,"ultimate"),1.18 * 1.12 * 1.2,reward.id + " ult burned bonus")
				"extraDamageVsStatus":
					b.apply_status(t,"burn",3)
					b._events = []
					b._execute_skill(a,"kaldi_normal")
					var hits = b._events.filter(func(e): return e.type == "damage" and e.get("skill_id","") == "kaldi_normal_rogue")
					check(hits.size() == 1 and hits[0].amount == 37,reward.id + " true extra damage")
				"enemyBattleStartStatus":
					var count = b.state.enemies.filter(func(e): return b.has_status(e,effect.statusId)).size()
					check(count == effect.get("count",3),reward.id + " opening enemy status count")
				"healMult":
					a.skills.append("ayla_ult")
					a.energy = 100
					b.state.allies[1].currentHp = 1
					b._events = []
					b._execute_skill(a,"ayla_ult")
					var heals = b._events.filter(func(e): return e.type == "heal" and e.get("skill_id","") == "ayla_ult")
					check(heals[0].requestedAmount == int(185 * 1.8 * 1.16),reward.id + " healing multiplier")
				"statusAfterHeal":
					b._heal(a,a,10,"test",true,"skill")
					check(b.has_status(a,"regen"),reward.id + " heal grants regen")
				"energyOnHitStatus":
					a.energy = 0
					var frozen = b.state.enemies.filter(func(e): return b.has_status(e,"freeze"))[0]
					b._execute_skill(a,"kaldi_normal",frozen.uid)
					check(a.energy == 30,reward.id + " hit frozen energy")
				"victoryHealPct": check(effect.value == 0.18,reward.id + " settlement owned by GameModel")
		rewards_exercised += 1
	var b = Battle.new(catalog)
	var hero = ally("kaldi")
	hero.currentHp = 600
	hero.maxHp = 1200
	b.start({"enemies":["wolf"],"isAbyss":true,"floor":1},[hero],[{"type":"stat","stat":"maxHpMult","value":0.1}])
	check(b.state.allies[0].maxHp == 1320 and b.state.allies[0].currentHp == 660,"abyss preserves carried HP ratio")
	hero.currentHp = 1320
	hero._abyssSavedMaxHp = 1320
	b.start({"enemies":["wolf"],"isAbyss":true,"floor":2},[hero],[{"type":"stat","stat":"maxHpMult","value":0.1}])
	check(b.state.allies[0].maxHp == 1320 and b.state.allies[0].currentHp == 1320,"inflated carried max HP remains full across floors")
	hero.stats.spd = 1000.75
	b.start({"enemies":["wolf"]},[hero])
	near(b.state.allies[0].stats.spd,1000.75,"fractional relic speed preserved")
	hero.currentHp = 0
	b.start({"enemies":["wolf"],"isAbyss":true,"floor":1},[hero,ally("ayla")],[{"type":"stat","stat":"maxHpMult","value":0.1}])
	check(b.state.allies[0].currentHp == 0,"abyss does not revive dead units")
	b.start({"enemies":["wolf"]},[ally("kaldi")],[{"type":"stat","stat":"atkMult","value":100},{"type":"battleStartEnergy","value":100}])
	check(b.state.allies[0].stats.atk == 185 and b.state.allies[0].energy == 0,"rogue effects cannot leak into story")
	b = arena("kaldi",0,[{"type":"damageTakenMult","value":-10},{"type":"damageTakenWhileStatus","statusId":"regen","value":-10}])
	b.apply_status(b.state.allies[0],"regen",2)
	near(b._damage_multiplier(b.state.enemies[0],b.state.allies[0],"enemy"),0.1,"stacked incoming rogue reduction has 10 percent floor")
	b = arena("kaldi",0,[{"type":"extraDamageVsStatus","statusId":"burn","multiplier":0.2,"trueDamage":true}])
	b.catalog = catalog.duplicate(true)
	b.catalog.SkillData.test_double = {"name":"test","type":"normal","effects":[{"type":"damage","target":"single","multiplier":0.1},{"type":"damage","target":"single","multiplier":0.1}]}
	b.apply_status(b.state.enemies[0],"burn",4)
	b._events = []
	b._extra_flags = {}
	b._execute_skill(b.state.allies[0],"test_double")
	check(event_count(b._events,"damage","test_double") == 2 and event_count(b._events,"damage","test_double_rogue") == 1,"rogue extra damage once per skill and target")
	var scale = b.abyss_scale(51,"wolf")
	check(scale.hpMod > b.abyss_scale(1,"wolf").hpMod and scale.atkMod < scale.hpMod,"abyss v2 HP grows faster than attack")

func test_battles_and_safety() -> void:
	var party = [ally("kaldi",6),ally("ayla",6,900),ally("gus",6,800)]
	for unit in party:
		unit.stats.atk *= 6
		unit.stats.hp *= 6
		unit.stats.maxHp = unit.stats.hp
	for chapter in catalog.StageData.chapters:
		for stage in chapter.stages:
			var b = Battle.new(catalog)
			var config = stage.duplicate(true)
			config.seed = 700
			b.start(config,party)
			var n = 0
			while b.state.phase not in ["victory","defeat"] and n < 1000:
				b.auto_step()
				n += 1
			check(b.state.phase == "victory",stage.id + " entire battle victory")
			check(event_count(b.state.events,"win") == 1,stage.id + " win event")
	var b = Battle.new(catalog)
	b.start({"waves":[{"enemies":["wolf"]},{"enemies":["goblin"]},{"enemies":["boss_flame_lord"]}],"seed":12},party)
	var n = 0
	while b.state.phase not in ["victory","defeat"] and n < 1000:
		b.auto_step()
		n += 1
	check(b.state.phase == "victory" and b.state.wave == 3,"three-wave progression")
	b = Battle.new(catalog)
	b.start({"enemies":["boss_flame_lord"],"seed":2},[ally("tide",0,1)])
	var boss = b.state.enemies[0]
	boss.currentHp = int(boss.maxHp * 0.3)
	b._seek_actor()
	check(boss.inPhase2 and event_count(b._events,"phase_change") == 1,"boss phase two")
	for i in range(20):
		check(boss.phase2Skills.has(b._enemy_choice(boss,b._available(boss))),"boss phase2 AI skill pool")
	var hashes: Array = []
	for run in range(2):
		b = Battle.new(catalog)
		b.start({"enemies":["boss_storm_witch"],"seed":9381},party)
		var trace: Array = []
		n = 0
		while b.state.phase not in ["victory","defeat"] and n < 1000:
			trace.append(b.auto_step().events)
			n += 1
		hashes.append(JSON.stringify(trace).sha256_text())
	check(hashes[0] == hashes[1],"seeded simulation fully deterministic")
	b = Battle.new(catalog)
	var immortal = ally("tide")
	immortal.stats.maxHp = 1000000000
	immortal.stats.hp = immortal.stats.maxHp
	immortal.stats.atk = 1
	b.start({"enemies":["stone_golem"],"maxSteps":1000,"seed":1},[immortal])
	b.state.enemies[0].maxHp = 1000000000
	b.state.enemies[0].currentHp = 1000000000
	b.state.enemies[0].stats.atk = 1
	n = 0
	while b.state.phase not in ["victory","defeat"] and n < 1100:
		b.auto_step()
		n += 1
	check(b.state.phase == "defeat" and b.state.steps == 1000,"long battle step cap terminates")
	check(b.state.reason.contains("上限"),"step cap reports reason")
	check(b.state.log.size() <= 300,"battle event log bounded")
	check(b.auto_step().finished,"terminal auto_step safe")
	b = Battle.new(catalog)
	b.start({"enemies":["boss_flame_lord"],"scaleMult":1000},[ally("ember",0,1)])
	n = 0
	while b.state.phase not in ["victory","defeat"] and n < 100:
		b.auto_step()
		n += 1
	check(b.state.phase == "defeat", "loss state works")
	b = Battle.new(catalog)
	check(not b.auto_step().success,"unstarted step rejected")
