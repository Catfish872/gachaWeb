extends "res://tests/test_relic_optimizer_v250.gd"
const Battle=preload("res://scripts/battle_model.gd")
const Cycle=preload("res://scripts/relic_cycle.gd")
const Sets=preload("res://scripts/relic_sets.gd")
const Quick=preload("res://scripts/relic_quick_optimizer.gd")

func fixture(team: Array=["raisa","vika","eve"]) -> Variant:
	var game=Game.new("")
	game.state.team=team.duplicate()
	game.state.relics=[]
	for id in ["raisa","vika","eve"]:
		game.state.ownedCharacters[id]=game.default_character()
	return game

func test_cycles() -> void:
	var skills: Array=[{"type":"normal","gain":18,"cost":0,"cooldown":0},{"type":"skill","gain":25,"cost":0,"cooldown":3},{"type":"ultimate","gain":0,"cost":100,"cooldown":0}]
	var transitions: Array=[[{"energy":0,"p":1.0}],[{"energy":0,"p":1.0}],[{"energy":0,"p":1.0}]]
	for turns in [4,5]:
		var cycle: Dictionary=Cycle.thunder_weights(skills,transitions,turns)
		ck(cycle.success and cycle.residual<1e-9,"thunder probabilities normalize "+str(turns))
		ck(cycle.meanCycleLength==5+turns,"cast-inclusive thunder duration "+str(turns))
		ck(is_equal_approx(float(cycle.skillWeights[5]),float(turns-3)/float(5+turns)),"one or two armor ultimates "+str(turns))
		var opening: Dictionary=Cycle.thunder_weights(skills,transitions,turns,turns,100)
		ck(opening.skillWeights[0]==0.0 and opening.skillWeights[1]==0.0,"full-energy opening enters armor immediately")
		ck(is_equal_approx(float(opening.skillWeights[5]),float(turns-3)/turns),"opening armor sequence "+str(turns))
		for entry in opening.entries:
			if int(entry.index)>=3: ck(entry.energy==100,"armor energy stays at 100")
	transitions[0]=[{"energy":0,"p":0.5},{"energy":4,"p":0.5}]
	transitions[1]=[{"energy":0,"p":0.125},{"energy":4,"p":0.875}]
	var random_cycle: Dictionary=Cycle.thunder_weights(skills,transitions,4)
	ck(random_cycle.success and random_cycle.meanCycleLength<=9.0,"critical energy advances exact renewal")

func test_runtime_parity() -> void:
	for constellation in [0,6]:
		var game=fixture(["raisa",null,null])
		game.state.ownedCharacters.raisa.constellation=constellation
		var scorer=Optimizer.new(game,"raisa")
		var stats: Dictionary=game.computed_stats("raisa")
		stats.cri=0.0;stats.critRate=0.0
		var expected: float=scorer._evaluate(stats,[])
		var cycle: Dictionary=scorer.cycle_summary(stats,[])
		var battle=scorer._battle
		var reference: Dictionary=scorer._reference(stats,[])
		var actor: Dictionary=reference.actor
		var total:=0.0
		var sequence: Array=[]
		for _turn in range(int(cycle.meanCycleLength)):
			battle.state.turn=_turn+1
			var available: Array=battle._available(actor)
			var sid: String=available[0]
			for candidate in available:
				var skill: Dictionary=game.catalog.SkillData[candidate]
				if skill.type=="ultimate": sid=candidate;break
				if skill.type=="skill":sid=candidate
			sequence.append(sid)
			battle._events=[]
			battle._execute_skill(actor,sid)
			battle._after_active_action(actor)
			for event in battle._events:
				if event.type=="damage":total+=float(event.amount)
			battle._end_round()
		ck(absf(expected-total/float(cycle.meanCycleLength))<1e-7,"live runtime damage matches armor renewal C"+str(constellation))
		ck(actor.energy==0 and not battle.thunder_armor_active(actor),"live exit clears armor and energy C"+str(constellation))
		ck(sequence.count("raisa_armor_ult")== (2 if constellation==6 else 1),"live sequence consumes correct ultimate count")

