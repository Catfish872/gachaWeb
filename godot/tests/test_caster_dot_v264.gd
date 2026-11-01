extends SceneTree
const Game=preload("res://scripts/game_model.gd")
const Battle=preload("res://scripts/battle_model.gd")
const Balance=preload("res://scripts/abyss_balance.gd")
var checks:=0
var failures:=0
func ck(value:bool,label:String)->void:
	checks+=1
	if not value:failures+=1;printerr("FAIL ",label)
func setup(data:Dictionary,mode:String="story"):
	var config:Dictionary={"enemies":["wolf"],"seed":45}
	if mode=="abyss":config.isAbyss=true
	elif mode=="extraction":config.isExtraction=true
	var allies:Array=[{"id":"ember","stats":{"maxHp":1000000,"atk":1000,"def":50,"spd":500,"cri":0.0,"criDmg":1.5}}]
	var battle=Battle.new(data);battle.start(config,allies)
	battle.state.enemies[0].maxHp=1000000000;battle.state.enemies[0].currentHp=1000000000
	return battle
func _init()->void:
	var game=Game.new("")
	var b=setup(game.catalog)
	var caster:Dictionary=b.state.allies[0]
	var enemy:Dictionary=b.state.enemies[0]
	ck(b.apply_status(enemy,"burn",2,null,caster),"caster burn applies")
	ck(int(enemy.statuses[0].dotAttack)==1000,"burn snapshots effective source attack")
	caster.stats.atk=200
	b.apply_status(enemy,"burn",3,null,caster)
	ck(int(enemy.statuses[0].dotAttack)==1000 and int(enemy.statuses[0].duration)==5,"weak burn extends duration without overwriting stronger snapshot")
	caster.stats.atk=5000;enemy.baseAtk=99999999;enemy.stats.atk=99999999
	var before:int=enemy.currentHp;b._events=[];b._end_round()
	ck(before-int(enemy.currentHp)==180,"burn fixed180 independent of victim and later caster attack")
	var burn_events:Array=b._events.filter(func(e):return e.type=="damage" and e.get("status","")=="burn")
	ck(burn_events.size()==1 and burn_events[0].actor==caster.uid and burn_events[0].damageSource=="burn","burn source metadata")
	b.apply_status(enemy,"burn",1,null,caster)
	ck(int(enemy.statuses[0].dotAttack)==5000,"stronger burn upgrades source snapshot")
	for row in [[1,20],[5,140],[10,380],[30,2340],[50,5900],[100,21800]]:
		enemy.statuses=[];enemy.currentHp=1000000000;caster.stats.atk=1000;caster.currentHp=caster.maxHp
		for i in range(row[0]):b.apply_status(enemy,"poison",2,null,caster)
		var preview:Dictionary=b.poison_damage_preview(enemy)
		ck(preview.stacks==row[0] and preview.amount==row[1],"poison curve %d" % row[0])
		before=enemy.currentHp;b._events=[];b._end_round()
		ck(before-int(enemy.currentHp)==row[1] and enemy.statuses.size()==row[0],"poison damage and permanent layers %d" % row[0])
		var events:Array=b._events.filter(func(e):return e.type=="damage" and e.get("status","")=="poison")
		ck(events.size()==1 and int(events[0].poisonStacks)==row[0],"one poison event for %d layers" % row[0])
	ck(b.poison_damage_preview(enemy).amount>180,"high stacks exceed burn")
	for i in range(3):b._end_round()
	ck(enemy.statuses.size()==100 and int(enemy.statuses[0].duration)==1,"layers stay through many rounds")
	enemy.statuses=[];caster.stats.atk=1000
	b.apply_status(enemy,"poison",1,null,caster)
	var weak:Dictionary=caster.duplicate(true);weak.uid="ally_weak";weak.name="Weak";weak.stats.atk=100
	b.apply_status(enemy,"poison",1,null,weak)
	var mixed:Dictionary=b.poison_damage_preview(enemy)
	ck(mixed.amount==24 and mixed.sources.size()==2,"mixed caster snapshots add before shared stack growth")
	caster.stats.atk=999999;caster.currentHp=0;enemy.maxHp=9000000000;enemy.baseAtk=999999999
	ck(b.poison_damage_preview(enemy).amount==24,"poison independent of victim stats and subsequent source growth or death")
	ck(not b.apply_status(enemy,"poison",2) and not b.apply_status(enemy,"burn",2),"missing source cannot derive victim-percent damage")
	enemy.statuses=[{"id":"burn","duration":2,"value":null},{"id":"poison","duration":2,"value":null}]
	before=enemy.currentHp;b._end_round()
	ck(before==enemy.currentHp,"unknown legacy DOT has no victim-stat fallback")
	for mode in ["story","abyss","extraction"]:
		var battle=setup(game.catalog,mode)
		var source:Dictionary=battle.state.allies[0];var target:Dictionary=battle.state.enemies[0]
		battle.apply_status(target,"poison",2,null,source)
		battle.apply_status(source,"burn",1,null,target)
		ck(int(source.statuses[0].dotAttack)==int(target.stats.atk),"enemy burn uses enemy source in "+mode)
		ck(battle.poison_damage_preview(target).amount==20,"same poison rules in "+mode)
		battle.start({"enemies":["wolf"]},[{"id":"ember"}])
		ck(battle.state.allies[0].statuses.is_empty() and battle.state.enemies[0].statuses.is_empty(),"new battle resets poison in "+mode)
	var opening=Battle.new(game.catalog)
	var party:Array=[{"id":"ember","stats":{"maxHp":1000,"atk":100,"def":50,"spd":500}}, {"id":"kaldi","stats":{"maxHp":1000,"atk":300,"def":50,"spd":400}}]
	opening.start({"isAbyss":true,"enemies":["wolf"]},party,[{"type":"enemyBattleStartStatus","statusId":"burn","duration":3}])
	ck(opening.state.enemies[0].statuses[0].sourceUid=="ally_1" and opening.state.enemies[0].statuses[0].dotAttack==300,"opening blessing binds strongest ally")
	var mods:Dictionary=Balance.web_endless_scale(100,"boss_flame_lord")
	ck(int(4000*mods.hpMod)==89516 and int(60*mods.defMod)==3402,"endless restored original4.2percent")
	print("CASTER DOT V264: %d checks, %d failures" %[checks,failures])
	quit(0 if failures==0 else 1)
