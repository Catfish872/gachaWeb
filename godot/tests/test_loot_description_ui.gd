extends SceneTree
const View=preload("res://scripts/ui/extraction_view.gd")
const Game=preload("res://scripts/game_model.gd")
var checks:=0
var failures:=0
func ck(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;printerr("FAIL ",label)
func frames()->void:
 for i in range(8):await process_frame
func _initialize()->void:call_deferred("run_test")
func run_test()->void:
 var app=load("res://main.tscn").instantiate();root.add_child(app);await frames()
 app.test_session=true;app.set_process(false);app.music_enabled=false;app.sound_enabled=false
 for dims in [Vector2i(960,540),Vector2i(2048,945)]:
  root.size=dims;app.size=Vector2(dims);app.model=Game.new("")
  var ex=app.model.extraction;ex.start_run();ex.run().phase="room";ex.run().containers=[]
  ex._container("测试收藏匣",0,0)
  var c:Dictionary=ex.run().containers.back()
  var item:Dictionary=ex._make_item("thunder_city_first_bell");item.revealed=true;c.items=[item]
  app.navigate("extraction");await frames()
  View._open_container(app,c.id);View._stop_search(app,false);View._select_container_item(app,c.id,item.uid);await frames()
  var label=app.overlay.find_child("ExtractionItemDescription",true,false)
  ck(label is Label and label.text==ex.item_def(item.itemId).description,"full loot description visible")
  ck(label is Label and label.autowrap_mode!=TextServer.AUTOWRAP_OFF,"description wraps")
  var pickup=app.overlay.find_child("ExtractionPickup_"+item.uid,true,false)
  ck(pickup is Button and not pickup.disabled,"pickup action retained")
  var close=app.overlay.find_child("ExtractionCloseContainer",true,false)
  ck(close is Button and not close.disabled,"close action retained")
  pickup.pressed.emit();await frames()
  ck(ex.run().bag.any(func(entry):return entry.uid==item.uid),"description does not break pickup")
  View._select_search_bag_item(app,c.id,item.uid);await frames()
  label=app.overlay.find_child("ExtractionItemDescription",true,false)
  ck(label is Label and label.text==ex.item_def(item.itemId).description,"backpack keeps item description")
  app._clear_overlay()
 app.queue_free();await frames()
 print("LOOT DESCRIPTION UI ",checks," checks ",failures," failures")
 quit(1 if failures else 0)
