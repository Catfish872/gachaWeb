extends SceneTree
var app
var checks:=0
var failures:=0
func _initialize():call_deferred('run')
func frames():
 for i in 12:await process_frame
func ck(ok:bool,label:String):
 checks+=1
 if not ok:failures+=1;push_error(label)
func icons(node:Node)->int:
 var result:=0
 for child in node.get_children():
  if child is TextureRect and child.texture!=null:result+=1
  result+=icons(child)
 return result
func run():
 app=load('res://main.tscn').instantiate();root.add_child(app);await frames();app.set_process(false)
 for resolution in [Vector2i(1170,540),Vector2i(960,540)]:
  root.size=resolution;await frames()
  app.navigate('home');app._show_navigation();await frames()
  for tab in app.TABS:
   var button=app.find_child('MenuNav_'+tab[0],true,false)
   ck(button!=null and button.icon!=null,'menu semantic icon '+tab[0])
   ck(button.get_global_rect().end.y<=app.size.y,'menu entry visible '+tab[0])
  app._clear_overlay();app.navigate('save');await frames()
  ck(icons(app.main_body)>=12,'three save slots have identity and summary icons')
  app.navigate('growth');app.growth_panel='stats';app._render_screen();await frames()
  var stats_count:=icons(app.main_body)
  ck(stats_count>=9,'stats semantic icons exist')
  app.growth_panel='skills';app._render_screen();await frames();ck(icons(app.main_body)>=6,'skill semantic icons exist')
  app.growth_panel='constellation';app._render_screen();await frames();ck(icons(app.main_body)>=10,'constellation semantic icons exist')
 app.queue_free();await frames();await create_timer(.3).timeout
 print('UI SEMANTIC COVERAGE: %d checks, %d failures'%[checks,failures]);quit(1 if failures else 0)
