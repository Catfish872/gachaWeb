extends SceneTree
const Extraction = preload("res://scripts/extraction_model.gd")
const View = preload("res://scripts/ui/extraction_view.gd")
var checks := 0
var failures := 0
class SoundProbe extends RefCounted:
	var cues: Array = []
	var operations := 0
	func _ui_sound(clip: String) -> void: cues.append(clip)
	func _extraction_operation(_result: Dictionary, _message: String) -> void: operations += 1
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
func _initialize() -> void:
	for case in [
		[{"outcome":"extracted","value":700,"securedValue":300},1000,"courier + final bag"],
		[{"outcome":"extracted","value":700,"securedValue":850},1550,"courier + boss parcel + final bag"],
		[{"outcome":"extracted","value":0,"securedValue":850},850,"empty final bag retains parcels"],
		[{"outcome":"defeat","value":700,"securedValue":850},850,"lost bag excluded after defeat"],
		[{"outcome":"retreat","value":700,"securedValue":300},300,"retreat keeps courier value"],
		[{"outcome":"extracted","value":700},700,"legacy successful report"],
		[{"outcome":"defeat","value":700},0,"legacy loss does not invent parcels"],
		[{},0,"empty report"],
		[{"outcome":"extracted","value":700,"securedValue":300,"salvageGold":99},1000,"no cash double counting"]
	]:
		var report: Dictionary = case[0]
		var before := report.duplicate(true)
		check(Extraction.secured_summary_value(report)==case[1],case[2])
		check(report==before,"summary query never mutates report")
	var app := SoundProbe.new()
	View._operate_sound(app,{"success":true},"coin")
	check(app.cues==["coin"] and app.operations==1,"successful sale one cue")
	View._operate_sound(app,{"success":false},"coin")
	check(app.cues==["coin"] and app.operations==2,"failed sale no cue")
	var ui := FileAccess.get_file_as_string("res://scripts/ui/extraction_view.gd")
	check(ui.contains('app.model.extraction.secured_summary_value(summary)'),"departure uses total secured value")
	check(ui.contains('app.model.extraction.call(method,uids.duplicate()),"coin" if method=="sell_items"'),"batch routes one operation one cue")
	check(ui.contains('if app._check(result):\n\t\t\tapp._ui_sound("pickup" if collect else "coin")'),"sell-all sound only on success")
	var main := FileAccess.get_file_as_string("res://scripts/main.gd")
	check(main.contains('if not sound_enabled:return') and main.contains('ui_audio.volume_db = effects_volume_db-'),"UI audio retains mute and effects volume")
	var clip := AudioStreamOggVorbis.load_from_file("res://assets/audio/ui/coin.ogg")
	check(clip != null and clip.get_length() > .1 and clip.get_length() < .8,"short decodable coin sound")
	print("SECURED SUMMARY AUDIO V260: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
