extends Node
## Explicit, read-only release checks. The browser and user handle APK installation.
## data/version.json is shared with the Android export pipeline.
## version_code = major * 10000 + minor * 100 + patch; minor/patch are 0..99.

signal state_changed(state: Dictionary)

const REPOSITORY := "Catfish872/gachaWeb"
const API_URL := "https://api.github.com/repos/" + REPOSITORY + "/releases/latest"
const RELEASES_URL := "https://github.com/" + REPOSITORY + "/releases"
const DOWNLOAD_HOST_ALLOWLIST := ["github.com"]
const RELEASE_ASSET := "universal.apk"
const REQUEST_TIMEOUT_SECONDS := 12.0
const MAX_RESPONSE_BYTES := 1048576
const MAX_RELEASE_NOTES := 6000
const MAX_ANDROID_VERSION_CODE := 2100000000

var local_version: Dictionary = {}
var state: Dictionary = {"status": "idle", "message": "尚未检查更新"}
var busy := false
var _request: HTTPRequest

func _ready() -> void:
	local_version = read_local_version()
	_request = HTTPRequest.new()
	_request.name = "PublicReleaseRequest"
	_request.timeout = REQUEST_TIMEOUT_SECONDS
	_request.body_size_limit = MAX_RESPONSE_BYTES
	# Repository transfers require review instead of following an arbitrary redirect.
	_request.max_redirects = 0
	_request.request_completed.connect(_on_request_completed)
	add_child(_request)
	# No startup request, timer, persistent token, or gameplay/save-data access.

static func parse_version(value: String) -> Dictionary:
	var pattern := RegEx.new()
	pattern.compile("^(?:android-v|v)?(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)(?:-([0-9A-Za-z-]+(?:\\.[0-9A-Za-z-]+)*))?(?:\\+([0-9A-Za-z-]+(?:\\.[0-9A-Za-z-]+)*))?$")
	var found := pattern.search(value)
	if found == null or found.get_string() != value:
		return {}
	# Bound before integer conversion to avoid overflow and invalid Android codes.
	if found.get_string(1).length() > 6 or found.get_string(2).length() > 2 or found.get_string(3).length() > 2:
		return {}
	var major := int(found.get_string(1))
	var minor := int(found.get_string(2))
	var patch := int(found.get_string(3))
	var version_code := major * 10000 + minor * 100 + patch
	if version_code <= 0 or version_code > MAX_ANDROID_VERSION_CODE:
		return {}
	var prerelease := found.get_string(4)
	for identifier in prerelease.split("."):
		if identifier.is_valid_int() and identifier.length() > 1 and identifier.begins_with("0"):
			return {}
	return {"major": major, "minor": minor, "patch": patch, "prerelease": prerelease,
		"version_name": "%d.%d.%d" % [major, minor, patch], "version_code": version_code}

static func compare_versions(left: Dictionary, right: Dictionary) -> int:
	for key in ["major", "minor", "patch"]:
		if int(left.get(key, 0)) != int(right.get(key, 0)):
			return 1 if int(left.get(key, 0)) > int(right.get(key, 0)) else -1
	return 0

static func read_local_version() -> Dictionary:
	if not FileAccess.file_exists("res://data/version.json"):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/version.json"))
	if not parsed is Dictionary or not valid_local_version(parsed):
		return {}
	return parsed

static func valid_local_version(metadata: Dictionary) -> bool:
	if not metadata.get("version_name") is String:
		return false
	var parsed := parse_version(metadata.version_name)
	if parsed.is_empty() or parsed.prerelease != "" or parsed.version_name != metadata.version_name:
		return false
	var code: Variant = metadata.get("version_code")
	if not (code is int or code is float) or not is_finite(float(code)) or float(code) != float(parsed.version_code):
		return false
	return metadata.get("repository") == REPOSITORY and metadata.get("release_asset") == RELEASE_ASSET

static func _status(code: String, message: String) -> Dictionary:
	return {"status": code, "message": message}

static func trusted_release_url(url: String, tag: String) -> bool:
	return not parse_version(tag).is_empty() and url == RELEASES_URL + "/tag/" + tag

static func trusted_download_url(url: String, tag: String) -> bool:
	# Exact origin, repository, tag and filename, with no userinfo, ports, query,
	# fragments, encoded separators or normalization ambiguity.
	if parse_version(tag).is_empty() or not url.begins_with("https://"):
		return false
	var host := url.trim_prefix("https://").get_slice("/", 0)
	return host in DOWNLOAD_HOST_ALLOWLIST and url == RELEASES_URL + "/download/" + tag + "/" + RELEASE_ASSET

static func evaluate_response(result: int, response_code: int, body: PackedByteArray, metadata: Dictionary) -> Dictionary:
	if result == HTTPRequest.RESULT_TIMEOUT:
		return _status("timeout", "检查超时。请稍后重试，或直接打开 GitHub 发布页。")
	if result != HTTPRequest.RESULT_SUCCESS:
		return _status("network_error", "无法连接 GitHub。请检查网络后重试。")
	if response_code == 404:
		return _status("no_release", "尚未找到公开的正式版本。发布 APK 后可在这里检查。")
	if response_code == 429:
		return _status("rate_limited", "GitHub 请求次数已达上限，请稍后再试。")
	if response_code == 403:
		return _status("rate_limited", "GitHub 暂时限制了请求，可能已达访问上限。请稍后再试。")
	if response_code != 200:
		return _status("http_error", "GitHub 返回错误（HTTP %d），请稍后重试。" % response_code)
	if body.size() > MAX_RESPONSE_BYTES:
		return _status("invalid_response", "版本信息过大，已停止读取。")
	var parser := JSON.new()
	if parser.parse(body.get_string_from_utf8()) != OK:
		return _status("invalid_response", "GitHub 版本信息格式无效。")
	var release: Variant = parser.data
	if not release is Dictionary:
		return _status("invalid_response", "GitHub 版本信息格式无效。")
	return evaluate_release(release, metadata)

