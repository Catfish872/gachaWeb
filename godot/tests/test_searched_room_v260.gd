extends "res://tests/test_redesign_loot_interactions.gd"
const View=preload("res://scripts/ui/extraction_view.gd")

func status(expected:bool,label:String)->void:
	var saved:Dictionary=app.model.state.duplicate(true)
	var rng_state:int=app.model.rng.state
	var result:Dictionary=app.model.extraction.room_interaction_status()
	check(bool(result.hasRemaining)==expected,label+" "+str(result.reasons))
	check(app.model.state==saved and app.model.rng.state==rng_state,label+" query keeps assets and RNG unchanged")

func run()->void:
	root.size=Vector2i(1280,720)
	app=load("res://main.tscn").instantiate();root.add_child(app);await frames(8)
	app.extraction_auto_pick=false;app.extraction_sound=false;app.extraction_reduced_motion=true
	app.model.rng.seed=2
	var x=app.model.extraction
	check(x.start_run(0).success,"start actual run")
	check(x.enter_room(str(x.route_options()[0].id)).success,"enter actual map node")
	x.run().phase="room";x.run().activeEncounter={};x.run().pendingChoices=[]
	x.run().room.type="cache";x.run().room.guardPending=false;x.run().roomActions=[]
	x.run().containers=[];x.run().bag=[]
	for room in x.run().map.rooms:
		if room.id==x.run().room.id:room.type="cache";room.guardPending=false;room.actions=[]
	x._container("已搜索物资",0,0);x._container("最后一个箱子",0,0)
	var first:Dictionary=x.run().containers[0]
	var last:Dictionary=x.run().containers[1]
	for box in [first,last]:
		var item:Dictionary=x._make_item("wire");item.revealed=true
		check(x._place(box.items,item,Vector2i(box.width,box.height)),"place actual leftover loot")
	last.items[0].revealed=false
	status(true,"unsearched last box retains room")
	last.items[0].revealed=true
	status(false,"all searched boxes complete even with collectible loot remaining")
	x.run().pendingChoices=[{"choiceId":"pending"}]
	status(true,"unresolved growth remains interactive")
	x.run().pendingChoices=[];x.run().room.guardPending=true
	status(true,"pending guard retains room")
	x.run().room.guardPending=false;x.run().activeEncounter={"token":"pending"}
	status(true,"pending battle retains room")
	x.run().activeEncounter={};x.run().room.type="rest";x._prepare_room_actions("rest")
	status(true,"available room service retains room")
	x.run().room.type="cache";x.run().roomActions=[]
	var before_boxes:Array=x.run().containers.duplicate(true)
	var before_bag:Array=x.run().bag.duplicate(true)
	var before_gold:int=app.model.state.resources.gold
	var room_id:String=x.run().room.id
	app.navigate("extraction");await frames(8)
	await open_box(str(last.id))
	check(x.run().phase=="room","search result remains visible until actual close")
	await click(target("ExtractionCloseContainer"))
	check(x.run().phase=="route" and target("ExtractionMap")!=null,"closing searched last box displays actual map")
	check(x.run().containers==before_boxes and x.run().bag==before_bag,"auto return preserves every leftover UID and bag item")
	check(x.run().map.currentRoomId==room_id and app.model.state.resources.gold==before_gold,"auto return stays at node and keeps gold")
	check(x.view_current_room().success,"searched node remains manually revisit-able")
	app._render_screen();await frames(8)
	await open_box(str(first.id))
	check(target("ExtractionContainer_"+str(first.id))!=null and x.run().containers==before_boxes,"revisited searched box preserves and displays original loot")
	View._stop_search(app,false);app._clear_overlay()
	app.queue_free();await frames(3)
	print("SEARCHED ROOM V260: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
