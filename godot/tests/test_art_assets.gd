extends SceneTree

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
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	for id in ["ayla", "bolt", "cinder", "ember", "gus", "lorin", "shana", "tide", "zeph"]:
		var path := "res://assets/characters/%s.png" % id
		var tex = load(path)
		check(tex is Texture2D, id + " portrait imported")
		var card = scene._portrait(scene.main_body, id, 180)
		var image = card.get_child(0)
		check(image is TextureRect and image.texture.resource_path == path, id + " selects generated portrait")
		check(image.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED, id + " complete portrait aspect")
		check(image.mouse_filter == Control.MOUSE_FILTER_IGNORE, id + " does not intercept touch")
	for screen in ["home", "story", "abyss"]:
		scene.current_screen = screen
		scene.selected_chapter = 1
		scene._render_screen()
		await process_frame
		var expected: String = {"home": "camp", "story": "snowfield", "abyss": "abyss"}[screen]
		check(scene.get_node("SceneBackdrop").texture.resource_path == "res://assets/backgrounds/%s.png" % expected, screen + " background mapped")
		scene._resize_layout()
		check(scene.find_children("SceneBackdrop", "TextureRect", false, false).size() == 1, screen + " resize keeps single background")
	print("ART ASSETS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
