extends SceneTree
const Game = preload("res://scripts/game_model.gd")
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)
func _init() -> void:
	var game = Game.new("")
	var ex = game.extraction
	var baseline: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/loot-prices-v2810.json"))
	for id in baseline:
		var definition: Dictionary = ex.item_def(id)
		for risk in range(6):
			check(ex.item_value({"itemId":id, "appraisalRisk":risk, "appraisalAct":3, "legacyValue":999999}) == int(definition.value), "fixed catalog appraisal " + id)
		check(abs(int(definition.value)-int(baseline[id])) <= maxi(1,int(float(baseline[id])*.10)), "modest price change " + id)
	check(ex.start_run(0).success, "start extraction")
	for theme in ex.data.environmentThemes:
		var order: Array = ex.run().environmentOrder
		var index: int = order.find(theme)
		if index >= 0: order[index] = order[0]
		order[0] = theme
		for id in ex.data.items:
			var definition: Dictionary = ex.item_def(id)
			if definition.get("environmentTheme", "") != theme or not definition.has("variantOf"): continue
			check(ex._environment_loot_id(definition.variantOf) == id, "production themed substitution " + id)
			check(ex.item_value(ex._make_item(id)) == int(definition.value), "newly generated item uses appraisal " + id)
	# Sale and reload use the same fixed value for a regional collectible.
	var item: Dictionary = ex._make_item("windpass_compass")
	ex._end("defeat")
	item.revealed = true
	ex.state().stash = [item]
	var before: int = game.state.resources.gold
	var sale: Dictionary = ex.sell_item(item.uid)
	check(sale.get("success", false), "sell adjusted loot")
	check(int(game.state.resources.gold)-before == int(ex.item_def("windpass_compass").value), "sale credits catalog price")
	check(game.valid_save(game.state), "adjusted sale preserves valid save")
	var reloaded = Game.new("")
	reloaded.state = game.state.duplicate(true)
	check(reloaded.valid_save(reloaded.state), "save reload remains compatible")
	check(reloaded.extraction.item_value({"itemId":"windpass_compass"}) == int(ex.item_def("windpass_compass").value), "reload uses same catalog appraisal")
	print("LOOT_PRICE_VARIATION_TEST checks=",checks," failures=",failures)
	quit(1 if failures else 0)
