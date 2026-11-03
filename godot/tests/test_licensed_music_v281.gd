extends "res://tests/test_lantern_journey_ui_v270.gd"
const Music=preload("res://scripts/windpass_audio.gd")
func run()->void:
 app=load("res://main.tscn").instantiate();root.add_child(app);await frames(12);app.set_process(false);app.music_enabled=true
 var manifest=JSON.parse_string(FileAccess.get_file_as_string(Music.LICENSED_ROOT+"manifest.json"))
 ck(manifest.size()==4,"exactly four licensed substitutions")
 for entry in manifest:
  var id=str(entry.id);var path=Music.music_path(id)
  ck(path==entry.path,"exact licensed routing "+id)
  ck(FileAccess.get_sha256(path)==entry.sha256,"runtime asset checksum "+id)
  var stream=AudioStreamOggVorbis.load_from_file(ProjectSettings.globalize_path(path))
  ck(stream!=null,"decode "+id)
  ck(absf(stream.get_length()-float(entry.duration_seconds))<.03,"duration "+id)
  ck(is_equal_approx(Music.music_loop_offset(id),float(entry.loop_offset_seconds)),"loop offset manifest "+id)
  app.current_screen="summon";app.selected_pool="limited_tiya" if id=="tiya_reveal" else "limited_lumi" if id=="lumi_reveal" else "standard"
  if id.begins_with("windpass_"):
   app.current_screen="battle";app.battle_config={"trialKind":"wind","enemies":["wolf"],"background":"res://assets/content_v280/backgrounds/resonance_gallery.png" if id=="windpass_gallery" else "res://assets/content_v280/backgrounds/windpass_road.png"}
  app._sync_music()
  ck(app.music_audio.get_meta("track")==id,"actual context "+id)
  ck(app.music_audio.stream.loop,"runtime loop enabled "+id)
  ck(is_equal_approx(app.music_audio.stream.loop_offset,float(entry.loop_offset_seconds)),"runtime stream offset "+id)
 ck(Music.music_path("windpass_core")==Music.ROOT+"windpass_core.ogg","boss track untouched")
 ck(Music.music_path("lantern_road").is_empty(),"legacy routing left to original branch")
 app.current_screen="battle";app.battle_config={"enemies":["boss_highland_roc"],"isBoss":true};app._sync_music()
 ck(app.music_audio.get_meta("track")=="windpass_core","actual boss context unchanged")
 app._show_music_credits();await frames(4)
 var shown=text_under(app.overlay)
 for entry in Music.music_credits():
  for field in ["title","creator","license","source_url","license_url","changes"]:
   ck(shown.contains(str(entry[field])),"visible credits field "+str(entry.id)+" "+field)
 ck(shown.contains("piermic") and shown.contains("324085"),"sample attribution visible")
 ck(shown.contains("Medieval Exploration") and shown.contains("游戏原创配乐"),"legacy credits preserved")
 app.queue_free();await frames(4)
 print("LICENSED MUSIC V281: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
