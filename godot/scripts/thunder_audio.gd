extends RefCounted
## Thunder-city score routing. Playback ownership, user volume and crossfades
## stay in Main. Track selection reads scene IDs and never changes game state.
const ROOT := "res://assets/audio/content_v290/"
const CHARACTER_ROOT := "res://assets/audio/content_v293/"
const CHARACTER_MUSIC := ["vika_reveal", "eve_reveal"]
const MUSIC := ["thunder_city_gate", "thunder_city_core", "thunder_city_shrine", "thunder_summon", "thunder_boss"]
const AREA_TRACKS := {"thunder_city_street":"thunder_city_gate"}
const REVEAL_TRACKS := {"raisa_reveal":"thunder_summon", "vika_reveal":"vika_reveal", "eve_reveal":"eve_reveal"}
const CREDITS := [
  {
    "id": "vika_reveal",
    "title": "Cipher",
    "creator": "Kevin MacLeod (incompetech.com)",
    "license": "CC BY 4.0",
    "source_url": "https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1100844",
    "license_url": "https://creativecommons.org/licenses/by/4.0/",
    "changes": "改动：保留完整曲目、原速与自然尾音；首尾各5毫秒平滑；固定增益对齐至-22 LUFS；Ogg Vorbis转码；整曲结束后从头播放。"
  },
  {
    "id": "eve_reveal",
    "title": "Ascending the Vale",
    "creator": "Kevin MacLeod (incompetech.com)",
    "license": "CC BY 4.0",
    "source_url": "https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1600064",
    "license_url": "https://creativecommons.org/licenses/by/4.0/",
    "changes": "改动：保留完整曲目、原速与自然尾音；首尾各5毫秒平滑；固定增益对齐至-22 LUFS；Ogg Vorbis转码；整曲结束后从头播放。"
  },
  {
    "id": "thunder_city_gate",
    "title": "Electric City - Part 1",
    "creator": "Tsorthan Grove",
    "license": "CC BY 4.0",
    "source_url": "https://opengameart.org/content/electric-city",
    "license_url": "https://creativecommons.org/licenses/by/4.0/",
    "changes": "改动：保留作者完整循环及原速；首尾各5毫秒平滑；固定增益对齐至-22 LUFS；Ogg Vorbis转码。"
  },
  {
    "id": "thunder_city_core",
    "title": "Electric City - Part 2",
    "creator": "Tsorthan Grove",
    "license": "CC BY 4.0",
    "source_url": "https://opengameart.org/content/electric-city",
    "license_url": "https://creativecommons.org/licenses/by/4.0/",
    "changes": "改动：保留作者完整循环及原速；首尾各5毫秒平滑；固定增益对齐至-22 LUFS；Ogg Vorbis转码。"
  },
  {
    "id": "thunder_city_shrine",
    "title": "Dark Shrine Loop",
    "creator": "qubodup and yd",
    "license": "CC0 1.0",
    "source_url": "https://opengameart.org/content/dark-shrine-loop",
    "license_url": "https://creativecommons.org/publicdomain/zero/1.0/",
    "changes": "改动：保留作者完整循环及原速；首尾各5毫秒平滑；固定增益对齐至-22 LUFS；Ogg Vorbis转码。"
  },
  {
    "id": "thunder_summon",
    "title": "Wasteland Overdrive",
    "creator": "Music by Matthew Pablo (www.matthewpablo.com)",
    "license": "CC BY 3.0",
    "source_url": "https://opengameart.org/content/wasteland-overdrive",
    "license_url": "https://creativecommons.org/licenses/by/3.0/",
    "changes": "改动：保留作者完整循环及原速；首尾各5毫秒平滑；固定增益对齐至-22 LUFS；Ogg Vorbis转码。"
  },
  {
    "id": "thunder_boss",
    "title": "Colossal Boss Battle Theme",
    "creator": "Music by Matthew Pablo (www.matthewpablo.com)",
    "license": "CC BY 3.0",
    "source_url": "https://opengameart.org/content/colossal-boss-battle-theme",
    "license_url": "https://creativecommons.org/licenses/by/3.0/",
    "changes": "改动：保留作者完整循环及原速；首尾各5毫秒平滑；固定增益对齐至-22 LUFS；Ogg Vorbis转码。"
  }
]

static func music_path(track: String) -> String:
	var resolved: String = AREA_TRACKS.get(track, REVEAL_TRACKS.get(track, track))
	if resolved in CHARACTER_MUSIC: return CHARACTER_ROOT + resolved + ".ogg"
	return ROOT + resolved + ".ogg" if resolved in MUSIC else ""

static func music_gain_db(_track: String) -> float:
	return 0.0

static func music_loop_offset(_track: String) -> float:
	return 0.0

static func music_credits() -> Array:
	return CREDITS.duplicate(true)

static func scene_track(background: String) -> String:
	if not background.begins_with("res://assets/content_v290/backgrounds/"): return ""
	if background.get_file().get_basename() in ["observatory", "sunken_tower"]: return "thunder_city_shrine"
	if background.get_file().get_basename() == "rift_core": return "thunder_city_core"
	if background.get_file().get_basename() in ["rain_street", "storm_market", "ward_clinic", "sealed_station"]: return "thunder_city_street"
	return "thunder_city_gate"

static func effect(clip: String, gain_db: float = -11.0) -> Dictionary:
	# These are intentional reuses of the established original battle effects.
	return {"clip":"thunder_city_"+clip, "path":"res://assets/audio/battle/"+clip+".ogg", "gain_db":gain_db, "max_voices":1}

static func battle_sound(events: Array, _units: Array = []) -> Dictionary:
	for event in events:
		if not event is Dictionary or str(event.get("type", "")) != "skill": continue
		var sid := str(event.get("skill_id", ""))
		if sid.begins_with("raisa_"):
			return effect("shield_cast" if sid in ["raisa_ult", "raisa_ultimate"] else "thunder")
		if sid.begins_with("vika_"): return effect("ultimate" if sid in ["vika_ult", "vika_ultimate"] else "thunder", -13.0)
		if sid.begins_with("eve_"): return effect("heal" if sid in ["eve_ult", "eve_ultimate", "eve_skill"] else "thunder", -13.0)
		if sid.begins_with("sealer_"): return effect("shield_cast" if sid == "sealer_ward_guard" else "thunder", -14.0)
	return {}

static func field_entry(data_id: String) -> Dictionary:
	return effect("shield_cast", -16.0) if data_id in ["sealer_core", "sealer_ward"] else {}
