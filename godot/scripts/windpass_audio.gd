extends RefCounted
## Wind chapter audio routing. The caller owns playback, pause, volume and voices.
## Selection reads events only and never advances combat or random state.

const ROOT := "res://assets/audio/content_v280/"
const MUSIC := ["windpass_road", "windpass_gallery", "windpass_core", "tiya_reveal", "lumi_reveal"]
const LICENSED_ROOT := "res://assets/audio/licensed_wind_v281/"
const LICENSED_MUSIC := ["tiya_reveal", "lumi_reveal", "windpass_road", "windpass_gallery"]
const LICENSED_CREDITS := [
	{
		"id": "tiya_reveal",
		"title": "Bright Wish · 缇娅卡池",
		"creator": "Kevin MacLeod (incompetech.com)",
		"license": "CC BY 4.0",
		"source_url": "https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1100377",
		"license_url": "https://creativecommons.org/licenses/by/4.0/",
		"changes": "改动：响度对齐、末尾 5 毫秒柔化、Ogg 转码；保留整曲自然落音。"
	},
	{
		"id": "lumi_reveal",
		"title": "Happy moments 1.4 · 露弥卡池",
		"creator": "Centurion_of_war",
		"license": "CC0 1.0",
		"source_url": "https://opengameart.org/content/happy-moments",
		"license_url": "https://creativecommons.org/publicdomain/zero/1.0/",
		"changes": "改动：响度对齐、保留引子并从 25.6 秒循环、末尾 20 毫秒接缝修整、Ogg 转码。"
	},
	{
		"id": "windpass_road",
		"title": "Happy Flutes · 风谷",
		"creator": "Tomasz Kucza / magory.games",
		"license": "CC BY 3.0（OpenGameArt 文件许可）",
		"source_url": "https://opengameart.org/content/happy-flutes-for-fantasy-setting",
		"license_url": "https://creativecommons.org/licenses/by/3.0/",
		"changes": "改动：响度对齐、末尾 5 毫秒柔化、Ogg 转码；保留整曲。",
		"extra": "采样：Improvisation with Sopranino recorder，piermic，CC0 1.0\nhttps://freesound.org/people/piermic/sounds/324085/\nhttps://creativecommons.org/publicdomain/zero/1.0/"
	},
	{
		"id": "windpass_gallery",
		"title": "The World At Your Door · 风廊",
		"creator": "Composed by Jonathan Shaw (www.jshaw.co.uk)",
		"license": "CC BY 3.0",
		"source_url": "https://opengameart.org/content/the-world-at-your-door-rpg-orchestral-essentials-overworld-music",
		"license_url": "https://creativecommons.org/licenses/by/3.0/",
		"changes": "改动：截取原曲第二个完整循环、末尾 20 毫秒接缝修整、响度对齐及 Ogg 转码。"
	}
]
const SKILL_CLIPS := {
	"tiya_normal": "tiya_basic", "tiya_skill": "tiya_skill", "tiya_ult": "tiya_ultimate",
	"lumi_normal": "lumi_basic", "lumi_skill": "lumi_skill", "lumi_ult": "lumi_ultimate",
	"roc_warning": "roc_warning", "roc_warning_high": "roc_warning",
	"roc_gale": "roc_gust", "roc_storm": "roc_gust",
	"windfield_updraft_feed": "wind_field_pulse", "windfield_crosswind_guard": "wind_field_pulse",
	"windwheel_warning": "wind_mechanism_turn"
}

static func music_path(track: String) -> String:
	if track in LICENSED_MUSIC:
		return LICENSED_ROOT + track + ".ogg"
	return ROOT + track + ".ogg" if track in MUSIC else ""

static func music_loop_offset(track: String) -> float:
	# Keep Happy moments 1.4's introduction on first playback only.
	return 25.6 if track == "lumi_reveal" else 0.0

static func music_credits() -> Array:
	return LICENSED_CREDITS

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
