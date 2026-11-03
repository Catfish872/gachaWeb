extends "res://tests/test_wind_team_balance_v286.gd"
var decision_count := 0
var shop_ledger: Array = []
var selected_counts: Dictionary = {}
func must(result: Dictionary, label: String) -> bool:
 check(bool(result.get("success",false)),label)
 return bool(result.get("success",false))
func reward_score(id: String, _style: String) -> int:
 var count := int(selected_counts.get(id,0))
 var priorities := {"common_vampiric_blue":120,"ayla_heal_regen_gold":125,"ayla_regen_guard_blue":115,"common_guard_gold":110,"common_victory_heal_blue":90,"common_atk_white":100,"common_hp_white":85,"common_def_white":80,"wind_pierce_gold":120,"kaldi_burn_execute_gold":120,"lumi_open_gold":125,"kaldi_start_burn_gold":125,"lumi_guard_blue":110,"selin_burn_energy_blue":110,"tiya_follow_gold":105,"selin_burn_amp_gold":105,"tiya_follow_white":95,"selin_burn_duration_white":95,"wind_linked_blue":90,"kaldi_burn_spread_blue":90,"wind_opening_white":90,"kaldi_burn_amp_white":90}
 if id in ["ayla_heal_regen_gold","lumi_open_gold","kaldi_start_burn_gold"] and count>=1:return 5
 if id in ["common_vampiric_blue","ayla_regen_guard_blue","common_guard_gold","lumi_guard_blue","selin_burn_energy_blue","selin_burn_duration_white"] and count>=4:return 15
 return int(priorities.get(id,50))
func refresh_counts(game) -> void:
 selected_counts={}
 for reward in game.state.abyss.rogue.selectedRewards:selected_counts[reward.id]=int(selected_counts.get(reward.id,0))+1
func run() -> void:
 started_ms=Time.get_ticks_msec()
 var hashes_before:=source_hashes()
 var basis:=make_basis(286031)
 var route_reports:Array=[]
 for variant in ["fire","wind_current","wind_legacy"]:
  var game=make_game(basis,6,variant)
  game.rng.seed=286051
  game.state.abyss.meta.unlockedDifficulty=3
  if not must(game.set_abyss_difficulty(3),"natural endless difficulty"):break
  var route:Dictionary={"variant":variant,"seed":286051,"c":6,"floorsCleared":0,"battles":[],"outcome":"active"}
  shop_ledger=[]
  var route_started_ms:=Time.get_ticks_msec()
  for floor_number in range(1,131):
   if Time.get_ticks_msec()-route_started_ms>15000:route.outcome="time_censored";break
   refresh_counts(game)
   if not resolve_nodes(game,"balanced"):route.outcome="node_blocker";break
   refresh_counts(game)
   var prep:Dictionary=game.prepare_abyss()
   if not must(prep,"natural prepare"):route.outcome="prepare_blocker";break
   var battle=Battle.new(game.catalog)
   battle.start(prep.config,game.battle_party(true),game.rogue_effects())
   var stats:=metric()
   var steps:=0
   var enemies:Array=[]
   for enemy in battle.state.enemies:enemies.append({"id":enemy.id,"stats":enemy.stats.duplicate(true)})
   while battle.state.phase not in ["victory","defeat"] and steps<500 and Time.get_ticks_msec()-route_started_ms<=15000:
    var result:Dictionary=battle.auto_step();accumulate(battle,stats,result.get("events",[]));steps+=1
   var alive:=0;var hp:=0.0;var maximum:=0.0
   for ally in battle.state.allies:
    if int(ally.currentHp)>0:alive+=1
    hp+=float(ally.currentHp);maximum+=float(ally.maxHp)
   var terminal:bool=battle.state.phase in ["victory","defeat"]
   route.battles.append({"floor":floor_number,"result":battle.state.phase if terminal else "censored","steps":steps,"round":battle.state.turn,"alive":alive,"hpRatio":hp/maxf(1.0,maximum),"enemies":enemies,"blessings":selected_counts.duplicate(true),"blessingTotal":game.state.abyss.rogue.selectedRewards.size(),"metrics":stats})
   if not terminal:route.outcome="battle_censored";break
   if not must(game.finish_battle(prep.config,battle.state),"natural settlement"):route.outcome="settlement_blocker";break
   if battle.state.phase=="defeat":route.outcome="defeat";break
   route.floorsCleared=floor_number
   if floor_number==130:route.outcome="target130"
  route.shopLedger=shop_ledger.duplicate(true);route.elapsedTotalMs=Time.get_ticks_msec()-started_ms
  route_reports.append(route)
  print("NATURAL_ROUTE ",variant," floors=",route.floorsCleared," outcome=",route.outcome," elapsed_ms=",Time.get_ticks_msec()-started_ms)
 var report:Dictionary={"routes":route_reports,"failures":failures,"checks":checks,"elapsedMs":Time.get_ticks_msec()-started_ms,"sourceHashesBefore":hashes_before,"sourceHashesAfter":source_hashes(),"scope":"C6 single seed natural climbs from floor1; same legal gear and initial cost. Native issued encounters/AI, actual reward options, shops/currency, persistent HP/energy/cooldowns and settlement. Fixed synergy-aware selection prioritizes sustain, four copies of key defensive/energy rewards then offense. Actual blessing counts can diverge and are logged. 500-step battle bound or equal15-second per-route wall budget is censored, not defeat. No optimal-policy or win-rate claim."}
 var file=FileAccess.open("res://validation/v286-team-balance/natural-report.json",FileAccess.WRITE)
 if file:file.store_string(JSON.stringify(report,"  "))
 print("NATURAL_BALANCE_V286 ",checks," checks / ",failures.size()," failures")
 quit(1 if not failures.is_empty() else 0)
