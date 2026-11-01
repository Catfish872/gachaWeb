extends "res://tests/test_relic_loadout_ui_v250.gd"
func target(id:String):return app.find_child(id,true,false)
func tap(control:Control)->void:
 if control==null:ck(false,'target exists at '+str(app.current_screen)+' overlay '+str(app.overlay.get_child_count()));return
 for attempt in 8:
  var clip:=Rect2(Vector2.ZERO,app.size)
  var parent=control.get_parent()
  var scroll:ScrollContainer=null
  while parent is Control:
   if parent.clip_contents:clip=clip.intersection(parent.get_global_rect())
   if scroll==null and parent is ScrollContainer:scroll=parent
   parent=parent.get_parent()
  if clip.encloses(control.get_global_rect()):break
  if scroll==null:break
  var bounds:Rect2=scroll.get_global_rect().intersection(Rect2(Vector2.ZERO,app.size))
  var upward:bool=control.get_global_rect().position.y>=clip.position.y
  var begin:=bounds.position+bounds.size*Vector2(.85,.8 if upward else .2)
  var end:=bounds.position+bounds.size*Vector2(.85,.2 if upward else .8)
  var down=InputEventScreenTouch.new();down.index=0;down.pressed=true;down.position=begin;root.push_input(down,true);await process_frame
  var previous:Vector2=begin
  for step in range(1,9):
   var current:Vector2=begin.lerp(end,float(step)/8)
   var drag=InputEventScreenDrag.new();drag.index=0;drag.position=current;drag.relative=current-previous;drag.velocity=drag.relative*30;root.push_input(drag,true);previous=current;await frames(2)
  var up=InputEventScreenTouch.new();up.index=0;up.pressed=false;up.position=end;root.push_input(up,true);await frames(10)
 await super.tap(control)
func stage(wanted:String,seconds:=15)->void:
 var start:=Time.get_ticks_msec()
 while is_instance_valid(app.summon_sequence) and app.summon_sequence.stage!=wanted and Time.get_ticks_msec()-start<seconds*1000:await process_frame
 ck(is_instance_valid(app.summon_sequence) and app.summon_sequence.stage==wanted,'actual sequence reaches '+wanted)
func capture_native(label:String)->void:
 if DisplayServer.get_name()=='headless':return
 await RenderingServer.frame_post_draw
 DirAccess.make_dir_recursive_absolute('res://validation/native-features-v250')
 root.get_texture().get_image().save_png('res://validation/native-features-v250/'+label+'.png')
