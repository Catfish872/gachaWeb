extends "res://tests/test_service_layout_v241.gd"
const View=preload("res://scripts/ui/extraction_view.gd")
var baseline:Dictionary

func capture(label:String)->void:
	if DisplayServer.get_name()=="headless":return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://validation/room-return-v250/"+label+".png")

func reset_room(kind:String="cache")->void:
	View._stop_search(app,false);app._clear_overlay()
	app.model.state=baseline.duplicate(true);app.model.save_blocked=false;app.model.last_error=""
	var x=app.model.extraction
	x.run().phase="room";x.run().room.type=kind;x.run().room.guardPending=false
	x.run().room.depositUsed=false;x.run().activeEncounter={};x.run().pendingChoices=[]
	x.run().roomActions=[];x.run().containers=[];x.run().bag=[];x.run().equipped=[]
	for room in x.run().map.rooms:
		if room.id==x.run().room.id:room.type=kind;room.containers=[];room.actions=[];room.guardPending=false
	app.extraction_panel="expedition";app.extraction_selected="";app.extraction_auto_pick=false
	app.navigate("extraction");await frames(10)

func box_with(item_ids:Array=[],revealed:bool=true)->Dictionary:
	var x=app.model.extraction
	x._container("测试物资箱",0,0)
	var box:Dictionary=x.run().containers.back()
	for id in item_ids:
		var item:Dictionary=x._make_item(str(id));item.revealed=revealed
		check(x._place(box.items,item,Vector2i(box.width,box.height)),"fixture packs physical source item")
	return box

func pure_status(remaining:bool,label:String)->Dictionary:
	var state:Dictionary=app.model.state.duplicate(true)
	var rng_state:int=app.model.rng.state
	app.model.last_error="query sentinel"
	var status:Dictionary=app.model.extraction.room_interaction_status()
	check(status.hasRemaining==remaining,label+" remaining="+str(status.reasons))
	check(app.model.extraction.has_remaining_interaction()==remaining,label+" boolean contract")
	check(app.model.state==state and app.model.rng.state==rng_state and app.model.last_error=="query sentinel",label+" pure query preserves all state, RNG and errors")
	return status

func show_room()->void:
	app._render_screen();await frames(10)

func back()->void:
	app.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST);await frames(10)

func model_contract()->void:
	var x=app.model.extraction
	await reset_room()
	var box:=box_with()
	check(pure_status(false,"empty shell").canAutoReturn,"empty shell allows auto return")
	x.run().room.cleared=false
	pure_status(false,"cleared flag is independent of interaction completion")
	box=box_with(["wire"],false)
	pure_status(true,"second searchable container")
	box.items[0].revealed=true
	fill_wire(x,30)
	pure_status(true,"full bag keeps manual exchange")
	box.items=[]
	var med:Dictionary=x._make_item("medkit");med.revealed=true;med.exchangeLocked=true;box.items=[med]
	pure_status(true,"full bag and ineffective medicine still allow manual exchange")
	for unit in x.run().party:unit.currentHp=1
	pure_status(true,"direct healing remains available with full bag")
	x.data.items.future_huge={"name":"大型物资","kind":"loot","width":9,"height":9,"value":1,"rarity":0}
	var huge:Dictionary=x._make_item("future_huge");huge.revealed=true;box.items=[huge];box.width=12;box.height=12
	pure_status(false,"oversized future loot has no pickup or exchange path")
	check(box.items[0].uid==huge.uid,"blocked world item remains intact")
	x.data.items.future_medicine=x.item_def("medkit").duplicate(true);x.data.items.future_medicine.width=9;x.data.items.future_medicine.height=9
	var medicine:Dictionary=x._make_item("future_medicine");medicine.revealed=true;box.items=[medicine]
	pure_status(true,"oversized usable medicine keeps direct use")
	x.data.items.future_gear=x.item_def("blade").duplicate(true);x.data.items.future_gear.width=9;x.data.items.future_gear.height=9
	var gear:Dictionary=x._make_item("future_gear");gear.revealed=true;box.items=[gear]
	pure_status(true,"oversized tactical gear keeps direct equip")
	x.data.items.erase("future_huge");x.data.items.erase("future_medicine");x.data.items.erase("future_gear")
	await reset_room("key_vault")
	x._prepare_room_actions("key_vault")
	pure_status(false,"locked vault without matching key")
	var key:Dictionary=x._make_item(x._room_key_id());key.revealed=true;x.state().keyring.append(key)
	pure_status(true,"matching key enables actual vault action")
	await reset_room()
	box=box_with(["key_ruins"])
	x.state().keyring=[]
	for i in 20000:
		var entry:Dictionary=box.items[0].duplicate(true);entry.uid="capacity_key_"+str(i);x.state().keyring.append(entry)
	pure_status(false,"full keyring blocks revealed key pickup without discarding it")
	x.state().keyring.append(box.items[0].duplicate(true))
	pure_status(true,"invalid over-capacity keyring conservatively keeps room")
	await reset_room()
	x.run().pendingChoices=[{"choiceId":"pending"}]
	pure_status(true,"pending growth blocks completion")
	x.run().pendingChoices=[];x.run().room.guardPending=true
	pure_status(true,"pending service guard blocks completion")
	x.run().room.guardPending=false;x.run().activeEncounter={"token":"pending"}
	pure_status(true,"pending encounter blocks completion")
	x.run().activeEncounter={};x.run().phase="boss_exit"
	pure_status(true,"boss exit remains an available interaction")
	await reset_room("relay")
	fill_wire(x,1);app.model.state.resources.gold=50
	pure_status(true,"payable single-item parcel")
	app.model.state.resources.gold=49;pure_status(false,"unaffordable parcel")
	app.model.state.resources.gold=50;x.run().room.depositUsed=true;pure_status(false,"used parcel")
	x.run().room.depositUsed=false;x.run().bag=[];pure_status(false,"empty bag has no parcel")
	fill_wire(x,1)
	x.state().stash=[]
	for y in 12:
		for col in 10:
			var item:Dictionary=x._make_item("wire");item.revealed=true;item.x=col;item.y=y;x.state().stash.append(item)
	x.state().mailbox=[]
	for i in 10000:
		var item:Dictionary=x._make_item("wire");item.revealed=true;x.state().mailbox.append(item)
	pure_status(false,"full warehouse and mailbox cannot accept parcel")
	x.state().stash.pop_back();pure_status(true,"one physical warehouse cell permits a manual parcel")
	await reset_room()
	box=box_with();box.width=0
	pure_status(true,"invalid container capacity is retained safely")
	await reset_room();x.run().erase("bag")
	pure_status(true,"missing inventory is retained safely")
	await reset_room();x.run().erase("room")
	pure_status(true,"missing room is retained safely")

