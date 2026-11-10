extends "res://tests/test_wind_natural_balance_v286.gd"
## Native progression, not hand-picked blessing portfolios or invulnerable targets.
const TEAMS={"fire":["kaldi","selin","ayla"],"wind":["tiya","lumi","ayla"],"duo":["raisa","vika","ayla"],"thunder":["raisa","vika","eve"]}
const SETS={"kaldi":"flame_oath","selin":"ember_lantern","ayla":"aurora_prayer","tiya":"wind_blades","lumi":"wind_strings","raisa":"storm_armor","vika":"storm_tracer","eve":"storm_shelter"}
func reward_score(id:String,style:String)->int:
 var n:=int(selected_counts.get(id,0))
 var thunder:={"eve_dawn_gold":125,"eve_guard_blue":115,"eve_shield_white":100,"vika_open_gold":125,"thunder_link_gold":120,"raisa_armor_gold":110,"raisa_charge_white":100,"raisa_armor_blue":105,"thunder_mark_blue":90,"thunder_shelter_white":90,"vika_link_blue":95,"vika_mark_white":80}
 if id in ["eve_dawn_gold","vika_open_gold"] and n>=1:return 5
 if id=="eve_guard_blue" and n>=4:return 15
 return int(thunder[id]) if thunder.has(id) else super.reward_score(id,style)
func natural_basis(seed_value:int,rarity:int,upgrade:int)->Dictionary:
 var game=Game.new("");game.rng.seed=seed_value;prepare_characters(game,["tiya","lumi","ayla"],0)
 var result:Dictionary={}
 for id in ["tiya","lumi","ayla"]:
  result[id]=[]
  for slot in SLOTS:
   var best:Dictionary={};var score:float=-INF
   for draw in range(4):
    var item:Dictionary=game.generate_relic(rarity,slot,"")
    while int(item.level)<upgrade:game._upgrade_relic_one(item)
    var stats:Dictionary=game.computed_stats_for_relic_loadout(id,[item]);var value:float=stats.atk
    if id=="tiya":value*=1.0+float(stats.cri)*(float(stats.criDmg)-1.0)
    if value>score:score=value;best=item
   check(game._valid_relic(best),"natural legal gear")
   result[id].append(best)
 return result
func natural_game(basis:Dictionary,rank:int,team:String,level:int):
 var game=Game.new("");prepare_characters(game,TEAMS[team],rank)
 for i in range(3):
  var id:String=TEAMS[team][i];game.state.ownedCharacters[id].level=level
  equip(game,id,basis[["tiya","lumi","ayla"][i]],SETS[id])
 return game
func run()->void:
 started_ms=Time.get_ticks_msec();var before:Dictionary=source_hashes();var routes:Array=[]
 for seed_value in [290051,290052,290053,290054]:
  for stage in [{"id":"developing","rarity":4,"upgrade":12,"level":5,"difficulty":1,"target":50},{"id":"built","rarity":5,"upgrade":25,"level":10,"difficulty":3,"target":60}]:
   var basis:Dictionary=natural_basis(seed_value,stage.rarity,stage.upgrade)
   for rank in [0,6]:
    for team in TEAMS:
     var game=natural_game(basis,rank,team,stage.level);game.rng.seed=seed_value;game.state.abyss.meta.unlockedDifficulty=3
     if not must(game.set_abyss_difficulty(stage.difficulty),"natural selected difficulty"):continue
     var report:Dictionary={"team":team,"rank":rank,"seed":seed_value,"stage":stage,"floorsCleared":0,"battles":[],"outcome":"active"}
     shop_ledger=[];var route_start:=Time.get_ticks_msec()
     for floor_number in range(1,int(stage.target)+1):
      refresh_counts(game)
      if not resolve_nodes(game,"balanced"):report.outcome="node_blocker";break
      refresh_counts(game)
      var prep:Dictionary=game.prepare_abyss()
      if not must(prep,"natural prepare"):report.outcome="prepare_blocker";break
      var battle=Battle.new(game.catalog);battle.start(prep.config,game.battle_party(true),game.rogue_effects())
      var stats:Dictionary=metric();var steps:=0
      while battle.state.phase not in ["victory","defeat"] and steps<500:
       var step:Dictionary=battle.auto_step();check(step.get("success",false),"native natural action");accumulate(battle,stats,step.get("events",[]));steps+=1
      var hp:float=0;var maximum:float=0;var alive:=0
      for ally in battle.state.allies:hp+=ally.currentHp;maximum+=ally.maxHp;alive+=int(ally.currentHp>0)
      var terminal:bool=battle.state.phase in ["victory","defeat"]
      report.battles.append({"floor":floor_number,"result":battle.state.phase if terminal else "censored","round":battle.state.turn,"alive":alive,"hpRatio":hp/maxf(1.0,maximum),"blessings":selected_counts.duplicate(true),"blessingTotal":game.state.abyss.rogue.selectedRewards.size(),"metrics":stats})
      if not terminal:report.outcome="battle_censored";break
      if not must(game.finish_battle(prep.config,battle.state),"native natural settlement"):report.outcome="settlement_blocker";break
      if battle.state.phase=="defeat":report.outcome="defeat";break
      report.floorsCleared=floor_number
      if floor_number==int(stage.target):report.outcome="target_reached"
     report.shopLedger=shop_ledger.duplicate(true);report.elapsedMs=Time.get_ticks_msec()-route_start;routes.append(report)
     print("THUNDER_NATURAL ",seed_value," ",stage.id," C",rank," ",team," cleared=",report.floorsCleared," ",report.outcome)
 var after:Dictionary=source_hashes();check(before==after,"natural production snapshot stable")
 var result:Dictionary={"scope":"64 native abyss climbs, four paired seeds, C0/C6. Developing Lv5 four-star+12 gear, difficulty1 to50; built Lv10 five-star+25 gear, endless3 to60. Equal per-role legal relic rolls chosen from4 candidates per slot, each team's signature set. Real issued encounters, AI, persistent HP/energy/cooldowns, reward choices, shops and currency, battle XP and settlement. Synergy-aware fixed selection prioritizes healing/defense, then offense; new thunder priorities mirror existing fire/wind utility. No manual blessings, immortal enemies, enemy stat edits or forced victories. Natural offerings and resulting blessing counts may diverge. Each battle limited500 actions; censored is not defeat. Four seeds establish functional/progression evidence, not statistical win rates.","routes":routes,"checks":checks,"failures":failures,"sourceHashesBefore":before,"sourceHashesAfter":after,"elapsedMs":Time.get_ticks_msec()-started_ms}
 var file=FileAccess.open("res://validation/v290-thunder/natural-abyss.json",FileAccess.WRITE);file.store_string(JSON.stringify(result,"  "))
 print("THUNDER_NATURAL_REPORT ",routes.size()," routes; ",checks," checks; ",failures.size()," failures; ms=",result.elapsedMs)
 quit(1 if not failures.is_empty() else 0)
