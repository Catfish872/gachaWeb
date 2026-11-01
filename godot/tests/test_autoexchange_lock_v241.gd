extends "res://tests/test_loot_v24_interactions.gd"
func fixture()->Dictionary:
 var x=app.model.extraction
 x.run().bag=[]
 for i in 29:
  var item:Dictionary=x._make_item('diamond_ring');item.revealed=true
  check(x._place(x.run().bag,item,x.dimensions('bag')),'valuable one-cell filler uses real item valuation')
 var supply:Dictionary=x._make_item('bandage');supply.revealed=true
 check(x._place(x.run().bag,supply,x.dimensions('bag')),'exact consumable occupies final cell')
 var box:Dictionary=x._find_container(x.containers()[0].id)
 var treasure:Dictionary=x._make_item('gold_watch');treasure.revealed=true;box.items=[treasure]
 return {'supply':supply,'treasure':treasure,'box':box}
func run()->void:
 root.size=Vector2i(2048,945)
 app=load('res://main.tscn').instantiate();root.add_child(app);await frames(12)
 app.extraction_auto_pick=false;app.extraction_sound=false;app.extraction_reduced_motion=true
 app.model.rng.seed=2
 var x=app.model.extraction
 check(x.start_run(0).success,'start actual locked-supply UI fixture')
 for room in x.route_options():
  if room.type=='cache':check(x.enter_room(room.id).success,'actual cache');break
 for hurt in [true,false]:
  var f:=fixture();var uid:String=f.supply.uid
  for unit in x.run().party:unit.currentHp=1 if hurt else unit.maxHp
  app.navigate('extraction');await frames(12)
  await click(target('ExtractionQuickSupplies'))
  var lock=target('ExtractionSupplyLock_'+uid)
  visible_control(lock,'consumable per-instance exchange lock')
  var instance:int=lock.get_instance_id()
  await click(lock)
  check(target('ExtractionSupplyLock_'+uid).get_instance_id()==instance,'lock updates in place without rebuilding scrolling supply list')
  check(target('ExtractionSupplyLock_'+uid).get_meta('exchange_locked',false),'lock button reflects persisted item state')
  await capture('v241-supply-locked-'+('hurt' if hurt else 'full'))
  await click(target('ExtractionSupplyClose'))
  await open_box(str(f.box.id))
  var before:Dictionary=app.model.state.duplicate(true)
  await click(target('ExtractionSmartLoot'))
  check(target('ExtractionSmartConfirm')==null,'locked cheap supply cannot be sacrificed automatically')
  check(app.model.state==before,'unavailable automatic exchange leaves entire state untouched')
  await click(target('ExtractionCloseContainer'))
  await click(target('ExtractionQuickSupplies'))
  check(target('ExtractionSupplyLock_'+uid).get_meta('exchange_locked',false),'lock survives closing search and reopening supplies')
  await click(target('ExtractionSupplyLock_'+uid))
  check(not target('ExtractionSupplyLock_'+uid).get_meta('exchange_locked',true),'explicit unlock releases only this supply UID')
  await click(target('ExtractionSupplyClose'))
  await open_box(str(f.box.id))
  await click(target('ExtractionSmartLoot'))
  var group=target('ExtractionSmartWillUse' if hurt else 'ExtractionSmartReturned')
  visible_control(group,'automatic exchange clearly previews use versus returned supply')
  await capture('v241-autoexchange-'+('heal' if hurt else 'full-health')+'-preview')
  await click(target('ExtractionSmartConfirm'))
  check(x.run().bag.any(func(item):return item.uid==f.treasure.uid),'exact higher-value loot enters backpack')
  check(not x.run().bag.any(func(item):return item.uid==uid),'selected cheap supply leaves backpack')
  var remaining:Array=x._find_container(str(f.box.id)).items
  check(remaining.filter(func(item):return item.uid==uid).size()==(0 if hurt else 1),'used supply is consumed once; ineffective supply returns once without duplication')
  if hurt:check(x.run().party.all(func(unit):return unit.currentHp>1),'auto-used supply applies actual healing')
  else:check(x.run().party.all(func(unit):return unit.currentHp==unit.maxHp),'full-health supply is not wasted')
  visible_control(target('ExtractionSmartUsed' if hurt else 'ExtractionSmartReturned'),'actual automatic exchange outcome')
  await capture('v241-autoexchange-'+('used' if hurt else 'returned'))
  await click(target('ExtractionCloseContainer'))
 # Locks constrain automatic exchange only, never deliberate use.
 var f:=fixture();var uid:String=f.supply.uid
 for unit in x.run().party:unit.currentHp=1
 app._render_screen();await frames()
 await click(target('ExtractionQuickSupplies'))
 await click(target('ExtractionSupplyLock_'+uid))
 await click(target('ExtractionQuickUse_'+uid))
 check(not x.run().bag.any(func(item):return item.uid==uid),'locked supply can still be deliberately used')
 check(target('ExtractionQuickUse_'+uid)==null and target('ExtractionSupplyLock_'+uid)==null,'consumed supply leaves no stale action or lock button')
 await click(target('ExtractionSupplyClose'))
 app.queue_free();await frames();await create_timer(.3).timeout
 print('AUTOEXCHANGE LOCK V241: %d checks, %d failures'%[checks,failures]);quit(1 if failures else 0)
