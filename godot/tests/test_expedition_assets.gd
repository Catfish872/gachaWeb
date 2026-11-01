extends SceneTree

var checks := 0
var errors := 0

func ck(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error("EXPEDITION_ASSETS: " + message)

func _initialize() -> void:
	var ids: Array[String] = []
	for i in 6: ids.append("armor_%d" % i)
	for i in range(1, 6): ids.append("pack_%d" % i)
	for id in ["key_ruins", "key_forest", "key_sanctum", "repair_patch", "repair_kit", "repair_core", "energy_tonic", "energy_flask", "energy_crystal", "revival_incense", "revival_bloom", "revival_phoenix", "cleanse_salt", "cleanse_water", "cleanse_censer"]: ids.append(id)
	for i in 6: ids.append("ration_%d" % i)
	ck(ids.size() == 32, "all 32 inventory asset identifiers")
	ids.append("relay_chest")
	for id in ids:
		var path := "res://assets/items/expedition_v230/" + id + ".png"
		var texture = load(path)
		ck(texture is Texture2D, id + " imports as texture")
		if texture is Texture2D:
			var image: Image = texture.get_image()
			ck(image.get_width() >= 200 and image.get_height() >= 200, id + " sufficient source resolution")
			ck(image.detect_alpha() != Image.ALPHA_NONE, id + " preserves transparency")
			ck(image.get_pixel(0, 0).a == 0, id + " transparent corner")
	for id in ["astral_vault", "courier_waystation"]:
		var texture = load("res://assets/extraction/rooms/" + id + ".webp")
		ck(texture is Texture2D, id + " background imported")
		if texture is Texture2D: ck(texture.get_width() > texture.get_height(), id + " landscape")
	for id in ["old_tower_inn", "dungeon_mystic"]:
		var stream = load("res://assets/audio/music/licensed/" + id + ".ogg")
		ck(stream is AudioStreamOggVorbis, id + " music imported")
		if stream is AudioStreamOggVorbis: ck(stream.get_length() > 60, id + " complete long-form track")
	for id in ["pickup", "repair", "key", "relay"]:
		var stream = load("res://assets/audio/ui/" + id + ".ogg")
		ck(stream is AudioStreamOggVorbis, id + " feedback imported")
		if stream is AudioStreamOggVorbis: ck(stream.get_length() > 0.1 and stream.get_length() < 0.8, id + " brief feedback")
	print("EXPEDITION_ASSETS: %d checks, %d failures" % [checks, errors])
	quit(1 if errors else 0)
