extends SceneTree

var checks := 0
var failures := 0
var app

func _initialize() -> void: call_deferred("run")

func ck(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("SUMMON MUSIC: " + label)

func select_pool(pool: String, expected: String) -> void:
	app.selected_pool = pool
	app.current_screen = "summon"
	app._sync_music()
	ck(app.music_audio.get_meta("track") == expected, pool + " selects " + expected)
	var player: AudioStreamPlayer = app.music_audio
	player.seek(3.0)
	for page in ["growth", "party", "relics", "shop", "save"]:
		app.current_screen = page
		app._sync_music()
		ck(app.music_audio == player, pool + " keeps the same player on " + page)
	app.current_screen = "summon"
	app._sync_music()
	ck(app.music_audio == player and player.get_playback_position() >= 2.9, pool + " returns without replaying music")

func run() -> void:
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	for frame in 8: await process_frame
	app.set_process(false)
	app.music_enabled = true
	app.sound_enabled = false
	app.current_screen = "home"
	app._sync_music()
	for entry in [["standard","old_tower_inn"], ["limited_kaldi","old_tower_inn"], ["limited_selin","lantern_road"], ["limited_tiya","tiya_reveal"], ["limited_lumi","lumi_reveal"], ["limited_selin","lantern_road"], ["standard","old_tower_inn"]]:
		select_pool(entry[0], entry[1])
	ck(app._music_pool.size() == 4, "all banner switches reuse four existing track players")
	app.current_screen = "story"
	app.selected_chapter = 2
	app._sync_music()
	select_pool("standard", "lantern_road")
	select_pool("limited_tiya", "tiya_reveal")
	select_pool("limited_kaldi", "lantern_road")
	app.current_screen = "story"
	app.selected_chapter = 0
	app._sync_music()
	select_pool("limited_lumi", "lumi_reveal")
	select_pool("standard", "medieval_exploration")
	select_pool("limited_selin", "lantern_road")
	var selin_player: AudioStreamPlayer = app.music_audio
	app.music_enabled = false
	app._sync_music()
	ck(selin_player.stream_paused, "mute pauses selected old-character score")
	app.music_enabled = true
	app._sync_music()
	ck(app.music_audio == selin_player and not selin_player.stream_paused, "unmute restores selected old-character score")
	app.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	ck(selin_player.stream_paused, "background pauses current banner music")
	app.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	ck(app.music_audio == selin_player and not selin_player.stream_paused, "foreground resumes same banner player")
	var audible := 0
	for player in app._music_pool.values():
		if player.playing and not player.stream_paused: audible += 1
	ck(audible == 1, "foreground leaves one current score audible")
	app.queue_free()
	await process_frame
	print("SUMMON MUSIC V280: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
