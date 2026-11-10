extends "res://tests/test_lantern_journey_ui_v270.gd"
const Thunder = preload("res://scripts/thunder_audio.gd")

func run() -> void:
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await frames(8)
	app.set_process(false)
	app.dialogue_key = ""
	app.music_enabled = true
	app.music_volume_db = -7.0
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(Thunder.CHARACTER_ROOT + "manifest.json"))
	ck(manifest.size() == 2, "two approved new recordings")
	for entry in manifest:
		var path = Thunder.music_path(str(entry.id))
		ck(path == entry.path, "manifest route " + str(entry.id))
		ck(FileAccess.get_sha256(path) == entry.sha256, "asset checksum " + str(entry.id))
		var decoded = AudioStreamOggVorbis.load_from_file(ProjectSettings.globalize_path(path))
		ck(decoded != null, "decode " + str(entry.id))
		ck(absf(decoded.get_length() - float(entry.duration_seconds)) < .03, "full duration " + str(entry.id))
		ck(absf(float(entry.measured_lufs) + 22) < .25, "loudness " + str(entry.id))
		ck(float(entry.measured_true_peak_db) <= -2, "peak ceiling " + str(entry.id))
		ck(bool(entry.seam_jump_below_p999), "sample boundary " + str(entry.id))
		ck(str(entry.mode) == "whole_piece_restart", "honest whole-piece repeat " + str(entry.id))
	var paths: Array = []
	var players: Dictionary = {}
	app.current_screen = "summon"
	for character in ["raisa", "vika", "eve"]:
		var track: String = character + "_reveal"
		app.selected_pool = "limited_" + character
		ck(app._music_track_for_context() == track, "pool chooses " + character)
		var path: String = Thunder.music_path(track)
		ck(not paths.has(path), "unique recording " + character)
		paths.append(path)
		app._sync_music()
		await frames(3)
		var player: AudioStreamPlayer = app.music_audio
		players[character] = player
		ck(str(player.get_meta("track")) == track, "actual player route " + character)
		ck(player.has_stream_playback() and not player.stream_paused, "actual playback " + character)
		ck(player.stream.loop and is_equal_approx(player.stream.loop_offset, 0.0), "whole-piece restart " + character)
		ck(is_equal_approx(app._music_gain(player), -7.0), "user volume respected " + character)
		var expected: AudioStream = load(path)
		ck(absf(player.stream.get_length() - expected.get_length()) < .03, "actual stream duration " + character)
	ck(Thunder.music_path("raisa_reveal") == Thunder.ROOT + "thunder_summon.ogg", "Raisa retained Wasteland")
	await create_timer(1.1).timeout
	ck(players.raisa.stream_paused and players.vika.stream_paused, "previous scores pause after crossfade")
	app.selected_pool = "limited_vika"
	app._sync_music()
	ck(app.music_audio == players.vika, "return reuses player cursor")
	await create_timer(1.1).timeout
	ck(is_equal_approx(app.music_audio.volume_db, -7.0), "crossfade reaches selected volume")
	app.music_enabled = false
	app._sync_music()
	for player in app._music_pool.values():
		ck(player.stream_paused, "music toggle pauses all streams")
	app.music_enabled = true
	app._sync_music()
	ck(app.music_audio == players.vika and not players.vika.stream_paused, "toggle resumes current score")
	app._show_music_credits()
	await frames(3)
	var shown = text_under(app.overlay)
	for entry in Thunder.music_credits():
		for field in ["title", "creator", "license", "source_url", "license_url", "changes"]:
			ck(shown.contains(str(entry[field])), "visible credit " + str(entry.id) + " " + field)
	ck(shown.contains("Cipher") and shown.contains("Ascending the Vale") and shown.contains("Wasteland Overdrive"), "three selected titles visible")
	app.queue_free()
	await frames(4)
	await create_timer(.5).timeout
	print("CHARACTER SUMMON AUDIO V293: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
