extends SceneTree
var checks := 0
var failed := 0
var travels: Array = []
var previews: Array = []
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
 checks += 1
 if not value: failed += 1;push_error("ATLAS: "+message)
func touch(map, id: int, position: Vector2, down: bool) -> void:
 var e := InputEventScreenTouch.new();e.index=id;e.position=position;e.pressed=down;map._gui_input(e)
func motion(map, id: int, position: Vector2) -> void:
 var e := InputEventScreenDrag.new();e.index=id;e.position=position;map._gui_input(e)
func fixture() -> Dictionary:
 var g := {"rooms":[],"edges":[],"districts":[],"currentRoomId":"r0","bossRoomId":"r18","explored":2,"bossUnlocked":false}
 var types := ["entry","cache","rest","battle","event","elite","workshop","hospital","cache","shrine","battle","rest","elite","vault","battle","event","cache","rest","boss"]
 for d in 3:g.districts.append({"id":"d%d"%d,"theme":["ruins","forest","sanctum"][d],"name":["旧王城遗址","幽光林地","星核圣所"][d]})
 for i in 19:
  var d := mini(2,i/6)
  var col := i%6/3+d*2
  var row := i%3
  g.rooms.append({"id":"r%d"%i,"name":"房间%d"%i,"type":types[i],"x":.04+col*.16 if i<18 else .99,"y":.08+row*.4 if i<18 else .9,"districtId":"d%d"%d,"visited":i<3,"cleared":i<3})
  if i>0:g.edges.append(["r%d"%(i-1),"r%d"%i])
 return g
