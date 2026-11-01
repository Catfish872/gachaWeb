extends SceneTree
var checks:=0
var failures:=0
func _initialize():call_deferred('run')
func ck(ok:bool,label:String):
 checks+=1
 if not ok:failures+=1;push_error('MUSIC: '+label)
func run():
 var app=load('res://main.tscn').instantiate();root.add_child(app)
 for i in 12:await process_frame
 app.set_process(false)
 for page in ['home','shop']:
  app.current_screen=page;ck(app._music_track_for_context()=='old_tower_inn','camp music '+page)
 app.current_screen='battle';ck(app._music_track_for_context()=='determined_pursuit','combat track')
 app.current_screen='extraction';app.model.extraction.start_run(0)
 for kind in ['rest','vault','key_vault','shrine','cache']:
  app.model.state.extraction.run.room={'type':kind,'districtId':'none'}
  var expected='old_tower_inn' if kind=='rest' else ('sunset_walk' if kind=='cache' else 'dungeon_mystic')
  ck(app._music_track_for_context()==expected,'room track '+kind)
 app.current_screen='home';app.music_enabled=true;app._sync_music()
 var first=app.music_audio
 for i in 20:app._sync_music()
 ck(app.music_audio==first,'rerender never restarts same track')
 app._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
 ck(app.get_meta('application_paused',false) and app.music_audio.stream_paused,'pause freezes music and UI clock')
 app._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
 ck(not app.get_meta('application_paused',true) and not app.music_audio.stream_paused,'resume restores without replay')
 app.music_enabled=false;app._sync_music()
 ck(not app.music_audio.playing,'mute stops current music')
 for name in ['old_tower_inn','dungeon_mystic']:
  ck(ResourceLoader.exists('res://assets/audio/music/licensed/'+name+'.ogg'),'licensed track '+name)
 app.queue_free();await process_frame;await create_timer(.3).timeout
 print('MUSIC CONTEXT: %d checks, %d failures' % [checks,failures]);quit(1 if failures else 0)
