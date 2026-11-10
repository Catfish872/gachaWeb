extends "res://tools/audit_thunder_natural_v290.gd"
func ex_counts(ex)->void:
 selected_counts={}
 for reward in ex.run().get("blessings",[]):selected_counts[reward.id]=int(selected_counts.get(reward.id,0))+1
func room_score(room:Dictionary)->int:
 if room.get("locked",false) or room.get("visited",false):return -10000
 return {"boss":1000,"rest":900,"hospital":900,"shrine":800,"workshop":700,"event":600,"battle":500,"elite":450,"vault":400,"key_vault":-100,"start":-200}.get(str(room.type),100)-int(room.tier)
func service_score(action:Dictionary,ex)->float:
 var effect:Dictionary=action.get("presentationEffect",{});var low:=false
 for unit in ex.run().party:
  if float(unit.currentHp)/maxf(1,float(unit.maxHp))<.75:low=true
 var value:float=0
 if effect.has("heal"):value+=float(effect.heal)*(1000 if low else 100)
 if effect.get("revive",false):
  for unit in ex.run().party:
   if unit.currentHp<=0:value+=1000
 if effect.has("blessing"):value+=200 if effect.blessing=="gold" else 150 if effect.blessing=="blue" else 100
 value+=float(effect.get("energy",0))*1.5
 value-=float(effect.get("hpCost",0))*200
 value-=float(action.get("cost",0))*.1
 if effect.has("battle"):value-=100
 return value
func run()->void:
 started_ms=Time.get_ticks_msec();var before:Dictionary=source_hashes();var routes:Array=[]
 for seed_value in [290061,290062,290063,290064]:
  for stage in [{"id":"developing","rarity":4,"upgrade":12,"level":5,"difficulty":0},{"id":"built","rarity":5,"upgrade":25,"level":10,"difficulty":2},{"id":"advanced","rarity":5,"upgrade":25,"level":10,"difficulty":3}]:
   var basis:Dictionary=natural_basis(seed_value,stage.rarity,stage.upgrade)
   for rank in [0,6]:
    for team in TEAMS:
     var game=natural_game(basis,rank,team,stage.level);game.rng.seed=seed_value;game.state.extraction.unlockedDifficulty=5
     var ex=game.extraction
     if not must(ex.start_run(stage.difficulty),"native extraction start"):continue
     var report:Dictionary={"team":team,"rank":rank,"seed":seed_value,"stage":stage,"environments":ex.run().environmentOrder.duplicate(),"battles":[],"decisions":[],"outcome":"active"}
     var route_start:=Time.get_ticks_msec()
     for guard in range(250):
      if not ex.active():report.outcome=game.state.extraction.lastRun.outcome;report.lastRun=game.state.extraction.lastRun.duplicate(true);break
      ex_counts(ex)
      var choices:Array=ex.growth_choices()
      if not choices.is_empty():
       choices.sort_custom(func(a,b):return reward_score(a.id,"balanced")>reward_score(b.id,"balanced"))
       report.decisions.append({"kind":"blessing","act":ex.run().act,"choice":choices[0].id,"offered":choices.map(func(x):return x.id)})
       if not must(ex.choose_growth(choices[0].choiceId),"native extraction blessing"):report.outcome="blessing_blocker";break
       continue
      var phase:String=ex.run().phase
      if phase=="battle":
       var battle=Battle.new(game.catalog);var prepared:Dictionary=ex.start_battle(battle)
       if not must(prepared,"native extraction battle"):report.outcome="battle_blocker";break
       var stats:Dictionary=metric();var steps:=0
       while battle.state.phase not in ["victory","defeat"] and steps<500:
        var action:Dictionary=battle.auto_step();check(action.get("success",false),"native extraction action");accumulate(battle,stats,action.get("events",[]));steps+=1
       var hp:float=0;var maximum:float=0;var alive:=0
       for unit in battle.state.allies:hp+=unit.currentHp;maximum+=unit.maxHp;alive+=int(unit.currentHp>0)
       report.battles.append({"act":ex.run().act,"node":ex.run().node,"kind":prepared.config.kind,"environment":ex.environment_theme(),"enemies":prepared.config.enemies,"result":battle.state.phase,"round":battle.state.turn,"hpRatio":hp/maxf(1,maximum),"alive":alive,"blessingTotal":ex.run().blessings.size(),"blessings":selected_counts.duplicate(true),"metrics":stats})
       if battle.state.phase not in ["victory","defeat"]:report.outcome="battle_censored";break
       if not must(ex.settle_battle(prepared.config,battle.state),"native extraction settlement"):report.outcome="settlement_blocker";break
       continue
      if phase=="boss_exit":
       if int(ex.run().act)==ex.max_acts():
        if not must(ex.extract(),"native final extract"):report.outcome="extraction_blocker";break
       elif not must(ex.continue_act(),"native next act"):report.outcome="act_blocker";break
       continue
      if phase=="room":
       var actions:Array=ex.room_actions().filter(func(a):return a.enabled)
       if not actions.is_empty():
        actions.sort_custom(func(a,b):return service_score(a,ex)>service_score(b,ex))
        report.decisions.append({"kind":"service","act":ex.run().act,"room":ex.run().room.id,"choice":actions[0].id})
        if not must(ex.choose_room_action(actions[0].id),"native room service"):report.outcome="service_blocker";break
        continue
       if not must(ex.advance_room(),"native room exit"):report.outcome="route_blocker";break
      var options:Array=ex.route_options().filter(func(x):return not x.get("visited",false) and not x.get("locked",false))
      options.sort_custom(func(a,b):return room_score(a)>room_score(b))
      if options.is_empty():report.outcome="no_reachable_room";check(false,"extraction reachable room");break
      report.decisions.append({"kind":"route","act":ex.run().act,"room":options[0].id,"type":options[0].type})
      if not must(ex.choose_route(options[0].id),"native extraction room"):report.outcome="enter_blocker";break
     report.elapsedMs=Time.get_ticks_msec()-route_start;routes.append(report)
     print("THUNDER_NATURAL_EXTRACTION ",seed_value," ",stage.id," C",rank," ",team," ",report.outcome," battles=",report.battles.size())
 var after:Dictionary=source_hashes();check(before==after,"extraction production snapshot stable")
 var report:Dictionary={"scope":"96 native three-act extraction routes, four paired seeds, four teams, C0/C6. Developing Lv5 four-star+12 at rank0; built Lv10 five-star+25 at rank2 and advanced rank3. Real generated maps, enemy themes, reachable rooms, service choices, growth offers, persistent HP/energy/cooldowns, battle XP, engine-bound settlement and final extraction. Fixed route policy prefers available boss after unlock, otherwise rest/hospital/shrine/workshop before combat; service policy favors healing when injured and blessings/energy otherwise. No injected blessings, forced victories or enemy edits. No consumables or tactical armor supplied, so results are a consistent lean-supply route, not optimal play. Natural reward offerings may diverge. Limited500 actions per battle and250 route decisions; censoring distinct from defeat. Four seeds are functional/progression evidence rather than win rates.","routes":routes,"checks":checks,"failures":failures,"sourceHashesBefore":before,"sourceHashesAfter":after,"elapsedMs":Time.get_ticks_msec()-started_ms}
 var file=FileAccess.open("res://validation/v290-thunder/natural-extraction.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "))
 print("THUNDER_NATURAL_EXTRACTION_REPORT ",routes.size()," routes; ",checks," checks; ",failures.size()," failures; ms=",report.elapsedMs)
 quit(1 if not failures.is_empty() else 0)
