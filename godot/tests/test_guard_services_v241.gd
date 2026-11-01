extends "res://tests/test_service_layout_v241.gd"
func grown_party()->void:
 app.model.state.resources.gold=10000000
 for id in ['kaldi','ayla','gus']:
  app.model.state.ownedCharacters[id]=app.model.default_character()
  app.model.state.ownedCharacters[id].level=10;app.model.state.ownedCharacters[id].constellation=6
  for slot in app.model.catalog.RelicSlots:
   var relic:Dictionary=app.model.generate_relic(5,str(slot.id))
   check(app.model.add_relic(relic).success,'real guard fixture relic')
   check(app.model.upgrade_relic_to_max(relic.uid).success,'legally upgrade guard fixture relic')
   check(app.model.equip_relic(relic.uid,id).success,'legally equip guard fixture relic')
 check(app.model.set_team(['kaldi','ayla','gus']).success,'real three-person guard party')
func resolve_visible_growth()->void:
 var x=app.model.extraction
 while not x.growth_choices().is_empty():
  var choice:Dictionary=x.growth_choices()[0]
  await click(target('ExtractionGrowth_'+str(choice.choiceId)))
func real_ui_battle()->void:
 await click(target('ExtractionBattle'))
 app.set_process(false);app.battle_auto=false
 check(app.current_screen=='battle','actual visible encounter action enters battle')
 var steps:=0
 while app.battle.state.phase not in ['victory','defeat'] and steps<5000:
  app.battle.auto_step();steps+=1
 check(app.battle.state.phase=='victory','legal grown party wins real engine encounter without synthetic damage')
 await app._finish_battle();await frames()
 await click(target('ExtractionBattleContinue'))
 await resolve_visible_growth()
 app.set_process(true)
func run()->void:
 for kind in ['workshop','relay']:
  root.size=Vector2i(2048,945)
  app=load('res://main.tscn').instantiate();root.add_child(app);await frames(12)
  app.extraction_sound=false;app.extraction_reduced_motion=true
  grown_party();app.model.rng.seed=241000
  var x=app.model.extraction
  check(x.start_run(0).success,'real guarded expedition departure')
  var room:Dictionary=x.route_options()[0]
  for candidate in x.run().map.rooms:
   if candidate.id==room.id:candidate.type=kind;candidate.name=kind
  # Force only encounter probability in an isolated fixture; all actual battle and settlement APIs remain real.
  x.data.serviceGuards[kind]=1.0
  check(x.enter_room(room.id).success,'enter actual model-generated service guard')
  check(x.run().phase=='battle' and x.run().room.guardPending,'service is locked by real encounter')
  app.navigate('extraction');await frames(12)
  for id in ['kaldi','ayla','gus']:
   var hp:Label=target('ExtractionPartyHP_'+id)
   visible_control(hp,'grown party health label')
   check(hp.get_theme_font('font').get_string_size(hp.text,HORIZONTAL_ALIGNMENT_LEFT,-1,hp.get_theme_font_size('font_size')).x<=hp.size.x,'grown party health text fits without ellipsis')
   check(not hp.tooltip_text.is_empty(),'full health numbers remain available in tooltip')
  var scene=target('ExtractionRoomScene')
  check(scene.enemies.map(func(e):return e.id)==x.run().activeEncounter.enemies,'visible enemies are actual encounter IDs')
  check(scene.service_id=='' and scene.containers.is_empty(),'guard scene exposes no service or containers')
  check(scene.enemy_rects.size()==scene.enemies.size(),'every actual guard has a drawn portrait hit rectangle')
  for rect in scene.enemy_rects:check(Rect2(Vector2.ZERO,scene.size).encloses(rect),'guard portrait touch rectangle stays inside scene')
  check(target('ExtractionDepositPreview')==null,'guard blocks parcel UI')
  check(target('ExtractionRoomAction_study')==null,'guard blocks original workshop UI')
  await capture('v241-guard-'+kind+'-before')
  await real_ui_battle()
  if x.run().phase=='route':
   check(kind=='relay' and x.run().bag.is_empty(),'empty relay automatically returns after the final guard blessing')
   # Revisit the preserved node to inspect its original service controls.
   check(x.view_current_room().success,'automatic return preserves current node for revisit')
   app._render_screen();await frames(12)
  check(x.run().phase=='room' and not x.run().room.guardPending and x.run().room.type==kind,'victory restores exact original service')
  check(target('ExtractionRoomScene').enemies.is_empty(),'defeated guard disappears')
  if kind=='workshop':
   check(x.room_actions().size()==3,'all three original workshop choices restored')
   await reach_service(target('ExtractionRoomAction_study'))
   await click(target('ExtractionRoomAction_study'));await resolve_visible_growth()
   check(x.room_actions().all(func(a):return a.used),'real service can be used after guard victory')
  else:
   visible_control(target('ExtractionDepositPreview'),'cleared relay parcel action')
   await click(target('ExtractionDepositPreview'))
   visible_control(target('ExtractionDepositCancel'),'guarded relay parcel fixed cancel')
   await click(target('ExtractionDepositCancel'))
  await capture('v241-guard-'+kind+'-after')
  var actions:Array=x.room_actions().duplicate(true);var boxes:Array=x.containers().duplicate(true);var xp:int=x.run().expEarned
  check(x.enter_room(x.run().map.rooms[0].id).success and x.enter_room(room.id).success,'real cleared service re-entry')
  check(x.room_actions()==actions and x.containers()==boxes and x.run().expEarned==xp and x.run().phase=='room','re-entry does not respawn guard loot or experience')
  app.queue_free();await frames();await create_timer(.3).timeout
 print('GUARD SERVICES V241: %d checks, %d failures'%[checks,failures]);quit(1 if failures else 0)
