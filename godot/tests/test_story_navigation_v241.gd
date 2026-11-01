extends SceneTree
var app
var checks:=0
var failures:=0
func _initialize():call_deferred('run')
func frames(n:int=10):
 for i in n:await process_frame
func ck(ok:bool,label:String):
 checks+=1
 if not ok:failures+=1;push_error(label)
func clip_rect(c:Control)->Rect2:
 var rect:=c.get_global_rect();var parent=c.get_parent()
 while parent:
  if parent is Control and (parent.clip_contents or parent is ScrollContainer):rect=rect.intersection(parent.get_global_rect())
  parent=parent.get_parent()
 return rect.intersection(Rect2(Vector2.ZERO,app.size))
func tap(c:Control):
 ck(c!=null,'tap target exists')
 if c==null:return
 var rect:=clip_rect(c);ck(rect.has_area(),'tap target visible')
 var down:=InputEventMouseButton.new();down.position=rect.get_center();down.global_position=down.position;down.button_index=MOUSE_BUTTON_LEFT;down.pressed=true;root.push_input(down,true)
 await process_frame
 var up:=InputEventMouseButton.new();up.position=rect.get_center();up.global_position=up.position;up.button_index=MOUSE_BUTTON_LEFT;root.push_input(up,true)
 await frames()
func scroll_list():
 var list:ScrollContainer=app.find_child('StoryStageScroll',true,false)
 var point:=list.get_global_rect().get_center()+Vector2(0,70)
 var start:=InputEventScreenTouch.new();start.index=0;start.position=point;start.pressed=true;root.push_input(start,true)
 await frames(2)
 for i in range(1,11):
  var drag:=InputEventScreenDrag.new();drag.index=0;drag.position=point+Vector2(0,-16*i);drag.relative=Vector2(0,-16);root.push_input(drag,true);await process_frame
 var release:=InputEventScreenTouch.new();release.index=0;release.position=point+Vector2(0,-160);root.push_input(release,true);await frames()
func back():
 var down:=InputEventKey.new();down.keycode=KEY_ESCAPE;down.pressed=true;root.push_input(down,true)
 var up:=InputEventKey.new();up.keycode=KEY_ESCAPE;root.push_input(up,true);await frames()
func offset()->int:return app.find_child('StoryStageScroll',true,false).scroll_vertical
func capture():
 if DisplayServer.get_name()=='headless':return
 await RenderingServer.frame_post_draw
 var folder='/workspace/scratch/8f1fc457a062/story-navigation-v241';DirAccess.make_dir_recursive_absolute(folder)
 root.get_texture().get_image().save_png(folder+'/selected-last-'+str(root.size.x)+'.png')
func run():
 app=load('res://main.tscn').instantiate();root.add_child(app);await frames();app.set_process(false)
 for resolution in [Vector2i(960,540),Vector2i(1170,540),Vector2i(2048,945)]:
  root.size=resolution;await frames()
  app.model=load('res://scripts/game_model.gd').new('')
  for chapter in app.model.catalog.StageData.chapters:
   for stage in chapter.stages:app.model.state.stageProgress[stage.id]={'cleared':true}
  app.selected_chapter=0;app.selected_stage_id='';app.story_list_positions.clear();app.navigate('story');await frames()
  await scroll_list();var saved:=offset()
  ck(saved>0,'native touch drags stage list down')
  ck(app.selected_stage_id=='ch1_1','scroll does not select another stage')
  await tap(app.find_child('StageCard_ch1_5',true,false))
  ck(app.selected_stage_id=='ch1_5','tap last stage selects it')
  ck(abs(offset()-saved)<=1,'last stage selection preserves list offset')
  await tap(app.find_child('StageCard_ch1_4',true,false));ck(app.selected_stage_id=='ch1_4','consecutive fourth stage selection')
  ck(abs(offset()-saved)<=1,'consecutive selection preserves offset')
  await tap(app.find_child('StageCard_ch1_5',true,false));ck(abs(offset()-saved)<=1,'return to last stage preserves offset')
  await tap(app.find_child('StoryChapter_0',true,false));ck(abs(offset()-saved)<=1 and app.selected_stage_id=='ch1_5','same chapter tab keeps stage and offset')
  var stamina:int=app.model.state.resources.stamina
  await tap(app.find_child('StoryEnter',true,false));ck(app.dialogue_key=='ch1_5_pre','selected late stage opens its real dialogue')
  await back();ck(app.dialogue_key=='' and app.overlay.get_child_count()==0,'back cancels prebattle dialogue')
  ck(app.model._issued_config.is_empty() and app.model.state.resources.stamina==stamina,'cancel leaves battle and stamina untouched')
  ck(abs(offset()-saved)<=1 and app.selected_stage_id=='ch1_5','dialogue cancel retains selection and scroll')
  app.navigate('home');await frames();await back()
  ck(app.current_screen=='story' and abs(offset()-saved)<=1 and app.selected_stage_id=='ch1_5','page back restores story list locally')
  ck(Rect2(Vector2.ZERO,app.size).encloses(app.shell.get_global_rect()),'story shell stays within viewport')
  await capture()
  await tap(app.find_child('StoryChapter_1',true,false));ck(offset()==0 and app.selected_stage_id=='ch2_1','genuine chapter switch starts at first stage')
  await tap(app.find_child('StoryChapter_0',true,false));ck(offset()==0 and app.selected_stage_id=='ch1_1','returning chapter follows explicit start-at-first rule')
 app.queue_free();await frames();await create_timer(.3).timeout
 print('STORY NAVIGATION V241: %d checks, %d failures'%[checks,failures]);quit(1 if failures else 0)
