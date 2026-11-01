extends SceneTree
const Avatars = preload("res://scripts/ui/character_avatar.gd")
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("AVATARS: " + label)
func _initialize() -> void:
	var catalog = JSON.parse_string(FileAccess.get_file_as_string("res://data/catalog.json"))
	for id in catalog.CharacterData:
		check(Avatars.FACE_REGIONS.has(id), id + " curated face region")
		for mode in ["face", "bust"]:
			var texture = Avatars.get_texture(id, mode)
			check(texture is AtlasTexture, id + " " + mode + " uses original atlas")
			if texture is AtlasTexture:
				check(texture.region == Avatars.region_for(id, mode), id + " exact region")
				check(texture.atlas.resource_path == Avatars.source_path(id), id + " original identity")
				check(texture.filter_clip, id + " clipped filtering")
				check(Avatars.get_texture(id, mode) == texture, id + " cached texture")
				check(texture.get_image().get_used_rect().get_area() > texture.region.get_area() * 0.15, id + " nonempty visible portrait")
	check(Avatars.get_texture("unknown_character") == null, "unknown safely falls back")
	check(Avatars.source_path("kaldi").ends_with("kaldi-battle.png"), "Kaldi uses humanoid art, not landscape dragon")
	print("AVATARS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
