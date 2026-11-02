extends SceneTree
const Game=preload("res://scripts/game_model.gd")
const Battle=preload("res://scripts/battle_model.gd")
var checks:=0
var failures:=0
func ck(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func make(id:String,mode:String="isExtraction"):
	var game=Game.new("");var b=Battle.new(game.catalog)
	b.start({mode:true,"enemies":[id],"floor":1,"seed":275},[{"id":"kaldi","stats":{"maxHp":1000000,"atk":10,"def":100,"spd":1000,"cri":0.0,"criDmg":1.5}}])
	return b
func _initialize()->void:call_deferred("run")
func run()->void:
	for mode in ["isExtraction","isAbyss"]:
		for id in ["ash_moth","lamp_overseer","boss_hedor","cracked_puppet"]:
			var b=make(id,mode);var unit:Dictionary=b.state.enemies[0];var config:Dictionary=b._enemy_pacing_config(unit)
			ck(is_equal_approx(float(config.aoeChance),.25),"configured quarter area chance "+id)
			var before:int=b.rng.state;var available:Array=b._available(unit)
			for sid in available:b._enemy_skill_is_aoe(sid)
			ck(b.rng.state==before,"UI availability/classification does not consume RNG")
			ck(b._enemy_pacing_config(b.state.allies[0]).is_empty(),"player AI untouched")
			var area:=str(unit.skills[1] if id in ["lamp_overseer","cracked_puppet"] else unit.skills[0])
			if id=="boss_hedor":area="hedor_embers"
			b._record_enemy_pacing(unit,area)
			ck(unit.get("pacingRecoveryPending",false),"executed area schedules recovery")
			unit.inPhase2=true
			ck(b._enemy_choice(unit,b._available(unit))=="enemy_recover","phase change cannot chain different area")
			for sid in unit.skills:unit.cooldowns[sid]=3
			ck(b._enemy_choice(unit,b._available(unit))=="enemy_recover","cooldowns cannot erase recovery")
			b._record_enemy_pacing(unit,"enemy_recover");ck(not unit.pacingRecoveryPending,"actual recovery clears pending")
			unit.currentHp=0;b._record_enemy_pacing(unit,area);ck(unit.pacingRecoveryPending,"dead source still classified by declared skill")
	var moth=make("ash_moth");var m:Dictionary=moth.state.enemies[0];var opts:Array=moth._available(m)
	ck(opts.has("ash_moth_dive_expedition"),"area-only enemy gets single fallback")
	ck(moth._paced_enemy_choice(m,opts,{"aoeChance":0.0})=="ash_moth_dive_expedition","zero area chance chooses fallback")
	ck(moth._paced_enemy_choice(m,opts,{"aoeChance":1.0})=="ash_moth_dust","one area chance chooses area")
	ck(moth._paced_enemy_choice(m,["ash_moth_dust"],{"aoeChance":0.0})=="enemy_recover","only area unavailable roll recovers")
	var boss=make("boss_hedor");var h:Dictionary=boss.state.enemies[0]
	boss._record_enemy_pacing(h,"hedor_hammer");ck(h.pacingRecoveryPending,"boss ordinary damaging action also gets low pressure interval")
	var puppet=make("cracked_puppet");var p:Dictionary=puppet.state.enemies[0];p.currentHp=int(p.maxHp*.2)
	ck(puppet._enemy_choice(p,puppet._available(p))=="cracked_puppet_warn" and not p.get("chargeReady",false),"preview warning choice does not mark executed charge")
	puppet._record_enemy_pacing(p,"cracked_puppet_warn");ck(p.chargeReady,"warning execution arms charge")
	puppet._record_enemy_pacing(p,"cracked_puppet_burst");ck(p.chargeSpent and not p.chargeReady,"burst consumes one-time charge")
	var story=make("boss_hedor","isStory");ck(story._enemy_pacing_config(story.state.enemies[0]).is_empty(),"story AI excluded")
	# One real action: the UI event identifies the exact low-pressure skill selected.
	var real=make("boss_hedor");var r:Dictionary=real.state.enemies[0];r.pacingRecoveryPending=true
	real._cursor=real._queue.find(r);real._seek_actor();var rng_before:int=real.rng.state;var hp:int=real.state.allies[0].currentHp
	var outcome:Dictionary=real.auto_step()
	ck(outcome.success,"real recovery auto action succeeds")
	ck(outcome.events.any(func(e):return e.get("type","")=="skill" and e.get("skill_id","")=="enemy_recover"),"display event matches executed recovery")
	ck(real.state.allies[0].currentHp==hp,"recovery action causes no damage")
	ck(real.rng.state==rng_before,"recovery selection consumes no random roll")
	var controlled=make("boss_hedor");var cu:Dictionary=controlled.state.enemies[0];cu.pacingRecoveryPending=true;cu.statuses.append({"id":"freeze","duration":2})
	controlled._cursor=controlled._queue.find(cu);controlled._seek_actor();ck(cu.pacingRecoveryPending,"control skip preserves pending recovery")
	var legacy=make("wolf");ck(legacy._enemy_pacing_config(legacy.state.enemies[0]).is_empty(),"existing enemy remains outside new pacing")
	print("ENEMY PACING V275: %d checks, %d failures"%[checks,failures]);quit(0 if failures==0 else 1)
