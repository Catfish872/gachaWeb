extends SceneTree
var app
var checks:=0
var failures:=0
func _initialize():call_deferred('run')
func frames(n:int=8):
 for i in n:await process_frame
func ck(ok:bool,label:String):
 checks+=1
 if not ok:failures+=1;push_error('STORY: '+label)
func click(control:Control):
 var pos:Vector2=control.get_global_rect().get_center()
 var ev:=InputEventMouseButton.new();ev.button_index=MOUSE_BUTTON_LEFT;ev.position=pos;ev.global_position=pos;ev.pressed=true;root.push_input(ev)
 await frames(2)
 ev=InputEventMouseButton.new();ev.button_index=MOUSE_BUTTON_LEFT;ev.position=pos;ev.global_position=pos;ev.pressed=false;root.push_input(ev)
 await frames()
func fits(control:Control,label:String):
 ck(control!=null,label+' exists')
 if control:ck(Rect2(Vector2.ZERO,app.size).encloses(control.get_global_rect()),label+' fits viewport')
func run():
 app=load('res://main.tscn').instantiate();root.add_child(app);await frames(16);app.set_process(false)
 for resolution in [Vector2i(1170,540),Vector2i(960,540)]:
  root.size=resolution;await frames(16)
  app.navigate('story');await frames()
  fits(app.main_body.find_child('StoryEnter',true,false),'enter action')
  var second=app.main_body.find_child('StageCard_ch1_2',true,false)
  await click(second);ck(app.selected_stage_id=='ch1_2','stage card selects without entering combat')
  var done=[0]
  app._play_dialogue('ch1_1_pre',func():done[0]+=1);await frames(2)
  fits(app.overlay.find_child('DialogueSkip',true,false),'skip action')
  fits(app.overlay.find_child('DialogueNext',true,false),'next action')
  await click(app.overlay.find_child('DialogueNext',true,false))
  ck(app.dialogue_index==0 and app.dialogue_prose.visible_characters==-1,'first next reveals line')
  await click(app.overlay.find_child('DialogueNext',true,false))
  ck(app.dialogue_index==1,'next advances exactly once')
  await click(app.overlay.find_child('DialogueSkip',true,false))
  ck(done[0]==1 and app.dialogue_key.is_empty(),'skip completes once')
  app._play_dialogue('ch1_1_pre',func():done[0]+=1);await frames(2)
  await click(app.dialogue_prose)
  ck(app.dialogue_index==0 and app.dialogue_prose.visible_characters==-1,'prose tap reveals text')
  var guard=0
  while not app.dialogue_key.is_empty() and guard<60:
   await click(app.overlay.find_child('DialogueNext',true,false));guard+=1
  ck(done[0]==2 and app.dialogue_key.is_empty(),'repeat full reading finishes without lock')
  app.navigate('story');await frames()
  fits(app.main_body.find_child('StoryEnter',true,false),'story remains interactive after reading')
 app.queue_free();await frames();await create_timer(.3).timeout
 print('STORY PRESENTATION: %d checks, %d failures' % [checks,failures]);quit(1 if failures else 0)
