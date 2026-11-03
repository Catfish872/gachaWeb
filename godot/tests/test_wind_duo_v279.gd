extends SceneTree
const Game = preload("res://scripts/game_model.gd")
const Battle = preload("res://scripts/battle_model.gd")
const Optimizer = preload("res://scripts/relic_optimizer.gd")
var passed := 0
var failed := 0
func check(value: bool,label: String) -> void:
	if value: passed+=1
	else: failed+=1; push_error(label)
func _initialize() -> void: call_deferred("run_tests")
func actor(b,id: String,index: int=0,c6: int=0) -> Dictionary:
	return b._make_ally({"id":id,"stats":{"maxHp":1000000,"atk":1000,"def":100,"spd":100,"cri":0.0,"criDmg":3.0},"constellation":c6},index)
func fixture(g) -> Dictionary:
	var b=Battle.new(g.catalog)
	var t: Dictionary=actor(b,"tiya")
	var l: Dictionary=actor(b,"lumi",1)
	var enemy: Dictionary=actor(b,"reference",9)
	enemy.uid="enemy_0"; enemy.isAlly=false; enemy.passiveId=""; enemy.element="neutral"; enemy.stats.def=1000000
	b.state={"allies":[t],"enemies":[enemy],"turn":1,"config":{},"events":[],"log":[]}
	return {"b":b,"t":t,"l":l,"e":enemy}
func damage_events(b,sid: String) -> Array:
	return b._events.filter(func(e):return e.type=="damage" and e.get("skill_id","")==sid)
func set_effect(g,id: String) -> Dictionary:
	return g.catalog.RelicSets[id].bonuses[1].effects[0].duplicate(true)
