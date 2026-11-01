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
  var old: Vector2=map.offset
  touch(map,0,anchor,true);motion(map,0,anchor-Vector2(100,50));touch(map,0,anchor-Vector2(100,50),false)
  check(map.offset!=old,"drag pans")
  check(travels.size()==1,"drag never travels")
  map.zoom_at(anchor,100);check(map.zoom<=1.8,"upper zoom clamp")
  map.zoom_at(anchor,.001);check(map.zoom>=.2,"lower zoom clamp")
 check(map._known("r0") and map._known("r1"),"current and neighbor visible")
 check(map._known("r13") and map._known("r18"),"surveyed landmarks visible")
 check(not map._known("r7"),"remote ordinary detail is unsurveyed")
 # Actual generated maps must fit a compact panel without intersecting
 # travel routes or overlapping 44 px touch targets.
 var Game=load("res://scripts/game_model.gd")
 var minimum_distance := INF
 for seed in 100:
  var game=Game.new("");game.rng.seed=seed;game.extraction.start_run(0)
  map.configure(game.extraction.map_state());map.size=Vector2(510,340);map.fit_view()
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