func run() -> void:
 var map=load("res://scripts/ui/extraction_map.gd").new()
 map.configure(fixture());root.add_child(map)
 map.room_previewed.connect(func(id):previews.append(id))
 map.room_selected.connect(func(id):travels.append(id))
 for dimensions in [Vector2(510,340),Vector2(660,400),Vector2(900,550),Vector2(1280,720)]:
  map.size=dimensions;map.fit_view();await process_frame
  check(map.rooms.size()==19,"all rooms retained")
  for id in map.rooms:
   check(map._view_rect().has_point(map.room_point(id)),"fit contains "+id+" at "+str(dimensions))
  check(map.get_node("AtlasTools").position.x>=0,"toolbar inside")
  check(map.get_node("AtlasTools").position.x+map.get_node("AtlasTools").size.x<=dimensions.x,"toolbar width")
  var point: Vector2=map.room_point("r1")
  previews.clear();travels.clear();map.selected_room_id="r0"
  touch(map,0,point,true);touch(map,0,point,false);await process_frame
  check(previews==["r1"] and travels.is_empty(),"first tap previews")
  touch(map,0,point,true);touch(map,0,point,false);await process_frame
  check(travels==["r1"],"second tap travels")
  var anchor: Vector2=map._view_rect().get_center()
  var before: float=map.zoom
  touch(map,0,anchor-Vector2(30,0),true);touch(map,1,anchor+Vector2(30,0),true)
  motion(map,1,anchor+Vector2(100,0));touch(map,1,anchor+Vector2(100,0),false);touch(map,0,anchor-Vector2(30,0),false)
  check(map.zoom>before,"pinch zooms")
  check(travels.size()==1,"pinch never travels")
  map.focus_current();check(map.zoom>=.75,"locate readable zoom")
  for zoom_step in 8:
   if map._content_bounds().size.x*map.zoom>map._view_rect().size.x+1:break
   map.get_node("AtlasTools/AtlasZoomIn").pressed.emit()
  check(map._content_bounds().size.x*map.zoom>map._view_rect().size.x,"zoomed map has horizontal travel")
  var old: Vector2=map.offset
  touch(map,0,anchor,true);motion(map,0,anchor-Vector2(100,50));touch(map,0,anchor-Vector2(100,50),false)
  check(map.offset!=old,"drag pans")
  check(travels.size()==1,"drag never travels")
  map.zoom_at(anchor,100);check(map.zoom<=1.8,"upper zoom clamp")
  map.zoom_at(anchor,.001);check(map.zoom>=.2,"lower zoom clamp")
 # Native landscape CI regression: overview may fit horizontally and must
 # stay steady on drag. Zoom using the real map button before testing pan.
 for dimensions in [Vector2(575,254),Vector2(734.7,324)]:
  map.size=dimensions;map.fit_view()
  var before: Vector2=map.offset
  var center: Vector2=map._view_rect().get_center()
  touch(map,0,center+Vector2(80,0),true);motion(map,0,center-Vector2(80,0));touch(map,0,center-Vector2(80,0),false)
  check(map.offset==before,"overview drag stays centered without first-touch jump")
  for zoom_step in 8:
   if map._content_bounds().size.x*map.zoom>map._view_rect().size.x+1:break
   map.get_node("AtlasTools/AtlasZoomIn").pressed.emit()
  check(map._content_bounds().size.x*map.zoom>map._view_rect().size.x,"native-size zoom unlocks horizontal travel")
  before=map.offset
  touch(map,0,center+Vector2(80,0),true);motion(map,0,center-Vector2(80,0));touch(map,0,center-Vector2(80,0),false)
  check(map.offset.x!=before.x,"native-size zoomed horizontal drag moves map")
  map.get_node("AtlasTools/AtlasFit").pressed.emit()
  check(is_equal_approx(map.zoom,map._minimum_zoom()),"overview button resets zoom")
 check(map._known("r0") and map._known("r1"),"current and neighbor visible")
 check(map._known("r13") and map._known("r18"),"surveyed landmarks visible")
 check(not map._known("r7"),"remote ordinary detail is unsurveyed")
 # The exact native CI graph and final logical canvas size. No explicit fit
 # call is allowed before these initial-layout assertions.
 var native_game=load("res://scripts/game_model.gd").new("")
 native_game.rng.seed=2;native_game.extraction.start_run(0)
 var native=load("res://scripts/ui/extraction_map.gd").new()
 native.configure(native_game.extraction.map_state());root.add_child(native)
 for layout_size in [Vector2(320,320),Vector2(800,500),Vector2(575,332)]:
  native.size=layout_size
  await process_frame;await process_frame
  check(is_equal_approx(native.zoom,native._minimum_zoom()),"untouched resize remains overview "+str(layout_size))
  for id in native.rooms:check(native._view_rect().has_point(native.room_point(id)),"default native layout contains "+id)
 check(native._view_rect().size==Vector2(551,243),"exact CI logical inner rectangle")
 var native_center: Vector2=native._view_rect().get_center()
 var native_before: Vector2=native.offset
 var native_selected: String=native.selected_room_id
 touch(native,0,native_center+Vector2(100,0),true);motion(native,0,native_center-Vector2(100,0));touch(native,0,native_center-Vector2(100,0),false)
 check(native.offset==native_before and native.selected_room_id==native_selected,"seed2 overview drag stable and no navigation")
 for zoom_step in 8:
  if native._content_bounds().size.x*native.zoom>native._view_rect().size.x+60:break
  native.get_node("AtlasTools/AtlasZoomIn").pressed.emit()
 native_before=native.offset
 touch(native,0,native_center+Vector2(100,0),true);motion(native,0,native_center-Vector2(100,0));touch(native,0,native_center-Vector2(100,0),false)
 check(native.offset.x<native_before.x-12,"seed2 zoomed finger drag moves left over12px")
 check(native.selected_room_id==native_selected,"seed2 drag keeps selection")
 native.zoom_at(native_center,1.25)
 var manual_zoom: float=native.zoom
 native.size=Vector2(660,400);await process_frame;await process_frame
 check(is_equal_approx(native.zoom,manual_zoom),"manual zoom survives resize")
 native.get_node("AtlasTools/AtlasFit").pressed.emit()
 native.size=Vector2(575,332);await process_frame;await process_frame
 check(is_equal_approx(native.zoom,native._minimum_zoom()),"overview restores responsive fit")
 native.queue_free();await process_frame
 # v2.3: travel hints follow model reachability, never a visual shortcut.
 var travel_graph := fixture()
 travel_graph.reachableRoomIds=["r1","r2","r3"]
 travel_graph.travelPaths={"r1":["r0","r1"],"r2":["r0","r1","r2"],"r3":["r0","r1","r2","r3"]}
 var travel_map=load("res://scripts/ui/extraction_map.gd").new()
 travel_map.configure(travel_graph,true);root.add_child(travel_map);travel_map.size=Vector2(660,400)
 await process_frame
 check(travel_map.adjacent_ids()==["r1"],"physical neighbor API unchanged")
 check(travel_map.reachable_ids()==["r1","r2","r3"],"model reachable component and frontier consumed")
 check(travel_map.travel_path("r3")==["r0","r1","r2","r3"],"full safe travel path preserved")
 check(travel_map.frontier_ids()==["r3"],"only unvisited reachable frontier pulses")
 check(travel_map.travel_path("r4").is_empty(),"unreachable destination has no path hint")
 travel_map.graph.travelPaths.r3=["r0","r3"]
 check(travel_map.travel_path("r3").is_empty(),"route hint rejects disconnected straight shortcut")
 travel_map.graph.travelPaths.r3=["r1","r2","r3"]
 check(travel_map.travel_path("r3").is_empty(),"route hint starts at current room")
 travel_map.graph.travelPaths.r3=["r0","r1","r2","r3"]
 travel_map.graph.reachableRoomIds=[]
 check(travel_map.reachable_ids().is_empty() and travel_map.frontier_ids().is_empty(),"explicit blocked movement has no fallback or pulse")
 travel_map.graph.reachableRoomIds=["r3"]
 check(not travel_map.get_node("AtlasRouteMotion").is_processing(),"reduced motion stops animation clock")
 var motion_phase: float=travel_map.get_node("AtlasRouteMotion").phase
 travel_map.get_node("AtlasRouteMotion")._process(1.0)
 check(travel_map.get_node("AtlasRouteMotion").phase==motion_phase,"reduced motion has static route")
 travel_map.reduced_motion=false
 check(travel_map.get_node("AtlasRouteMotion").is_processing(),"animation resumes when preference disabled")
 travel_map.get_node("AtlasRouteMotion")._process(.5)
 check(travel_map.get_node("AtlasRouteMotion").phase>motion_phase,"pulse clock advances")
 check(travel_map.get_node("AtlasRouteMotion").mouse_filter==Control.MOUSE_FILTER_IGNORE,"animation overlay never captures touches")
 travel_map.reduced_motion=true
 check(travel_map.travel_path("r3")==["r0","r1","r2","r3"],"motion preference retains travel affordance")
 check(travel_map.TYPE_NAMES.has("key_vault") and travel_map.TYPE_NAMES.has("relay"),"key room and relay named icons reserved")
 travel_map.queue_free();await process_frame
 # Joint model/control regression: cache -> visited entrance -> unexplored
 # camp is one selected destination, not three repeated map taps.
 var journey=load("res://scripts/game_model.gd").new("")
 journey.rng.seed=2;journey.extraction.start_run(0)
 var cache_id := ""
 for option in journey.extraction.route_options():
  if option.type=="cache":cache_id=option.id;break
 check(not cache_id.is_empty(),"seed2 initial cache reachable")
 check(journey.extraction.enter_room(cache_id).success,"joint enters real cache")
 check(journey.extraction.advance_room().success,"joint returns to map")
 var journey_map=load("res://scripts/ui/extraction_map.gd").new()
 journey_map.configure(journey.extraction.map_state(),true);root.add_child(journey_map);journey_map.size=Vector2(660,400)
 await process_frame;await process_frame
 var camp_id := ""
 for option in journey.extraction.route_options():
  if option.type=="rest" and option.path.size()>2:camp_id=option.id;break
 check(not camp_id.is_empty(),"nonadjacent camp reachable through surveyed corridor")
 if not camp_id.is_empty():
  check(camp_id not in journey_map.adjacent_ids() and camp_id in journey_map.reachable_ids(),"logical travel distinguished from neighbor edge")
  check(journey_map.travel_path(camp_id).size()==3,"joint full corridor rendered")
  var travel_results:Array=[]
  journey_map.room_previewed.connect(func(_id):pass)
  journey_map.room_selected.connect(func(id):travel_results.append(journey.extraction.enter_room(id)))
  var camp_point:Vector2=journey_map.room_point(camp_id)
  var explored_before:int=journey.extraction.run().map.explored
  var previous_boxes:Array=journey.extraction.containers().duplicate(true)
  touch(journey_map,0,camp_point,true);touch(journey_map,0,camp_point,false);await process_frame
  check(journey.extraction.run().map.currentRoomId==cache_id,"first distant tap previews without moving")
  touch(journey_map,0,camp_point,true);touch(journey_map,0,camp_point,false);await process_frame
  check(travel_results.size()==1 and travel_results[0].success,"second distant tap executes valid model travel")
  check(journey.extraction.run().map.currentRoomId==camp_id,"joint travel reaches frontier directly")
  check(journey.extraction.run().map.explored==explored_before+1,"transit does not replay exploration rewards")
  for room in journey.extraction.run().map.rooms:
   if room.id==cache_id:check(room.containers==previous_boxes,"travel preserves previous container state")
 journey_map.queue_free();await process_frame
 # Actual generated maps must fit a compact panel without intersecting
 # travel routes or overlapping 44 px touch targets.
 var Game=load("res://scripts/game_model.gd")
 var minimum_distance := INF
 for seed in 200:
  var game=Game.new("");game.rng.seed=seed;game.extraction.start_run(0)
  map.configure(game.extraction.map_state());map.size=Vector2(510,340);map.fit_view()
  # Fitted float32 extents must not unlock the 24px overscroll margin.
  # Seed1 at 575x332 and seed2 at 516x1000 reproduced this before the fix.
  for dimensions in [Vector2(510,340),Vector2(575,332),Vector2(516,600),Vector2(516,1000),Vector2(660,400)]:
   map.size=dimensions;map.fit_view()
   var fitted_offset:Vector2=map.offset
   var stable_bounds:Rect2=map._content_bounds()
   touch(map,0,Vector2(190,170),true);motion(map,0,Vector2(50,60));touch(map,0,Vector2(50,60),false)
   for frame in 5:map._process(1.0/60.0)
   check(map.offset.is_equal_approx(fitted_offset),"fitted drag remains fixed seed=%d size=%s"%[seed,dimensions])
   check(map._auto_fit,"fit drag preserves responsive camera")
   map.zoom_at(map._view_rect().get_center(),map.zoom*1.8)
   check(map._content_bounds()==stable_bounds,"world bounds independent of zoom")
   var zoomed_offset:Vector2=map.offset
   touch(map,0,Vector2(190,170),true);motion(map,0,Vector2(50,60));touch(map,0,Vector2(50,60),false)
   check(map.offset.x<zoomed_offset.x-12,"real zoom still pans seed=%d size=%s"%[seed,dimensions])
  map.size=Vector2(510,340);map.fit_view()
  var ids: Array=map.rooms.keys()
  for a in range(ids.size()):
   check(map._view_rect().has_point(map.room_point(ids[a])),"actual seed fits "+str(seed))
   for b in range(a+1,ids.size()):
    minimum_distance=minf(minimum_distance,map.room_point(ids[a]).distance_to(map.room_point(ids[b])))
  for e in map.graph.edges:
   for f in map.graph.edges:
    if e[0] in f or e[1] in f:continue
    check(Geometry2D.segment_intersects_segment(map.room_point(e[0]),map.room_point(e[1]),map.room_point(f[0]),map.room_point(f[1]))==null,"routes do not cross")
   for id in ids:
    if id in e:continue
    check(Geometry2D.get_closest_point_to_segment(map.room_point(id),map.room_point(e[0]),map.room_point(e[1])).distance_to(map.room_point(id))>=22,"routes avoid other targets")
 check(minimum_distance>=44,"44px touch targets never overlap")
 print("ATLAS minimum compact target spacing ",minimum_distance)
 map.queue_free();await process_frame
 print("ATLAS ",checks," checks; ",failed," failures")
 quit(1 if failed else 0)
