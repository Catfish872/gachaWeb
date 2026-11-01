extends SceneTree

# Headless contact review through Godot's Image API, using the production
# AtlasTexture region/margin metadata. The original generated atlas is unchanged.
# These QA images are not a substitute for an in-game GPU-rendered screenshot.
const BASE := "res://assets/relic_sets/"

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BASE + "art_manifest.json"))
	var output_directory := "res://validation/relic-art-v250"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_directory))
	for edge in [40, 80, 160]:
		var gap: int = 16 if edge < 160 else 24
		var tile: int = edge + gap
		var sheet := Image.create(tile * 5 + gap, tile * 6 + gap, false, Image.FORMAT_RGBA8)
		sheet.fill(Color("101522"))
		for index in range(manifest.entries.size()):
			var entry: Dictionary = manifest.entries[index]
			var texture := load(str(entry.resource)) as AtlasTexture
			var padded := Image.create(texture.get_width(), texture.get_height(), false, Image.FORMAT_RGBA8)
			padded.fill(Color.TRANSPARENT)
			var crop := texture.get_image()
			crop.convert(Image.FORMAT_RGBA8)
			padded.blit_rect(crop, Rect2i(Vector2i.ZERO, crop.get_size()), Vector2i(texture.margin.position))
			padded.resize(edge, edge, Image.INTERPOLATE_LANCZOS)
			var destination := Vector2i(gap + (index % 5) * tile, gap + (index / 5) * tile)
			sheet.fill_rect(Rect2i(destination - Vector2i(2, 2), Vector2i(edge + 4, edge + 4)), Color("1c2738"))
			sheet.blend_rect(padded, Rect2i(Vector2i.ZERO, padded.get_size()), destination)
		var path: String = output_directory + "/contact_%dpx.png" % edge
		var error := sheet.save_png(path)
		if error != OK:
			push_error("Cannot save contact review: " + path)
			quit(1)
			return
		print("GODOT IMAGE CONTACT: " + ProjectSettings.globalize_path(path))
	quit()
