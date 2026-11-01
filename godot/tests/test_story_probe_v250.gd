extends "res://tests/test_relic_loadout_ui_v250.gd"
func tap(control:Control)->void:
 var observed:Array=[];app._probe_controls(app,observed)
 ck(control!=null,'actual tap target exists')
 if control==null:return
 var matches=observed.filter(func(item):return item.name==str(control.name))
 ck(matches.size()==1,'every remaining native action is observed exactly once '+str(control.name))
 if matches.size()==1:ck(matches[0].rect==app._probe_rect(control),'native action coordinates derive from real control')
 await super.tap(control)
func run()->void:
 root.size=Vector2i(1280,720)
 app=load('res://main.tscn').instantiate();app.set_script(load('res://tools/android/runtime_probe.gd'));root.add_child(app);await frames(14);app.set_process(false)
 app.navigate('story');await frames()
 var state_before:Dictionary=app.model.state.duplicate(true)
 var rng_before:int=app.model.rng.state
 var controls:Array=[];app._probe_controls(app,controls)
 for id in ['ch1_1','ch1_2']:
  var matches=controls.filter(func(item):return item.name=='StageCard_'+id)
  ck(matches.size()==1,'actual gui_input stage panel observed once '+id)
  var card=app.find_child('StageCard_'+id,true,false)
  ck(card is PanelContainer and not card is BaseButton,'fixture is actual clickable panel, not synthetic button')
  ck(matches[0].rect==app._probe_rect(card) and matches[0].clip==app._probe_clip(card),'probe records actual screen geometry and ancestor clip')
  ck(not str(matches[0].scroll_owner).is_empty(),'stage panel exposes actual local scroll owner')
  await tap(card)
  controls=[];app._probe_controls(app,controls)
  ck(controls.any(func(item):return item.name=='StageCard_'+id and item.get('selected',false)),'real input updates observed selection '+id)
 ck(app.model.state==state_before and app.model.rng.state==rng_before,'observation and stage preview do not mutate wallet or RNG')
 await tap(app.find_child('StageCard_ch1_1',true,false));await tap(app.find_child('StoryEnter',true,false))
 var skip=app.find_child('DialogueSkip',true,false)
 if skip!=null:await tap(skip)
 ck(app.current_screen=='battle','observed panel input then real enter starts combat')
 var steps:=0
 while app.battle.state.phase not in ['victory','defeat'] and steps<3000:app.battle.auto_step();steps+=1
 ck(app.battle.state.phase=='victory','actual initial team wins story battle without granted rewards')
 await app._finish_battle();await frames()
 ck(app.model.state.relics.size()==1,'actual settlement produces one earned relic')
 await tap(app.find_child('BattleSettlementContinue',true,false))
 skip=app.find_child('DialogueSkip',true,false)
 if skip!=null:await tap(skip)
 app.navigate('relics');await frames()
 var owned:Dictionary=app._probe_relics()
 ck(owned.art.any(func(item):return item.resource.ends_with('.tres')),'earned inventory art is observable')
 await tap(app.find_child('RelicAutoEquip',true,false));await wait_plan()
 var preview:Dictionary=app._probe_relics()
 ck(preview.has('displayed_plan') and preview.displayed_plan.has('after'),'real displayed optimizer plan is observable')
 await tap(app.find_child('RelicLoadoutCancel',true,false))
 ck(app._probe_relics().inventory_digest==owned.inventory_digest and app._probe_relics().equipped==owned.equipped,'preview and cancellation conserve owned items and loadout')
 app.queue_free();await frames();await create_timer(.3).timeout
 print('STORY PROBE V250: %d checks, %d failures'%[checks,failures.size()]);quit(1 if failures.size() else 0)
