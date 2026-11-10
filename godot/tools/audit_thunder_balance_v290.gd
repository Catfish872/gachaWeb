extends "res://tests/test_wind_team_balance_v286.gd"
const Optimizer = preload("res://scripts/relic_optimizer.gd")
const AUDIT_TEAMS = {"fire":["kaldi","selin","ayla"],"wind":["tiya","lumi","ayla"],"duo":["raisa","vika","ayla"],"thunder":["raisa","vika","eve"]}
const AUDIT_SETS = {"kaldi":"flame_oath","selin":"ember_lantern","ayla":"aurora_prayer","tiya":"wind_blades","lumi":"wind_strings","raisa":"storm_armor","vika":"storm_tracer","eve":"storm_shelter"}
var audit_rows:Array=[]
func source_hashes() -> Dictionary:
 var result:Dictionary=super.source_hashes()
 for path in ["scripts/relic_optimizer.gd","scripts/relic_cycle.gd","scripts/relic_quick_optimizer.gd","scripts/extraction_model.gd","data/extraction.json","tools/audit_thunder_balance_v290.gd"]:result[path]=FileAccess.get_sha256("res://"+path)
 return result
func metric() -> Dictionary:
 var result:Dictionary=super.metric();result.bySegment={};return result
func accumulate(battle,stats:Dictionary,events:Array)->void:
 super.accumulate(battle,stats,events)
 for event in events:
  if event.get("type","")!="damage":continue
  var target:Dictionary=battle.get_unit(str(event.get("target","")))
  if target.is_empty() or target.isAlly:continue
  var key:String=str(event.get("skill_id",event.get("status","unknown")))+("/piercing" if float(event.get("defPierce",0))>=1.0 else "/ordinary")
  stats.bySegment[key]=float(stats.bySegment.get(key,0.0))+float(event.amount)
func audit_game(basis:Dictionary, rank:int, team:String):
 var game=Game.new("")
 prepare_characters(game,AUDIT_TEAMS[team],rank)
 for index in range(3):
  var id:String=AUDIT_TEAMS[team][index]
  equip(game,id,basis[["tiya","lumi","ayla"][index]],AUDIT_SETS[id])
 return game
func audit_plan(game, count:int, team:String)->Dictionary:
 if count==0:return {"effects":[],"counts":{},"total":0,"rarities":{"white":0,"blue":0,"gold":0}}
 var pools:Dictionary={
  "fire":{"white":["common_atk_white","kaldi_burn_amp_white","selin_burn_duration_white","ayla_heal_amp_white"],"blue":["common_vampiric_blue","kaldi_ult_burn_blue","selin_burn_energy_blue","ayla_regen_guard_blue"],"gold":["kaldi_start_burn_gold","kaldi_burn_execute_gold","selin_burn_amp_gold","ayla_heal_regen_gold"]},
  "wind":{"white":["common_atk_white","wind_opening_white","tiya_follow_white","ayla_heal_amp_white"],"blue":["common_vampiric_blue","wind_linked_blue","tiya_rhythm_blue","ayla_regen_guard_blue"],"gold":["lumi_open_gold","wind_pierce_gold","tiya_follow_gold","ayla_heal_regen_gold"]},
  "duo":{"white":["common_atk_white","thunder_shelter_white","raisa_charge_white","ayla_heal_amp_white"],"blue":["common_vampiric_blue","thunder_mark_blue","raisa_armor_blue","ayla_regen_guard_blue"],"gold":["vika_open_gold","thunder_link_gold","raisa_armor_gold","ayla_heal_regen_gold"]},
  "thunder":{"white":["common_atk_white","thunder_shelter_white","raisa_charge_white","eve_shield_white"],"blue":["common_vampiric_blue","thunder_mark_blue","raisa_armor_blue","eve_guard_blue"],"gold":["vika_open_gold","thunder_link_gold","raisa_armor_gold","eve_dawn_gold"]}}
 var counts:Dictionary={};var rarities:Dictionary={"white":0,"blue":0,"gold":0}
 # Equal 4/4/4 portfolio; higher-count sensitivity retains equal common utility.
 for rarity in ["white","blue","gold"]:
  for id in pools[team][rarity]:add_reward(game,counts,id,rarity);rarities[rarity]+=1
 if count>12:
  var extras:Dictionary={"white":["common_atk_white","common_hp_white","common_def_white"],"blue":["common_vampiric_blue"],"gold":["common_guard_gold"]}
  for index in range(count-12):
   var rarity:String=["white","white","blue","white","blue","gold"][index%6]
   var ids:Array=extras[rarity];add_reward(game,counts,ids[(index/6)%ids.size()],rarity);rarities[rarity]+=1
 var effects:Array=[]
 for reward in game.catalog.AbyssData.rogue.rewards:
  for copy in range(int(counts.get(reward.id,0))):
   for original in reward.effects:
    var effect:Dictionary=original.duplicate(true);effect.rewardId=reward.id;effect.rewardInstanceId=reward.id+"_audit_"+str(copy);effects.append(effect)
 return {"effects":effects,"counts":counts,"total":count,"rarities":rarities}
