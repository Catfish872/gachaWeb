extends SceneTree
const Game = preload("res://scripts/game_model.gd")
const Optimizer = preload("res://scripts/relic_optimizer.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var report: Array = []
	for count in [100,500,2000,100000]:
		var game = Game.new("")
		game.rng.seed = 250001+count
		var sets: Array = game.catalog.RelicSets.keys()
		for index in range(count):
			var item: Dictionary = game.generate_relic(3+index%3,Optimizer.SLOTS[index%5])
			item.uid = "profile_%06d"%index
			item.setId = sets[index%sets.size()]
			item.level = index%13
			game.state.relics.append(item)
		var state_hash := JSON.stringify(game.state).sha256_text()
		var baseline_memory:=OS.get_static_memory_usage()
		var start := Time.get_ticks_usec()
		var search = Optimizer.new(game,"ember")
		var initialization := Time.get_ticks_usec()-start
		var slices: Array = []
		var result: Dictionary = search.preview()
		# Common sizes run to a certificate; 2000 observes a minute of interactive search.
		# The legal 100k case runs through full scan/preparation to its first applicable plan.
		while not result.done and (count<=500 or (count==2000 and Time.get_ticks_usec()-start<60000000) or (count==100000 and not result.canApply)):
			var tick := Time.get_ticks_usec()
			result = search.advance(4000)
			slices.append(Time.get_ticks_usec()-tick)
		var elapsed := Time.get_ticks_usec()-start
		slices.sort()
		var row := {"inventory":count,"initializationUsec":initialization,"elapsedUsec":elapsed,"slices":slices.size(),"maxSliceUsec":slices.back() if not slices.is_empty() else 0,"p95SliceUsec":slices[int(slices.size()*0.95)] if not slices.is_empty() else 0,"phase":result.phase,"scanned":result.scanned,"candidateCounts":result.candidateCounts,"visited":result.visited,"removed":result.pruned,"provenOptimal":result.provenOptimal,"lowerBound":result.lowerBound,"upperBound":result.upperBound,"gap":result.gap,"stateUnchanged":state_hash==JSON.stringify(game.state).sha256_text(),"memoryBytes":OS.get_static_memory_usage(),"incrementalMemoryBytes":OS.get_static_memory_usage()-baseline_memory,"evaluations":result.evaluationCalls,"cacheHits":result.evaluationCacheHits,"boundCacheHits":result.boundCacheHits,"fastBounds":result.fastBounds,"frontier":result.frontierNodes,"setCounts":result.after.get("counts",{}),"canApply":result.canApply}
		report.append(row); print(JSON.stringify(row))
		search.cancel()
		search=null
		game=null
	DirAccess.make_dir_recursive_absolute("res://validation/relic-optimizer-v250")
	var file := FileAccess.open("res://validation/relic-optimizer-v250/profile.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"host":"Godot 4.6.3 Linux headless; desktop proxy, Android remains to verify","budgetUsec":4000,"reference":"six-action actual-auto Ember; full proof at 100/500, sixty-second interaction at 2000, full preparation and first applicable recommendation at legal 100000","cases":report},"\t"))
	quit()
