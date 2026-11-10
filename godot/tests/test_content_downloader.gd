extends SceneTree
const Downloader = preload("res://scripts/content_downloader.gd")
const Updates = preload("res://scripts/update_checker.gd")
var failures := 0
var checks := 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var tag := "android-v2.9.9"
	var base := Downloader.RELEASES + tag + "/"
	check(Downloader.trusted_asset(base + "content-manifest.json", tag, "content-manifest.json"), "official manifest")
	for wrong in [base.replace("github.com", "github.com.evil.test"), base.replace("https:", "http:"), base.replace("Catfish872", "other"), base + "../", base + "?url="]:
		check(not Downloader.trusted_asset(wrong + "content-manifest.json", tag, "content-manifest.json"), "reject other manifest origin")
	var local := {"version_name":"2.9.3", "version_code":20903, "repository":Updates.REPOSITORY, "release_asset":"universal.apk"}
	var release := {"draft":false, "prerelease":false,"tag_name":tag,"html_url":Updates.RELEASES_URL + "/tag/" + tag,"assets":[]}
	for name in ["content-manifest.json", "content-manifest.sig"]:
		release.assets.append({"name":name,"state":"uploaded","browser_download_url":base + name,"size":100})
	var result := Updates.evaluate_release(release, local)
	check(result.status == "available" and result.content_manifest == base + "content-manifest.json", "content-only release available")
	var large := release.duplicate(true)
	for index in range(700):
		large.assets.append({"name":"obj-%064d.zip" % index, "description":"x".repeat(1600)})
	var large_body := JSON.stringify(large).to_utf8_buffer()
	check(large_body.size() > 1048576 and Updates.evaluate_response(HTTPRequest.RESULT_SUCCESS, 200, large_body, local).status == "available", "large release index accepted within bounded limit")
	var incomplete := release.duplicate(true)
	incomplete.assets.pop_back()
	check(Updates.evaluate_release(incomplete, local).status == "invalid_asset", "incomplete publication rejected")
	var duplicate := release.duplicate(true)
	duplicate.assets.append(duplicate.assets[0].duplicate())
	check(Updates.evaluate_release(duplicate, local).status == "untrusted_asset", "duplicate manifests rejected")
	var file := FileAccess.open("user://content-transfer-test.part", FileAccess.WRITE)
	file.store_string("real transferred bytes")
	file.close()
	var digest := FileAccess.get_sha256("user://content-transfer-test.part")
	check(Downloader.verify_file("user://content-transfer-test.part",digest,22), "exact disk bytes verified")
	check(not Downloader.verify_file("user://content-transfer-test.part",digest,23), "truncated transfer rejected")
	check(not Downloader.verify_file("user://content-transfer-test.part","a".repeat(64),22), "corrupt transfer rejected")
	DirAccess.remove_absolute("user://content-transfer-test.part")
	var downloader := Downloader.new()
	root.add_child(downloader)
	check(downloader.begin({}) == ERR_INVALID_DATA and not downloader.busy, "invalid request cannot start")
	downloader.queue_free()
	print("CONTENT_DOWNLOADER %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
