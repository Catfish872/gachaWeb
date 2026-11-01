extends SceneTree
const Battle=preload('res://scripts/battle_model.gd')
const OLD=[675,1000,1350,1625]
const NEW=[900,1350,1800,2200]
class ClockGame:
 extends 'res://scripts/game_model.gd'
 var clock_ms:int=1793570399999
 func _now()->int:return clock_ms
var checks:=0
var failures:=0
func ck(value:bool,label:String)->void:
 checks+=1
 if not value:failures+=1;printerr('FAIL DAILY UPGRADE: '+label)
func prepared(g,floor_number:int,rank:int)->Dictionary:
 g.reset_abyss();g.state.abyss.meta.unlockedDifficulty=3;g.state.abyss.meta.selectedDifficulty=rank
 g.prepare_abyss();g._issued_config={};g.state.abyss.rogue.activeEncounter={}
 g.state.abyss.currentFloor=floor_number;g.state.abyss.rogue.floorsCleared=floor_number-1
 g.state.abyss.savedPartyState=[]
 for unit in g.battle_party(false):g.state.abyss.savedPartyState.append({'id':unit.id,'currentHp':unit.maxHp,'maxHp':unit.maxHp,'energy':0,'cooldowns':{}})
 return g.prepare_abyss()
func won(g,config:Dictionary)->Dictionary:
 # Settlement fixture, not a balance/performance claim: deterministic strong
 # combat stats isolate the ledger while still producing an engine victory.
 var battle=Battle.new(g.catalog);battle.start(config,g.battle_party(true),g.rogue_effects())
 for ally in battle.state.allies:ally.stats.atk=100000000;ally.stats.spd=10000
 var steps:=0
 while battle.state.phase not in ['victory','defeat'] and steps<5000:battle.auto_step();steps+=1
 ck(battle.state.phase=='victory','real prepared encounter produces a valid victory state')
 return battle.state
func claim(g,floor_number:int,rank:int)->Dictionary:
 var prep:Dictionary=prepared(g,floor_number,rank)
 ck(prep.success,'issue actual milestone encounter')
 var wallet:int=g.state.resources.diamonds
 var result:Dictionary=g.finish_battle(prep.config,won(g,prep.config))
 ck(result.success and g.state.resources.diamonds-wallet==int(result.dailyAward.amount),'actual settlement credits only reported daily difference')
 return result
func legacy_ledger(g,rank:int)->void:
 g.state.abyss.meta.unlockedDifficulty=3;g.state.abyss.meta.selectedDifficulty=rank
 g.state.resources.diamonds=123456
 g.state.abyss.daily={'dayKey':g.abyss_daily_status().dayKey,'paid':{}}
 for floor_number in [10,20,30,40,50]:g.state.abyss.daily.paid[str(floor_number)]=OLD[rank]
 ck(g.valid_save(g.state),'legacy per-milestone paid ledger remains valid')
