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
 app.set_process(false);app.music_enabled=true
 app.current_screen='home';app._sync_music()
 var hub=app.music_audio
 for page in ['party','growth','relics','shop','save','summon']:
  app.current_screen=page;app._sync_music();ck(app.music_audio==hub,'hub functional visit preserves same player '+page)
 app.current_screen='extraction';app.model.extraction.start_run(0);app._sync_music()
 var exploration=app.music_audio
 for kind in ['rest','vault','key_vault','shrine','cache']:
  app.model.state.extraction.run.room={'type':kind,'districtId':'none'}
  app._sync_music();ck(app.music_audio==exploration,'room changes never interrupt same-act music '+kind)
 for page in ['growth','relics','shop','save','party']:
  app.current_screen=page;app._sync_music();ck(app.music_audio==exploration,'auxiliary visit inherits expedition '+page)
 app.current_screen='battle';app.battle_config={'isExtraction':true,'kind':'battle','enemies':['wolf']};app._sync_music()
 ck(app.music_audio==exploration,'ordinary encounter keeps exploration music')
 exploration.seek(12.0)
 app.battle_config.kind='boss';app._sync_music()
 ck(app.music_audio!=exploration and app.music_audio.get_meta('track')=='determined_pursuit','major boss battle transitions')
 app.current_screen='extraction';app._sync_music()
 ck(app.music_audio==exploration and exploration.get_playback_position()>=11.9,'return resumes existing exploration cursor')
 app.model.extraction.run().act=2;app._sync_music()
 ck(app.music_audio.get_meta('track')=='medieval_exploration','new act may change score')
 app.model.extraction.run().act=3;app._sync_music()
 ck(app.music_audio.get_meta('track')=='dungeon_mystic','final act has distinct score')
 app.current_screen='home';app._sync_music();ck(app.music_audio==hub,'camp returns to original player')
 app.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
 ck(app.get_meta('application_paused',false) and app.music_audio.stream_paused,'pause freezes current music')
 app.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
 ck(not app.music_audio.stream_paused,'resume restores current without replay')
 for voice in app._music_pool.values():
  ck(voice==app.music_audio or voice.stream_paused,'background tracks remain silent after app resume')
 app.music_enabled=false;app._sync_music();ck(app.music_audio.stream_paused,'music mute pauses without forgetting cursor')
 app.music_enabled=true;app._sync_music();ck(not app.music_audio.stream_paused,'unmute restores the current track')
 for i in 30:
  app.current_screen='home' if i%2==0 else 'story';app._sync_music()
 ck(app._music_pool.size()<=5,'scene switching has bounded stream players')
 var audible:=0
 for voice in app._music_pool.values():
  if voice.playing and not voice.stream_paused:audible+=1
 ck(audible<=2,'at most two sides of a crossfade play')
 app.queue_free();await process_frame;await create_timer(.3).timeout
 print('MUSIC CONTEXT: %d checks, %d failures' % [checks,failures]);quit(1 if failures else 0)
