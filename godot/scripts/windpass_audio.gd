extends RefCounted
## Wind chapter audio routing. The caller owns playback, pause, volume and voices.
## Selection reads events only and never advances combat or random state.

const ROOT := "res://assets/audio/content_v280/"
const MUSIC := ["windpass_road", "windpass_gallery", "windpass_core", "tiya_reveal", "lumi_reveal"]
const SKILL_CLIPS := {
	"tiya_normal": "tiya_basic", "tiya_skill": "tiya_skill", "tiya_ult": "tiya_ultimate",
	"lumi_normal": "lumi_basic", "lumi_skill": "lumi_skill", "lumi_ult": "lumi_ultimate",
	"roc_warning": "roc_warning", "roc_warning_high": "roc_warning",
	"roc_gale": "roc_gust", "roc_storm": "roc_gust",
	"windfield_updraft_feed": "wind_field_pulse", "windfield_crosswind_guard": "wind_field_pulse",
	"windwheel_warning": "wind_mechanism_turn"
}

static func music_path(track: String) -> String:
	return ROOT + track + ".ogg" if track in MUSIC else ""

static func music_gain_db(_track: String) -> float:
	# Assets share a measured -22 LUFS target. Existing master gain stays effective.
	return 0.0

static func effect(clip: String) -> Dictionary:
	var quiet := clip in ["wind_field_pulse", "wind_pierce"]
	return {"clip": clip, "path": ROOT + clip + ".ogg", "gain_db": -15.0 if quiet else -9.0, "max_voices": 1 if quiet else 2}

static func battle_sound(events: Array, units: Array = []) -> Dictionary:
	var selected := ""
	var priority := -1
	for event in events:
		if not event is Dictionary:
			continue
		var kind := str(event.get("type", ""))
		var skill := str(event.get("skill_id", ""))
		if kind == "skill" and SKILL_CLIPS.has(skill):
			var candidate: String = SKILL_CLIPS[skill]
			var rank := 3 if candidate.ends_with("ultimate") else 1 if candidate == "wind_field_pulse" else 2
			if rank > priority:
				selected = candidate
				priority = rank
		elif kind == "damage" and skill in ["wind_primary", "wind_gold"] and bool(event.get("follow_up", false)) and priority < 0:
			selected = "wind_pierce"
			priority = 0
		elif kind == "death" and priority < 1:
			var target := str(event.get("target", ""))
			for unit in units:
				if unit is Dictionary and str(unit.get("uid", "")) == target and str(unit.get("dataId", unit.get("id", ""))) in ["windfield_updraft", "windfield_crosswind"]:
					selected = "wind_field_release"
					priority = 1
	return effect(selected) if not selected.is_empty() else {}

static func field_entry(data_id: String) -> Dictionary:
	# Explicit scene-entry hook; no invented battle phase or timer event.
	return effect("wind_field_open") if data_id in ["windfield_updraft", "windfield_crosswind"] else {}
