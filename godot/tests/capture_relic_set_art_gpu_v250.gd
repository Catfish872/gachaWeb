extends SceneTree

# Run in an authorized graphical session with --rendering-method gl_compatibility.
# Actual TextureRect/AtlasTexture viewport capture; no game save is loaded or changed.
const BASE := "res://assets/relic_sets/"

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("GPU contact capture requires the authorized graphical display.")
		quit(2)
		return
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BASE + "art_manifest.json"))
	var output_directory := "res://validation/relic-art-v250"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_directory))
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.mode = Window.MODE_WINDOWED
	root.title = "Relic Set Art V2.5 GPU Review"
	for edge in [40, 80, 160]:
		var gap: int = 16 if edge < 160 else 24
		var tile: int = edge + gap
		var dimensions := Vector2i(tile * 5 + gap, tile * 6 + gap)
		root.size = dimensions
		var page := Control.new()
		page.size = Vector2(dimensions)
		root.add_child(page)
		var background := ColorRect.new()
		background.color = Color("101522")
		background.size = Vector2(dimensions)
		page.add_child(background)
		for index in range(manifest.entries.size()):
			var destination := Vector2(gap + (index % 5) * tile, gap + (index / 5) * tile)
			var square := ColorRect.new()
			square.color = Color("1c2738")
			square.position = destination - Vector2(2, 2)
			square.size = Vector2(edge + 4, edge + 4)
			page.add_child(square)
			var item := TextureRect.new()
			item.texture = load(str(manifest.entries[index].resource))
			item.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			item.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			item.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			item.position = destination
			item.size = Vector2(edge, edge)
			page.add_child(item)
		for frame in range(5):
			await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var path: String = output_directory + "/gpu_contact_%dpx.png" % edge
		if image.is_empty() or image.save_png(path) != OK:
			push_error("Cannot save GPU contact review: " + path)
			quit(1)
			return
		print("GODOT GPU CONTACT: " + ProjectSettings.globalize_path(path) + " size=" + str(image.get_size()))
		page.queue_free()
		await process_frame
	quit()
