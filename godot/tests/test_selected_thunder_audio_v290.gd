extends "res://tests/test_lantern_journey_ui_v270.gd"
const Thunder = preload("res://scripts/thunder_audio.gd")
func run() -> void:
 app=load("res://main.tscn").instantiate();root.add_child(app);await frames(8);app.set_process(false)
 var manifest=JSON.parse_string(FileAccess.get_file_as_string(Thunder.ROOT+"manifest.json"))
 ck(manifest.size()==5,"five approved unique recordings")
 var hashes: Array=[]
 for entry in manifest:
  var id=str(entry.id);var path=Thunder.music_path(id)
  ck(path==entry.path,"manifest route "+id)
  ck(FileAccess.get_sha256(path)==entry.sha256,"asset checksum "+id)
  var stream=AudioStreamOggVorbis.load_from_file(ProjectSettings.globalize_path(path))
  ck(stream!=null,"decode "+id)
  ck(absf(stream.get_length()-float(entry.duration_seconds))<.03,"duration "+id)
  var imported: AudioStream=load(path)
  ck(imported!=null and absf(imported.get_length()-float(entry.duration_seconds))<.03,"import cache duration "+id)
  ck(absf(float(entry.measured_lufs)+22)<.25,"loudness "+id)
  ck(float(entry.measured_true_peak_db)<=-2,"peak ceiling "+id)
  ck(bool(entry.seam_jump_below_p999),"sample seam "+id)
  ck(not hashes.has(entry.sha256),"distinct audio "+id);hashes.append(entry.sha256)
 ck(Thunder.music_path("thunder_city_street")==Thunder.music_path("thunder_city_gate"),"shared exploration theme")
 for id in ["raisa_reveal","vika_reveal","eve_reveal"]:
  ck(Thunder.music_path(id)==Thunder.music_path("thunder_summon"),"approved Wasteland summon "+id)
 ck(Thunder.music_path("thunder_boss")!=Thunder.music_path("thunder_city_core"),"boss no longer aliases core")
 ck(Thunder.music_path("thunder_boss")!=Thunder.music_path("thunder_summon"),"boss and summon distinct")
 app._show_music_credits();await frames(3)
 var shown=text_under(app.overlay)
 for entry in Thunder.music_credits():
  for field in ["title","creator","license","source_url","license_url","changes"]:
   ck(shown.contains(str(entry[field])),"visible credit "+str(entry.id)+" "+field)
 ck(shown.contains("Wasteland Overdrive") and shown.contains("Colossal Boss Battle Theme"),"selected titles displayed")
 ck(not shown.contains("Cinematic intro soundtrack"),"discarded candidate excluded")
 app.queue_free();await frames(4)
 await create_timer(0.5).timeout
 print("SELECTED THUNDER AUDIO V290: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
