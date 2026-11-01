extends SceneTree
const View=preload("res://scripts/ui/extraction_view.gd")
var checks:=0
var failures:=0
var app
func _initialize():call_deferred("run")
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures+=1;push_error("LOOTING FEEDBACK: "+label)
func frames(n:int=5):
 for i in n:await process_frame
func run():
 root.size=Vector2i(1170,540)
 app=load("res://main.tscn").instantiate();root.add_child(app);await frames(15)
 app.extraction_sound=false;app.extraction_reduced_motion=false;app.extraction_auto_pick=false
 app.navigate("extraction");await frames()
 app.extraction_panel="shop";app._render_screen();await frames()
 for id in app.model.extraction.data.items:
  var d:Dictionary=app.model.extraction.item_def(str(id))
  if int(d.get("buyPrice",0))<=0:continue
  var label=app.main_body.find_child("ExtractionSupplyEffect_"+str(id),true,false)
  check(label!=null and not str(label.text).is_empty(),"purchase has effect before paying "+str(id))
 for rarity in range(1,6):check(View.search_duration(rarity)>View.search_duration(rarity-1),"rarity increases scan duration")
 for rarity in range(6):check(View.search_duration(rarity,true)==View.search_duration(rarity,false),"reduced motion never accelerates search")
 var grid=load("res://scripts/ui/inventory_grid.gd").new();root.add_child(grid)
 var defs={"a":{"width":1,"height":1,"rarity":2,"kind":"loot"}}
 grid.configure(6,5,[{"uid":"a","itemId":"a","x":0,"y":0}],defs);await frames()
 var old:Rect2=grid.item_rect(grid.items[0])
 grid.configure(6,5,[{"uid":"a","itemId":"a","x":3,"y":1}],defs)
 check(grid.movements.has("a"),"sorting retains a per-item transition")
 check(grid.visual_rect(grid.items[0])==old,"movement starts at actual previous slot")
 await create_timer(.35).timeout
 check(grid.visual_rect(grid.items[0])==grid.item_rect(grid.items[0]),"movement finishes in new slot")
 var transfer:=View._transfer_rect(grid,{"uid":"new","x":2,"y":1,"rotated":true},{"width":2,"height":3})
 check(transfer.size==Vector2(3*grid.cell-4,2*grid.cell-4),"transfer uses new item dimensions before target grid refresh")
 grid.arrival_flash("a");check(grid.arrivals.has("a"),"arrival highlights actual UID")
 grid.reveal_flash("a");grid.reveal_flash("b");check(grid.flashes.size()==2,"overlapping reveals retain both flashes")
 grid.queue_free()
 var room=load("res://scripts/ui/extraction_room.gd").new()
 check(room.container_state({"items":[]})=="empty","empty box state")
 check(room.container_state({"items":[{"revealed":true}]})=="remaining","searched box with remaining loot")
 check(room.container_state({"items":[{"revealed":true},{"revealed":false}]})=="unsearched","part searched is not complete")
 room.configure({},[],"",[{"id":"wolf","name":"狼"},{"id":"fire_imp","name":"烈火精灵"}])
 check(room.enemies.size()==2 and room.enemy_sprites.has("wolf") and room.enemy_sprites.has("fire_imp"),"scene loads exact encounter sprites")
 room.configure({},[],"",[])
 check(room.enemies.is_empty(),"resolved room removes combatants")
 room.free()
 app.extraction_panel="expedition"
 var found:=false
 for seed_value in range(1,80):
  if not app.model.state.extraction.run.is_empty():app.model.extraction.retreat()
  app.model.rng.seed=seed_value;app.model.extraction.start_run(0)
  for option in app.model.extraction.route_options():
   if option.type=="cache":app.model.extraction.enter_room(option.id);found=true;break
  if found:break
 check(found,"resource room fixture")
 app._render_screen();await frames()
 var boxes: Array=app.model.extraction.containers()
 check(not boxes.is_empty(),"fixture containers")
 var id:=str(boxes[0].id)
 app.set_meta("application_paused",true)
 View._open_container(app,id);await frames(10)
 check(app.extraction_searching,"opening container starts scanning automatically")
 check(app.overlay.find_child("ExtractionSearch",true,false)==null and app.overlay.find_child("ExtractionStopSearch",true,false)==null,"no redundant search controls")
 var source=app.overlay.find_child("ExtractionContainer_"+id,true,false)
 var before:=float(source.scan_progress)
 await create_timer(.2).timeout
 check(is_equal_approx(float(source.scan_progress),before),"background freezes scan progress")
 app.set_meta("application_paused",false)
 await create_timer(.25).timeout
 check(float(source.scan_progress)>before,"foreground resumes remaining scan")
 View._close_container(app);await frames()
 check(not app.extraction_searching,"closing cancels current generation")
 var unknown:=0
 for item in app.model.extraction.containers()[0].items:
  if not item.get("revealed",false):unknown+=1
 await create_timer(.5).timeout
 var after:=0
 for item in app.model.extraction.containers()[0].items:
  if not item.get("revealed",false):after+=1
 check(unknown==after,"closed scan cannot reveal silently")
 # Single locked-room option includes its disabled reason without hiding the footer.
 app.model.state.extraction.run.phase="room";app.model.state.extraction.run.activeEncounter={}
 app.model.state.extraction.run.room.type="key_vault";app.model.state.extraction.run.pendingChoices=[]
 app.model.state.extraction.run.containers=[];app.model.state.extraction.run.room.containers=[]
 app.model.extraction._prepare_room_actions("key_vault")
 app._render_screen();await frames(10)
 for name in ["ExtractionRoomAction_unlock","ExtractionSort_bag"]:
  var control=app.main_body.find_child(name,true,false)
  check(control!=null and control.get_global_rect().end.y<=app.size.y,"locked-room footer remains visible "+name+" rect="+str(control.get_global_rect() if control!=null else null)+" app="+str(app.size))
 app.queue_free();await frames(20);await create_timer(.3).timeout
 print("LOOTING FEEDBACK: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