func audit_pressure(game,effects:Array,config:Dictionary)->Dictionary:
 var battle=Battle.new(game.catalog)
 battle.start(config,game.battle_party(false),effects)
 var stats:Dictionary=metric();stats.initialEnemies=[]
 for enemy in battle.state.enemies:stats.initialEnemies.append({"id":enemy.id,"stats":enemy.stats.duplicate(true)})
 var guard:=0
 while battle.state.phase not in ["victory","defeat"] and guard<600 and int(battle.state.turn)<=40:
  var actor:Dictionary=battle.current_actor()
  if not actor.is_empty():
   if actor.isAlly:stats.allyActions+=1
   else:stats.enemyActions+=1
  var step:Dictionary=battle.auto_step();check(step.get("success",false),"actual battle step")
  accumulate(battle,stats,step.get("events",[]));guard+=1
 stats.result=battle.state.phase if battle.state.phase in ["victory","defeat"] else "censored";stats.round=battle.state.turn;stats.alive=0;stats.hp=0;stats.maxHp=0;stats.enemyHp=0;stats.enemyMaxHp=0
 for ally in battle.state.allies:
  stats.alive+=int(ally.currentHp>0);stats.hp+=ally.currentHp;stats.maxHp+=ally.maxHp
 for enemy in battle.state.enemies:stats.enemyHp+=enemy.currentHp;stats.enemyMaxHp+=enemy.maxHp
 return stats
func audit_output(game,effects:Array,config:Dictionary)->Dictionary:
 var battle=Battle.new(game.catalog)
 battle.start(config,game.battle_party(false),effects)
 for enemy in battle.state.enemies:enemy.maxHp=1000000000;enemy.currentHp=enemy.maxHp;enemy.stats.maxHp=enemy.maxHp;enemy.element="neutral"
 var stats:Dictionary=metric();var windows:Dictionary={}
 for round_index in range(96):
  for ally in battle._queue.filter(func(unit):return unit.isAlly):
   var available:Array=battle._available(ally);var chosen:String=str(available[0])
   for sid in available:
    var skill:Dictionary=battle.skill_data(sid)
    if battle._hold_healing_skill(ally,skill):continue
    if skill.get("type","")=="ultimate":chosen=sid;break
    if skill.get("type","")=="skill":chosen=sid
   battle._events=[];battle._execute_skill(ally,chosen);battle._after_active_action(ally);battle._consume_action_statuses(ally)
   accumulate(battle,stats,battle._events);stats.allyActions+=1
  battle._events=[];battle._end_round();accumulate(battle,stats,battle._events);battle._build_queue()
  if round_index+1 in [6,12,24,48,96]:windows[str(round_index+1)]=stats.outgoing
 stats.windows=windows
 return stats
func extraction_config(seed_value:int,rank:int)->Dictionary:
 var game=Game.new("");game.rng.seed=seed_value;game.state.extraction.unlockedDifficulty=5
 prepare_characters(game,["kaldi","selin","ayla"],0)
 var result:Dictionary=game.extraction.start_run(rank);check(result.success,"extraction fixture starts")
 game.extraction.run().environmentOrder=["ruins","ruins","ruins"];game.extraction.run().act=3;game.extraction.run().node=4
 game.extraction._generate_encounter("boss")
 return game.extraction.run().activeEncounter.duplicate(true)
