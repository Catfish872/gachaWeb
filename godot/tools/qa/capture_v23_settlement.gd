extends SceneTree
var app
func _initialize():call_deferred('run')
func run():
 root.size=Vector2i(1170,540)
 app=load('res://main.tscn').instantiate();root.add_child(app)
 for i in 16:await process_frame
 app.set_process(false)
 app.model.extraction.start_run(0)
 app.model.extraction._generate_encounter('battle')
 var prepared=app.model.extraction.prepare_battle()
 app._start_battle(prepared.config)
 app.battle_auto=false
 var guard=0
 while app.battle.state.phase not in ['victory','defeat'] and guard<3000:
  app.battle.auto_step();guard+=1
 app._finish_battle()
 await create_timer(1).timeout
 for i in 16:await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png('/workspace/scratch/8f1fc457a062/v23-shell-review/extraction-settlement.png')
 app.queue_free();await process_frame;await create_timer(.3).timeout
 print('SETTLEMENT CAPTURE COMPLETE');quit()
