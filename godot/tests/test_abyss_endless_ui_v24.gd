extends SceneTree
class ClockModel extends "res://scripts/game_model.gd":
 var now_ms:int=1793500000000
 func _now()->int:return now_ms
var app
var checks:=0
var failures:=0
func _initialize():call_deferred('run')
func frames():
 for i in 12:await process_frame
func ck(ok:bool,label:String):
 checks+=1
 if not ok:failures+=1;push_error(label)
func fits(control:Control,label:String):
 ck(control!=null,label+' exists')
 if control==null:return
 var clip:=Rect2(Vector2.ZERO,app.size);var p=control.get_parent()
 while p:
  if p is Control and (p.clip_contents or p is ScrollContainer):clip=clip.intersection(p.get_global_rect())
  p=p.get_parent()
 if not clip.encloses(control.get_global_rect()):print('GEOMETRY ',label,' rect=',control.get_global_rect(),' clip=',clip)
 ck(clip.encloses(control.get_global_rect()),label+' visible')
func click(control:Control):
 var point=control.get_global_rect().get_center()
 var down:=InputEventMouseButton.new();down.position=point;down.button_index=MOUSE_BUTTON_LEFT;down.pressed=true;root.push_input(down)
 var up:=InputEventMouseButton.new();up.position=point;up.button_index=MOUSE_BUTTON_LEFT;root.push_input(up)
 await frames()
func capture(key:String):
 if DisplayServer.get_name()=="headless":return
 await RenderingServer.frame_post_draw
 var folder="/workspace/scratch/8f1fc457a062/abyss-endless-v24"
 DirAccess.make_dir_recursive_absolute(folder)
 root.get_texture().get_image().save_png(folder+"/"+key+"-"+str(root.size.x)+".png")
