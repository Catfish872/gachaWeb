extends "res://tests/test_loot_v24_interactions.gd"
const SERVICE_SIZES=[Vector2i(2048,945),Vector2i(1920,1080),Vector2i(2340,1080),Vector2i(1280,720)]
func clipped(control:Control)->Rect2:
 var rect:Rect2=Rect2(Vector2.ZERO,app.size)
 var parent=control.get_parent()
 while parent!=null:
  if parent is Control and (parent.clip_contents or parent is ScrollContainer):rect=rect.intersection(parent.get_global_rect())
  parent=parent.get_parent()
 return rect
func footer(label:String)->void:
 check(app.shell.size.x<=app.size.x+.5 and app.shell.size.y<=app.size.y+.5,label+" shell never expands beyond screen")
 visible_control(target("ExtractionPersistentActions"),label+" fixed right footer")
 for name in ["ExtractionSort_bag","ExtractionQuickSupplies","ExtractionBuild","ExtractionAbandon"]:
  var control=target(name)
  visible_control(control,label+" "+name)
  if control!=null:check(control.size.x>=44 and control.size.y>=44,label+" real touch target at least 44 logical pixels "+name)
 check(target("ExtractionSalvageOpen")==null,label+" no removed salvage action")
 for button in app.main_body.find_children('*','Button',true,false):check(button.text!="更多",label+" no extra More menu")
func reach_service(button:Control)->void:
 var scroll=target("ExtractionServiceScroll")
 check(scroll is ScrollContainer and scroll!=app.page_scroll,"service choices have their own local scroll, not whole-screen overflow")
 if not scroll is ScrollContainer:return
 var gestures:=0
 while not clipped(button).encloses(button.get_global_rect()) and gestures<12:
  var r:Rect2=scroll.get_global_rect().intersection(clipped(scroll))
  check(r.size.y>=44,"local service scroll retains a usable finger area")
  var old:int=scroll.scroll_vertical
  await touch_drag_between(Vector2(r.position.x+r.size.x*.65,r.end.y-12),Vector2(r.position.x+r.size.x*.65,r.position.y+12))
  await create_timer(.15).timeout
  gestures+=1
  check(scroll.scroll_vertical>old,"real vertical finger gesture moves service content")
  footer("during service finger scroll")
 check(button.size.x>=44 and button.size.y>=44,"last service retains a real forty-four-pixel touch target")
 check(clipped(button).encloses(button.get_global_rect()),"last workshop service action is fully reachable without moving main footer")
func scene_container_hits()->void:
 var boxes:Array=app.model.extraction.containers().duplicate(true)
 for box in boxes:
  for name_hit in [false,true]:
   var scene=target("ExtractionRoomScene")
   var visual:Rect2=scene.container_visual_rect(box)
   for attempt in 4:
    if Rect2(Vector2.ZERO,scene.size).encloses(visual):break
    var dx:float=clampf(scene.size.x*.5-visual.get_center().x,-scene.size.x*.35,scene.size.x*.35)
    await touch_drag_between(scene.global_position+scene.size*.5,scene.global_position+scene.size*.5+Vector2(dx,0))
    await create_timer(.3).timeout
    visual=scene.container_visual_rect(box)
   check(Rect2(Vector2.ZERO,scene.size).encloses(visual),"complete container badge sprite and name fit actual room viewport "+str(box.id))
   var point:Vector2=visual.get_center() if not name_hit else Vector2(visual.get_center().x,visual.end.y-8)
   await click_at(scene.global_position+point)
   check(target("ExtractionContainer_"+str(box.id))!=null,"visible container "+("name" if name_hit else "sprite")+" opens exact same ID")
   await click(target("ExtractionCloseContainer"))
   footer("after exact scene container hit")
func run()->void:
 for resolution in SERVICE_SIZES:
  root.size=resolution
  app=load('res://main.tscn').instantiate();root.add_child(app);await frames(12)
  app.extraction_auto_pick=false;app.extraction_sound=false;app.extraction_reduced_motion=true
  for id in ['kaldi','ayla']:
   if not app.model.state.ownedCharacters.has(id):app.model.state.ownedCharacters[id]=app.model.default_character()
  check(app.model.set_team(['kaldi','ember','ayla']).success,"three actual characters match screenshot density")
  app.model.state.resources.gold=1000000
  var x=app.model.extraction
  x.state().unlockedDifficulty=5
  for item_id in ['pack_5','armor_5']:
   check(x.buy_supply(item_id).success,"purchase actual persistent utility "+item_id)
   var item:Dictionary=x.state().stash.back()
   check(x.set_utility_slot(str(x.item_def(item_id).slot),str(item.uid)).success,"equip actual utility "+item_id)
  app.model.rng.seed=2;check(x.start_run(0).success,"start real service layout run")
  for room in x.route_options():
   if room.type=='cache':x.enter_room(room.id);break
  # Presentation fixture: real room/action APIs, isolated from random guarded-route tests.
  x.run().phase='room';x.run().room.type='workshop';x.run().room.name='符文工坊'
  for room in x.run().map.rooms:
   if room.id==x.run().room.id:room.type='workshop';room.name='符文工坊'
  x._prepare_room_actions('workshop')
  x.run().containers=[]
  x._container('封存木箱',2,0);x._container('晶石储匣',2,0)
  fill_wire(x,26)
  x.run().equipped=[x._make_item('shield')]
  app.navigate('extraction');await frames(16)
  check(x.dimensions('bag')==Vector2i(6,10),"screenshot fixture uses sixty physical backpack cells")
  check(x.room_actions().size()==3,"unresolved workshop renders all three real choices")
  check(x.containers().size()==2,"screenshot fixture retains both searchable containers")
  for box in x.containers():visible_control(target('ExtractionOpenContainer_'+str(box.id)),"both real container buttons remain fully visible")
  footer(str(resolution)+" unresolved three-service room")
  await capture('v241-workshop-'+str(resolution.x))
  await scene_container_hits()
  var navigation_before:Dictionary=app.model.state.duplicate(true)
  await click(target('ExtractionBuild'))
  check(app.extraction_panel=='build',"direct footer opens the actual build page")
  await click(target('ExtractionTab_expedition'))
  footer('return from build retains fixed layout')
  check(app.model.state==navigation_before,"build navigation does not consume service or mutate run")
  await click(target('ExtractionQuickSupplies'));await click(target('ExtractionSupplyClose'))
  footer('return from quick supplies retains fixed layout')
  check(app.model.state==navigation_before,"opening and closing supplies does not mutate run")
  var last=target('ExtractionRoomAction_study')
  check(last!=null,"last real workshop action exists")
  if last!=null:
   await reach_service(last)
   await capture("v241-workshop-"+str(resolution.x)+"-scrolled")
   await click(last)
   check(not x.growth_choices().is_empty(),"reachable last service opens actual blessing choices")
   footer("after choosing workshop service")
  # Cancel means no action loss; do not call retreat directly.
  var before:Dictionary=app.model.state.duplicate(true)
  await click(target('ExtractionAbandon'))
  visible_control(target('ExtractionAbandonCancel'),'fixed abandon cancellation')
  visible_control(target('ExtractionAbandonConfirm'),'fixed abandon confirmation')
  await click(target('ExtractionAbandonCancel'))
  check(app.overlay.get_child_count()==0 and app.model.state==before,"abandon cancellation preserves entire real run and inventory")
  footer('after abandon cancellation')
  app.queue_free();await frames();await create_timer(.3).timeout
 print('SERVICE LAYOUT V241: %d checks, %d failures'%[checks,failures]);quit(1 if failures else 0)