func run()->void:
 if '--require-gl' in OS.get_cmdline_user_args() and DisplayServer.get_name()=='headless':
  printerr('FAIL actual GL required');quit(1);return
 root.size=Vector2i(1280,720)
 app=load('res://main.tscn').instantiate();app.set_script(load('res://tools/android/runtime_probe.gd'));root.add_child(app);await frames(14)
 app.set_process(false)
 # Real initialized model, no injected characters, diamonds, equipment or random result.
 app.navigate('summon');await frames()
 var before:Dictionary=app._probe_summon()
 await tap(target('SummonPull_1'))
 var committed:Dictionary=app._probe_summon()
 ck(committed.total_pulls==before.total_pulls+1 and committed.diamonds==before.diamonds-160,'real single purchase commits exactly once')
 app.notification(MainLoop.NOTIFICATION_APPLICATION_PAUSED);await frames(2)
 var paused:Dictionary=app._probe_summon()
 await create_timer(.25).timeout
 ck(app._probe_summon().sequence_time==paused.sequence_time,'notification pauses visible-frame summon clock')
 app.notification(MainLoop.NOTIFICATION_APPLICATION_RESUMED);await frames(1)
 ck(app._probe_summon().transaction_digest==committed.transaction_digest,'resume never repeats committed transaction')
 await stage('result')
 var revealed:Dictionary=app._probe_summon()
 var stages:Array=revealed.history.map(func(item):return item.stage)
 for required in ['opening','constellation','seal','unseal','portrait','result']:ck(stages.has(required),'real visible sequence includes '+required)
 ck(revealed.ready_frames>=2 and revealed.sequence_time>=3.7,'actual frame clock consumes full reveal')
 await capture_native('single-result')
 await tap(target('SummonSkip'));await stage('summary');await create_timer(.5).timeout
 await tap(target('SummonAccept'))
 ck(app._probe_summon().transaction_digest==committed.transaction_digest,'single skip/accept conserve exact result transaction')
 app.navigate('shop');await frames()
 for i in 3:
  var old:int=app.model.state.resources.diamonds
  await tap(target('ShopPurchase_recharge_traveler'))
  ck(app.model.state.resources.diamonds==old+60,'actual virtual supply buys sixty diamonds without payment API')
 app.navigate('summon');await frames();before=app._probe_summon()
 await tap(target('SummonPull_10'));await create_timer(.7).timeout
 committed=app._probe_summon()
 ck(committed.total_pulls==before.total_pulls+10 and committed.diamonds==before.diamonds-1600,'ten real results commit once')
 await tap(target('SummonSkip'));await stage('summary');await create_timer(1.3).timeout
 ck(app._probe_summon().visible_cards==10,'ten summary cards are actually visible')
 await capture_native('ten-summary');await tap(target('SummonAccept'))
 ck(app._probe_summon().transaction_digest==committed.transaction_digest,'ten skip/accept never reroll')
 app.navigate('growth');await frames();await tap(target('GrowthSelect_zeph'));await tap(target('CharacterRecommendedRelics'))
 var options=app.overlay.find_children('CharacterSetTarget_*','Button',true,false)
 var chosen=''
 for option in options:
  if not option.disabled:
   chosen=str(option.name).trim_prefix('CharacterSetTarget_');print('V250_TARGET before '+chosen+' '+JSON.stringify(app.model.abyss_relic_drop_info()));await tap(option);print('V250_TARGET after '+JSON.stringify(app.model.abyss_relic_drop_info()));break
 ck(not chosen.is_empty() and app.model.abyss_relic_drop_info().targetSetId==chosen,'actual recommendation chooses a different target')
 await capture_native('recommendations');await tap(target('CharacterRecommendationsAbyss'))
 ck(app.current_screen=='abyss' and app._probe_relics().target.targetSetId==chosen,'selected target survives real navigation')
 await tap(target('AbyssChooseRelicSet'));await capture_native('target-picker');await tap(target('AbyssSetPickerClose'))
 app.navigate('story');await frames();await tap(target('StageCard_ch1_1'));await tap(target('StoryEnter'))
 if target('DialogueSkip')!=null:await tap(target('DialogueSkip'))
 ck(app.current_screen=='battle','actual story controls enter combat')
 var steps:=0
 while app.battle.state.phase not in ['victory','defeat'] and steps<3000:app.battle.auto_step();steps+=1
 ck(app.battle.state.phase=='victory','unchanged initial team wins actual first battle')
 await app._finish_battle();await frames()
 ck(app.model.state.relics.size()==1,'real story settlement awards one relic without injection')
 var relic:Dictionary=app.model.state.relics[0]
 await tap(target('BattleSettlementContinue'))
 if target('DialogueSkip')!=null:await tap(target('DialogueSkip'))
 app.navigate('relics');await frames()
 var saved_state:Dictionary=app.model.state.duplicate(true)
 var saved_rng:int=app.model.rng.state
 var observed:Dictionary=app._probe_relics()
 for query in 5:app._probe_relics();app._probe_summon()
 ck(app.model.state==saved_state and app.model.rng.state==saved_rng,'new native observability never mutates game state or RNG')
 ck(observed.art.any(func(item):return item.set_id==str(relic.get('setId','')) and item.resource.ends_with('.tres')),'actual earned relic uses its set artwork')
 await tap(target('RelicAutoEquip'));await wait_plan()
 var preview:Dictionary=app._probe_relics()
 ck(preview.has('displayed_plan') and preview.displayed_plan.has('after'),'probe reads the actual displayed optimizer plan')
 ck(preview.inventory_digest==observed.inventory_digest and preview.equipped==observed.equipped,'preview does not equip or consume inventory')
 await capture_native('earned-preview');await tap(target('RelicLoadoutCancel'))
 ck(app._probe_relics().inventory_digest==observed.inventory_digest and app._probe_relics().equipped==observed.equipped,'cancel preserves precise ownership and loadouts')
 app.queue_free();await frames();await create_timer(.3).timeout
 print('NATIVE FEATURES V250: %d checks, %d failures'%[checks,failures.size()]);quit(1 if failures.size() else 0)