func test_critical_energy_order() -> void:
	var game=fixture(["raisa",null,null])
	var scorer=Optimizer.new(game,"raisa")
	var stats: Dictionary=game.computed_stats("raisa")
	stats.cri=0.5;stats.critRate=0.5
	var effects: Array=[{"type":"energyOnCrit","value":4}]
	var reference: Dictionary=scorer._reference(stats,effects)
	var actor: Dictionary=reference.actor
	var target: Dictionary=reference.target
	var skill: Dictionary=game.catalog.SkillData.raisa_skill
	var actual: float=scorer._thunder_entry_damage(actor,target,skill,0,false,false)
	var expected:=0.0
	for outcome in range(8):
		actor.energy=scorer._battle.action_energy_gain(actor,skill)
		var used:=false
		for hit in range(3):
			var critical: bool=(outcome & (1<<hit))!=0
			expected+=scorer._battle.predict_effect_damage(actor,target,skill,skill.effects[0],critical)/8.0
			if critical and not used:
				actor.energy=mini(100,int(actor.energy)+4);used=true
		actor.energy=0
	ck(absf(actual-expected)<1e-7,"AoE critical energy affects later targets exactly once")

func test_party_and_sets() -> void:
	var game=fixture()
	var original:=JSON.stringify(game.state)
	var rng_state: int=game.rng.state
	for id in ["raisa","vika","eve"]:
		var scorer=Optimizer.new(game,id)
		var snapshot: Dictionary=scorer.evaluate_loadout([])
		ck(snapshot.objective>0 and snapshot.breakdown.teamDamage>0,"positive party output "+id)
		ck(snapshot.breakdown.referenceTeam.size()==3,"three real reference members "+id)
		var upper: float=scorer._evaluate(snapshot.stats,[],true)
		ck(upper+1e-7>=float(snapshot.objective),"safe thunder upper bound "+id)
		var set_id: String={"raisa":"storm_armor","vika":"storm_tracer","eve":"storm_shelter"}[id]
		var effects: Array=[]
		for bonus in game.catalog.RelicSets[set_id].bonuses:
			for effect in bonus.effects:
				if effect.type!="stat":effects.append(effect.duplicate())
		var equipped: float=scorer._evaluate(snapshot.stats,effects)
		ck(equipped>float(snapshot.objective),"owner effect priced for "+set_id)
		ck(absf(scorer._evaluate(snapshot.stats,effects)-equipped)<1e-9,"warm objective cache "+id)
		if id=="eve":
			ck(snapshot.breakdown.shieldSupply>0 and snapshot.breakdown.passiveHealing>0 and snapshot.breakdown.regeneration>0,"Eve shield and regeneration included")
			ck(is_equal_approx(float(snapshot.objective),float(snapshot.breakdown.activeHealing)+float(snapshot.breakdown.shieldSupply)+float(snapshot.breakdown.passiveHealing)+float(snapshot.breakdown.regeneration)),"HP sustain excludes separately reported damage")
	ck(original==JSON.stringify(game.state) and rng_state==game.rng.state,"optimizer preserves save and gameplay RNG")
	var solo=fixture(["vika",null,null])
	var solo_score=Optimizer.new(solo,"vika")
	var party_score=Optimizer.new(game,"vika")
	var own: Dictionary=solo_score.evaluate_loadout([])
	var party: Dictionary=party_score.evaluate_loadout([])
	ck(party.objective>own.objective,"Vika scores allies and their conduct triggers")
	var low: Dictionary=game.computed_stats("vika")
	var high: Dictionary=low.duplicate();high.atk*=2
	var solo_delta: float=solo_score._evaluate(high,[])-solo_score._evaluate(low,[])
	var party_delta: float=party_score._evaluate(high,[])-party_score._evaluate(low,[])
	ck(party_delta>solo_delta,"Vika ATK prices teammate-triggered conduct, beyond own skill sum")