func _initialize()->void:call_deferred('run')
func run()->void:
 for rank in range(4):
  var folder='/tmp/voidrift-daily-upgrade-%d-%d'%[Time.get_ticks_usec(),rank]
  var old=ClockGame.new(folder);legacy_ledger(old,rank)
  ck(old.save_game(),'persist actual legacy-rate ledger fixture')
  var old_wallet:int=old.state.resources.diamonds
  var ledger:Dictionary=old.state.abyss.daily.duplicate(true)
  var game=ClockGame.new(folder)
  ck(game.state.resources.diamonds==old_wallet and JSON.parse_string(JSON.stringify(game.state.abyss.daily))==JSON.parse_string(JSON.stringify(ledger)),'loading new rules never silently credits a rate increase')
  var before:Dictionary=game.state.duplicate(true);var rng_before:int=game.rng.state
  for i in 20:
   var daily:Dictionary=game.abyss_daily_status()
   ck(daily.reward==NEW[rank] and daily.remaining==NEW[rank]-OLD[rank],'pure daily view reports exact same-rank top-up')
  ck(game.state==before and game.rng.state==rng_before,'reading new entitlement leaves save and RNG unchanged')
  for floor_number in [10,20,30,40,50]:
   var result:Dictionary=claim(game,floor_number,rank)
   ck(result.dailyAward.amount==[225,350,450,575][rank] and result.dailyAward.previousPaid==OLD[rank] and result.dailyAward.totalPaid==NEW[rank],'each old milestone receives only its same-rank difference')
   ck(claim(game,floor_number,rank).dailyAward.amount==0,'replaying paid milestone cannot claim the difference twice')
  ck(game.abyss_daily_status().paidToday==NEW[rank]*5,'daily ledger equals five new entitlements, not five old plus five new awards')
  ck(game.save_game(),'persist topped-up ledger')
  var reloaded=ClockGame.new(folder)
  ck(reloaded.state.resources.diamonds==game.state.resources.diamonds and JSON.parse_string(JSON.stringify(reloaded.state.abyss.daily))==JSON.parse_string(JSON.stringify(game.state.abyss.daily)),'disk reload after top-up grants nothing extra')
  ck(claim(reloaded,10,3).dailyAward.amount==NEW[3]-NEW[rank],'higher difficulty grants only the maximum entitlement difference')
  ck(claim(reloaded,10,0).dailyAward.amount==0,'lower difficulty never refunds or duplicates paid high-rank entitlement')
  var day:int=reloaded.abyss_daily_status().dayKey
  reloaded.clock_ms=(day+1)*86400000-7200000-1
  ck(reloaded.abyss_daily_status().dayKey==day,'one millisecond before UTC8 six retains old claim day')
  reloaded.clock_ms+=1
  ck(reloaded.abyss_daily_status().paidToday==0,'exact UTC8 six starts a fresh daily ledger view')
  ck(claim(reloaded,10,rank).dailyAward.amount==NEW[rank],'new day grants the full new same-rank entitlement')
  reloaded.clock_ms-=86400000
  ck(claim(reloaded,10,rank).dailyAward.amount==0,'clock rollback cannot replay the new daily grant')
 # Save failure must roll back every asset/ledger, and retry the same token once.
 var game=ClockGame.new('');legacy_ledger(game,0)
 var prep:Dictionary=prepared(game,10,0);var outcome:Dictionary=won(game,prep.config)
 var before:Dictionary=game.state.duplicate(true);game.save_blocked=true
 ck(not game.finish_battle(prep.config,outcome).success and game.state==before,'failed write rolls back daily top-up, relic, XP and wallet atomically')
 game.save_blocked=false
 ck(game.finish_battle(prep.config,outcome).dailyAward.amount==225,'retry grants exactly the missing top-up')
 ck(not game.finish_battle(prep.config,outcome).success,'same settlement token remains replay-protected')
 # Paired old/new configurations demonstrate rates do not change encounter,
 # relic, XP or combat RNG. Only the daily diamond ledger/wallet may differ.
 for rank in range(4):
  var a=ClockGame.new('');legacy_ledger(a,rank)
  var b=ClockGame.new('');b.state=a.state.duplicate(true)
  a.rogue_data.dailyDiamondsPer10=OLD.duplicate();a.rng.seed=250901+rank;b.rng.seed=250901+rank
  var pa:Dictionary=prepared(a,10,rank);var pb:Dictionary=prepared(b,10,rank)
  ck(pa.config==pb.config and a.rng.state==b.rng.state,'rate change does not alter issued enemies, relic roll or preparation RNG')
  var wa:Dictionary=won(a,pa.config);var wb:Dictionary=won(b,pb.config)
  ck(wa==wb,'same actual combat outcome under old and new diamond rules')
  var ra:Dictionary=a.finish_battle(pa.config,wa);var rb:Dictionary=b.finish_battle(pb.config,wb)
  ck(ra.success and rb.success and ra.relic==rb.relic and ra.progression==rb.progression,'relic identity and experience remain identical')
  ck(a.rng.state==b.rng.state and ra.rewards.exp==rb.rewards.exp and ra.rewards.gold==rb.rewards.gold,'diamond increase does not consume RNG or alter other rewards')
  ck(ra.dailyAward.amount==0 and rb.dailyAward.amount==NEW[rank]-OLD[rank],'paired settlement differs only by the requested unpaid diamond increase')
 for rank in range(4):
  var fallback=ClockGame.new('');legacy_ledger(fallback,rank);fallback.rogue_data.erase('dailyDiamondsPer10')
  ck(fallback.abyss_daily_status().reward==NEW[rank],'missing optional data uses updated display fallback')
  ck(claim(fallback,10,rank).dailyAward.amount==NEW[rank]-OLD[rank],'missing optional data uses the same updated settlement fallback')
 print('DAILY REWARD UPGRADE V250: %d checks, %d failures'%[checks,failures]);quit(1 if failures else 0)
