extends Node
## Android's system download service owns transfer lifetime; installation always
## goes through the operating system's confirmation screen. No native plugin.
signal changed(value: Dictionary)

const MIME_APK := "application/vnd.android.package-archive"
const RECORD := "user://android_update.json"
const MAX_APK_BYTES := 536870912
var state: Dictionary = {"status": "idle"}
var record: Dictionary = {}
var _clock := 0.0
var _runtime
var _wrapper
var _context
var _activity
var _manager

func _ready() -> void:
	if not _bridge():
		return
	if FileAccess.file_exists(RECORD):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(RECORD))
		if valid_record(parsed):
			record = parsed
			_poll()

static func valid_record(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for key in ["id", "size"]:
		if not (value.get(key) is int or value.get(key) is float) or not is_finite(float(value[key])) or float(value[key]) != float(int(value[key])):
			return false
	if int(value.id) <= 0 or int(value.size) <= 0 or int(value.size) > MAX_APK_BYTES:
		return false
	var digest_re := RegEx.new()
	digest_re.compile("^[0-9a-f]{64}$")
	var tag_re := RegEx.new()
	tag_re.compile("^android-v[0-9]+\\.[0-9]+\\.[0-9]+$")
	var tag := str(value.get("tag", ""))
	return digest_re.search(str(value.get("sha256", ""))) != null and tag_re.search(tag) != null and str(value.get("filename", "")) == "voidrift-" + tag + ".apk"

func _bridge() -> bool:
	if _manager != null:
		return true
	if not Engine.has_singleton("AndroidRuntime") or not Engine.has_singleton("JavaClassWrapper"):
		return false
	_runtime = Engine.get_singleton("AndroidRuntime")
	_wrapper = Engine.get_singleton("JavaClassWrapper")
	_context = _runtime.getApplicationContext()
	_activity = _runtime.getActivity()
	if _context == null or _activity == null:
		return false
	_manager = _context.getSystemService("download")
	return _manager != null

func probe() -> Dictionary:
	if not _bridge():
		return {"success": false, "error": "Android 更新接口尚未就绪"}
	var query_class = _wrapper.wrap("android.app.DownloadManager$Query")
	var request_class = _wrapper.wrap("android.app.DownloadManager$Request")
	var uri_class = _wrapper.wrap("android.net.Uri")
	var request = request_class.call("DownloadManager$Request", uri_class.parse("https://github.com/Catfish872/gachaWeb/releases"))
	var request_ok := request != null
	var metered_ok := request != null and request.setAllowedOverMetered(true) != null
	if request_ok:
		request_ok = request.setTitle("更新接口检查") != null and request.setMimeType(MIME_APK) != null and metered_ok and request.setAllowedOverRoaming(false) != null and request.setNotificationVisibility(1) != null
	var intent_class = _wrapper.wrap("android.content.Intent")
	var content_uri = uri_class.parse("content://downloads/all_downloads/-1")
	var intent = intent_class.Intent("android.intent.action.VIEW")
	intent.setDataAndType(content_uri, MIME_APK)
	intent.addFlags(1)
	var intent_ok := str(intent.getType()) == MIME_APK and int(intent.getFlags()) == 1 and str(intent.getData().toString()) == "content://downloads/all_downloads/-1"
	var settings_intent = intent_class.Intent("android.settings.MANAGE_UNKNOWN_APP_SOURCES", uri_class.parse("package:" + str(_context.getPackageName())))
	var settings_ok := settings_intent != null and str(settings_intent.getAction()) == "android.settings.MANAGE_UNKNOWN_APP_SOURCES"
	var runnable = _runtime.createRunnableFromGodotCallable(func(): pass)
	var install_allowed := can_install()
	var permission_read_ok := _wrapper.get_exception() == null
	var query = query_class.call("DownloadManager$Query")
	query.setFilterById(PackedInt64Array([-1]))
	var cursor = _manager.query(query)
	var query_ok := cursor != null
	if cursor != null:
		cursor.close()
	return {"success": request_ok and intent_ok and settings_ok and runnable != null and permission_read_ok and query != null and query_ok, "package": str(_context.getPackageName()), "install_allowed": install_allowed, "network_policy": {"metered_permitted": metered_ok, "roaming_permitted": false}}

func begin(url: String, tag: String, sha256: String, size_bytes: int) -> Error:
	if not _bridge():
		return ERR_UNAVAILABLE
	if not record.is_empty():
		return ERR_BUSY
	var version_re := RegEx.new()
	version_re.compile("^android-v[0-9]+\\.[0-9]+\\.[0-9]+$")
	if version_re.search(tag) == null or url != "https://github.com/Catfish872/gachaWeb/releases/download/" + tag + "/universal.apk":
		return ERR_INVALID_PARAMETER
	var proposed := {"id": 1, "tag": tag, "filename": "voidrift-" + tag + ".apk", "sha256": sha256, "size": size_bytes}
	if not valid_record(proposed):
		return ERR_INVALID_PARAMETER
	var uri_class = _wrapper.wrap("android.net.Uri")
	var request_class = _wrapper.wrap("android.app.DownloadManager$Request")
	var request = request_class.call("DownloadManager$Request", uri_class.parse(url))
	request.setTitle("虚空裂变 " + tag.trim_prefix("android-v"))
	request.setDescription("下载完成后在游戏内确认安装，存档保留")
	request.setMimeType(MIME_APK)
	request.setAllowedOverMetered(true)
	request.setAllowedOverRoaming(false)
	request.setNotificationVisibility(1)
	request.setDestinationInExternalFilesDir(_context, "updates", proposed.filename)
	# A prior canceled/corrupt download may leave a file; remove only this exact
	# application-owned destination before asking DownloadManager to recreate it.
	var path := _download_path(str(proposed.filename))
	if path.is_empty():
		return ERR_CANT_OPEN
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var id: int = int(_manager.enqueue(request))
	if id <= 0:
		return ERR_CANT_CREATE
	proposed.id = id
	record = proposed
	_save()
	_set_download_state({"status": "downloading", "message": "正在自动下载更新", "progress": 0.0, "tag": tag})
	return OK

func _process(delta: float) -> void:
	if record.is_empty() or state.get("status") in ["downloaded", "install_permission", "installing", "download_error"]:
		return
	_clock += delta
	if _clock >= 0.8:
		_clock = 0
		_poll()

func _download_path(filename: String) -> String:
	var folder = _context.getExternalFilesDir("updates")
	return str(folder.getAbsolutePath()).path_join(filename) if folder != null else ""

func _poll() -> void:
	if record.is_empty() or not _bridge():
		return
	var query_class = _wrapper.wrap("android.app.DownloadManager$Query")
	var query = query_class.call("DownloadManager$Query")
	query.setFilterById(PackedInt64Array([int(record.id)]))
	var cursor = _manager.query(query)
	if cursor == null:
		_set_download_state({"status": "download_error", "message": "无法读取系统下载进度，请取消后重试"})
		return
	if not cursor.moveToFirst():
		cursor.close()
		record = {}
		_save()
		_set_download_state({"status": "download_error", "message": "系统下载记录已移除，可以重新下载"})
		return
	var status: int = int(cursor.getInt(cursor.getColumnIndex("status")))
	var received: int = int(cursor.getLong(cursor.getColumnIndex("bytes_so_far")))
	var total: int = int(cursor.getLong(cursor.getColumnIndex("total_size")))
	var reason: int = int(cursor.getInt(cursor.getColumnIndex("reason")))
	cursor.close()
	if status == 8:
		var path := _download_path(str(record.filename))
		var file := FileAccess.open(path, FileAccess.READ)
		var length := file.get_length() if file != null else -1
		if file != null:
			file.close()
		if length != int(record.size) or FileAccess.get_sha256(path) != str(record.sha256):
			_set_download_state({"status": "download_error", "message": "更新包校验失败，已停止安装。请取消并重新下载。"})
			return
		_set_download_state({"status": "downloaded", "message": "更新已下载并校验，点击安装更新", "progress": 1.0, "tag": str(record.tag)})
	elif status == 16:
		_set_download_state({"status": "download_error", "message": "系统下载失败（%d），可以取消后重试" % reason})
	else:
		var fraction := clampf(float(received) / maxf(1, float(total)), 0, 1) if total > 0 else 0.0
		_set_download_state({"status": "downloading", "message": "等待网络或系统恢复下载" if status == 4 else "正在自动下载更新 · %d%%" % int(fraction * 100), "progress": fraction, "tag": str(record.tag)})

func can_install() -> bool:
	if not _bridge():
		return false
	var version = _wrapper.wrap("android.os.Build$VERSION")
	return int(version.SDK_INT) < 26 or bool(_context.getPackageManager().canRequestPackageInstalls())

func install() -> Error:
	if not _bridge() or record.is_empty() or state.get("status") not in ["downloaded", "install_permission", "installing"]:
		return ERR_UNAVAILABLE
	if not can_install():
		_set_download_state({"status": "install_permission", "message": "请先在 Android 设置中允许本应用安装更新，然后返回点击安装。"})
		return ERR_UNAUTHORIZED
	# Verify immediately before install as well as after the completed transfer.
	var path := _download_path(str(record.filename))
	if FileAccess.get_sha256(path) != str(record.sha256):
		_set_download_state({"status": "download_error", "message": "更新包校验失败，已停止安装"})
		return ERR_FILE_CORRUPT
	var uri = _manager.getUriForDownloadedFile(int(record.id))
	if uri == null:
		return ERR_FILE_NOT_FOUND
	var intent_class = _wrapper.wrap("android.content.Intent")
	var intent = intent_class.Intent("android.intent.action.VIEW")
	intent.setDataAndType(uri, MIME_APK)
	intent.addFlags(1)
	var launch = func():
		_activity.startActivity(intent)
		var failed: bool = _wrapper.get_exception() != null
		_finish_activity_launch.call_deferred(failed, true)
	_activity.runOnUiThread(_runtime.createRunnableFromGodotCallable(launch))
	return OK

func open_install_settings() -> Error:
	if not _bridge():
		return ERR_UNAVAILABLE
	var intent_class = _wrapper.wrap("android.content.Intent")
	var uri_class = _wrapper.wrap("android.net.Uri")
	var intent = intent_class.Intent("android.settings.MANAGE_UNKNOWN_APP_SOURCES", uri_class.parse("package:" + str(_context.getPackageName())))
	var launch = func():
		_activity.startActivity(intent)
		var failed: bool = _wrapper.get_exception() != null
		_finish_activity_launch.call_deferred(failed, false)
	_activity.runOnUiThread(_runtime.createRunnableFromGodotCallable(launch))
	return OK

func _finish_activity_launch(failed: bool, installing: bool) -> void:
	if failed:
		_set_download_state({"status": "download_error", "message": "Android 无法打开安装界面，请检查系统安装器后重试。" if installing else "Android 无法打开安装权限设置，请在系统设置中检查本应用的安装权限。"})
	elif installing:
		_set_download_state({"status": "installing", "message": "请在 Android 安装界面确认更新；取消后可再次点击安装"})

func cancel() -> void:
	if not record.is_empty() and _bridge():
		_manager.remove(PackedInt64Array([int(record.id)]))
	record = {}
	_save()
	_set_download_state({"status": "idle", "message": "已取消下载，可重新检查更新"})

func _save() -> void:
	var file := FileAccess.open(RECORD, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(record))
		file.close()

func _set_download_state(value: Dictionary) -> void:
	state = value
	changed.emit(state.duplicate(true))