func test_small_search() -> void:
	for id in ["raisa","vika","eve"]:
		var game=fixture()
		var slots: Array=[]
		var set_id: String={"raisa":"storm_armor","vika":"storm_tracer","eve":"storm_shelter"}[id]
		for slot in Optimizer.SLOTS:
			var a:=relic("a_"+id+slot,slot,"atk_flat",10,set_id)
			var b:=relic("b_"+id+slot,slot,"atk_flat",15,"")
			game.state.relics.append_array([a,b]);slots.append([a,b])
		var exact=Optimizer.new(game,id)
		var exhaustive:=oracle(exact,slots)
		var result:=finish(exact)
		ck(result.provenOptimal and absf(float(result.lowerBound)-exhaustive)<1e-6,"exact search matches raw oracle "+id)
		var quick=Quick.new(game,id,{"quickBudgetMs":300,"quickEvaluationCap":128})
		var fast:=finish(quick)
		ck(fast.success and fast.after.objective>0 and fast.referenceTeam.size()==3,"quick recommendation inherits thunder evaluator "+id)

func test_current_runtime_parameters() -> void:
	var game=fixture()
	var scorer=Optimizer.new(game,"raisa")
	var reference: Dictionary=scorer._reference(game.computed_stats("raisa"),[])
	var party: Array=scorer._thunder_reference_party(reference.actor,reference.target)
	ck(is_equal_approx(float(scorer._battle.modifiers(reference.target).defMult),0.65),"maintained conduct uses current 35 percent DEF reduction")
	var vika: Dictionary=party.filter(func(a):return a.id=="vika")[0]
	vika.ownerEffects=[{"type":"onStatusAppliedPartyArmorAmp","statusId":"thunder_mark","value":0.20,"duration":2}]
	scorer._battle._apply_owner_status_effects(vika,"thunder_mark")
	ck(is_equal_approx(scorer._battle._timed_status_value(reference.actor,"thunder_oath"),0.20),"runtime team armor set buff is available")
	var armor_skill: Dictionary=game.catalog.SkillData.raisa_armor_skill
	reference.actor.stats.cri=1.0
	var predicted: float=scorer._thunder_entry_damage(reference.actor,reference.target,armor_skill,100,true,false)
	var expected:=0.0
	reference.actor.energy=100;reference.actor.thunderArmor={"remainingTurns":4}
	for effect in armor_skill.effects:
		if effect.type=="damage":
			var chain:=1.0
			for target_index in range(3):
				expected+=scorer._battle.predict_effect_damage(reference.actor,reference.target,armor_skill,effect,bool(effect.get("canCrit",true)),false,chain)
				chain=maxf(float(effect.get("chainFloor",0.3)),chain-float(effect.get("chainDecay",0.0)))
	ck(absf(predicted-expected)<1e-7,"armor mixed critical and noncritical segments match predictor")
	var effect: Dictionary=armor_skill.effects.filter(func(e):return e.get("canCrit",true)==false)[0]
	ck(scorer._battle.predict_effect_damage(reference.actor,reference.target,armor_skill,effect,true)==scorer._battle.predict_effect_damage(reference.actor,reference.target,armor_skill,effect,false),"predictor rejects critical on a declared noncritical segment")

func test_opening_conduct_runtime() -> void:
	for rank in [0,6]:
		var game=fixture()
		for id in game.state.team:
			game.state.ownedCharacters[id].constellation=rank
			game.catalog.CharacterData[id].baseStats.cri=0.0
		var scorer=Optimizer.new(game,"vika",{"actions":8,"enemyCount":3})
		var predicted: Dictionary=scorer.evaluate_loadout([])
		var battle=Battle.new(game.catalog)
		battle.start({"enemies":["boss_flame_lord","boss_flame_lord","boss_flame_lord"],"seed":290031},game.battle_party(false))
		for enemy in battle.state.enemies:
			enemy.currentHp=100000000;enemy.maxHp=100000000;enemy.element="neutral"
			battle.apply_status(enemy,"thunder_mark",99,null,battle.state.allies[1])
		for ally in battle.state.allies: battle.apply_status(ally,"shield",99,null,ally,1000)
		var triggers:=0
		for turn in range(8):
			# Match the disclosed maintained-mark reference, isolating cadence/cap.
			for enemy in battle.state.enemies: battle.apply_status(enemy,"thunder_mark",99,null,battle.state.allies[1])
			for ally in battle.state.allies:
				var skills: Array=battle._available(ally);var selected: String=skills[0]
				for sid in skills:
					var skill: Dictionary=battle.skill_data(sid)
					if battle._hold_healing_skill(ally,skill):continue
					if skill.type=="ultimate":selected=sid;break
					if skill.type=="skill":selected=sid
				battle._events=[];battle._execute_skill(ally,selected);battle._after_active_action(ally)
				for event in battle._events:
					if event.type=="damage" and event.get("skill_id","")=="vika_passive":triggers+=1
			battle._end_round();battle._build_queue()
		ck(absf(float(predicted.breakdown.conductTriggersPerRound)*8.0-triggers)<1e-7,"opening per-target two-hit cap matches actual C"+str(rank))
		ck(predicted.breakdown.conductTriggersPerRound<=6.0,"three targets cap at six pursuits per round")

