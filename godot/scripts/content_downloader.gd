extends Node
## Downloads immutable, signed content into a persistent hash cache. Completed
## objects survive interruption; only verified complete releases can be staged.
signal changed(value: Dictionary)
signal apk_required

const Store = preload("res://scripts/content_store.gd")
const RELEASES := "https://github.com/Catfish872/gachaWeb/releases/download/"
const MANIFEST_LIMIT := 4194304
var busy := false
var _cancelled := false
var _request: HTTPRequest
var _generation := 0
var _progress_clock := 0.0
var _received := 0
var _total := 0

static func trusted_asset(url: String, tag: String, name: String) -> bool:
	var pattern := RegEx.new()
	pattern.compile("^android-v[0-9]+\\.[0-9]+\\.[0-9]+$")
	return pattern.search(tag) != null and url == RELEASES + tag + "/" + name

func _ready() -> void:
	_request = HTTPRequest.new()
	_request.timeout = 90
	_request.max_redirects = 5
	add_child(_request)

func _process(delta: float) -> void:
	_progress_clock += delta
	if _progress_clock < 0.3:
		return
	_progress_clock = 0.0
	if busy and _total > 0 and _request != null:
		changed.emit({"status": "downloading", "progress": minf(1.0, float(_received + maxi(0, _request.get_downloaded_bytes())) / _total), "message": "正在下载变化内容，已完成的素材会保留……"})

func cancel() -> void:
	_generation += 1
	_cancelled = true
	if _request != null:
		_request.cancel_request()
	busy = false
	changed.emit({"status": "download_error", "message": "下载已取消，重新检查可继续下载缺少的内容。"})

func _fetch(url: String, limit: int, destination: String = "") -> Dictionary:
	_request.body_size_limit = limit
	_request.download_file = destination
	var error := _request.request(url)
	if error != OK:
		return {}
	var response: Array = await _request.request_completed
	if _cancelled or response[0] != HTTPRequest.RESULT_SUCCESS or response[1] != 200:
		return {}
	return {"body": response[3]}

func _fail(message: String) -> void:
	busy = false
	changed.emit({"status": "download_error", "message": message})

func begin(candidate: Dictionary) -> Error:
	if busy:
		return ERR_BUSY
	var tag := str(candidate.get("tag", ""))
	if not trusted_asset(str(candidate.get("content_manifest", "")), tag, "content-manifest.json") or not trusted_asset(str(candidate.get("content_signature", "")), tag, "content-manifest.sig"):
		return ERR_INVALID_DATA
	busy = true
	_cancelled = false
	_received = 0
	_total = 0
	_generation += 1
	_run.call_deferred(candidate, _generation)
	return OK

func _run(candidate: Dictionary, generation: int) -> void:
	changed.emit({"status": "downloading", "progress": 0.0, "message": "正在验证内容更新……"})
	var response: Dictionary = await _fetch(candidate.content_manifest, MANIFEST_LIMIT)
	if generation != _generation:
		return
	if response.is_empty():
		_fail("内容清单下载失败，当前游戏保持可用。")
		return
	var body: PackedByteArray = response.body
	response = await _fetch(candidate.content_signature, 16384)
	if generation != _generation:
		return
	if response.is_empty():
		_fail("内容签名下载失败，请稍后重试。")
		return
	var signature: PackedByteArray = response.body
	var manifest: Dictionary = Store.verify_manifest(body, signature)
	if manifest.is_empty() or int(manifest.get("version_code", 0)) != int(candidate.get("version_code", -1)):
		_fail("内容更新签名或版本校验失败，当前版本保持可用。")
		return
	if not Store.compatible(manifest):
		busy = false
		apk_required.emit()
		return
	if Store.remember_download(body, signature) != OK:
		_fail("无法保存更新进度，请检查可用存储空间后重试。")
		return
	var missing: Array = Store.missing_objects(manifest)
	for object in missing:
		_total += int(object.size)
	for object in missing:
		if _cancelled or generation != _generation:
			return
		var path: String = Store.object_path(str(object.sha256))
		if DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK:
			_fail("无法创建内容缓存，请检查可用存储空间。")
			return
		var part := path + ".part"
		response = await _fetch(str(object.url), int(object.size), part)
		if _cancelled or generation != _generation:
			return
		if response.is_empty() or not verify_file(part, str(object.sha256), int(object.size)):
			DirAccess.remove_absolute(part)
			_fail("内容下载中断或校验失败，已完成的素材会保留，请重试。")
			return
		if DirAccess.rename_absolute(part, path) != OK:
			_fail("内容保存失败，请检查可用存储空间后重试。")
			return
		_received += int(object.size)
	if Store.stage(body, signature) != OK:
		_fail("更新暂未完成保存，当前游戏保持可用，请重试。")
		return
	busy = false
	changed.emit({"status": "content_ready", "message": "内容更新已就绪。完全关闭游戏后重新打开即可应用，存档会保留。", "progress": 1.0})

static func verify_file(path: String, sha256: String, size: int) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() != size:
		return false
	file.close()
	return FileAccess.get_sha256(path) == sha256
