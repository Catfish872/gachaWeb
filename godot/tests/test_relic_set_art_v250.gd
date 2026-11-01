extends SceneTree

const BASE := "res://assets/relic_sets/"
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		push_error(description)

func run() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BASE + "art_manifest.json"))
	var source := (load(BASE + "relic_sets_atlas_v250.png") as Texture2D).get_image()
	check(source != null and not source.is_empty(), "source atlas loads")
	check(source.get_size() == Vector2i(1145, 1374), "source dimensions preserved")
	check(source.detect_alpha() == Image.ALPHA_BLEND, "original transparent alpha preserved")
	check(FileAccess.get_sha256(BASE + "relic_sets_atlas_v250.png") == manifest.sha256, "generated source SHA-256 matches provenance")
	check(manifest.entries.size() == 30, "thirty set-specific sprites")
	var regions := {}
	var paths := {}
	for entry in manifest.entries:
		var description: String = entry.set_id + "/" + entry.slot_id
		var texture := load(str(entry.resource)) as AtlasTexture
		check(texture != null, description + " AtlasTexture loads")
		if texture == null:
			continue
		check(texture.atlas != null and texture.atlas.resource_path == BASE + "relic_sets_atlas_v250.png", description + " shares original sheet")
		check(texture.filter_clip, description + " clips neighboring texels")
		check(texture.region == Rect2(entry.region[0], entry.region[1], entry.region[2], entry.region[3]), description + " fitted integer region")
		check(Rect2(Vector2.ZERO, Vector2(source.get_size())).encloses(texture.region), description + " region stays inside atlas")
		check(texture.margin == Rect2(entry.margin[0], entry.margin[1], entry.margin[2], entry.margin[3]), description + " transparent virtual margin")
		check(texture.get_width() == texture.get_height() and texture.margin.position.x >= 8 and texture.margin.position.y >= 8, description + " padded square inventory footprint")
		check(not regions.has(str(texture.region)), description + " unique source region")
		check(not paths.has(str(entry.resource)), description + " unique resource identity")
		regions[str(texture.region)] = true
		paths[str(entry.resource)] = true
		var pixels := source.get_region(Rect2i(texture.region))
		var used := pixels.get_used_rect()
		check(used.size.x > 100 and used.size.y > 100, description + " substantial visible artwork")
		var opaque_count := 0
		var transparent_count := 0
		for y in range(pixels.get_height()):
			for x in range(pixels.get_width()):
				var alpha := pixels.get_pixel(x, y).a
				if alpha >= 0.75:
					opaque_count += 1
				if alpha <= 0.01:
					transparent_count += 1
		check(opaque_count > 7000 and transparent_count > pixels.get_width() * pixels.get_height() * 0.08, description + " cutout has solid artwork and transparent negative space")
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/catalog.json"))
	for set_id in catalog.get("RelicSets", {}):
		var set_data: Dictionary = catalog.RelicSets[set_id]
		for slot in catalog.RelicSlots:
			var expected: String = BASE + str(set_id) + "/" + str(slot.id) + ".tres"
			check(str(set_data.get("slotIcons", {}).get(slot.id, "")) == expected, str(set_id) + "/" + str(slot.id) + " catalog path resolves")
	print("RELIC SET ART V2.5: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
