extends SceneTree
const Store = preload("res://scripts/content_store.gd")
var failures := 0
var checks := 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
func _initialize() -> void:
	var object := {"sha256": "a".repeat(64), "size": 100, "url": "https://github.com/Catfish872/gachaWeb/releases/download/android-v2.9.3-assets/obj-" + "a".repeat(64) + ".zip"}
	check(Store._valid_object(object), "Sidecar URL accepted")
	object.url += "\n"
	check(not Store._valid_object(object), "Trailing newline rejected")
	object.url = "https://evil.example/" + "a".repeat(64) + ".zip"
	check(not Store._valid_object(object), "External host rejected")
	check(Store.object_path("../bad").is_empty(), "Unsafe cache path rejected")
	check(Store.write_state({"active_version": 20903, "active": "a".repeat(64)}) == OK, "State writes atomically")
	check(not Store.read_state().get("_invalid", false), "Valid state readable")
	for bad in [{"active": "../bad"}, {"active_version": -1}, {"active_version": true}, {"booting": 1}, {"pending": 12}, {"previous_version": 2.5}]:
		Store.write_state(bad)
		check(Store.read_state().get("_invalid", false), "Malformed journal rejected: " + str(bad))
	Store.atomic_write(Store.STATE, "broken".to_utf8_buffer())
	check(Store.read_state().get("_invalid", false), "Corrupt JSON fails closed")
	DirAccess.remove_absolute(Store.STATE)
	print("CONTENT_STORE %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
