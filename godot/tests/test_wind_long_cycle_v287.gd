extends "res://tests/test_wind_team_recalibration_v287.gd"
func source_hashes() -> Dictionary:
 var result:Dictionary=super.source_hashes()
 result["tests/test_wind_long_cycle_v287.gd"]=FileAccess.get_sha256("res://tests/test_wind_long_cycle_v287.gd")
 result["validation/v286-team-balance/natural-report.json"]=FileAccess.get_sha256("res://validation/v286-team-balance/natural-report.json")
 return result
func profile_effects(game, counts: Dictionary) -> Array:
 var result:Array=[]
 for reward in game.catalog.AbyssData.rogue.rewards:
  for copy in range(int(counts.get(reward.id,0))):result.append_array(reward.effects.duplicate(true))
 return result
func assign_main_set(game,set_id: String) -> void:
 for item in game.state.relics:
  if item.equippedBy=="tiya":item.setId="" if item.slotId=="necklace" else set_id
func long_cycle(game, context: Dictionary, effects: Array, initial_energy: int) -> Array:
 var production=Battle.new(game.catalog)
 production.start({"isAbyss":true,"difficulty":3,"abyssGrowthVersion":3,"floor":100,"enemies":["boss_flame_lord"],"seed":287001},game.battle_party(false),effects)
 var stats:Dictionary=production.state.allies[0].stats.duplicate(true)
 var owner_effects:Array=production.state.allies[0].ownerEffects.duplicate(true)
 var scorer=ScoreOptimizer.new(game,"tiya",context)
 scorer._battle._effects=effects.duplicate(true)
 var reference:Dictionary=scorer._reference(stats,owner_effects)
 var actor:Dictionary=reference.actor
 var target:Dictionary=reference.target
 scorer._prepare_skills(actor,target)
 for index in range(actor.skills.size()):
  var skill:Dictionary=game.catalog.SkillData[actor.skills[index]]
  var targets:int=scorer._wind_skill_targets(skill)
  var coefficient:float=(0.66 if int(actor.constellation)>=6 else 0.60)*(1.0+scorer._battle._timed_follow_up_amp(actor,"innate_piercing")+scorer._battle._effect_sum("windPrimaryAmp"))
  scorer._rewards[index]+=targets*scorer._battle.predict_effect_damage(actor,target,{"type":"follow_up","element":"wind"},{"multiplier":coefficient,"defPierce":1.0,"rawAtk":true},false,true)
  for effect in effects:
   if effect.get("type","")=="windGoldPierce":scorer._rewards[index]+=targets*scorer._battle.predict_effect_damage(actor,target,{"type":"follow_up","element":"wind"},{"multiplier":float(effect.multiplier),"defPierce":1.0,"rawAtk":true},false,true)
 var distribution:Dictionary={initial_energy*20:1.0}
 var cumulative:=0.0
 var actions:Dictionary={"normal":0.0,"skill":0.0,"ultimate":0.0}
 var output:Array=[]
 for turn in range(1,49):
  var next:Dictionary={}
  for token in distribution:
   var energy:=int(token)/20
   var cooldown:=int(token)%20
   var probability:=float(distribution[token])
   var selected:=-1
   for index in scorer._auto_skill_order:
    var skill:Dictionary=scorer._skills[index]
    if skill.type=="ultimate" and energy<int(skill.cost):continue
    if skill.type=="skill" and cooldown>0:continue
    selected=index;break
   check(selected>=0,"long cycle legal action")
   var chosen:Dictionary=scorer._skills[selected]
   actions[chosen.type]+=probability
   cumulative+=probability*float(scorer._rewards[selected])
   var after_energy:=0 if chosen.type=="ultimate" else mini(100,energy+int(chosen.gain))
   var after_cd:=maxi(0,int(chosen.cooldown)-1) if chosen.type=="skill" else maxi(0,cooldown-1)
   for branch in scorer._transitions[selected]:
    var key:=mini(100,after_energy+int(branch.energy))*20+after_cd
    next[key]=float(next.get(key,0.0))+probability*float(branch.p)
  distribution=next
  var mass:=0.0
  for p in distribution.values():mass+=float(p)
  check(absf(mass-1.0)<0.000001,"long cycle probability normalized")
  if turn in [6,24,48]:
   scorer._memo.clear();scorer._policy_optimal=false
   var native_kernel:float=scorer._value(turn,initial_energy,0)
   check(absf(native_kernel-cumulative)<0.001,"forward expectation equals production recurrence "+str(turn))
   output.append({"actions":turn,"expectedDamage":cumulative,"damagePerAction":cumulative/turn,"skillCounts":actions.duplicate(true),"stats":stats,"initialEnergy":initial_energy,"stateCount":distribution.size()})
 return output
