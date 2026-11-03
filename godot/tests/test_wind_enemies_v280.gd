extends SceneTree
const Game = preload("res://scripts/game_model.gd")
const Battle = preload("res://scripts/battle_model.gd")
var checks := 0
var failures := 0
var game
func ck(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
func _initialize() -> void: call_deferred("run_tests")
func battle(ids: Array, config: Dictionary = {}):
	var settings: Dictionary = config.duplicate(true)
	settings.enemies = ids; settings.waves = [{"enemies":ids}]; settings.seed = int(config.get("seed",280))
	var party: Array = []
	for index in range(3):
		party.append({"id":"fixture_%d"%index,"element":"neutral","skills":[],"stats":{"maxHp":1000000000,"atk":1,"def":int(config.get("fixtureDef",100)),"spd":1000,"cri":0.0,"criDmg":1.5}})
	var b = Battle.new(game.catalog); b.start(settings,party)
	return b
func force_enemy_action(b, unit: Dictionary) -> Dictionary:
	b._cursor = b._queue.find(unit)
	b._seek_actor()
	return b.auto_step()
func sample_budget(ids: Array, config: Dictionary, phase2: bool, samples: int = 32) -> Dictionary:
	var result := {"damage":0.0,"singlePeak":0.0,"teamPeak":0.0,"shieldPeak":0.0,"attackActions":0.0,"hpDamage":0.0,"shieldAbsorbed":0.0}
	for seed_value in range(samples):
		var settings: Dictionary = config.duplicate(true); settings.seed = seed_value+280
		var b = battle(ids,settings)
		for player in b.state.allies:
			var amount := int(config.get("fixtureShield",0))
			if amount > 0:
				player.statuses.append({"id":"shield","duration":100,"shieldHp":amount,"persistent":true})
				b._sync_shield(player)
		var order: Array = b.state.enemies.duplicate()
		order.sort_custom(func(a,c):return float(a.stats.spd)>float(c.stats.spd))
		for u in order:
			if u.isBoss:u.inPhase2 = phase2
		for round_number in range(6):
			for u in order:
				var sid: String = b._enemy_choice(u,b._available(u))
				var skill: Dictionary = b.skill_data(sid,false)
				var team := 0.0; var single := 0.0
				for effect in skill.get("effects",[]):
					if effect.type != "damage": continue
					var one: float = b.expected_effect_damage(u,b.state.allies[0],skill,effect)
					var targets := 3 if effect.get("target","single") in ["all","all_enemies","chain3"] else 1
					team += one*targets; single += one
				result.damage += team/float(samples)
				result.singlePeak = maxf(result.singlePeak,single)
				result.teamPeak = maxf(result.teamPeak,team)
				if team>0.0:result.attackActions += 1.0/float(samples)
				b._execute_skill(u,sid)
				b._record_enemy_pacing(u,sid)
				b._record_enemy_cycle_action(u,sid)
				var total_shield := 0
				for friend in order: total_shield += int(friend.shield)
				result.shieldPeak = maxf(result.shieldPeak,total_shield)
			b._end_round()
		for player in b.state.allies:
			result.hpDamage += float(player.maxHp-player.currentHp)/float(samples)
			result.shieldAbsorbed += float(int(config.get("fixtureShield",0))-int(player.shield))/float(samples)
	return result
func extraction_config(theme: String, kind: String) -> Dictionary:
	var g = Game.new("");g.rng.seed=280;g.extraction.start_run()
	var ex=g.extraction
	ex.run().environmentOrder=["ruins","forest",theme] if theme!="ruins" else ["forest","sanctum","ruins"]
	ex.run().act=3;ex.run().difficulty=5;ex.run().node=4;ex._generate_map();ex._generate_encounter(kind)
	return ex.run().activeEncounter.duplicate(true)
func run_tests() -> void:
	game=Game.new("")
	var override_ids: Array = ["boss_highland_roc","windfield_updraft","windfield_crosswind"]
	var original = battle(override_ids,{"isExtraction":true,"scaleMult":{"hpMod":2.0,"atkMod":3.0,"defMod":1.0,"spdMod":1.0}})
	var overridden = battle(override_ids,{"isExtraction":true,"scaleMult":{"hpMod":2.0,"atkMod":3.0,"defMod":1.0,"spdMod":1.0},"enemyAttackOverrides":{"windfield_updraft":37}})
	ck(overridden.state.enemies[1].stats.atk==37,"attachment final attack override is exact after scaling")
	ck(overridden.state.enemies[0].stats==original.state.enemies[0].stats and overridden.state.enemies[2].stats==original.state.enemies[2].stats,"override leaves boss and unrelated target stats intact")
	var rejected = battle(override_ids,{"isExtraction":true,"scaleMult":{"hpMod":2.0,"atkMod":3.0,"defMod":1.0,"spdMod":1.0},"enemyAttackOverrides":{"windfield_updraft":-1}})
	ck(rejected.state.enemies[1].stats==original.state.enemies[1].stats,"invalid attack override retains original scaling")
	for mode in [{},{"isAbyss":true,"floor":10},{"isExtraction":true}]:
		var b=battle(["boss_highland_roc","windfield_updraft","windfield_crosswind"],mode)
		var boss:Dictionary=b.state.enemies[0]
		var cycle:Array=game.catalog.EnemyData.boss_highland_roc.actionCycle
		for action in range(6):
			var rng_before:int=b.rng.state
			var next:String=b._enemy_choice(boss,b._available(boss))
			ck(next==cycle[action%cycle.size()] and b._enemy_choice(boss,b._available(boss))==next and b.rng.state==rng_before,"cycle preview is stable "+str([mode,action]))
			var outcome:Dictionary=force_enemy_action(b,boss)
			ck(outcome.success and outcome.events.any(func(e):return e.get("type","")=="skill" and e.get("skill_id","")==next),"actual action matches telegraphed cycle "+str([mode,action]))
			ck(int(boss.actionCycleCursor)==(action+1)%cycle.size(),"cursor advances after execution")
		# Phase change after a warning preserves the promise; after another action it warns afresh.
		boss.actionCycleCursor=0;boss.actionCycleLastSkill="";boss.actionCyclePhase2=false;boss.inPhase2=false
		force_enemy_action(b,boss);boss.inPhase2=true
		ck(b._enemy_choice(boss,b._available(boss))=="roc_storm","phase after warning retains announced area action")
		boss.actionCycleLastSkill="roc_gale";boss.actionCyclePhase2=false;boss.actionCycleCursor=2
		ck(b._enemy_choice(boss,b._available(boss))=="roc_warning_high","phase after area warns before another area")
	var controlled=battle(["boss_highland_roc"],{"isAbyss":true,"floor":10})
	var cu:Dictionary=controlled.state.enemies[0]
	force_enemy_action(controlled,cu)
	var hp:int=cu.currentHp;var uid:String=cu.uid;var cursor:int=cu.actionCycleCursor
	controlled.apply_status(cu,"freeze",1,null,controlled.state.allies[0])
	controlled._cursor=controlled._queue.find(cu);controlled._seek_actor()
	ck(cu.currentHp==hp and cu.uid==uid and int(cu.actionCycleCursor)==cursor,"control skip preserves health identity and pending cycle")
	var fields=battle(["boss_highland_roc","windfield_updraft","windfield_crosswind"])
	var boss:Dictionary=fields.state.enemies[0];var up:Dictionary=fields.state.enemies[1];var cross:Dictionary=fields.state.enemies[2]
	ck(fields._targets("boss_ally",up,"",{}).size()==1 and fields._targets("boss_ally",up,"",{})[0].uid==boss.uid,"field targets the living boss")
	for repeat in range(6):
		fields._execute_skill(up,"windfield_updraft_feed");fields._execute_skill(cross,"windfield_crosswind_guard")
	ck(is_equal_approx(float(fields.modifiers(boss).atkMult),1.08),"field attack remains a single eight-percent source")
	ck(boss.shield==200 and boss.statuses.filter(func(s):return s.id=="shield").size()==1,"shield refresh uses caster HP and never accumulates")
	ck(boss.statuses.all(func(s):return int(s.duration)==2),"refresh duration stays bounded")
	fields.state.currentActor=fields.state.allies[0].uid;fields.state.allies[0].skills=["ember_normal"]
	ck(fields.legal_targets("ember_normal").has(up.uid) and fields.legal_targets("ember_normal").has(cross.uid),"both fields are independent selectable enemy targets")
	up.currentHp=0;cross.currentHp=0;fields._end_round();fields._end_round()
	ck(not fields.has_status(boss,"atk_up") and boss.shield==0,"broken fields stop refreshing and expire")
	for id in ["wind_falcon","leaf_spirit","moss_climber","bridge_warden","songwing_attendant","brokenbridge_hunter","windwheel_sentinel","boss_highland_roc"]:
		var d:Dictionary=game.catalog.EnemyData[id]
		var abyss=battle([id],{"isAbyss":true,"floor":1})
		var story=battle([id])
		ck(story.state.enemies[0].maxHp==d.baseStats.hp,"story base remains chapter-sized "+id)
		var mods:Dictionary=abyss.abyss_scale(1,id)
		ck(abyss.state.enemies[0].maxHp==maxi(1,int(d.abyssBaseStats.hp*mods.hpMod)),"abyss uses explicit budget "+id)
	for id in ["brokenbridge_hunter","windwheel_sentinel"]:
		var fresh:Dictionary=sample_budget([id],{"isAbyss":true,"floor":5,"fixtureDef":100},false)
		var old:Dictionary=sample_budget(["dark_knight"],{"isAbyss":true,"floor":5,"fixtureDef":100},false)
		ck(float(fresh.damage)<=float(old.damage)*1.15,"elite six-action budget "+id)
		print("WIND_BUDGET "+JSON.stringify({"mode":"abyss5","enemy":id,"new":fresh,"reference":old,"ratio":fresh.damage/old.damage}))
	var new_config:Dictionary=extraction_config("windpass","boss")
	var old_config:Dictionary=extraction_config("ruins","boss")
	for protection in [[0,false],[100,false],[500,false],[100,true]]:
		var defense: int = protection[0]
		for phase2 in [false,true]:
			for mode in ["abyss","extraction"]:
				var fresh_config:Dictionary={"isAbyss":true,"floor":10} if mode=="abyss" else new_config.duplicate(true)
				var reference_config:Dictionary={"isAbyss":true,"floor":10} if mode=="abyss" else old_config.duplicate(true)
				fresh_config.fixtureDef=defense;reference_config.fixtureDef=defense
				var shield_amount := (100 if mode=="abyss" else 10000) if protection[1] else 0
				fresh_config.fixtureShield=shield_amount;reference_config.fixtureShield=shield_amount
				var ids:Array=["boss_highland_roc"] if mode=="abyss" else ["boss_highland_roc","windfield_updraft","windfield_crosswind"]
				var refs:Array=["boss_storm_witch"] if mode=="abyss" else ["boss_storm_witch","dark_knight","thunder_hawk"]
				var fresh:Dictionary=sample_budget(ids,fresh_config,phase2)
				var old:Dictionary=sample_budget(refs,reference_config,phase2)
				ck(float(fresh.damage)<=float(old.damage)*1.10,"full-formation six-action budget "+str([mode,defense,phase2]))
				ck(float(fresh.singlePeak)<=float(old.singlePeak)*1.10,"bounded single-target peak "+str([mode,defense,phase2]))
				print("WIND_BUDGET "+JSON.stringify({"mode":mode,"defense":defense,"shieldPerPlayer":shield_amount,"phase2":phase2,"new":fresh,"reference":old,"ratio":fresh.damage/old.damage}))
	print("WIND ENEMIES V280: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)
