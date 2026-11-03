extends "res://tests/test_wind_team_recalibration_v287.gd"
## Read-only design diagnostic. No production catalog mutation is persisted.
## One mean five-star upgrade roll: 0.8 times the midpoint of the base range.
const ROLLS := {"atk_flat":20.0,"atk_pct":0.034,"cri_rate":0.028,"cri_dmg":0.044,"energy_rate":0.048}
var value_rows: Array=[]
func change_set(game, id: String, set_id: String, stat: String="", rolls: int=0) -> void:
 for index in range(game.state.relics.size()):
  var item: Dictionary=game.state.relics[index]
  if item.equippedBy!=id:continue
  var slot_index: int=SLOTS.find(item.slotId)
  item.setId=""
  if slot_index<4:item.setId=("wind_blades" if slot_index<2 else "ember_lantern") if set_id=="atk22" else set_id
  if slot_index==4 and rolls>0:
   # Net attribute-budget sensitivity, not a claim this exact item can drop.
   item.subStats.append({"stat":stat,"name":stat,"value":float(ROLLS[stat])*rolls})
func effects_for(game, counts: Dictionary) -> Array:
 var result: Array=[]
 for reward in game.catalog.AbyssData.rogue.rewards:
  for copy in range(int(counts.get(reward.id,0))):result.append_array(reward.effects.duplicate(true))
 return result
func value_game(game, context: Dictionary, effects: Array) -> Dictionary:
 var live=Battle.new(game.catalog)
 live.start({"isAbyss":true,"difficulty":3,"abyssGrowthVersion":3,"floor":100,"enemies":["boss_flame_lord"],"seed":289001},game.battle_party(false),effects)
 var scorer=ScoreOptimizer.new(game,"tiya",context)
 scorer._battle._effects=effects.duplicate(true)
 scorer._wind_team_specs.clear() # Constructor snapshots already populated this cache.
 for unit in live.state.allies:
  if unit.id!="tiya":scorer._wind_team_specs.append({"id":unit.id,"stats":unit.stats.duplicate(true),"constellation":unit.constellation,"ownerEffects":unit.ownerEffects.duplicate(true)})
 var main: Dictionary=live.state.allies[0]
 var reference: Dictionary=scorer._reference(main.stats,main.ownerEffects)
 check(scorer._battle.state.allies.size()==3,"exactly three declared reference allies")
 var output: Dictionary={"teamDamage":0.0,"units":{}}
 for unit in scorer._battle.state.allies:
  scorer._prepare_skills(unit,reference.target)
  for skill_index in range(unit.skills.size()):
   var skill: Dictionary=game.catalog.SkillData[unit.skills[skill_index]]
   var counts: Array=[]
   counts.resize(int(context.enemyCount));counts.fill(0)
   for effect in skill.effects:
    if effect.type!="damage":continue
    var hit_count: int=int(context.enemyCount) if effect.get("target","") in ["all","all_enemies","chain3"] else 1
    for target_index in range(hit_count):counts[target_index]+=1
   for hit_count in counts:
    if int(hit_count)>0 and unit.passiveId=="tiya_passive":
     var coefficient: float=(0.66 if int(unit.constellation)>=6 else 0.60)*(1.0+scorer._battle._timed_follow_up_amp(unit,"innate_piercing")+scorer._battle._effect_sum("windPrimaryAmp"))
     scorer._rewards[skill_index]+=scorer._battle.predict_effect_damage(unit,reference.target,{"type":"follow_up","element":"wind"},{"multiplier":coefficient,"defPierce":1.0,"rawAtk":true},false,true)
    if int(hit_count)>=2:
     for effect in effects:
      if effect.get("type","")=="windGoldPierce":scorer._rewards[skill_index]+=scorer._battle.predict_effect_damage(unit,reference.target,{"type":"follow_up","element":"wind"},{"multiplier":float(effect.multiplier),"defPierce":1.0,"rawAtk":true},false,true)
  var cycle: Dictionary=scorer._current_cycle()
  check(bool(cycle.get("success",false)),"set-value exact cycle "+unit.id)
  var value: float=scorer._weighted_reward(scorer._rewards,cycle.get("skillWeights",[]))
  check(not output.units.has(unit.id),"reference ally counted exactly once "+unit.id)
  output.units[unit.id]={"damage":value,"stats":unit.stats.duplicate(true),"skillWeights":cycle.get("skillWeights",[])}
  output.teamDamage+=value
 var summed: float=0.0
 for item in output.units.values():summed+=float(item.damage)
 check(absf(summed-float(output.teamDamage))<0.00001,"team value equals unique actor components")
 return output
