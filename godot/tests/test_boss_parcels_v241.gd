extends "res://tests/test_guard_services_v241.gd"
func run()->void:
 root.size=Vector2i(2048,945)
 app=load('res://main.tscn').instantiate();root.add_child(app);await frames(12)
 app.extraction_sound=false;app.extraction_reduced_motion=true
 grown_party();app.model.rng.seed=241000
 var x=app.model.extraction
 x.state().unlockedDifficulty=5
 check(x.buy_supply('pack_5').success,'purchase actual sixty-cell backpack for oversized source fixture')
 var pack:Dictionary=x.state().stash.back()
 check(x.set_utility_slot('backpack',str(pack.uid)).success,'equip purchased sixty-cell backpack before departure')
 check(x.start_run(0).success,'actual boss parcel fixture departure')
 for act in [1,2,3]:
  # Move the isolated fixture to the actual generated boss; no fabricated victory or parcel result.
  x.run().act=act;x._generate_map()
  var boss:Dictionary=x.run().map.rooms.back()
  boss.visited=true;x.run().map.currentRoomId=boss.id;x.run().room=boss.duplicate(true)
  x.run().node=4;x.run().bossesDefeated=act-1
  x._generate_encounter('boss')
  app.navigate('extraction');await frames(12)
  await real_ui_battle()
  check(x.run().phase=='boss_exit','actual boss victory opens exit service')
  fill_wire(x,37);app._render_screen();await frames(12)
  var original:Array=x.run().bag.map(func(item):return item.uid)
  var before:Dictionary=app.model.state.duplicate(true)
  await click(target('ExtractionDepositPreview'))
  visible_control(target('ExtractionDepositConfirm'),'boss parcel fixed confirmation')
  visible_control(target('ExtractionDepositCancel'),'boss parcel fixed cancellation')
  await click(target('ExtractionDepositCancel'))
  check(app.model.state==before,'boss parcel cancellation preserves all assets')
  await click(target('ExtractionDepositPreview'))
  await click(target('ExtractionDepositAuto'))
  var plan:Dictionary=app.overlay.get_meta('deposit_plan')
  check(int(plan.width)==6 and int(plan.height)==6,'every act boss quotes a real six by six parcel')
  check(plan.uids.size()==36 and int(plan.fee)==50,'auto chooses thirty-six one-cell objects and exact fee')
  var grid=target('ExtractionGrid_deposit')
  visible_control(grid,'entire six by six preview within modal')
  for i in grid.items.size():
   check(original.has(grid.items[i].uid),'preview retains actual source UID')
   for j in range(i+1,grid.items.size()):check(not grid.item_rect(grid.items[i]).intersects(grid.item_rect(grid.items[j])),'thirty-six preview cells do not overlap')
  for resolution in [Vector2i(1920,1080),Vector2i(2340,1080),Vector2i(1280,720),Vector2i(2048,945)]:
   root.size=resolution;await frames(12)
   for node_name in ['ExtractionGrid_deposit','ExtractionDepositConfirm','ExtractionDepositCancel','ExtractionDepositAuto']:
    visible_control(target(node_name),'six by six parcel '+str(resolution)+' '+node_name)
  await capture('v241-boss-parcel-act-'+str(act))
  var gold:int=app.model.state.resources.gold
  await click(target('ExtractionDepositConfirm'))
  check(app.model.state.resources.gold==gold-50,'boss parcel pays fee once')
  check(x.run().bag.size()==1,'one omitted item remains in source bag')
  for uid in plan.uids:check(x.state().stash.filter(func(item):return item.uid==uid).size()==1,'exact boss parcel UID transferred once')
  check(target('ExtractionDepositPreview').disabled and x.run().room.depositUsed,'used boss source cannot resubmit')
  check(x.state().stash.size()==act*36,'prior act parcels preserved')
  if act<3:check(x.continue_act().success,'next act remains available after parcel')
 app.queue_free();await frames();await create_timer(.3).timeout
 print('BOSS PARCELS V241: %d checks, %d failures'%[checks,failures]);quit(1 if failures else 0)
