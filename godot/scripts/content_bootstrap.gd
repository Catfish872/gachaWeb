extends Node
## This scene and its dependencies belong to the signed native bootstrap.
const Store = preload("res://scripts/content_store.gd")
const Saves = preload("res://scripts/content_save_guard.gd")
var _state: Dictionary
var _pending := false

func _ready() -> void:
	_boot.call_deferred()

func _failure(message: String) -> void:
	var label := Label.new()
	label.text = message
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(label)
	push_error(message)

func _boot() -> void:
	_state = Store.read_state()
	if _state.get("_invalid", false):
		_failure("更新记录校验失败，已保留存档。请恢复更新记录后重试。")
		return
	# A pending version that never reached the health checkpoint is rolled back.
	if _state.get("booting", false):
		var backup_id := str(_state.get("save_backup", ""))
		if not Store._hash(backup_id):
			_failure("更新恢复记录不完整，存档已保留。")
			return
		var restore_error := Saves.restore(Store.ROOT + "/save-backups/" + backup_id)
		if restore_error != OK:
			_failure("更新恢复存档失败，已保留全部文件。请重新启动后重试。")
			return
		var rejected := Store.load_manifest(str(_state.get("active", "")))
		_state["rejected_version"] = int(rejected.get("version_code", 0))
		_state["active"] = str(_state.get("previous", ""))
		_state["active_version"] = int(_state.get("previous_version", 0))
		_state.erase("booting")
		_state.erase("pending")
		_state.erase("save_backup")
		if Store.write_state(_state) != OK:
			_failure("更新恢复记录保存失败，请检查可用存储空间。")
			return
	var embedded: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/version.json"))
	var embedded_code := int(embedded.get("version_code", 0)) if embedded is Dictionary else 0
	# Version metadata survives signing-key changes in a newer native APK.
	# App-private state records this when activation is committed.
	if int(_state.get("active_version", 0)) > 0 and embedded_code >= int(_state.active_version):
		for field in ["active", "active_version", "previous", "previous_version"]:
			_state.erase(field)
		if Store.write_state(_state) != OK:
			_failure("完整安装包更新记录保存失败，请检查可用存储空间。")
			return
	var pending_id := str(_state.get("pending", ""))
	if not pending_id.is_empty():
		var candidate := Store.load_manifest(pending_id)
		if not candidate.is_empty() and int(candidate.version_code) > embedded_code and Store.compatible(candidate) and Store.missing_objects(candidate).is_empty():
			var backup_id := (pending_id + str(Time.get_unix_time_from_system()) + str(Time.get_ticks_usec())).sha256_text()
			if Saves.capture(Store.ROOT + "/save-backups/" + backup_id) != OK:
				_failure("更新前存档备份未完成，请检查可用存储空间后重新启动。")
				return
			_state["previous"] = str(_state.get("active", ""))
			_state["previous_version"] = int(_state.get("active_version", 0))
			_state["active"] = pending_id
			_state["active_version"] = int(candidate.version_code)
			_state["booting"] = true
			_state["save_backup"] = backup_id
			_state.erase("pending")
			if Store.write_state(_state) != OK:
				_failure("更新激活记录保存失败，请重新启动。")
				return
			_pending = true
		else:
			_state.erase("pending")
			if Store.write_state(_state) != OK:
				_failure("更新记录保存失败，请检查可用存储空间。")
				return
	var active := Store.load_manifest(str(_state.get("active", ""))) if not str(_state.get("active", "")).is_empty() else {}
	if not str(_state.get("active", "")).is_empty() and active.is_empty():
		_failure("已安装的更新内容验证失败，存档已保留。请重新安装最新完整安装包。")
		return
	if not active.is_empty() and int(active.version_code) > embedded_code and not Store.compatible(active):
		_failure("游戏内容需要匹配的完整安装包，存档已保留。请安装最新完整安装包。")
		return
	# A newer platform APK supersedes old cached game snapshots.
	if not active.is_empty() and int(active.version_code) > embedded_code and Store.compatible(active):
		if not Store.mount(active):
			_failure("更新内容校验失败。请关闭并重新启动游戏以恢复原版本。")
			return
	var scene: PackedScene = load("res://main.tscn")
	if scene == null:
		_failure("游戏加载失败。请关闭并重新启动游戏以恢复原版本。")
		return
	var game := scene.instantiate()
	if game == null:
		_failure("游戏初始化失败。请关闭并重新启动游戏以恢复原版本。")
		return
	get_tree().root.add_child(game)
	get_tree().current_scene = game
	await get_tree().process_frame
	await get_tree().process_frame
	# The actual main controller sets this only after save/UI initialization.
	if _pending:
		if game.get("_ready_done") != true:
			game.queue_free()
			_failure("游戏初始化未完成。请重新启动游戏以恢复原版本。")
			return
		_state.erase("booting")
		_state.erase("save_backup")
		if Store.write_state(_state) != OK:
			_failure("更新确认保存失败。请检查可用存储空间。")
			return
	Store.collect_garbage()
	queue_free()
