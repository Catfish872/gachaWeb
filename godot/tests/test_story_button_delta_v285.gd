extends "res://tests/test_story_background_v284.gd"
func run()->void:
 app=load("res://main.tscn").instantiate();root.add_child(app);await frames(10);app.set_process(false)
 for resolution in [Vector2i(960,540),Vector2i(2048,945)]:
  root.size=resolution;await frames(6);await fixture_story()
  fits(app.find_child("StoryEnter",true,false),"complete story action "+str(resolution))
  ck(app.find_child("StoryEnter",true,false).size.y>=44,"story action touch height")
  assert_story_scene("res://assets/content_v280/backgrounds/rope_bridge.png","final bridge")
  await capture(str(resolution.x)+"-chapter4-final")
  var scroll=app.find_child("StoryDetailScroll",true,false)
  if scroll!=null:
   var before:int=scroll.scroll_vertical;var button_y:float=app.find_child("StoryEnter",true,false).global_position.y;var selected:String=app.selected_stage_id
   var point:Vector2=scroll.get_global_rect().get_center()
   var down=InputEventScreenTouch.new();down.index=0;down.pressed=true;down.position=point;root.push_input(down,true);await frames(2)
   var drag=InputEventScreenDrag.new();drag.index=0;drag.position=point-Vector2(0,90);drag.relative=Vector2(0,-90);root.push_input(drag,true);await frames(2)
   var up=InputEventScreenTouch.new();up.index=0;up.pressed=false;up.position=drag.position;root.push_input(up,true);await frames(3)
   ck(scroll.scroll_vertical>before,"actual touch scroll reveals details")
   ck(app.selected_stage_id==selected and app.find_child("StoryEnter",true,false).global_position.y==button_y,"scroll keeps selected stage and fixed action")
  app._select_story_chapter(2);await frames(6)
  fits(app.find_child("StoryEnter",true,false),"cleared chapter action")
  fits(app.find_child("StoryReplay",true,false),"cleared chapter replay")
  await capture(str(resolution.x)+"-chapter3-final")
 app.queue_free();await frames(4)
 # Allow the audio mixer to release stopped Ogg playback before process exit.
 await create_timer(0.3).timeout
 print("STORY BUTTON DELTA V285: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
