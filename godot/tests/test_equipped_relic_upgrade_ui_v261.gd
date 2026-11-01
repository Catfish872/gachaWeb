extends "res://tests/test_relic_loadout_ui_v250.gd"
const OUT261="res://validation/equipped-upgrade-v261/"
func capture(label:String)->void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT261+label+".png")
func find_text(node:Node,text:String):
	if node is Button and node.text==text:return node
	for child in node.get_children():
		var found=find_text(child,text)
		if found!=null:return found
	return null
func text_all(node:Node)->String:
	var text:String=str(node.text) if node is Label or node is Button else ""
	for child in node.get_children():text+="\n"+text_all(child)
	return text
func equipped_game():
	var game=load("res://scripts/game_model.gd").new("");game.rng.seed=26131
	game.state.resources.gold=10000000
	for i in range(5):
		var relic:Dictionary=game.generate_relic(5,str(game.catalog.RelicSlots[i].id),str(game.catalog.RelicSets.keys()[i%6]))
		relic.level=[0,5,12,24,25][i];game.add_relic(relic)
		ck(game.equip_relic(str(relic.uid),"ember").success,"fixture equips actual slot")
	return game
func run()->void:
	if DisplayServer.get_name()=="headless":quit(2);return
	DirAccess.make_dir_recursive_absolute(OUT261)
	app=load("res://main.tscn").instantiate();root.add_child(app);await frames(12);app.set_process(false)
	for resolution in [Vector2i(2048,945),Vector2i(960,540)]:
		root.size=resolution;await frames();app.model=equipped_game();app.selected_character="ember";app.growth_panel="gear";app.navigate("growth");await frames()
		var label:=str(resolution.x)
		var expected:=0
		for relic in app.model.equipped_relics("ember"):
			for level in range(int(relic.level),25):expected+=app.model.relic_upgrade_cost(level)
		var action=app.find_child("GrowthUpgradeAllRelics",true,false)
		fits(action,"upgrade footer "+label);fits(app.find_child("GrowthAutoRelics",true,false),"auto equip preserved")
		ck(str(expected) in action.text,"exact total visible on button")
		await capture("ready-"+label)
		var before:int=app.model.state.resources.gold
		await tap(action)
		ck(str(expected) in text_all(app.overlay) and "4 件遗物" in text_all(app.overlay),"confirmation exact cost and current equipped count")
		ck(app.model.state.resources.gold==before,"opening confirmation spends nothing")
		await capture("confirm-"+label)
		await tap(find_text(app.overlay,"确认"));await frames()
		ck(app.model.state.resources.gold==before-expected,"one exact deduction")
		for relic in app.model.equipped_relics("ember"):ck(int(relic.level)==25,"every worn relic reaches max")
		action=app.find_child("GrowthUpgradeAllRelics",true,false)
		ck(action.disabled and action.text=="已全部满级","completed button clear and disabled")
		await tap(action);ck(app.model.state.resources.gold==before-expected,"repeat tap no second deduction")
		await capture("complete-"+label)
	# Only the modified action: insufficient funds and empty equipped slots.
	app.model=equipped_game();app.model.state.resources.gold=1;app.navigate("growth");await frames()
	var before_state:Dictionary=app.model.state.duplicate(true)
	await tap(app.find_child("GrowthUpgradeAllRelics",true,false))
	ck(app.model.state==before_state and app.overlay.get_child_count()==0,"insufficient gold no mutation or confirmation")
	ck("金币不足" in text_all(app),"insufficient gold has direct feedback")
	app.model=load("res://scripts/game_model.gd").new("");app.navigate("growth");await frames()
	var empty=app.find_child("GrowthUpgradeAllRelics",true,false)
	fits(empty,"empty equipped footer");ck(empty.disabled and empty.tooltip_text=="请先装备遗物","empty slots explain disabled upgrade")
	await capture("empty-960")
	app.queue_free();await frames();print("EQUIPPED RELIC UI V261: %d checks, %d failures"%[checks,failures.size()]);quit(0 if failures.is_empty() else 1)
