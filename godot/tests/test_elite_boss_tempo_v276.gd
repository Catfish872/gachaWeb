extends "res://tests/test_enemy_pacing_v275.gd"
func run()->void:
	for mode in ["isExtraction","isAbyss"]:
		for id in ["boss_hedor","lamp_overseer"]:
			var b=make(id,mode);var u:Dictionary=b.state.enemies[0];var cfg:Dictionary=b._enemy_pacing_config(u)
			var area:String="hedor_embers" if id=="boss_hedor" else "lamp_overseer_sweep"
			var single:String="hedor_hammer" if id=="boss_hedor" else "lamp_overseer_chain"
			ck(is_equal_approx(float(cfg.aoeChance),.5) and cfg.recoveryPolicy=="single","half-area single recovery "+mode+id)
			ck(not cfg.has("idleChance") and not cfg.has("recoveryAfterDamage"),"no idle/ordinary recovery")
			var before:int=b.rng.state;b._available(u);ck(before==b.rng.state,"availability preserves RNG")
			b._record_enemy_pacing(u,single);ck(not u.get("pacingRecoveryPending",false),"ordinary does not schedule recovery")
			b._record_enemy_pacing(u,area);u.inPhase2=true
			var selected:String=b._enemy_choice(u,b._available(u))
			ck(b._enemy_skill_has_single_damage(selected),"phase pending forces damaging single")
			ck(u.pacingRecoveryPending,"choice alone does not clear execution state")
			u.statuses.append({"id":"freeze","duration":2});b._cursor=b._queue.find(u);b._seek_actor()
			ck(u.pacingRecoveryPending,"control skip keeps single obligation")
			u.statuses.clear();b._record_enemy_pacing(u,selected);ck(not u.pacingRecoveryPending,"executed single clears obligation")
			u.currentHp=0;b._record_enemy_pacing(u,area);ck(u.pacingRecoveryPending,"dead source still records area")
			u.currentHp=u.maxHp
			for sid in u.skills+u.phase2Skills:u.cooldowns[sid]=3
			ck(b._enemy_choice(u,b._available(u))=="enemy_recover","no legal single uses cooldown-safe recovery")
			b._record_enemy_pacing(u,"enemy_recover");ck(not u.pacingRecoveryPending,"executed fallback clears obligation")
			u.cooldowns.clear()
			var saw_area:=false;var saw_single:=false;var no_idle:=true;var no_chain:=true;var previous_area:=false
			for step in range(24):
				var sid:String=b._enemy_choice(u,b._available(u));var is_area:bool=b._enemy_skill_is_aoe(sid)
				saw_area=saw_area or is_area;saw_single=saw_single or b._enemy_skill_has_single_damage(sid)
				no_idle=no_idle and sid!="enemy_recover";no_chain=no_chain and not(previous_area and is_area)
				b._record_enemy_pacing(u,sid);previous_area=is_area
			ck(saw_area and saw_single and no_idle and no_chain,"fixed 24 choices attack continuously without area chain")
			var real=make(id,mode);var r:Dictionary=real.state.enemies[0];real._record_enemy_pacing(r,area)
			real._cursor=real._queue.find(r);real._seek_actor();var hp:int=real.state.allies[0].currentHp
			var out:Dictionary=real.auto_step()
			ck(out.success and not r.pacingRecoveryPending,"real action clears pending")
			ck(real.state.allies[0].currentHp<hp,"real recovery single damages target")
			ck(out.events.any(func(e):return e.get("type","")=="skill" and real._enemy_skill_has_single_damage(str(e.get("skill_id","")))),"real event displays executed single")
	for id in ["ash_moth","cracked_puppet"]:
		var b=make(id);var u:Dictionary=b.state.enemies[0];var cfg:Dictionary=b._enemy_pacing_config(u)
		ck(is_equal_approx(float(cfg.aoeChance),.25) and cfg.get("recoveryPolicy","idle")=="idle","ordinary new enemy unchanged")
		b._record_enemy_pacing(u,"ash_moth_dust" if id=="ash_moth" else "cracked_puppet_burst")
		ck(b._enemy_choice(u,b._available(u))=="enemy_recover","ordinary enemy still low-pressure recovery")
	for id in ["boss_hedor","lamp_overseer"]:
		var b=make(id,"isStory");ck(b._enemy_pacing_config(b.state.enemies[0]).is_empty(),"story unaffected")
	var old=make("wolf");ck(old._enemy_pacing_config(old.state.enemies[0]).is_empty(),"old enemy unaffected")
	print("ELITE BOSS TEMPO V276: %d checks, %d failures"%[checks,failures]);quit(0 if failures==0 else 1)
