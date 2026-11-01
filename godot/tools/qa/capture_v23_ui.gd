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
 DirAccess.make_dir_recursive_absolute(OUT)
 root.size=Vector2i(1170,540)
 app=load('res://main.tscn').instantiate();root.add_child(app);await frames()
 app.set_process(false)
 app.navigate('home');await shot('home')
 app.navigate('abyss');await shot('abyss-departure')
 app.model.prepare_abyss()
 app.model.state.abyss.rogue.nextStep={'type':'reward'}
 app.model.state.abyss.rogue.pendingChoices=app.model.catalog.AbyssData.rogue.rewards.slice(0,3)
 app._render_screen();await shot('abyss-effects')
 app.abyss_panel='meta';app._render_screen();await shot('abyss-meta')
 app.battle_settled=true
 var abyss_snapshot=app.model.state.abyss.duplicate(true)
 app.model.reset_abyss()
 var prepared=app.model.prepare_stage('ch1_1')
 if prepared.get('success',false):app._start_battle(prepared.config);await shot('battle-icons')
 root.size=Vector2i(960,540);await frames()
 app.battle_settled=true;app.navigate('home');await shot('home-960')
 app.model.state.abyss=abyss_snapshot
 app.abyss_panel='expedition';app.navigate('abyss');await shot('abyss-effects-960')
 app.queue_free();await frames();await create_timer(.3).timeout
 print('V23 SHELL CAPTURE COMPLETE');quit()
