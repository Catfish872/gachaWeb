extends SceneTree
const Game=preload("res://scripts/game_model.gd")
var checks:=0
var failures:=0
func ck(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func _initialize()->void:call_deferred("run")
func abyss():
	var g=Game.new("");g.rng.seed=278;g.prepare_abyss();g._issued_config={};g.state.abyss.rogue.activeEncounter={};g.state.abyss.rogue.temporaryCurrency=1000;g.state.abyss.savedPartyState=[]
	for u in g.battle_party(true):g.state.abyss.savedPartyState.append({"id":u.id,"currentHp":100,"maxHp":1000,"energy":0,"cooldowns":{"x":3}})
	return g
func expedition():
	var g=Game.new("");g.rng.seed=278;g.extraction.start_run();var ex=g.extraction;ex.run().phase="room";ex.run().activeEncounter={};ex.run().pendingChoices=[];ex.run().containers=[]
	for u in ex.run().party:u.currentHp=100;u.maxHp=1000;u.energy=0
	return g
func ids(options:Array)->Array:return options.map(func(o):return o.id)
func run()->void:
	var g=abyss();ck(g.rogue_data.events.size()==8,"eight abyss event types")
	for event in g.rogue_data.events:
		var chosen:Array=g._sample_abyss_option_ids(event.options)
		ck(event.options.size()==4 and chosen.size()==3 and chosen[0]!=chosen[1] and chosen[0]!=chosen[2] and chosen[1]!=chosen[2],"unique three of four "+event.id)
		g.state.abyss.rogue.nextStep={"type":"event","floor":2};g.state.abyss.rogue.pendingNode={"id":"event_2","type":"event","eventId":event.id,"eventOptionIds":chosen}
		var rng_before:int=g.rng.state;g.node_options();g.state=g._normalize(JSON.parse_string(JSON.stringify(g.state)))
		ck(ids(g.node_options().options)==chosen and g.rng.state==rng_before,"reload and display stable "+event.id)
		for option in event.options:
			if option.id not in chosen:
				var before:String=JSON.stringify(g.state);ck(not g.choose_abyss_node(option.id).success and before==JSON.stringify(g.state),"hidden choice rejected "+event.id)
	g=abyss();g.state.abyss.rogue.eventHistory=[{"type":"event","eventId":"blood_altar"},{"type":"event","eventId":"lost_caravan"}];g._set_after_floor(2)
	ck(g.state.abyss.rogue.pendingNode.eventId not in ["blood_altar","lost_caravan"],"recent two excluded")
	g.state.abyss.rogue.nextStep={"type":"rest","floor":2};g.state.abyss.rogue.pendingNode={"id":"rest_2","type":"rest","restOptionIds":g._sample_abyss_option_ids(g.rogue_data.restOptions,"recover")}
	ck(g.node_options().options.size()==3 and "recover" in ids(g.node_options().options),"camp fixed recovery")
	g.state.abyss.savedPartyState[1].currentHp=0;ck(g.choose_abyss_node("recover").success and g.state.abyss.savedPartyState[0].currentHp==450 and g.state.abyss.savedPartyState[1].currentHp==350,"actual heal and revive")
	g=abyss();g.state.abyss.rogue.nextStep={"type":"rest","floor":2};g.state.abyss.rogue.pendingNode={"id":"rest_2","type":"rest"}
	ck(ids(g.node_options().options)==["recover","meditate","scavenge"],"legacy camp unchanged")
	g.state.abyss.rogue.nextStep.type="event";g.state.abyss.rogue.pendingNode={"id":"event_2","type":"event","eventId":"blood_altar"}
	ck(ids(g.node_options().options)==["sacrifice","offering","leave"],"legacy event unchanged")
	ck(g.choose_abyss_node("offering").success and g.state.abyss.rogue.temporaryCurrency==955 and g.state.abyss.rogue.selectedRewards.size()==1,"actual paid blessing")
	g=expedition();var ex=g.extraction
	for index in range(9):
		ex._prepare_room_actions("event",index);var menu:String=JSON.stringify(JSON.parse_string(JSON.stringify(ex.run().roomActions)));var chosen:Array=ids(ex.room_actions());var rng_before=ex.run().rngState
		ck(chosen.size()==3 and chosen[0]!=chosen[1] and chosen[0]!=chosen[2] and chosen[1]!=chosen[2],"expedition unique options "+str(index))
		ex.room_actions();g.state=g._normalize(JSON.parse_string(JSON.stringify(g.state)))
		ck(JSON.stringify(ex.run().roomActions)==menu and ex.run().rngState==rng_before,"expedition reload stable "+str(index))
	ex.run().recentEventIds=[0,1];ex._prepare_room_actions("event");ck(ex.run().recentEventIds.back() not in [0,1],"expedition recent two excluded")
	var before:String=JSON.stringify(g.state);ck(not ex.choose_room_action("not_shown").success and JSON.stringify(g.state)==before,"hidden expedition choice rejected")
	for kind in ["rest","hospital"]:
		g=expedition();ex=g.extraction;ex._prepare_room_actions(kind);ex.run().party[1].currentHp=0
		ck(ex.room_actions().size()==3 and ex.room_actions()[0].id=="recover","fixed recover "+kind)
		ck(ex.choose_room_action("recover").success and ex.run().party[0].currentHp==450 and ex.run().party[1].currentHp==350,"actual camp recovery "+kind)
	g=expedition();ex=g.extraction;ex._prepare_room_actions("hospital");var action:Dictionary=ex.run().roomActions[2];var expected:int=action.effect.items.size()
	ck(ex.choose_room_action(action.id).success,"supply action commits");var box:Dictionary=ex.run().containers.back();var uids:Array=box.items.map(func(i):return i.uid)
	ck(uids.size()==expected and box.items.all(func(i):return not i.revealed),"new supplies require search")
	for uid in uids:ck(ex.reveal_next(box.id).success and ex.take_item(box.id,uid).success,"real search and take")
	ck(not ex.choose_room_action(action.id).success and not ex.take_item(box.id,uids[0]).success,"no repeated grants")
	ex.run().phase="boss_exit";ck(ex.extract().success,"actual extraction")
	var stored:Array=ex.state().stash.map(func(i):return i.uid);ck(uids.all(func(uid):return stored.count(uid)==1),"UIDs reach warehouse exactly once")
	g.state=g._normalize(JSON.parse_string(JSON.stringify(g.state)));ck(ex.state().stash.map(func(i):return i.uid)==stored,"warehouse reload stable")
	print("RECOVERED EVENTS V278: %d checks, %d failures"%[checks,failures]);quit(0 if failures==0 else 1)