func run():
 app=load('res://main.tscn').instantiate();root.add_child(app);await frames();app.set_process(false)
 app.model=ClockModel.new('');app.model.random_source=func():return .01
 for resolution in [Vector2i(960,540),Vector2i(1170,540)]:
  root.size=resolution;await frames()
  for floor_number in [50,60]:
   app.model.reset_abyss();app.model.state.abyss.currentFloor=floor_number;app.model.state.abyss.maxFloor=60
   app.abyss_panel='expedition';app.navigate('abyss');await frames()
   var track=app.find_child('AbyssRouteTrack',true,false)
   ck(track.visible_floors().size()==10,'bounded ten-floor route')
   ck(track.visible_floors().has(floor_number) and track.visible_floors().max()>floor_number,'current and future floors shown beyond fifty')
   fits(app.shell,'entire abyss shell')
   fits(app.find_child('AbyssDailyCard',true,false),'daily card')
   fits(app.find_child('AbyssBegin',true,false),'begin action')
   ck(app.find_child('AbyssDailyMilestone',true,false).text=='第 %d 层'%floor_number,'correct milestone')
   await capture('route-'+str(floor_number))
   var prepared:Dictionary=app.model.prepare_abyss()
   ck(prepared.success,'real abyss preparation')
   app.battle_config=prepared.config
   app.battle.state={'allies':app.model.battle_party(true),'turn':3}
   var result:Dictionary=app.model.finish_battle(prepared.config,{'phase':'victory','allies':app.model.battle_party(true)})
   ck(result.success and not result.ended,'real milestone settlement continues endless')
   ck(not result.relic.is_empty() and not result.progression.is_empty(),'real finish yields relic and progression')
   app._render_battle_settlement(result,true,false);await frames()
   ck(app.find_child('SettlementReward_gold',true,false)==null,'abyss does not display gold')
   ck(app.find_child('SettlementReward_diamonds',true,false).text=='+%d'%result.dailyAward.amount,'actual daily amount displayed')
   fits(app.find_child('SettlementRelic',true,false),'actual relic visible')
   fits(app.find_child('BattleSettlementContinue',true,false),'continuation fixed')
   await capture('settlement-'+str(floor_number))
   app._clear_overlay();app.model.reset_abyss();app.model.state.abyss.currentFloor=floor_number;app.navigate('abyss');await frames()
   ck(app.find_child('AbyssDailyNext',true,false).text=='今日已领取','used award shown')
   var repeat_config:Dictionary=app.model.prepare_abyss()
   var repeated:Dictionary=app.model.finish_battle(repeat_config.config,{'phase':'victory','allies':app.model.battle_party(true)})
   ck(repeated.success and repeated.dailyAward.amount==0 and repeated.rewards.exp>0 and not repeated.relic.is_empty(),'repeat retains experience and actual relic with no duplicate crystals')
   app.battle_config=repeat_config.config;app._render_battle_settlement(repeated,true,false);await frames()
   ck(app.find_child('SettlementDailyAwardText',true,false).text=='第 %d 层 · 今日已领取'%floor_number,'repeat settlement states daily award already used')
   app._clear_overlay();app.model.reset_abyss();app.model.state.abyss.currentFloor=floor_number

   app.model.state.abyss.meta.selectedDifficulty=1;app._render_screen();await frames()
   ck(app.find_child('AbyssDailyNext',true,false).text=='+%d 星尘晶'%int(app.model.abyss_daily_status().remaining),'higher difficulty shows only difference')
   app.model.state.abyss.meta.selectedDifficulty=0
   var reset_at:int=app.model.abyss_daily_status().resetAt
   app.model.now_ms=reset_at-1;app._render_screen();await frames()
   ck(app.find_child('AbyssDailyNext',true,false).text=='今日已领取','before six AM retains claim')
   app.model.now_ms=reset_at;app.find_child('AbyssDailyRefresh',true,false).timeout.emit();await frames()
   ck(app.find_child('AbyssDailyPaid',true,false).text=='今日已领 0','next daily refresh resets display')
   ck(app.find_child('AbyssDailyNext',true,false).text=='+%d 星尘晶'%int(app.model.abyss_daily_status().reward),'new day award restored')
  app.model.reset_abyss();app.abyss_panel='meta';app.navigate('abyss');await frames()
  ck(app.find_child('MemoryExchangeOpen',true,false).disabled,'uncapped camp blocks exchange')
  for upgrade in app.model.rogue_data.metaUpgrades:app.model.state.abyss.meta.upgrades[upgrade.id]=upgrade.maxLevel
  app.model.state.abyss.meta.currency=123;app._render_screen();await frames()
  var before:int=app.model.state.resources.diamonds
  await click(app.find_child('MemoryExchangeOpen',true,false));fits(app.find_child('MemoryExchangeConfirm',true,false),'exchange confirm')
  await click(app.find_child('MemoryExchangeAll',true,false))
  ck(app.find_child('MemoryExchangePreview',true,false).text=='获得 123 星尘晶','all amount preview')
  fits(app.find_child('MemoryExchangePreview',true,false),'exchange amount preview')
  fits(app.find_child('MemoryExchangeAmount',true,false),'exchange numeric input')
  await capture('memory-exchange')
  await click(app.find_child('MemoryExchangeCancel',true,false))
  ck(app.model.state.abyss.meta.currency==123 and app.model.state.resources.diamonds==before,'cancel preserves balances')
  await click(app.find_child('MemoryExchangeOpen',true,false));await click(app.find_child('MemoryExchangeAll',true,false));await click(app.find_child('MemoryExchangeConfirm',true,false))
  ck(app.model.state.abyss.meta.currency==0 and app.model.state.resources.diamonds==before+123,'real exchange one to one')
  ck(app.overlay.get_child_count()==0,'exchange modal closes')
  app.model=ClockModel.new('');app.model.random_source=func():return .01
  for id in app.model.state.ownedCharacters:app.model.state.ownedCharacters[id].level=10
  app.model.extraction.start_run(0);app.model.extraction._generate_encounter('normal')
  app._start_battle(app.model.extraction.prepare_battle().config);app.set_process(false)
  for i in 1500:
   if app.battle.state.phase in ['victory','defeat']:break
   app.battle.auto_step()
  ck(app.battle.state.phase=='victory','extraction fixture wins actual combat')
  await app._finish_battle();await frames()
  fits(app.find_child('ExtractionBattleExperience',true,false),'extraction encounter experience')
  ck(app.find_child('ExtractionBattleExperience',true,false).text=='经验 +%d'%int(app.last_reward.rewards.exp),'actual encounter experience shown')
  fits(app.find_child('ExtractionBattleContinue',true,false),'extraction continuation')
  await create_timer(2).timeout;await capture('extraction-encounter');app._clear_overlay()
  app.model=ClockModel.new('');app.model.random_source=func():return .01
 app.queue_free();await frames();await create_timer(.3).timeout
 print('ABYSS ENDLESS UI V24: %d checks, %d failures'%[checks,failures]);quit(1 if failures else 0)
