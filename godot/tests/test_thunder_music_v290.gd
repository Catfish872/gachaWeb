extends "res://tests/test_lantern_journey_ui_v270.gd"
const Thunder = preload("res://scripts/thunder_audio.gd")
const BG := "res://assets/content_v290/backgrounds/"

func run() -> void:
	app=load("res://main.tscn").instantiate();root.add_child(app);await frames(8);app.set_process(false)
	app.music_enabled=true;app.sound_enabled=false
	for track in ["thunder_city_gate","thunder_city_street","thunder_city_core","thunder_city_shrine","thunder_summon","raisa_reveal","vika_reveal","eve_reveal","thunder_boss"]:
		var path: String=Thunder.music_path(track)
		ck(not path.is_empty() and FileAccess.file_exists(path),"music asset exists: "+track)
		if path.is_empty() or not FileAccess.file_exists(path):continue
		var stream:=AudioStreamOggVorbis.load_from_file(ProjectSettings.globalize_path(path))
		ck(stream!=null and stream.get_length()>20,"decodable full music: "+track)
	var expected_lengths := {}
	var distinct_hashes := {}
	var manifest: Array=JSON.parse_string(FileAccess.get_file_as_string(Thunder.ROOT+"manifest.json"))
	for entry in manifest:
		expected_lengths[entry.path]=float(entry.duration_seconds)
		distinct_hashes[FileAccess.get_sha256(entry.path)]=true
	ck(distinct_hashes.size()==5,"five distinct selected recordings")
	for character in ["raisa","vika","eve"]:
		app.current_screen="home";app._sync_music()
		app.current_screen="summon";app.selected_pool="limited_"+character;app._sync_music()
		ck(app.music_audio.get_meta("track")==character+"_reveal","dedicated banner: "+character)
		var player: AudioStreamPlayer=app.music_audio
		ck(absf(player.stream.get_length()-expected_lengths[Thunder.music_path(character+"_reveal")])<.03,"actual selected summon recording: "+character)
		player.seek(3.0)
		for screen in ["growth","party","relics","shop","save"]:
			app.current_screen=screen;app._sync_music()
			ck(app.music_audio==player,"functional page keeps banner: "+character+"/"+screen)
		app.current_screen="summon";app._sync_music()
		ck(app.music_audio==player and player.get_playback_position()>=2.9,"banner return resumes: "+character)
		app.music_enabled=false;app._sync_music();ck(player.stream_paused,"mute pauses: "+character)
		app.music_enabled=true;app._sync_music();ck(not player.stream_paused,"unmute resumes: "+character)
	for entry in [["rain_gate","thunder_city_gate"],["rain_street","thunder_city_street"],["rift_core","thunder_city_core"],["observatory","thunder_city_shrine"],["sunken_tower","thunder_city_shrine"]]:
		app.current_screen="battle";app.battle_config={"background":BG+entry[0]+".png","enemies":["slime"]}
		ck(app._music_track_for_context()==entry[1],"ordinary encounter retains area score: "+entry[0])
		app._sync_music()
		ck(app.music_audio.get_meta("track")==entry[1],"actual scene playback: "+entry[0])
		ck(absf(app.music_audio.stream.get_length()-expected_lengths[Thunder.music_path(entry[1])])<.03,"actual selected scene recording: "+entry[0])
		app.battle_config.isBoss=true
		ck(app._music_track_for_context()=="thunder_boss","boss overrides area score: "+entry[0])
	for mode in ["story","extraction","abyss"]:
		app.current_screen="battle"
		app.battle_config={"enemies":["boss_city_sealer"],"background":BG+"rift_core.png","isBoss":true,"isExtraction":mode=="extraction","isAbyss":mode=="abyss"}
		if mode=="abyss":
			app.battle_config.abyssScene={"theme":"thunder_city"}
			app.battle_config.abyssMusic="thunder_city_core"
			app.battle_config.abyssBossMusic=app.model.abyss_boss_music_track(app.battle_config.abyssScene)
		ck(app._music_track_for_context()=="thunder_boss","dedicated boss context: "+mode)
		app._sync_music();ck(app.music_audio.get_meta("track")=="thunder_boss","actual boss playback: "+mode)
		ck(absf(app.music_audio.stream.get_length()-expected_lengths[Thunder.music_path("thunder_boss")])<.03,"actual selected boss recording: "+mode)
	app.current_screen="battle";app.battle_config={"enemies":["boss_city_sealer"],"isBoss":true}
	ck(app._music_track_for_context()=="thunder_boss","boss ID works without background")
	app.current_screen="home";app._sync_music();ck(app.music_audio.get_meta("track")=="old_tower_inn","leaving encounter restores home")
	app.queue_free();await frames(4)
	await create_timer(0.3).timeout
	print("THUNDER MUSIC V290: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