static func evaluate_release(release: Dictionary, metadata: Dictionary) -> Dictionary:
	if not valid_local_version(metadata):
		return _status("configuration_error", "本地版本信息无效，请通过 GitHub 发布页核对安装包。")
	if not release.get("draft") is bool or not release.get("prerelease") is bool:
		return _status("invalid_response", "发布状态缺失，无法确认正式版本。")
	if release.draft or release.prerelease:
		return _status("ignored_release", "此版本为草稿或测试版，已跳过。")
	if not release.get("tag_name") is String:
		return _status("invalid_response", "发布版本号缺失。")
	var tag: String = release.tag_name
	var candidate := parse_version(tag)
	if candidate.is_empty():
		return _status("invalid_version", "发布版本号不符合 Android 版本规则，已跳过。")
	if candidate.prerelease != "":
		return _status("ignored_release", "此版本为测试版，已跳过。")
	var release_url: Variant = release.get("html_url")
	if not release_url is String or not trusted_release_url(release_url, tag):
		return _status("untrusted_release", "发布链接不属于指定 GitHub 仓库，已停止更新。")
	var local := parse_version(metadata.version_name)
	var comparison := compare_versions(candidate, local)
	if comparison <= 0 or int(candidate.version_code) <= int(metadata.version_code):
		return _status("up_to_date", "当前已是最新版本。" if comparison == 0 else "当前版本比 GitHub 正式版更新，无需降级。")
	var assets: Variant = release.get("assets")
	if not assets is Array:
		return _status("invalid_response", "发布附件信息缺失。")
	var download_url := ""
	var matched := 0
	for asset in assets:
		if not asset is Dictionary or asset.get("name") != RELEASE_ASSET:
			continue
		matched += 1
		var asset_url: Variant = asset.get("browser_download_url")
		var asset_size: Variant = asset.get("size")
		if not asset_url is String or not trusted_download_url(asset_url, tag) or asset.get("state") != "uploaded":
			return _status("untrusted_asset", "APK 附件或下载链接无效，已停止更新。")
		if not (asset_size is int or asset_size is float) or not is_finite(float(asset_size)) or float(asset_size) <= 0 or float(asset_size) != floor(float(asset_size)):
			return _status("invalid_asset", "APK 附件为空或尚未就绪。")
		download_url = asset_url
	if matched == 0:
		return _status("missing_asset", "发现新版本 %s，但尚未提供 universal.apk。" % candidate.version_name)
	if matched != 1:
		return _status("invalid_asset", "存在多个同名 APK 附件，无法安全选择。")
	var notes: Variant = release.get("body", "")
	if notes == null:
		notes = ""
	if not notes is String:
		return _status("invalid_response", "发布说明格式无效。")
	var display_notes: String = notes.left(MAX_RELEASE_NOTES)
	if notes.length() > MAX_RELEASE_NOTES:
		display_notes += "\n……完整说明请查看 GitHub 发布页。"
	return {"status": "available", "message": "发现新版本 %s" % candidate.version_name,
		"version_name": candidate.version_name, "version_code": candidate.version_code,
		"tag": tag, "release_url": release_url, "download_url": download_url,
		"release_notes": display_notes if not display_notes.is_empty() else "此版本未填写发布说明。"}

func check_for_updates() -> void:
	if busy:
		return
	if not valid_local_version(local_version):
		_set_state(_status("configuration_error", "本地版本信息无效，请通过 GitHub 发布页核对安装包。"))
		return
	busy = true
	_set_state(_status("checking", "正在连接 GitHub 检查版本……"))
	var error := _send_request(API_URL, PackedStringArray([
		"Accept: application/vnd.github+json", "X-GitHub-Api-Version: 2022-11-28",
		"User-Agent: VoidRift/" + str(local_version.version_name)
	]))
	if error != OK:
		busy = false
		_set_state(_status("network_error", "无法发起检查，请稍后重试。"))

func _send_request(url: String, headers: PackedStringArray) -> Error:
	return _request.request(url, headers, HTTPClient.METHOD_GET)

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	busy = false
	_set_state(evaluate_response(result, response_code, body, local_version))

func _set_state(next_state: Dictionary) -> void:
	state = next_state
	state_changed.emit(state.duplicate(true))

func open_download() -> Error:
	# Connected only to an explicit UI button; this opens the browser, not an APK.
	if state.get("status") != "available" or not trusted_download_url(str(state.get("download_url", "")), str(state.get("tag", ""))):
		return ERR_INVALID_DATA
	return OS.shell_open(state.download_url)

func open_releases() -> Error:
	var url := RELEASES_URL
	if state.get("status") == "available" and trusted_release_url(str(state.get("release_url", "")), str(state.get("tag", ""))):
		url = state.release_url
	return OS.shell_open(url)
