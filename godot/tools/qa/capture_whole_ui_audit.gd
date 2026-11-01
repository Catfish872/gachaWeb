extends SceneTree
var app
const OUT='/workspace/scratch/8f1fc457a062/v23-whole-ui-audit'
func _initialize():call_deferred('run')
func frames():
 for i in 16:await process_frame
func shot(name):
 await frames();await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(OUT+'/'+name+'.png')
func run():
 DirAccess.make_dir_recursive_absolute(OUT)
 root.size=Vector2i(960,540)
 app=load('res://main.tscn').instantiate();root.add_child(app);await frames();app.set_process(false)
 for page in ['home','story','party','growth','relics','summon','shop','abyss','extraction','save']:
  app.navigate(page);await shot(page)
 app._show_navigation();await shot('menu');app._clear_overlay()
 app._show_audio_settings();await shot('settings');app._clear_overlay()
 app.navigate('growth');app.growth_panel='skills';app._render_screen();await shot('growth-skills')
 app.navigate('abyss');app.model.prepare_abyss();app.model.state.abyss.rogue.nextStep={'type':'reward'}
 app.model.state.abyss.rogue.pendingChoices=app.model.catalog.AbyssData.rogue.rewards.slice(0,3)
 app._render_screen();await shot('abyss-reward')
 app.battle_settled=true;app.model.reset_abyss()
 var prepared=app.model.prepare_stage('ch1_1')
 if prepared.get('success',false):
  app._start_battle(prepared.config);await shot('battle')
  app._show_unit_details(app.battle.state.allies[0]);await shot('battle-details');app._clear_overlay()

 app.queue_free();await frames();await create_timer(.3).timeout
 print('WHOLE UI AUDIT COMPLETE');quit()
