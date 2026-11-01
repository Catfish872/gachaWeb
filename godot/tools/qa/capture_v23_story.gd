extends SceneTree
var app
const OUT='/workspace/scratch/8f1fc457a062/v23-shell-review'
func _initialize():call_deferred('run')
func frames():
 for i in 16:await process_frame
func shot(name):
 await frames();await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(OUT+'/'+name+'.png')
func run():
 root.size=Vector2i(1170,540)
 app=load('res://main.tscn').instantiate();root.add_child(app);await frames();app.set_process(false)
 for width in [1170,960]:
  root.size=Vector2i(width,540);await frames()
  app.navigate('story');await shot('story-'+str(width))
  app._play_dialogue('ch1_1_pre',func():pass)
  app.dialogue_prose.visible_characters=-1
  if app.dialogue_tween:app.dialogue_tween.kill()
  await shot('dialogue-'+str(width))
  var found=false
  for key in app.model.catalog.DialogueData:
   if found:break
   var lines=app.model.catalog.DialogueData[key]
   for index in lines.size():
    if lines[index].get('portrait') is String:
     app._play_dialogue(key,func():pass);app.dialogue_index=index;app._render_dialogue()
     if app.dialogue_tween:app.dialogue_tween.kill()
     app.dialogue_prose.visible_characters=-1
     await shot('dialogue-portrait-'+str(width));found=true;break
  app._finish_dialogue()
 app.queue_free();await frames();await create_timer(.3).timeout
 print('STORY CAPTURE COMPLETE');quit()
