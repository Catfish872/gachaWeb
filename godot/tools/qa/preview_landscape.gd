extends SceneTree
var app
func _initialize(): call_deferred('run')
func run():
 root.size=Vector2i(1170,540)
 app=load('res://main.tscn').instantiate()
 root.add_child(app)
 root.window_input.connect(handle)
 for i in 15: await process_frame
 show_page('home')
func handle(event):
 if event is InputEventKey and event.pressed:
  var pages={KEY_F1:'home',KEY_F2:'story',KEY_F3:'party',KEY_F4:'growth',KEY_F5:'extraction',KEY_F6:'relics',KEY_F7:'shop',KEY_F8:'abyss',KEY_F9:'battle',KEY_F10:'stash'}
  if pages.has(event.keycode):show_page(pages[event.keycode])
  if event.keycode==KEY_F11:capture_all()
  if event.keycode==KEY_U:
   app.updater.state.status='available'
   app.updater.state.message='发现新版本，点击安装'
   app._refresh_update_notice()
  if event.keycode==KEY_F12:quit()
func show_page(page):
 app.battle_settled=true
 app._clear_overlay()
 if page=='relics' and app.model.state.relics.is_empty():
  for i in 12:app.model.add_relic(app.model.generate_relic(3+i%3,['helmet','chest','belt','boots','necklace'][i%5]))
 if page=='battle':
  var prepared=app.model.prepare_stage('ch1_1')
  if prepared.get('success',false):app._start_battle(prepared.config)
 elif page=='stash':
  app.extraction_panel='stash'
  app.navigate('extraction')
 else:
  if page=='extraction':app.extraction_panel='expedition'
  app.navigate(page)

func capture_all():
 var output="/workspace/scratch/8f1fc457a062/shell-review"
 DirAccess.make_dir_recursive_absolute(output)
 for page in ["home","story","party","growth","relics","shop","summon","abyss","battle"]:
  show_page(page)
  for frame in 20:await process_frame
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png(output+"/"+page+"-1170x540.png")
 print("SHELL SCREENSHOTS COMPLETE")
