extends SceneTree
const Game = preload("res://scripts/game_model.gd")
func packed_value(ex, offers: Array, prices: Dictionary) -> int:
	var ordered: Array = offers.duplicate(true)
	ordered.sort_custom(func(a,b):
		var da: Dictionary = ex.item_def(a.itemId)
		var db: Dictionary = ex.item_def(b.itemId)
		var av: float = float(prices.get(a.itemId,da.value))/float(da.width*da.height)
		var bv: float = float(prices.get(b.itemId,db.value))/float(db.width*db.height)
		return av > bv if av != bv else str(a.uid) < str(b.uid))
	var bag: Array = []
	var total := 0
	for item in ordered:
		if ex._place(bag,item,Vector2i(6,5)):
			total += int(prices.get(item.itemId,ex.item_def(item.itemId).value))
	return total
func _init() -> void:
	var game = Game.new("")
	var ex = game.extraction
	game.rng.seed = 2811009
	ex.start_run(0)
	var old: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/loot-prices-v2810.json"))
	var rows: Array = []
	var all_before := 0
	var all_after := 0
	var samples := 0
	for theme in ex.data.environmentThemes:
		var order: Array = ex.run().environmentOrder
		var index: int = order.find(theme)
		if index >= 0: order[index] = order[0]
		order[0] = theme
		for risk in [0,3,5]:
			ex.run().difficulty = risk
			var before := 0
			var after := 0
			for sample in range(100):
				var offers: Array = []
				for cache in range(8):
					ex.run().containers = []
					ex._container("price comparison",3,cache%3)
					offers.append_array(ex.containers()[0].items)
				before += packed_value(ex, offers, old)
				after += packed_value(ex, offers, {})
				samples += 1
			rows.append({"theme":theme,"risk":risk,"samples":100,"meanBefore":before/100.0,"meanAfter":after/100.0,"relativeChange":float(after-before)/before})
			all_before += before
			all_after += after
	var result := {"scope":"Conditional loot-only comparison: identical production container draws; 24 offered items packed by value density into 30 cells. No combat/survival or full-run earnings prediction.","seed":2811009,"samples":samples,"meanBefore":float(all_before)/samples,"meanAfter":float(all_after)/samples,"relativeChange":float(all_after-all_before)/all_before,"groups":rows}
	var file := FileAccess.open("res://validation/v2811-loot/packed-comparison.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"  "))
	print("PACKED_PRICE_COMPARISON samples=",samples," meanBefore=",result.meanBefore," meanAfter=",result.meanAfter," relativeChange=",result.relativeChange)
	quit(0)
