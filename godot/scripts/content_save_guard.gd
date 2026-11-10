extends RefCounted
## Bootstrap captures before activation and restores before loading old code.
const FILES := ["slot1.json", "slot2.json", "slot3.json", "active_slot.json", "slot1.json.tmp", "slot2.json.tmp", "slot3.json.tmp", "active_slot.json.tmp"]
const INDEX := "snapshot.json"

static func _copy_verified(source: String, destination: String, digest: String) -> Error:
	var error := DirAccess.copy_absolute(source, destination)
	if error != OK:
		return error
	return OK if FileAccess.get_sha256(destination) == digest else ERR_FILE_CORRUPT

static func capture(snapshot_dir: String, save_dir: String = "user://saves") -> Error:
	# Each activation owns a unique directory, preserving previous snapshots.
	if DirAccess.dir_exists_absolute(snapshot_dir) or FileAccess.file_exists(snapshot_dir):
		return ERR_ALREADY_EXISTS
	var error := DirAccess.make_dir_recursive_absolute(snapshot_dir)
	if error != OK:
		return error
	var entries: Dictionary = {}
	for name in FILES:
		var source := save_dir.path_join(name)
		if DirAccess.dir_exists_absolute(source):
			return ERR_FILE_BAD_PATH
		if FileAccess.file_exists(source):
			var digest := FileAccess.get_sha256(source)
			if digest.length() != 64:
				return ERR_FILE_CANT_READ
			error = _copy_verified(source, snapshot_dir.path_join(name), digest)
			if error != OK:
				return error
			entries[name] = digest
		else:
			entries[name] = null
	var output := FileAccess.open(snapshot_dir.path_join(INDEX + ".tmp"), FileAccess.WRITE)
	if output == null:
		return FileAccess.get_open_error()
	output.store_string(JSON.stringify({"schema": 1, "files": entries}))
	output.flush()
	error = output.get_error()
	output.close()
	if error != OK:
		return error
	return DirAccess.rename_absolute(snapshot_dir.path_join(INDEX + ".tmp"), snapshot_dir.path_join(INDEX))

static func _read_index(snapshot_dir: String) -> Dictionary:
	var path := snapshot_dir.path_join(INDEX)
	if not FileAccess.file_exists(path):
		return {}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not value is Dictionary or value.get("schema") != 1 or not value.get("files") is Dictionary:
		return {}
	var entries: Dictionary = value.files
	if entries.size() != FILES.size():
		return {}
	var pattern := RegEx.new()
	pattern.compile("^[0-9a-f]{64}$")
	for name in FILES:
		if not entries.has(name):
			return {}
		if entries[name] == null:
			continue
		if not entries[name] is String or pattern.search(entries[name]) == null:
			return {}
		if FileAccess.get_sha256(snapshot_dir.path_join(name)) != entries[name]:
			return {}
	return entries

static func validate(snapshot_dir: String) -> bool:
	return not _read_index(snapshot_dir).is_empty()

static func restore(snapshot_dir: String, save_dir: String = "user://saves") -> Error:
	# Validate all backup bytes first. Operations are repeatable after a crash.
	var entries := _read_index(snapshot_dir)
	if entries.is_empty():
		return ERR_FILE_CORRUPT
	var error := DirAccess.make_dir_recursive_absolute(save_dir)
	if error != OK:
		return error
	for name in FILES:
		if DirAccess.dir_exists_absolute(save_dir.path_join(name)):
			return ERR_FILE_BAD_PATH
	for name in FILES:
		var destination := save_dir.path_join(name)
		if entries[name] == null:
			if FileAccess.file_exists(destination):
				# Preserve new files from the failed activation for manual recovery.
				var quarantine := snapshot_dir.path_join("failed-" + name)
				if FileAccess.file_exists(quarantine):
					quarantine += "-" + str(Time.get_ticks_usec())
				error = DirAccess.rename_absolute(destination, quarantine)
				if error != OK:
					return error
			continue
		var temporary := destination + ".content-restore"
		error = _copy_verified(snapshot_dir.path_join(name), temporary, str(entries[name]))
		if error != OK:
			return error
		error = DirAccess.rename_absolute(temporary, destination)
		if error != OK:
			return error
	return OK
