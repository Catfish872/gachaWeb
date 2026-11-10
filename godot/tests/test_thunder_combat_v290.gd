extends SceneTree
const Game = preload("res://scripts/game_model.gd")
const Battle = preload("res://scripts/battle_model.gd")
var failures: Array = []
var checks := 0
func ck(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func _init() -> void:
	for rank in [0,6]: armor(rank)
	healer_and_links()
	regression_edges()
	auto_finishers()
	print("THUNDER_COMBAT_V290 ",checks," checks / ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
func arena(ids: Array, rank: int = 0, effects: Array = []):
	var game = Game.new("")
	for id in ids:
		game.state.ownedCharacters[id] = game.default_character()
		game.state.ownedCharacters[id].constellation = rank
	game.state.team = ids
	var battle = Battle.new(game.catalog)
	battle.start({"enemies":["boss_flame_lord"],"isAbyss":true,"floor":1,"seed":29001},game.battle_party(false),effects)
	for enemy in battle.state.enemies: enemy.maxHp=100000000;enemy.currentHp=enemy.maxHp;enemy.stats.def=100;enemy.stats.spd=0
	return battle
func next_round(battle) -> void:
	battle._end_round(); battle._build_queue()
func use(battle, unit: Dictionary, sid: String) -> void:
	battle._events=[];battle._execute_skill(unit,sid);battle._after_active_action(unit)
func armor(rank: int) -> void:
	var b=arena(["raisa"],rank)
	var a: Dictionary=b.state.allies[0]
	var original: Array=a.skills.duplicate()
	a.currentHp=1001; a.energy=100
	b.apply_status(a,"shield",12,null,a,99)
	use(b,a,"raisa_ult")
	ck(a.currentHp==501,"half current HP floors safely")
	ck(a.shield==599,"conversion adds exact lost HP to existing shield")
	ck(a.energy==100 and b.thunder_armor_active(a),"armor locks full energy")
	ck(a.image.ends_with("raisa_armor.png"),"armor battle image")
	ck(b._available(a)==["raisa_armor_normal"],"only armor normal initially unlocked")
	ck(not b.act("raisa_armor_ult").success,"manual locked ultimate rejected")
	b._gain_energy(a,-1000);ck(a.energy==100,"energy drains cannot break lock")
	next_round(b)
	ck(a.thunderArmor.remainingTurns==(4 if rank==6 else 3),"casting turn counts")
	use(b,a,"raisa_armor_normal")
	ck(b._available(a).has("raisa_armor_skill") and not b._available(a).has("raisa_armor_ult"),"normal unlocks skill only")
	next_round(b);use(b,a,"raisa_armor_skill")
	ck(b._available(a).has("raisa_armor_ult"),"skill unlocks ultimate")
	next_round(b);use(b,a,"raisa_armor_ult")
	ck(a.energy==100,"armor ultimate preserves100")
	next_round(b)
	if rank==6:
		ck(b.thunder_armor_active(a) and a.thunderArmor.remainingTurns==1,"C6 fifth turn available")
		ck(b._available(a).has("raisa_armor_ult"),"C6 second consecutive ultimate legal")
		use(b,a,"raisa_armor_ult");next_round(b)
	ck(not b.thunder_armor_active(a) and a.energy==0,"expiration clears energy")
	ck(a.skills==original and a.image.ends_with("raisa.png"),"normal skills and portrait restored")
	ck(a.shield==99,"conversion shield expires independently")
	ck(b.action_energy_gain(a,b.skill_data("raisa_normal"))>15,"normal charge passive applies")
	var empty_atk=b._effective_atk(a);a.energy=100
	ck(b._effective_atk(a)>empty_atk,"energy scales attack")
	a.currentHp=1;use(b,a,"raisa_ult");ck(a.currentHp==1,"one HP conversion remains alive")
	b._finish("victory","test");ck(a.energy==0 and not b.thunder_armor_active(a),"battle finish clears form and locked energy")
	b=arena(["raisa"],rank);a=b.state.allies[0];a.energy=100;use(b,a,"raisa_ult")
	a.currentHp=0;b._report_deaths();ck(not b.thunder_armor_active(a) and a.energy==0,"death clears form")
func healer_and_links() -> void:
	var b=arena(["raisa","vika","eve"])
	var r:Dictionary=b.state.allies[0];var v:Dictionary=b.state.allies[1];var e:Dictionary=b.state.allies[2];var target:Dictionary=b.state.enemies[0]
	ck(not b._hold_healing_skill(e,b.skill_data("eve_skill")),"shield skill auto casts at full health")
	use(b,e,"eve_skill")
	ck(b.state.allies.all(func(a):return a.shield>0),"Eve shields whole team")
	for a in b.state.allies:a.currentHp=100
	b._end_round()
	ck(b.state.allies.all(func(a):return a.currentHp>100),"shield regeneration independent of formation")
	use(b,v,"vika_skill");ck(b.has_status(target,"thunder_mark"),"Vika applies mark")
	use(b,r,"raisa_normal")
	ck(b._events.filter(func(event):return event.get("skill_id","")=="vika_passive" and event.type=="damage").size()==1,"one conduct hit per actor-target action")
	ck(absf(b._external_deepening(r,target)-.10)<.00001,"Eve shielded thunder amplification")
	r.shield=0;ck(b._external_deepening(r,target)==0,"amplification requires shield")
	var fx:Array=[]
	for i in range(10):fx.append({"type":"damageTakenWhileStatus","statusId":"shield","value":-.15})
	b=arena(["eve"],0,fx);e=b.state.allies[0];use(b,e,"eve_skill")
	ck(absf(b.ordinary_damage_taken_multiplier(e)-.1)<.00001,"healer blessing uses shared90percent floor")
	var g=Game.new("")
	for ids in [["raisa"],["raisa","vika"],["raisa","vika","eve"]]:
		var pool:Array=g.catalog.AbyssData.rogue.rewards.filter(func(reward):return reward.get("pool","")=="character" and g.reward_eligible_for_characters(reward,ids))
		ck(pool.size()==3+ids.size()*3,"six per character and shared union"+str(ids))

func regression_edges() -> void:
	var b=arena(["raisa","vika","eve"])
	var r:Dictionary=b.state.allies[0];var v:Dictionary=b.state.allies[1];var e:Dictionary=b.state.allies[2];var target:Dictionary=b.state.enemies[0]
	use(b,e,"eve_ult");b._end_round()
	var regen:Array=r.statuses.filter(func(status):return status.id=="regen")
	ck(regen.size()==1 and int(regen[0].duration)==2,"passive preserves ultimate regeneration duration")
	for ally in b.state.allies:
		ally.statuses=ally.statuses.filter(func(status):return status.id!="shield");b._sync_shield(ally);ally.currentHp=100
	b._end_round();ck(r.currentHp>100,"ultimate regeneration survives subsequent shield break")
	use(b,v,"vika_skill")
	ck(absf(b.modifiers(target).defMult-.65)<.00001,"conduct lowers defense35percent")
	var conduct:=0
	for actor in [r,v,e]:
		use(b,actor,str(actor.id)+"_normal")
		conduct+=b._events.filter(func(event):return event.type=="damage" and event.get("skill_id","")=="vika_passive").size()
	ck(conduct<=2,"conduct has two per target per round cap")
	b._build_queue();use(b,r,"raisa_normal")
	ck(b._events.any(func(event):return event.type=="damage" and event.get("skill_id","")=="vika_passive"),"conduct allowance refreshes next round")
	r.energy=100;use(b,r,"raisa_ult")
	var armor_skill:Dictionary=b.skill_data("raisa_armor_normal");var effect:Dictionary=armor_skill.effects[1]
	ck(b.predict_effect_damage(r,target,armor_skill,effect,true)==b.predict_effect_damage(r,target,armor_skill,effect,false),"armor piercing prediction cannot crit")
	b._build_queue();ck(r.thunderArmor.remainingTurns==3,"wave boundary updates visible armor time")
	var marker:Array=r.statuses.filter(func(status):return status.id=="thunder_armor")
	ck(marker.size()==1 and int(marker[0].duration)==3,"armor status display matches wave boundary")
	var progression=Game.new("")
	progression.state.ownedCharacters.raisa=progression.default_character()
	progression.state.ownedCharacters.raisa.constellation=5
	var entries:Array=progression.constellation_info("raisa")
	ck(entries[4].label=="雷鸣蓄势" and is_equal_approx(float(progression.constellation_bonuses("raisa").ultDmgBonus),0.0),"Raisa fifth constellation displays charge instead of ordinary ultimate bonus")
	var probe=arena(["raisa"],5);var charged:Dictionary=probe.state.allies[0]
	ck(probe.action_energy_gain(charged,probe.skill_data("raisa_normal"))==23,"fifth constellation charge enters real action gain")
	for defense in [0,100,35000]:
		target.stats.def=defense
		var previous_damage:=0.0
		for sid in ["raisa_armor_normal","raisa_armor_skill","raisa_armor_ult"]:
			var sk:Dictionary=b.skill_data(sid);var amount:=0.0
			for component in sk.effects:amount+=b.expected_effect_damage(r,target,sk,component)
			ck(amount>previous_damage,"ordered primary armor burst at defense"+str(defense)+" "+sid)
			previous_damage=amount
	var game=Game.new("");var effects:Array=[]
	for reward in game.catalog.AbyssData.rogue.rewards:
		if reward.id=="eve_guard_blue":
			for copy in range(10):effects.append_array(reward.effects.duplicate(true))
	b=arena(["eve"],0,effects);e=b.state.allies[0];use(b,e,"eve_ult")
	ck(absf(b.ordinary_damage_taken_multiplier(e)-.1)<.00001,"actual Eve blessing reaches shared90percent cap")


func auto_finishers() -> void:
	var b=arena(["raisa"])
	var a: Dictionary=b.state.allies[0]
	var t: Dictionary=b.state.enemies[0]
	a.energy=100;t.currentHp=1
	var available: Array=b._available(a)
	var before_rng=b.rng.state
	ck(b._raisa_auto_finisher(a,available,"raisa_ult")=="raisa_normal","auto finishes lone foe before transforming")
	ck(b.rng.state==before_rng and a.energy==100 and t.currentHp==1,"finisher preview preserves state and RNG")
	t.currentHp=t.maxHp
	ck(b._raisa_auto_finisher(a,available,"raisa_ult")=="raisa_ult","healthy foe preserves transformation priority")
	t.currentHp=1;t.shield=100000
	ck(b._raisa_auto_finisher(a,available,"raisa_ult")=="raisa_ult","finisher accounts for shield")
	t.shield=0;b.apply_status(t,"invincible",2)
	ck(b._raisa_auto_finisher(a,available,"raisa_ult")=="raisa_ult","invincible foe cannot trigger finisher")
	t.statuses=[]
	var second: Dictionary=t.duplicate(true);second.uid="enemy_extra";b.state.enemies.append(second)
	ck(b._raisa_auto_finisher(a,available,"raisa_ult")=="raisa_ult","multiple foes preserve rotation")
	b.state.enemies.pop_back()
	use(b,a,"raisa_ult")
	ck(b._raisa_auto_finisher(a,b._available(a),"raisa_armor_normal")=="raisa_armor_normal","finisher preserves armor unlock order")
	use(b,a,"raisa_armor_normal");use(b,a,"raisa_armor_skill")
	ck(b._raisa_auto_finisher(a,b._available(a),"raisa_armor_ult")=="raisa_armor_ult","finisher preserves armor ultimate priority")
	b=arena(["tiya"]);a=b.state.allies[0];b.state.enemies[0].currentHp=1
	ck(b._raisa_auto_finisher(a,b._available(a),"tiya_ult")=="tiya_ult","old characters retain original selection")
