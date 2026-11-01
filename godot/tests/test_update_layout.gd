extends SceneTree
var app
var failures:=0
var checks:=0
func _initialize():call_deferred('run')
func frames(n:int=12):
 for i in n:await process_frame
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures+=1;push_error(label)
func run():
 app=load('res://main.tscn').instantiate();root.add_child(app)
 await frames()
 app.set_process(false)
 for resolution in [Vector2i(2340,1080),Vector2i(1920,1080),Vector2i(1280,720)]:
  root.size=resolution;await frames()
  for page in ['home','extraction','abyss']:
   app.updater.state.status='idle'
   app.navigate(page);await frames()
   var before:Vector2=app.page_scroll.size
   app.updater.state.status='available'
   app.updater.state.message='发现新版本，欢迎体验更流畅的旅程，这是一段很长的更新提示'
   app._refresh_update_notice();await frames()
   check(app.update_notice.size.y>=48,'update touch target 48')
   check(app.update_notice.get_global_rect().end.x<=app.size.x,'update fits viewport')
   check(app.page_scroll.size.is_equal_approx(before),page+' update does not consume body space')
   check(app.shell.size.x<=app.size.x+1 and app.shell.size.y<=app.size.y+1,page+' shell fits')
   check(app.page_scroll.get_global_rect().end.y<=app.size.y+1,page+' body viewport fits')
   check(app.main_body.get_global_rect().end.y<=app.size.y+1,page+' fixed content fits')
 app.queue_free();await frames();await create_timer(.3).timeout
 print('UPDATE LAYOUT: %d checks, %d failures' % [checks,failures])
 quit(0 if failures==0 else 1)