func container_completion()->void:
	var x=app.model.extraction
	await reset_room()
	var box:=box_with(["wire"])
	await show_room();await open_box(box.id)
	await click(target("ExtractionTakeAll"))
	check(x.run().phase=="room" and app.overlay.get_child_count()>0,"last pickup keeps results visible until close")
	var context:Dictionary=app.overlay.find_child("ModalPanel",true,false).get_meta("extraction_context").duplicate(true)
	var before:Dictionary=app.model.state.duplicate(true)
	var map_id:String=x.run().map.currentRoomId
	await capture("last-item-before-close")
	await click(target("ExtractionCloseContainer"))
	check(x.run().phase=="route" and app.overlay.get_child_count()==0,"last container close returns to map")
	check(x.run().map.currentRoomId==map_id,"return keeps map current node")
	check(x.run().bag==before.extraction.run.bag and x.run().containers==before.extraction.run.containers and x.run().rngState==before.extraction.run.rngState and x.run().serial==before.extraction.run.serial and app.model.state.resources==before.resources,"advance preserves all items, RNG, UID serial and currencies")
	var stable:Dictionary=app.model.state.duplicate(true)
	var map_instance:int=target("ExtractionMap").get_instance_id()
	View._close_container(app,context);View._close_container(app,context);await frames()
	check(app.model.state==stable and target("ExtractionMap").get_instance_id()==map_instance,"duplicate stale close performs no save or render")
	for resolution in [Vector2i(1920,1080),Vector2i(2340,1080),Vector2i(1280,720),Vector2i(2048,945)]:
		root.size=resolution;await frames(12)
		visible_control(target("ExtractionMap"),"returned map "+str(resolution))
		footer("returned map "+str(resolution))
		check(x.run().map.currentRoomId==map_id,"dynamic layout preserves map node")
	await capture("returned-map")
	await reset_room()
	box=box_with();var other:=box_with(["wire"],false)
	await show_room();await open_box(box.id);await click(target("ExtractionCloseContainer"))
	check(x.run().phase=="room" and other.items.size()==1,"another unsearched container retains room")
	other.items[0].revealed=true;fill_wire(x,30);await show_room()
	await open_box(box.id);await click(target("ExtractionCloseContainer"))
	check(x.run().phase=="room","full bag retains revealed manual-exchange candidate")
	await reset_room();box=box_with();await show_room();await open_box(box.id)
	var prior:Dictionary=app.model.state.duplicate(true)
	app.model.save_blocked=true
	await click(target("ExtractionCloseContainer"))
	check(app.model.state==prior and target("ExtractionCloseContainer")!=null and x.run().phase=="room","failed advance save preserves room, modal and every asset")
	check(target("FeedbackToast")!=null,"failed save displays retryable error")
	app.model.save_blocked=false;await click(target("ExtractionCloseContainer"))
	check(x.run().phase=="route","close retries successfully after persistence recovers")
	await reset_room();box=box_with();await show_room();await open_box(box.id)
	var point:Vector2=target("ExtractionCloseContainer").get_global_rect().get_center()
	for repeat in 2:
		for down in [true,false]:
			var touch:=InputEventScreenTouch.new();touch.index=0;touch.position=point;touch.pressed=down;root.push_input(touch,true)
			var mouse:=InputEventMouseButton.new();mouse.button_index=MOUSE_BUTTON_LEFT;mouse.position=point;mouse.global_position=point;mouse.pressed=down;root.push_input(mouse,true)
	await frames(12)
	check(x.run().phase=="route" and target("ExtractionMap")!=null,"rapid touch plus synthesized mouse closes once into map")
	stable=app.model.state.duplicate(true);map_instance=target("ExtractionMap").get_instance_id();await frames(12)
	check(app.model.state==stable and target("ExtractionMap").get_instance_id()==map_instance,"rapid close leaves no deferred second navigation or render")