func run() -> void:
 started_ms=Time.get_ticks_msec()
 var hashes_before:=source_hashes()
 var prior:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://validation/v287-team-balance/report.json"))
 var natural:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://validation/v286-team-balance/natural-report.json"))
 var natural_counts:Dictionary={}
 for route in natural.routes:
  if route.variant=="wind_current":natural_counts=route.battles[-1].blessings.duplicate(true)
 check(int(natural_counts.get("common_energy_white",0))==1,"natural energy white count1")
 var profiles:Array=[{"name":"low_def_zero_blessings","context":{"enemyCount":3,"enemyDefense":100.0,"otherSpeed":100.0},"counts":{},"initialEnergy":0}]
 for energy_copies in [1,4,8]:
  var counts:Dictionary=natural_counts.duplicate(true)
  counts.common_energy_white=energy_copies
  profiles.append({"name":"high_def_natural_energy"+str(energy_copies),"context":{"enemyCount":1,"enemyDefense":35032.0,"otherSpeed":379.0},"counts":counts,"initialEnergy":100})
 var output:Array=[]
 for seed_value in [286031,286032]:
  var basis:=make_basis(seed_value)
  for constellation in [0,6]:
   for profile in profiles:
    for set_id in ["wind_blades","thunder_hunt","wind_voyager"]:
     var game=make_game(basis,constellation,"wind_current")
     assign_main_set(game,set_id)
     var effects:Array=profile_effects(game,profile.counts)
     var result:Array=long_cycle(game,profile.context,effects,int(profile.initialEnergy))
     if profile.name=="low_def_zero_blessings":
      for old in prior.expectedSets:
       if old.character=="tiya" and int(old.seed)==seed_value and int(old.constellation)==constellation and is_equal_approx(float(old.context.enemyDefense),100.0):check(absf(float(result[0].expectedDamage)-float(old.scores[set_id]))<0.001,"reproduce prior six-action expectation")
     output.append({"seed":seed_value,"constellation":constellation,"profile":profile.name,"set":set_id,"context":profile.context,"blessingCounts":profile.counts,"windows":result})
 var report:Dictionary={"scope":"Tiya-only deterministic expected output and energy cycle, not total-team or natural-route simulation. Uses production expected hit damage and exact crit-trigger energy branches/auto priority/cooldown/100-energy cap; forward distribution independently equals production recurrence at6/24/48 actions. Lumi15 deepening and signature40 innate amp maintained throughout; teammates supply only these fixed buffs, no actions or damage. Low-defense3-target case has zero blessings and zero starting energy. High-defense1-target case reuses actual88-blessing floor100 natural wind snapshot with100 opening energy; energy1 is observed, energy4/8 are equal-cost sensitivity profiles shared across compared sets, not observed acquisition. Invincible neutral targets, no incoming damage, all statuses maintained; no claim about all content or exact long-run win rate.","rows":output,"checks":checks,"failures":failures,"elapsedMs":Time.get_ticks_msec()-started_ms,"sourceHashesBefore":hashes_before,"sourceHashesAfter":source_hashes()}
 var file=FileAccess.open("res://validation/v287-team-balance/long-cycle.json",FileAccess.WRITE)
 if file:file.store_string(JSON.stringify(report,"  "))
 print("WIND_LONG_CYCLE_V287 ",checks," checks / ",failures.size()," failures; ms=",Time.get_ticks_msec()-started_ms)
 quit(1 if not failures.is_empty() else 0)
