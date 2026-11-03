extends SceneTree

const Audio := preload("res://scripts/windpass_audio.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		push_error(label)
		failures += 1

func _initialize() -> void:
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(Audio.ROOT + "manifest.json"))
	for asset in manifest:
		var stream := AudioStreamOggVorbis.load_from_file(ProjectSettings.globalize_path(str(asset.path)))
		check(stream != null, "Godot raw Vorbis decode: " + str(asset.id))
		if stream != null:
			check(absf(stream.get_length() - float(asset.duration_seconds)) < 0.02, "Godot duration: " + str(asset.id))
			stream.loop = bool(asset.loop)
			check(stream.loop == bool(asset.loop), "Music/effect loop flag: " + str(asset.id))
	for key in Audio.MUSIC:
		check(FileAccess.file_exists(Audio.music_path(key)), "Music source missing: " + key)
	check(Audio.music_path("lantern_road").is_empty(), "Historical music routing preserved")
	for pair in [["tiya_normal", "tiya_basic"], ["tiya_skill", "tiya_skill"], ["tiya_ult", "tiya_ultimate"], ["lumi_normal", "lumi_basic"], ["lumi_skill", "lumi_skill"], ["lumi_ult", "lumi_ultimate"]]:
		var sound := Audio.battle_sound([{"type": "skill", "skill_id": pair[0]}])
		check(sound.get("clip") == pair[1] and FileAccess.file_exists(sound.path), "Character clip: " + pair[0])
	check(Audio.battle_sound([{"type": "skill", "skill_id": "selin_skill"}]).is_empty(), "Historical character routing preserved")
	check(Audio.battle_sound([{"type": "skill", "skill_id": "roc_warning_high"}]).get("clip") == "roc_warning", "Boss warning is audible without damage")
	check(Audio.battle_sound([{"type": "skill", "skill_id": "roc_storm"}]).get("clip") == "roc_gust", "Boss gust")
	var proc := {"type": "damage", "skill_id": "wind_primary", "follow_up": true}
	check(Audio.battle_sound([proc, proc, proc]).get("max_voices") == 1, "Repeated pierce selects one quiet effect")
	check(Audio.battle_sound([proc, {"type": "skill", "skill_id": "tiya_ult"}]).get("clip") == "tiya_ultimate", "Ultimate takes precedence over follow-up")
	check(Audio.battle_sound([{"type": "skill", "skill_id": "windfield_updraft_feed"}]).get("clip") == "wind_field_pulse", "Wind field pulse")
	check(Audio.battle_sound([{"type": "death", "target": "enemy_4"}], [{"uid": "enemy_4", "dataId": "windfield_crosswind"}]).get("clip") == "wind_field_release", "Existing death event resolves field identity")
	check(Audio.field_entry("windfield_updraft").get("clip") == "wind_field_open", "Explicit field entry hook")
	check(Audio.field_entry("wolf").is_empty(), "Other encounter entry untouched")
	check(Audio.battle_sound([{}, 17, "bad"]).is_empty(), "Irrelevant events ignored")
	print("WINDPASS AUDIO ROUTING: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