func resolve_nodes(m: Variant, style: String) -> bool:
 for safe in range(20):
  var kind := str(m.state.abyss.rogue.nextStep.type)
  match kind:
   "none": return true
   "reward":
    var choices: Array = m.state.abyss.rogue.pendingChoices.duplicate(true)
    choices.sort_custom(func(a,b): return reward_score(str(a.id), style) > reward_score(str(b.id), style))
    if not must(m.choose_abyss_reward(choices[0].choiceId), "choose offered reward"): return false
   "route":
    var choices: Array = m.node_options().options
    var selected := str(choices[0].id)
    for choice in choices:
     if choice.id in ["rest", "shop"]: selected = choice.id
    if not must(m.choose_abyss_node(selected), "choose route"): return false
   "rest":
    if not must(m.choose_abyss_node("recover"), "rest recover"): return false
   "event":
    var choices: Array = m.node_options().options
    var picked := false
    for choice in choices:
     if choice.enabled:
      picked = must(m.choose_abyss_node(choice.id), "event")
      break
    if not picked: return false
   "shop":
    var items: Array = m.abyss_shop_items()
    var visit:={"floor":int(m.state.abyss.rogue.nextStep.floor),"currencyBefore":int(m.state.abyss.rogue.temporaryCurrency),"stock":[],"purchases":[]}
    for offered in items:visit.stock.append({"id":offered.id,"kind":offered.kind,"rarity":str(offered.get("rarity","")),"rewardId":str(offered.get("rewardId","")),"cost":int(offered.cost)})
    items.sort_custom(func(a,b): return (1000 if a.id == "heal" else reward_score(str(a.get("rewardId", "")), style)) > (1000 if b.id == "heal" else reward_score(str(b.get("rewardId", "")), style)))
    for item in items:
     for current in m.abyss_shop_items():
      if current.id == item.id and current.enabled:
       var before_coins:int=m.state.abyss.rogue.temporaryCurrency
       var purchase:Dictionary=m.purchase_abyss_item(current.id)
       if not must(purchase, "shop purchase"): return false
       visit.purchases.append({"id":current.id,"cost":int(purchase.cost),"kind":current.kind,"rarity":str(current.get("rarity","")),"currencyBefore":before_coins,"currencyAfter":int(m.state.abyss.rogue.temporaryCurrency)})
    visit.currencyAfter=int(m.state.abyss.rogue.temporaryCurrency);shop_ledger.append(visit)
    if not must(m.leave_abyss_shop(), "leave shop"): return false
   _:
    failures.append("unknown node: " + kind)
    return false
 failures.append("node resolution exceeded bound")
 return false