func scenario_game(basis: Dictionary, constellation: int, early: bool, legacy: bool=false):
 var game=make_game(basis,constellation,"wind_legacy" if legacy else "wind_current")
 if early:
  for id in game.state.team:game.state.ownedCharacters[id].level=1
 return game
func run() -> void:
 started_ms=Time.get_ticks_msec()
 var hashes: Dictionary=source_hashes()
 hashes["scripts/relic_optimizer.gd"]=FileAccess.get_sha256("res://scripts/relic_optimizer.gd")
 hashes["scripts/relic_cycle.gd"]=FileAccess.get_sha256("res://scripts/relic_cycle.gd")
 var natural: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://validation/v286-team-balance/natural-report.json"))
 var natural_counts: Dictionary={}
 for route in natural.routes:
  if route.variant=="wind_current":natural_counts=route.battles[-1].blessings.duplicate(true)
 for seed_value in [286031,286032]:
  for early in [true,false]:
   var basis: Dictionary=early_basis(seed_value) if early else make_basis(seed_value)
   for constellation in [0,6]:
    var profiles: Array=[{"name":"low_def_3","enemyCount":3,"enemyDefense":100.0,"otherSpeed":100.0,"counts":{}}]
    if not early:
     profiles.append({"name":"mid_def_1","enemyCount":1,"enemyDefense":1771.0,"otherSpeed":285.0,"counts":{}})
     profiles.append({"name":"high_natural_1","enemyCount":1,"enemyDefense":35032.0,"otherSpeed":379.0,"counts":natural_counts})
    for profile in profiles:
     var context: Dictionary={"enemyCount":profile.enemyCount,"enemyDefense":profile.enemyDefense,"otherSpeed":profile.otherSpeed,"evaluation":"steady"}
     var base_game=scenario_game(basis,constellation,early)
     var effects: Array=effects_for(base_game,profile.counts)
     var full: Dictionary=value_game(base_game,context,effects)
     var old: Dictionary=value_game(scenario_game(basis,constellation,early,true),context,effects)
     for id in ["tiya","lumi"]:
      var signature: String="wind_blades" if id=="tiya" else "wind_strings"
      var scores: Dictionary={}
      for set_id in base_game.catalog.RelicSets.keys()+["atk22"]:
       var game=scenario_game(basis,constellation,early)
       change_set(game,id,set_id)
       scores[set_id]=value_game(game,context,effects)
      var sensitivity: Dictionary={}
      for stat in ROLLS:
       var tests: Array=[]
       for roll_count in [1,2,4,8]:
        var game=scenario_game(basis,constellation,early)
        change_set(game,id,"atk22",stat,roll_count)
        tests.append({"rolls":roll_count,"value":value_game(game,context,effects)})
       sensitivity[stat]=tests
      value_rows.append({"seed":seed_value,"early":early,"constellation":constellation,"character":id,"signature":signature,"profile":profile.name,"context":context,"blessingCounts":profile.counts,"full":full,"legacy":old,"sets":scores,"sensitivity":sensitivity})
 var after: Dictionary=source_hashes()
 after["scripts/relic_optimizer.gd"]=FileAccess.get_sha256("res://scripts/relic_optimizer.gd")
 after["scripts/relic_cycle.gd"]=FileAccess.get_sha256("res://scripts/relic_cycle.gd")
 check(hashes==after,"set-value production sources stable")
 var report: Dictionary={"scope":"Exact long-run direct-skill plus innate/gold wind follow-up output per one action per ally, with maintained armor and Baiqiao buff. Same legal generated gear rerouted between sets; mean-upgrade-roll net-attribute sensitivity is not a drop/inventory reconstruction. No enemy actions, speed timeline, buff expiry, HP, healing, poison/common triggered damage or natural route. High profile reuses actual historical88-blessing floor100 snapshot; no new acquisition claim. Lumi team gains are full team deltas, never her marginal optimizer score mislabeled as total damage. Legacy is immutable complete pre-change catalog. These design diagnostics do not supersede paired actual pressure/six-round balance results.","rolls":ROLLS,"rows":value_rows,"checks":checks,"failures":failures,"elapsedMs":Time.get_ticks_msec()-started_ms,"sourceHashesBefore":hashes,"sourceHashesAfter":after}
 DirAccess.make_dir_recursive_absolute("res://validation/v289-wind-set-value")
 var file=FileAccess.open("res://validation/v289-wind-set-value/report.json",FileAccess.WRITE)
 check(file!=null,"write set-value report")
 if file:file.store_string(JSON.stringify(report,"  "));file.close()
 print("WIND_SET_VALUE_V289 ",checks," checks / ",failures.size()," failures; rows=",value_rows.size()," elapsed_ms=",Time.get_ticks_msec()-started_ms)
 quit(1 if not failures.is_empty() else 0)
