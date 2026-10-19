extends SceneTree
const U = preload("res://scripts/update_checker.gd")
var checks = 0
var fails = 0
func check(value, name):
 checks += 1
 if not value:
  fails += 1
  push_error("FAIL: " + name)
func _init():
 var local = U.read_local_version()
 check(U.valid_local_version(local), "local metadata")
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
 print("UPDATE TESTS: %d checks, %d failures" % [checks,fails])
 quit(1 if fails else 0)