func audit_mixed()->Array:
 var rows:Array=[]
 for ids in [["vika","tiya","lumi"],["raisa","tiya","lumi"],["raisa","kaldi","selin"]]:
  var game=Game.new("");prepare_characters(game,ids,0)
  var id:String=ids[0]
  var base=Optimizer.new(game,id)
  var a:Dictionary=base.evaluate_loadout([])
  var target_status:String="wind_armor" if ids[1]=="tiya" else "burn"
  var supplied=Optimizer.new(game,id,{"targetStatuses":[target_status,"thunder_mark"] if id=="vika" else [target_status]})
  var b:Dictionary=supplied.evaluate_loadout([])
  rows.append({"team":ids,"automatic":a.objective,"explicitMaintainedTeammateStatus":b.objective,"referenceTeam":a.get("breakdown",{}).get("referenceTeam",[]),"status":target_status})
 return rows
func audit_mechanics()->Dictionary:
 var game=Game.new("");prepare_characters(game,["raisa","vika","eve"],0)
 var b=Battle.new(game.catalog);b.start({"enemies":["boss_flame_lord"],"seed":29001},game.battle_party(false))
 var eve:Dictionary=b.state.allies[2];eve.energy=100;b._execute_skill(eve,"eve_ult");b._end_round()
 var durations:Array=[]
 for st in eve.statuses:
  if st.id=="regen":durations.append(st.duration)
 check(durations==[2],"Eve ult regen lasts after passive refresh")
 var enemy:Dictionary=b.state.enemies[0]
 var max_reduction:=0.0
 b._effects=[]
 for i in range(20):b._effects.append({"type":"damageTakenWhileStatus","statusId":"shield","value":-.15})
 max_reduction=1.0-b.ordinary_damage_taken_multiplier(eve,enemy)
 check(is_equal_approx(max_reduction,0.9),"stacked ordinary shield guard cap")
 return {"eveRegenAfterFirstRound":durations,"stackedReduction":max_reduction}
func run()->void:
 started_ms=Time.get_ticks_msec()
 var hashes_before:Dictionary=source_hashes()
 var basis:Dictionary=make_basis(290031)
 var configs:Array=[]
 for floor_number in [10,50,100]:
  configs.append({"label":"abyss_"+str(floor_number),"config":{"isAbyss":true,"difficulty":3,"abyssGrowthVersion":3,"floor":floor_number,"enemies":["boss_flame_lord"],"seed":290031},"blessings":0 if floor_number==10 else 12 if floor_number==50 else 36})
 for rank in [0,3,5]:configs.append({"label":"extraction_"+str(rank),"config":extraction_config(290032,rank),"blessings":0 if rank==0 else 12})
 for rank in [0,6]:
  for scenario in configs:
   for team in AUDIT_TEAMS:
    var game=audit_game(basis,rank,team)
    if scenario.label=="abyss_10":fixtures.append({"team":team,"rank":rank,"party":game.battle_party(false),"relics":game.state.relics.duplicate(true)})
    var plan:Dictionary=audit_plan(game,int(scenario.blessings),team)
    audit_rows.append({"team":team,"rank":rank,"scenario":scenario.label,"blessingCounts":plan.counts,"blessingRarities":plan.rarities,"pressure":audit_pressure(game,plan.effects,scenario.config),"output":audit_output(game,plan.effects,scenario.config)})
 var report:Dictionary={"scope":"Independent bounded diagnostic. C0/C6; same generated legal Lv10 five-star+25 per-role relic stat rolls, each team's declared signature sets. Equal-rarity constructed portfolios use real catalog blessings but do not claim natural acquisition. Actual-mode pressure uses native auto_step, enemy elements/actions, normal deaths and 40-round censoring, abyss native difficulty3 growth, extraction native act3/node4 boss generator. Separate output windows preserve scaled defense/target count and all real blessing mechanics but neutralize enemies, make them immortal and skip enemy turns. Therefore output windows are build diagnostics, not win-rate or universally guaranteed power claims.","rows":audit_rows,"fixtures":fixtures,"mixed":audit_mixed(),"mechanics":audit_mechanics(),"checks":checks,"failures":failures,"elapsedMs":Time.get_ticks_msec()-started_ms,"sourceHashesBefore":hashes_before,"sourceHashesAfter":source_hashes()}
 DirAccess.make_dir_recursive_absolute("res://validation/v290-thunder")
 var file=FileAccess.open("res://validation/v290-thunder/independent-audit.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "))
 print("THUNDER_INDEPENDENT_AUDIT ",audit_rows.size()," contexts; ",checks," checks; ",failures.size()," failures; ms=",Time.get_ticks_msec()-started_ms)
 quit(1 if not failures.is_empty() else 0)