func test_synchronized_conduct_schedule() -> void:
	var game=fixture()
	for id in game.state.team: game.catalog.CharacterData[id].baseStats.cri=0.0
	var scorer=Optimizer.new(game,"vika")
	var reference: Dictionary=scorer._reference(game.computed_stats("vika"),[])
	var allies: Array=scorer._thunder_reference_party(reference.actor,reference.target)
	var outputs: Array=[]
	for unit in allies: outputs.append(scorer._thunder_unit_output(unit,reference.target,false))
	var expected: float=scorer._thunder_synchronized_hits(allies,outputs)
	ck(expected>=0.0,"deterministic party exposes synchronous cycle")
	# Feed the synchronized model an adversarial same-period fixture: three
	# actors all hit on one round and all rest on the next. Marginal clipping
	# would incorrectly return1.5; the real two-hit cap yields1.0 per round.
	var synthetic: Array=[]
	for index in range(3):synthetic.append({"conductSchedule":{"prefix":[],"period":[[1.0,1.0,1.0],[0.0,0.0,0.0]]}})
	ck(absf(scorer._thunder_synchronized_hits(allies,synthetic)-3.0)<1e-7,"synchronous three-source cap retains correlation for each target")
	var independent: float=scorer._thunder_capped_hits([0.5,0.5,0.5])
	ck(absf(independent-1.375)<1e-7,"stochastic independent cap uses full probability distribution")

func test_mixed_party_statuses() -> void:
	for ids in [["vika","tiya","lumi"],["raisa","tiya","lumi"],["raisa","kaldi","selin"]]:
		var game=fixture(ids)
		for id in ids: game.state.ownedCharacters[id]=game.default_character()
		var id: String=ids[0]
		var ordinary=Optimizer.new(game,id)
		var status: String="wind_armor" if ids[1]=="tiya" else "burn"
		var explicit=Optimizer.new(game,id,{"targetStatuses":[status,"thunder_mark"] if id=="vika" else [status]})
		var first: Dictionary=ordinary.evaluate_loadout([])
		var second: Dictionary=explicit.evaluate_loadout([])
		ck(absf(float(first.objective)-float(second.objective))<1e-7,"mixed team status inferred from actual teammates "+str(ids))
		ck(ordinary._evaluate(first.stats,[],true)>=float(first.objective),"mixed team conservative upper "+str(ids))
		if status=="burn":ck(first.breakdown.burnDamage>0,"mixed fire team counts actual burn source")
		else:
			var reference: Dictionary=ordinary._reference(first.stats,[])
			ordinary._thunder_reference_party(reference.actor,reference.target)
			ck(ordinary._battle.has_status(reference.target,"wind_armor"),"mixed wind armor prepared")
			ck(is_equal_approx(float(ordinary._battle._external_deepening(reference.actor,reference.target)),0.15),"mixed Lumi deepening included")

func run() -> void:
	test_cycles()
	test_runtime_parity()
	test_critical_energy_order()
	test_party_and_sets()
	test_small_search()
	test_current_runtime_parameters()
	test_opening_conduct_runtime()
	test_mixed_party_statuses()
	test_synchronized_conduct_schedule()
	print("THUNDER_OPTIMIZER_V290 ",checks," checks; failures=",failures)
	quit(1 if not failures.is_empty() else 0)
