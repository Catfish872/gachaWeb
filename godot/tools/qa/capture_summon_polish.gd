extends SceneTree
var app
const OUT='/workspace/scratch/8f1fc457a062/v23-summon-review'
func _initialize():call_deferred('run')
func frames():
 for i in 18:await process_frame
func shot(label):
 await frames();await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(OUT+'/'+label+'.png')
func run():
 DirAccess.make_dir_recursive_absolute(OUT)
 app=load('res://main.tscn').instantiate();root.add_child(app);await frames();app.set_process(false)
 for width in [1170,960]:
  root.size=Vector2i(width,540);await frames()
  app.model.state.resources.diamonds=10000
  app.selected_pool='limited_kaldi';app.navigate('summon');await shot('banner-'+str(width))
  app._summon_character_preview('kaldi');await shot('preview-'+str(width));app._clear_overlay()
  app._pull(1);await shot('portal-'+str(width))
  app.summon_flipped=true;app._reveal_summon();await shot('reveal-'+str(width))
  app._clear_overlay();app._pull(10);app._summon_summary();await shot('ten-'+str(width))
  app._clear_overlay();app.navigate('shop');await shot('store-'+str(width))
 app.queue_free();await frames();await create_timer(.3).timeout
 print('SUMMON POLISH CAPTURE COMPLETE');quit()