func run_tests() -> void:
	var g=Game.new("")
	for id in ["tiya","lumi"]:
		check(g.catalog.CharacterData.has(id),id+" catalog")
		for sid in g.catalog.CharacterData[id].skills: check(g.catalog.SkillData[sid].get("onHitPerActionTarget",false),sid+" proc frequency")
	var f=fixture(g); var b=f.b; var t: Dictionary=f.t; var l: Dictionary=f.l; var e: Dictionary=f.e
	b.apply_status(e,"wind_armor",2,.35,t)
	b.apply_status(e,"wind_armor",3,.35,t)
	check(e.statuses.size()==1 and int(e.statuses[0].duration)==3,"armor refresh, no duration stacking")
	l.constellation=6; b.apply_status(e,"wind_armor",2,.35,l)
	check(is_equal_approx(float(e.statuses[0].value),.45),"Lumi C6 active armor45")
	b.apply_status(e,"wind_armor",4,.35,t)
	check(is_equal_approx(float(e.statuses[0].value),.45) and int(e.statuses[0].duration)==4,"weaker armor preserves strongest")
	e.statuses=[]; l.ownerEffects=[set_effect(g,"wind_strings")]; b.state.allies=[t,l]
	b._effects=[{"type":"enemyBattleStartStatus","statusId":"wind_armor","value":.35,"duration":3,"sourcePolicy":"blessing"}]
	b._apply_battle_start()
	check(is_equal_approx(float(e.statuses[0].value),.35),"opening blessing fixed35 despite C6 Lumi")
	check(is_zero_approx(b._timed_follow_up_amp(t,"innate_piercing")),"opening blessing does not proc wearer set")
	b._effects=[]
	b.apply_status(e,"wind_armor",3,.35,l)
	check(is_equal_approx(b._timed_follow_up_amp(t,"innate_piercing"),.4),"active armor grants party innate followup40")
	var generic: Dictionary=actor(b,"zeph",2); generic.ownerEffects=[set_effect(g,"wind_strings")]
	b.state.allies=[t,generic]; t.statuses=[]
	b.apply_status(e,"wind_armor",3,.35,generic)
	check(is_equal_approx(b._timed_follow_up_amp(t,"innate_piercing"),.4),"set trigger generic wearer")
	check(is_equal_approx(b._timed_follow_up_amp(generic,"innate_piercing"),.4),"set recipient generic and includes wearer")
	f=fixture(g); b=f.b; t=f.t; l=f.l; e=f.e
	b.apply_status(e,"wind_armor",3,.35,t)
	t.stats.cri=1.0; t.stats.normalDmgBonus=9.0
	b.apply_status(t,"atk_up",2,2.0,t)
	b._wind_piercing_hit(t,e,.60,true)
	var events:=damage_events(b,"wind_primary")
	check(events.size()==1 and int(events[0].amount)==600,"pierce uses rawAtk, ignores temp attack and ordinary type")
	check(not events[0].isCrit and is_equal_approx(float(events[0].defPierce),1.0),"noncritical100 percent defense pierce")
	check(events[0].followUpTag=="innate_piercing","innate tag")
	b._events=[]; b._effects=[{"type":"windPrimaryAmp","value":1.0/15.0},{"type":"windPrimaryAmp","value":1.0/6.0}]
	l.ownerEffects=[set_effect(g,"wind_strings")]; b.state.allies=[t,l]
	b.apply_status(e,"wind_armor",3,.35,l)
	b._wind_piercing_hit(t,e,.60,true)
	check(absi(int(damage_events(b,"wind_primary")[0].amount)-1127)<=1,"set and blessings additive coefficient then Lumi15 percent with integer rounding")
	b._wind_piercing_hit(t,e,.36,false)
	check(absi(int(damage_events(b,"wind_gold")[0].amount)-414)<=1,"gold excludes innate coefficient buff with Lumi15 percent and integer rounding")
	check(int(t.energy)==0,"piercing does not grant hit energy")
	f=fixture(g); b=f.b; t=f.t; l=f.l; e=f.e
	b.apply_status(e,"wind_armor",3,.35,t)
	b._effects=[{"type":"windGoldPierce","multiplier":.36},{"type":"windGoldPierce","multiplier":.36},{"type":"applyStatusAfterDamage","statusId":"poison","chance":1.0,"duration":1}]
	b._execute_skill(t,"tiya_normal",e.uid); b._after_active_action(t)
	check(damage_events(b,"tiya_normal").size()==2,"two native hits")
	check(damage_events(b,"wind_primary").size()==1,"once innate per action target")
	check(damage_events(b,"wind_gold").size()==2,"one gold per copy action target, no recursion")
	check(e.statuses.filter(func(s):return s.id=="poison").size()==1,"multi-hit poison once per copy action target")
	check(int(t.energy)==15,"normal gain15, no extra wind battery")
	b._events=[]; t.constellation=6; b._effects=[]
	b._execute_skill(t,"tiya_normal",e.uid); b._after_active_action(t)
	check(int(damage_events(b,"wind_primary")[0].amount)==660,"C6 innate66 percent")
	var second: Dictionary=e.duplicate(true); second.uid="enemy_1"; second.statuses=[]; b.state.enemies.append(second)
	b._events=[]; b._execute_skill(t,"tiya_skill",e.uid); b._after_active_action(t)
	check(damage_events(b,"wind_primary").size()==2,"area action once for each hit target")
	b.state.allies=[t,l]; b.apply_status(e,"wind_armor",3,.35,t)
	check(is_equal_approx(b._damage_taken_multiplier(t,e),.8),"Lumi armored source20 percent guard")
	l.currentHp=0
	check(is_equal_approx(b._damage_taken_multiplier(t,e),1.0),"Lumi passive stops after defeat")
	l.currentHp=l.maxHp
	second.statuses=[]
	check(is_equal_approx(b._status_taken_multiplier(t,{"dotSources":[{"uid":e.uid,"attackSum":1000},{"uid":second.uid,"attackSum":1000}]}),.9),"mixed poison weights armored source guard")
	var venom: Dictionary={}
	for reward in g.catalog.AbyssData.rogue.rewards:
		if reward.id=="common_venom_white": venom=reward
	check(not venom.is_empty() and is_equal_approx(float(venom.effects[0].chance),.20),"common venom20 percent")
	for id in ["tiya","lumi","ayla"]: g.state.ownedCharacters[id]=g.default_character()
	g.state.team=["tiya","lumi","ayla"]
	for id in ["tiya","lumi"]:
		var opt=Optimizer.new(g,id)
		var reference: Dictionary=opt.evaluate_loadout([])
		check(reference.objective>0 and is_finite(float(reference.objective)),id+" objective finite")
		check(opt._evaluate(reference.stats,[],true)>=reference.objective,id+" conservative upper bound")
		var enhanced: float=opt._evaluate(reference.stats,[set_effect(g,"wind_strings")])
		check(enhanced>reference.objective,id+" optimizer values team piercing set")
		check(opt._objective_key(reference.stats,[],false)!=opt._objective_key(reference.stats,[set_effect(g,"wind_strings")],false),id+" effect cache key distinct")
	print("WIND_DUO_V279 ",passed," passed / ",failed," failed")
	quit(1 if failed else 0)
