extends SceneTree
const Game=preload("res://scripts/game_model.gd")
var checks:=0
var failed:=0
func ck(ok:bool,label:String)->void:
	checks+=1
	if not ok:failed+=1;push_error(label)
func _initialize()->void:
	var g=Game.new("");var ex=g.extraction
	ex.state().stash=[{"uid":"owned","itemId":"guardian_seal","x":0,"y":0,"rotated":false,"revealed":true}]
	ck(ex.equip_item("owned").success and ex.start_run().success,"equipped departure")
	var utility:Dictionary=ex.state().utility.duplicate(true)
	ck(ex.retreat().success,"retreat commits original failure rule")
	ck(ex.state().run.is_empty() and ex.state().tactical.is_empty() and ex.state().stash.is_empty(),"failed action loses tactical rather than returning it")
	ck(ex.state().utility==utility,"persistent utility remains unchanged")
	ck(ex.start_run().success,"second run starts")
	ex._generate_encounter("battle");var config:Dictionary=ex.prepare_battle().config.duplicate(true);var rng_before:String=str(ex.run().rngState)
	ex.run().phase="battle";ex.state().equipmentRules=0
	g.state=g._normalize(g.state)
	ck(ex.prepare_battle().config==config and str(ex.run().rngState)==rng_before,"real issued config and RNG byte-equivalent across old-rule normalize")
	print("LOSS ISSUED V276: %d checks, %d failures"%[checks,failed]);quit(0 if failed==0 else 1)
