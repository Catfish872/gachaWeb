extends RefCounted
## Trusted, complete content snapshots. No game code loads before verification.
const ROOT := "user://content"
const STATE := ROOT + "/state.json"
const REPOSITORY := "Catfish872/gachaWeb"
const PREFIX := "https://github.com/" + REPOSITORY + "/releases/download/"
const MAX_BYTES := 536870912

static func _hash(value: String) -> bool:
	var re := RegEx.new()
	re.compile("^[0-9a-f]{64}$")
	return value.length() == 64 and re.search(value) != null

static func _integer(value: Variant, maximum: int = MAX_BYTES) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and value > 0 and value <= maximum

static func object_path(sha256: String) -> String:
	return ROOT + "/objects/" + sha256 + ".zip" if _hash(sha256) else ""

static func _valid_object(item: Variant) -> bool:
	if not item is Dictionary or not _hash(str(item.get("sha256", ""))) or not _integer(item.get("size")):
		return false
	var url := str(item.get("url", ""))
	if not url.begins_with(PREFIX):
		return false
	var tail := url.trim_prefix(PREFIX)
	var re := RegEx.new()
	re.compile("^android-v[0-9]+\\.[0-9]+\\.[0-9]+(?:-assets)?/" + "obj-" + item.sha256 + "\\.zip$")
	return re.search(tail) != null and tail.get_slice_count("/") == 2 and tail.ends_with("obj-" + item.sha256 + ".zip")

static func verify_manifest(body: PackedByteArray, signature: PackedByteArray) -> Dictionary:
	if body.is_empty() or body.size() > 4194304 or signature.size() > 1024:
		return {}
	var key := CryptoKey.new()
	if key.load("res://data/content_public_key.pem", true) != OK:
		return {}
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(body)
	if not Crypto.new().verify(HashingContext.HASH_SHA256, hashing.finish(), signature, key):
		return {}
	var value: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not value is Dictionary or value.get("schema") != 1 or value.get("repository") != REPOSITORY or value.get("entry_scene") != "res://main.tscn":
		return {}
	if not _integer(value.get("version_code"), 2100000000) or not value.get("version_name") is String or not _hash(str(value.get("platform_id", ""))):
		return {}
	var version := str(value.version_name).split(".")
	if version.size() != 3:
		return {}
	for part in version:
		if not part.is_valid_int() or int(part) < 0 or str(int(part)) != part:
			return {}
	if int(version[1]) > 99 or int(version[2]) > 99 or int(version[0]) * 10000 + int(version[1]) * 100 + int(version[2]) != int(value.version_code):
		return {}
	if not _valid_object(value.get("logic")) or not value.get("assets") is Array or value.assets.size() > 10000:
		return {}
	var paths := {}
	var total := int(value.logic.size)
	for item in value.assets:
		if not _valid_object(item) or not _hash(str(item.get("content_sha256", ""))) or not _integer(item.get("content_size")):
			return {}
		var path := str(item.get("path", ""))
		if not (path.begins_with("res://assets/") or path.begins_with("res://.godot/imported/")) or ".." in path or "\\" in path or path in paths:
			return {}
		paths[path] = true
		total += int(item.size)
		if total > 2147483648:
			return {}
	return value

static func compatible(manifest: Dictionary) -> bool:
	var config: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/content_platform.json"))
	return config is Dictionary and manifest.get("platform_id") == config.get("platform_id")

static func _file_matches(path: String, size: int, digest: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	return file != null and file.get_length() == size and FileAccess.get_sha256(path) == digest

static func _cached(item: Dictionary) -> bool:
	return _file_matches(object_path(item.sha256), int(item.size), item.sha256)

static func _embedded(item: Dictionary) -> bool:
	return _file_matches(item.path, int(item.content_size), item.content_sha256)

static func missing_objects(manifest: Dictionary) -> Array[Dictionary]:
	var missing: Array[Dictionary] = []
	if not _cached(manifest.logic):
		missing.append(manifest.logic)
	for item in manifest.assets:
		if not _cached(item) and not _embedded(item):
			missing.append(item)
	return missing

static func atomic_write(path: String, bytes: PackedByteArray) -> Error:
	var error := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if error != OK:
		return error
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_buffer(bytes)
	file.flush()
	error = file.get_error()
	file.close()
	if error != OK:
		return error
	return DirAccess.rename_absolute(path + ".tmp", path)

static func read_state() -> Dictionary:
	if not FileAccess.file_exists(STATE):
		return {}
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(STATE)) != OK:
		return {"_invalid": true}
	var value: Variant = parser.data
	if not value is Dictionary:
		return {"_invalid": true}
	for field in ["active", "previous", "pending", "downloading", "save_backup"]:
		if value.has(field) and (not value[field] is String or (not value[field].is_empty() and not _hash(value[field]))):
			return {"_invalid": true}
	for field in ["active_version", "previous_version", "rejected_version"]:
		if value.has(field) and (not (value[field] is int or value[field] is float) or (value[field] != 0 and not _integer(value[field], 2100000000))):
			return {"_invalid": true}
	if value.has("booting") and not value.booting is bool:
		return {"_invalid": true}
	return value

