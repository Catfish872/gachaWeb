extends SceneTree
var app
var checks:=0
var failures:=0
func _initialize():call_deferred("run")
func ck(ok:bool,label:String):
	checks+=1
	if not ok:failures+=1;push_error(label)
func frames(n:int=8):
	for i in n:await process_frame
func run():
	app=load("res://main.tscn").instantiate();root.add_child(app);await frames();app.set_process(false)
	app.model=load("res://scripts/game_model.gd").new("")
	for upgrade in app.model.rogue_data.metaUpgrades:app.model.state.abyss.meta.upgrades[upgrade.id]=upgrade.maxLevel
	app.model.state.abyss.meta.currency=123
	app.navigate("story");await frames()
	var stamina:int=app.model.state.resources.stamina
	app._begin_stage("ch1_1");await frames()
	ck(not app.dialogue_key.is_empty(),"actual story entry opens pre-battle dialogue")
	ck(app.model._issued_config.is_empty(),"real UI postpones prepare_stage until dialogue finishes")
	ck(app.model.state.resources.stamina==stamina,"pre-battle dialogue has not consumed stamina")
	app.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST);await frames()
	ck(app.dialogue_key.is_empty() and app.overlay.get_child_count()==0,"actual Back cancels dialogue exactly once")
	ck(app.model._issued_config.is_empty(),"cancelled pre-dialogue leaves no stale battle credential")
	ck(app.model.state.resources.stamina==stamina,"cancel has no hidden stamina charge")
	ck(app.model.memory_exchange_status().enabled,"maxed camp memory exchange remains available after cancel")
	ck(app.model.exchange_memory(1).get("success",false),"real exchange succeeds after cancellation")
	var prep:Dictionary=app.model.prepare_abyss()
	ck(prep.get("success",false),"next expedition can start after dialogue cancellation")
	app.queue_free();await process_frame;await create_timer(.3).timeout
	print("STORY CANCEL V24: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