func asynchronous_close()->void:
	var x=app.model.extraction
	await reset_room()
	var box:=box_with(["wire"],false)
	app.extraction_auto_pick=true;await show_room();await open_box(box.id)
	var deadline:int=Time.get_ticks_msec()+3000
	while int(app.overlay.get_meta("pending_loot",0))==0 and Time.get_ticks_msec()<deadline:await process_frame
	check(int(app.overlay.get_meta("pending_loot",0))==1 and box.items[0].revealed,"real search queues delayed auto pickup")
	var generation:int=app.extraction_search_generation
	await click(target("ExtractionCloseContainer"))
	check(x.run().phase=="room" and not app.extraction_searching and app.extraction_search_generation>generation,"close cancels delayed pickup before completion query")
	var stable:Dictionary=app.model.state.duplicate(true)
	await create_timer(.55).timeout
	check(app.model.state==stable and x.run().bag.is_empty() and x.run().containers[0].items.size()==1,"late auto pickup preserves exact source UID after close")
	await open_box(box.id)
	var stale:Dictionary=app.overlay.find_child("ModalPanel",true,false).get_meta("extraction_context").duplicate(true)
	View._stop_search(app,false)
	var stopped:int=app.extraction_search_generation
	await frames()
	check(app.extraction_search_generation==stopped and not app.extraction_searching,"queued scan obeys invalidated generation")
	app._clear_overlay();x.run().room.id="later_room";x.run().map.currentRoomId="later_room"
	var later:Dictionary=app.model.state.duplicate(true)
	View._close_container(app,stale)
	check(app.model.state==later,"stale room close leaves newer room unchanged")
	await reset_room();box=box_with(["wire"],false)
	await show_room();await open_box(box.id)
	app.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	stable=app.model.state.duplicate(true)
	await create_timer(.65).timeout
	check(app.model.state==stable,"background pauses real search without revealing or collecting")
	app.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	await back();stable=app.model.state.duplicate(true);await create_timer(.65).timeout
	check(app.model.state==stable and x.run().phase=="room","resume and Android Back cancel scan while searchable item keeps room")