static func write_state(value: Dictionary) -> Error:
	return atomic_write(STATE, JSON.stringify(value).to_utf8_buffer())

static func load_manifest(identifier: String) -> Dictionary:
	if not _hash(identifier):
		return {}
	return verify_manifest(FileAccess.get_file_as_bytes(ROOT + "/manifests/" + identifier + ".json"), FileAccess.get_file_as_bytes(ROOT + "/manifests/" + identifier + ".sig"))

static func remember_download(body: PackedByteArray, signature: PackedByteArray) -> Error:
	return _save_target(body, signature, false)

static func stage(body: PackedByteArray, signature: PackedByteArray) -> Error:
	return _save_target(body, signature, true)

static func _save_target(body: PackedByteArray, signature: PackedByteArray, complete: bool) -> Error:
	var manifest := verify_manifest(body, signature)
	if manifest.is_empty() or not compatible(manifest) or (complete and not missing_objects(manifest).is_empty()):
		return ERR_INVALID_DATA
	var version: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/version.json"))
	var state := read_state()
	if state.get("_invalid", false):
		return ERR_FILE_CORRUPT
	if not version is Dictionary or int(manifest.version_code) <= int(version.get("version_code", 0)) or int(manifest.version_code) == int(state.get("rejected_version", 0)):
		return ERR_INVALID_DATA
	var identifier := ""
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(body)
	identifier = context.finish().hex_encode()
	var base := ROOT + "/manifests/" + identifier
	var error := atomic_write(base + ".json", body)
	if error == OK:
		error = atomic_write(base + ".sig", signature)
	if error != OK:
		return error
	state["pending" if complete else "downloading"] = identifier
	if complete and state.get("downloading") == identifier:
		state.erase("downloading")
	return write_state(state)

static func mount(manifest: Dictionary) -> bool:
	if manifest.is_empty() or not compatible(manifest) or not missing_objects(manifest).is_empty():
		return false
	# Validate every required byte before mounting any executable resource.
	for item in manifest.assets:
		if _cached(item) and not ProjectSettings.load_resource_pack(object_path(item.sha256), true):
			return false
	return ProjectSettings.load_resource_pack(object_path(manifest.logic.sha256), true)

static func collect_garbage() -> Dictionary:
	# Run only after a successful activation commit, before background downloads.
	# Any ambiguous journal/manifest aborts cleanup and retains every byte.
	var state := read_state()
	if state.get("_invalid", false) or state.get("booting", false):
		return {"retained": true, "removed": 0}
	var keep := {}
	for field in ["active", "previous", "pending", "downloading"]:
		var identifier := str(state.get(field, ""))
		if identifier.is_empty():
			continue
		var manifest := load_manifest(identifier)
		if manifest.is_empty():
			return {"retained": true, "removed": 0}
		keep[str(manifest.logic.sha256)] = true
		for object in manifest.assets:
			keep[str(object.sha256)] = true
	var removed := 0
	var bytes_removed := 0
	var directory := DirAccess.open(ROOT + "/objects")
	if directory == null:
		return {"removed": 0, "bytes": 0}
	for name in directory.get_files():
		# Keep incomplete objects of the journaled transfer; discard abandoned ones.
		if not (name.ends_with(".zip") or name.ends_with(".zip.part")):
			continue
		var digest := name.trim_suffix(".part").trim_suffix(".zip")
		if not _hash(digest) or keep.has(digest):
			continue
		var path := ROOT + "/objects/" + name
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		var size := file.get_length()
		file.close()
		if directory.remove(name) == OK:
			removed += 1
			bytes_removed += size
	return {"removed": removed, "bytes": bytes_removed}
