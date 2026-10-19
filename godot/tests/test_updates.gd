extends SceneTree
const U = preload("res://scripts/update_checker.gd")
class FakeChecker extends U:
 var requests := 0
 func _send_request(_url: String, _headers: PackedStringArray) -> Error:
  requests += 1
  return OK

var checks = 0
var fails = 0
func check(value, name):
 checks += 1
 if not value:
  fails += 1
  push_error("FAIL: " + name)
func _init():
 call_deferred("run")

func run():
 var local = U.read_local_version()
 check(U.valid_local_version(local), "local metadata")
 # Keep comparison fixtures independent of the application release version.
 local = {"version_name":"2.0.0","version_code":20000,"repository":U.REPOSITORY,"release_asset":U.RELEASE_ASSET}
 for bad in ["", "v1", "01.0.0", "2.100.0", "2.0.100", "2.0.1-01", "0.0.0", "https://bad/2.0.1"]:
  check(U.parse_version(bad).is_empty(), "invalid version " + bad)
 var tag = "android-v2.0.1"
 var url = U.RELEASES_URL + "/download/" + tag + "/universal.apk"
 var good = {"draft":false,"prerelease":false,"tag_name":tag,"html_url":U.RELEASES_URL+"/tag/"+tag,"body":"New release", "assets":[{"name":"universal.apk","state":"uploaded","size":10000,"browser_download_url":url}]}
 check(U.evaluate_release(good,local).status == "available", "new APK available")
 for badurl in [url.replace("https:","http:"), url+"?x=1", url.replace("github.com","github.com.evil.test"), url.replace("Catfish872","other"),url.replace("universal.apk","malware.apk")]:
  var bad = good.duplicate(true)
  bad.assets[0].browser_download_url = badurl
  check(U.evaluate_release(bad,local).status == "untrusted_asset", "reject wrong download")
 for field in ["draft","prerelease"]:
  var bad=good.duplicate(true)
  bad[field]=true
  check(U.evaluate_release(bad,local).status == "ignored_release", field)
 var missing=good.duplicate(true)
 missing.assets=[]
 check(U.evaluate_release(missing,local).status == "missing_asset", "missing APK")
 var dup=good.duplicate(true)
 dup.assets.append(dup.assets[0].duplicate())
 check(U.evaluate_release(dup,local).status == "invalid_asset", "duplicate APK")
 for tag2 in ["v2.0.0","v1.9.9"]:
  var old=good.duplicate(true)
  old.tag_name=tag2
  old.html_url=U.RELEASES_URL+"/tag/"+tag2
  check(U.evaluate_release(old,local).status == "up_to_date", "no downgrade")
 for code in [404,403,429,500]:
  check(U.evaluate_response(HTTPRequest.RESULT_SUCCESS,code,PackedByteArray(),local).status != "available", "HTTP fail closed")
 check(U.evaluate_response(HTTPRequest.RESULT_TIMEOUT,0,PackedByteArray(),local).status == "timeout", "timeout")
 check(U.evaluate_response(HTTPRequest.RESULT_SUCCESS,200,"not json".to_utf8_buffer(),local).status == "invalid_response", "invalid JSON")
 check(U.evaluate_response(HTTPRequest.RESULT_SUCCESS,200,JSON.stringify(good).to_utf8_buffer(),local).status == "available", "valid HTTP body")
 var checker = FakeChecker.new()
 root.add_child(checker)
 checker.local_version = local
 checker.schedule_startup_check(true)
 check(not checker._startup_scheduled and checker.requests == 0, "test session skips startup timer and network")
 checker.run_startup_check()
 checker.run_startup_check()
 check(checker.requests == 1 and checker.busy, "startup requests once per session")
 checker.check_for_updates()
 check(checker.requests == 1, "manual check while busy deduplicated")
 checker._on_request_completed(HTTPRequest.RESULT_TIMEOUT, 0, PackedStringArray(), PackedByteArray())
 check(not checker.busy and checker.state.status == "timeout", "timeout releases request for retry")
 checker.check_for_updates()
 check(checker.requests == 2, "manual fallback after startup failure")
 checker.free()
 var scheduled = FakeChecker.new()
 root.add_child(scheduled)
 scheduled.schedule_startup_check()
 scheduled.schedule_startup_check()
 check(scheduled._startup_scheduled and scheduled.requests == 0, "startup waits before checking")
 await create_timer(U.STARTUP_DELAY_SECONDS + 0.1).timeout
 check(scheduled.requests == 1, "delayed startup request occurs once")
 scheduled.free()
 var opted_out = FakeChecker.new()
 root.add_child(opted_out)
 opted_out.auto_check_enabled = false
 opted_out.run_startup_check()
 check(opted_out.requests == 0, "opt out skips automatic request")
 opted_out.check_for_updates()
 check(opted_out.requests == 1, "manual check still works after opt out")
 opted_out.free()
 root.size = Vector2i(1080, 1920)
 var app = load("res://main.tscn").instantiate()
 root.add_child(app)
 await process_frame
 check(not app.updater._startup_scheduled, "test app stays offline")
 var before_screen = app.current_screen
 var before_body = app.main_body.get_child(0)
 app.updater._set_state(U.evaluate_release(good, local))
 check(app.current_screen == before_screen and app.main_body.get_child(0) == before_body, "available response preserves current screen")
 check(app.overlay.get_child_count() == 0 and app.update_notice.visible, "nonmodal update prompt")
 app.current_screen = "battle"
 app._refresh_update_notice()
 app.updater._set_state(U.evaluate_release(good, local))
 check(not app.update_notice.visible and app.overlay.get_child_count() == 0 and app.current_screen == "battle", "battle remains uninterrupted")
 app.current_screen = "home"
 app._refresh_update_notice()
 check(app.update_notice.visible, "update prompt returns after battle")
 app.updater._set_state(U._status("timeout", "timeout"))
 check(app.current_screen == "home" and app.overlay.get_child_count() == 0 and not app.update_notice.visible, "failed background response stays quiet")
 app.navigate("save")
 check(app.find_child("CheckForUpdates", true, false) != null and app.find_child("OpenReleases", true, false) != null, "manual and browser fallback remain accessible")
 var toggle = app.find_child("AutoCheckUpdates", true, false)
 toggle.button_pressed = false
 check(not app.updater.auto_check_enabled, "UI toggle controls auto check")
 # Tests run with isolated XDG directories; verify real preference serialization.
 app.test_session = false
 app._save_preferences()
 app.updater.auto_check_enabled = true
 app._load_preferences()
 check(not app.updater.auto_check_enabled, "opt out persists in application preferences")
 app.test_session = true
 var long_release = good.duplicate(true)
 long_release.tag_name = "android-v209999.99.99"
 long_release.html_url = U.RELEASES_URL + "/tag/" + long_release.tag_name
 long_release.assets[0].browser_download_url = U.RELEASES_URL + "/download/" + long_release.tag_name + "/universal.apk"
 long_release.body = "更新说明与手机安装测试 ".repeat(700)
 var phone_sizes = [Vector2i(1080, 1920), Vector2i(1080, 2400)]
 if "--mobile-ui" in OS.get_cmdline_user_args():
  phone_sizes.append(Vector2i(2400, 1080))
 for phone_size in phone_sizes:
  root.size = phone_size
  for frame in range(16):
   await process_frame
  app.navigate("home")
  app.updater._set_state(U.evaluate_release(long_release, local))
  for frame in range(8):
   await process_frame
  check(app.update_notice.size.y >= 48 and app.update_notice.get_global_rect().end.x <= app.size.x + 1, "update banner fits phone " + str(phone_size))
  app.update_notice.pressed.emit()
  for frame in range(8):
   await process_frame
  check(app.current_screen == "save" and app.main_body.get_parent().scroll_vertical > 0, "update notice jumps directly to update section")
  var auto_button = app.find_child("AutoCheckUpdates", true, false)
  var notes = app.find_child("UpdateReleaseNotes", true, false)
  check(auto_button.size.y >= 48 and auto_button.get_global_rect().end.x <= app.size.x + 1, "auto check touch target fits phone " + str(phone_size))
  check(notes != null and notes.get_global_rect().end.x <= app.size.x + 1, "long release notes wrap within phone " + str(phone_size))
 app.queue_free()
 await process_frame
 print("UPDATE TESTS: %d checks, %d failures" % [checks,fails])
 quit(1 if fails else 0)