func choices_and_back()->void:
	var x=app.model.extraction
	await reset_room("rest");x._prepare_room_actions("rest");await show_room()
	var button=target("ExtractionRoomAction_recover");await reach_service(button);await click(button)
	check(x.run().phase=="route","successful empty rest returns to map")
	await reset_room("event");x._prepare_room_actions("event",0);await show_room()
	button=target("ExtractionRoomAction_search");await reach_service(button);await click(button)
	check(x.run().phase=="room" and not x.containers().is_empty(),"event-spawned container keeps room")
	await reset_room("event");x._prepare_room_actions("event",5);await show_room()
	var battle_id:=""
	for action in x.run().roomActions:
		if action.effect.has("battle"):battle_id=action.id
	check(not battle_id.is_empty(),"actual event has prepared encounter choice")
	if not battle_id.is_empty():
		button=target("ExtractionRoomAction_"+battle_id);await reach_service(button);await click(button)
		check(x.run().phase=="battle" and target("ExtractionBattle")!=null,"event-created battle remains visible")
	await reset_room("workshop");x._prepare_room_actions("workshop");await show_room()
	button=target("ExtractionRoomAction_study");await reach_service(button);await click(button)
	check(x.run().phase=="room" and not x.growth_choices().is_empty(),"room action keeps actual pending blessing")
	var choice:Dictionary=x.growth_choices()[0]
	await click(target("ExtractionGrowth_"+str(choice.choiceId)))
	check(x.run().phase=="route" and x.growth_choices().is_empty(),"last growth choice completes empty workshop")
	await reset_room();var box:=box_with();await show_room();await open_box(box.id);await back()
	check(x.run().phase=="route","Android Back closes exact container like X")
	await reset_room();box=box_with();await show_room();await open_box(box.id)
	View._help(app);var stable:Dictionary=app.model.state.duplicate(true);await back()
	check(app.model.state==stable and x.run().phase=="room","new help modal ignores stale container overlay metadata")
	await open_box(box.id);app._clear_overlay();await click(target("ExtractionAbandon"));stable=app.model.state.duplicate(true);await back()
	check(app.model.state==stable and x.run().phase=="room","abandon cancellation retains room")
	await reset_room();box=box_with(["gold_watch"]);fill_wire(x,30);await show_room();await open_box(box.id)
	await select_item(box.id,box.items[0].uid)
	await click(target("ExtractionManualExchange_"+str(box.items[0].uid)))
	stable=app.model.state.duplicate(true);await back()
	check(app.model.state==stable and target("ExtractionCloseContainer")!=null and target("ExtractionManualExchangeCancel")==null,"Android Back cancels manual exchange inside same container")
	await click(target("ExtractionCloseContainer"));check(x.run().phase=="room","exchange cancellation retains available item")
	await reset_room("boss");x.run().phase="boss_exit";box=box_with();await show_room();await open_box(box.id);await back()
	check(x.run().phase=="boss_exit" and target("ExtractionExit")!=null and target("ExtractionNextAct")!=null,"empty boss container retains extract and continue actions")

func parcel_completion()->void:
	var x=app.model.extraction
	await reset_room("relay");fill_wire(x,1);await show_room()
	await click(target("ExtractionDepositPreview"))
	var stable:Dictionary=app.model.state.duplicate(true);await back()
	check(app.model.state==stable and x.run().phase=="room","parcel preview cancellation retains room")
	await click(target("ExtractionDepositPreview"));await click(target("ExtractionDepositConfirm"))
	check(x.run().phase=="room" and x.run().room.depositUsed and target("FeedbackToast")!=null,"successful parcel feedback precedes return")
	var gold:int=app.model.state.resources.gold
	await create_timer(2.2).timeout;await frames()
	check(x.run().phase=="route" and app.model.state.resources.gold==gold,"feedback completion auto returns and charges once")
	await reset_room("relay");fill_wire(x,1);await show_room()
	await click(target("ExtractionDepositPreview"));await click(target("ExtractionDepositConfirm"))
	app.notification(Node.NOTIFICATION_APPLICATION_PAUSED);await create_timer(2.2).timeout
	check(x.run().phase=="room","background defers completed parcel navigation")
	app.notification(Node.NOTIFICATION_APPLICATION_RESUMED);await frames(10)
	check(x.run().phase=="route","resume completes same parcel room once")
	await reset_room("relay");fill_wire(x,1);await show_room()
	await click(target("ExtractionDepositPreview"));await click(target("ExtractionDepositConfirm"))
	var context:Dictionary=View._room_context(app)
	View._stop_search(app,false)
	stable=app.model.state.duplicate(true);await create_timer(2.2).timeout
	check(app.model.state==stable and x.run().phase=="room","stale parcel generation cannot navigate")
	View._try_completed_room(app,context);check(app.model.state==stable,"explicit stale completion context is idempotent")
	await reset_room("relay");fill_wire(x,1);await show_room()
	await click(target("ExtractionDepositPreview"));await click(target("ExtractionDepositConfirm"))
	context=View._room_context(app)
	x.run().id="new_run";x.run().room.id="new_room";x.run().map.currentRoomId="new_room"
	stable=app.model.state.duplicate(true);await create_timer(2.2).timeout
	check(app.model.state==stable and x.run().phase=="room","late parcel feedback cannot navigate a newer run or room")
	View._try_completed_room(app,context);check(app.model.state==stable,"old run/room completion stays inert even with same generation")

func run()->void:
	DirAccess.make_dir_recursive_absolute("res://validation/room-return-v250")
	root.size=Vector2i(2048,945)
	app=load("res://main.tscn").instantiate();root.add_child(app);await frames(12)
	app.extraction_sound=false;app.extraction_reduced_motion=true;app.model.rng.seed=2
	var x=app.model.extraction
	check(x.start_run().success,"real model departure")
	for room in x.route_options():
		if room.type=="cache":check(x.enter_room(room.id).success,"real generated room entry");break
	baseline=app.model.state.duplicate(true)
	await model_contract()
	await container_completion()
	await asynchronous_close()
	await choices_and_back()
	await parcel_completion()
	View._stop_search(app,false);app.queue_free();await frames();await create_timer(.2).timeout
	print("ROOM RETURN V250: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
