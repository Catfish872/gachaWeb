extends SceneTree
const Game = preload("res://scripts/game_model.gd")
const Battle = preload("res://scripts/battle_model.gd")
const Optimizer = preload("res://scripts/relic_optimizer.gd")
var passed := 0
var failed := 0
func check(value: bool, label: String) -> void:
	if value: passed += 1
	else: failed += 1; push_error(label)
func _initialize() -> void:
	call_deferred("run_tests")
func actor(b, id: String, atk: int = 1000, constellation: int = 0) -> Dictionary:
	return b._make_ally({"id":id,"stats":{"maxHp":1000000,"atk":atk,"def":100,"spd":100,"cri":0.0,"criDmg":1.5},"constellation":constellation},0)
func fixture(game):
	var b = Battle.new(game.catalog)
	var selin: Dictionary = actor(b,"selin")
	var kaldi: Dictionary = actor(b,"kaldi",2000); kaldi.uid="ally_1"
	var target: Dictionary = actor(b,"target"); target.uid="enemy_0"; target.isAlly=false; target.passiveId=""; target.element="neutral"
	b.state={"allies":[selin,kaldi],"enemies":[target],"turn":1,"config":{},"events":[],"log":[]}
	return {"b":b,"s":selin,"k":kaldi,"t":target}
func run_tests() -> void:
	var g = Game.new("")
	check(g.catalog.CharacterData.has("selin"),"character merged")
	var f: Dictionary = fixture(g); var b=f.b; var s: Dictionary=f.s; var k: Dictionary=f.k; var t: Dictionary=f.t
	b.apply_status(t,"burn",5,null,k)
	check(is_equal_approx(b._damage_multiplier(k,t,"normal",false),1.2),"legacy Kaldi rare unchanged")
	b._refresh_combat_buff(k,"ember_oath",.8,2,s)
	check(is_equal_approx(b._damage_multiplier(k,t,"normal",false),2.0),"rare 20+80 additive")
	check(is_equal_approx(b._owner_follow_up_multiplier(k,t),1.8),"followup external only")
	check(is_equal_approx(b._external_deepening(s,t),0.0),"Selin excluded from own aura")
	b.apply_status(t,"poison",1,null,k); b.apply_status(t,"poison",1,null,s)
	check(int(b.poison_damage_preview(t).amount)==101,"mixed-source poison amplification once per source")
	var before := int(t.currentHp); var duration := int(b.burn_remaining_turns(t))
	b._after_active_action(s)
	check(before-int(t.currentHp)==155,"linear detonation at 5 remaining turns")
	check(int(b.burn_remaining_turns(t))==duration,"detonation preserves duration")
	check(int(s.energy)==0,"detonation gives no energy")
	s.ownerEffects=[{"type":"onBurnDetonation","partyBurnAmp":.4,"ownerDirectAmp":.25}]
	before=int(t.currentHp); b._after_active_action(s)
	check(before-int(t.currentHp)==155,"first set proc does not amplify initiating detonation")
	check(is_equal_approx(b.burn_damage_multiplier(k,t),2.52),"party burn 1.4 times external 1.8")
	check(is_equal_approx(b._damage_multiplier(s,t,"normal",false),1.25),"set direct additive bucket")
	before=int(t.currentHp); b._after_active_action(s)
	check(before-int(t.currentHp)==217,"next detonation receives one set multiplier")
	check(is_equal_approx(b._timed_status_value(k,"ember_lantern_burn"),.4),"set refresh without stacking")
	b._effects=[{"type":"burnDurationAdd","value":1},{"type":"burnDamageAmp","value":.25},{"type":"burnDamageAmp","value":.25}]
	s.constellation=6; t.statuses=[]; b.apply_status(t,"burn",2,null,s)
	check(b.burn_remaining_turns(t)==4,"C6 and blessing durations additive")
	check(is_equal_approx(b.burn_damage_multiplier(s,t),1.9),"blessing copies and set add within burn bucket")
	k.currentHp=0
	b._end_round(); b._end_round()
	check(is_equal_approx(b._external_deepening(k,t),0.0),"dead source timed deepening expires")
	check(is_equal_approx(b._timed_status_value(k,"ember_lantern_burn"),0.0),"dead source set buff expires")
	f=fixture(g); b=f.b; s=f.s; k=f.k; t=f.t; s.constellation=6
	b._execute_skill(s,"selin_ult",t.uid)
	check(b.has_status(k,"ember_oath") and not b.has_status(s,"ember_oath"),"ultimate allies-only aura")
	var last_damage := -1; var first_aura := -1
	for i in range(b._events.size()):
		var event: Dictionary=b._events[i]
		if event.type=="damage":last_damage=i
		if event.get("statusId","")=="ember_oath":first_aura=i
	check(last_damage>=0 and first_aura>last_damage,"ultimate C6 resolves before fresh aura")
	var shared: Dictionary={}
	for r in g.catalog.AbyssData.rogue.rewards:
		if r.id=="kaldi_burn_amp_white":shared=r
	check(g.reward_eligible_for_characters(shared,["selin"]),"shared available with Selin alone")
	check(is_equal_approx(g.reward_character_weight(shared,{"kaldi":.4},["kaldi"]),g.reward_character_weight(shared,{"kaldi":.4,"selin":.4},["kaldi","selin"])),"two shared owners do not add weight")
	for id in ["kaldi","selin","ayla"]:
		var rewards: Array=g._available_abyss_rewards({"eligibleCharacters":[id]})
		var count := 0; var seen: Dictionary={}
		for r in rewards:
			if r.pool=="character":count+=1
			check(not seen.has(r.id),"reward ID unique");seen[r.id]=true
		check(count==(5 if id=="ayla" else 6),id+" eligible pool count")
	# Smoke only: reference objective includes team support and can evaluate new set.
	g.state.ownedCharacters.selin=g.default_character();g.state.ownedCharacters.kaldi=g.default_character();g.state.team=["selin","kaldi"]
	var opt=Optimizer.new(g,"selin")
	var reference: Dictionary=opt.evaluate_loadout([])
	check(reference.objective>0,"Selin support-aware objective finite")
	check(opt._evaluate(reference.stats,[],true)>=reference.objective,"support-aware upper bound covers attainable score")
	print("SELIN_V270 ",passed," passed / ",failed," failed")
	quit(1 if failed else 0)
