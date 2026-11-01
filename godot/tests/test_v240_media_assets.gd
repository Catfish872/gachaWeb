extends SceneTree

var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("V240_MEDIA: " + label)

func _initialize() -> void:
	var seen: Array[String] = []
	for act in [2, 3]:
		for biome in ["ruins", "forest", "sanctum"]:
			var path := "res://assets/extraction/rooms/%s_act%d.webp" % [biome, act]
			var texture = load(path)
			check(texture is Texture2D, path + " loads")
			if texture is Texture2D:
				check(texture.get_width() >= 1600 and texture.get_height() >= 900, path + " resolution")
				check(float(texture.get_width()) / texture.get_height() > 1.7, path + " landscape")
			var digest := FileAccess.get_sha256(path)
			check(not digest.is_empty() and not seen.has(digest), path + " unique art")
			seen.append(digest)
	for id in ["slash", "blunt", "fire", "water", "ice", "thunder", "wind", "heal", "shield_cast", "shield_hit", "shield_break", "critical", "ultimate"]:
		var path := "res://assets/audio/battle/%s.ogg" % id
		var stream = load(path)
		check(stream is AudioStreamOggVorbis, id + " imports")
		if stream is AudioStreamOggVorbis:
			check(stream.get_length() > 0.1 and stream.get_length() < 0.8, id + " short battle feedback")
			check(not stream.loop, id + " not looping")
	print("V240_MEDIA: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
