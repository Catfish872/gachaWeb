extends SceneTree
const Game = preload("res://scripts/game_model.gd")
const Battle = preload("res://scripts/battle_model.gd")
var checks := 0
var failures := 0
func ck(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL: ",label)
func _init() -> void:
	var g = Game.new("")
	var x = g.extraction
	ck(g.valid_save(g.state),"default valid v6")
	for seed_value in range(64):
		g.rng.seed=seed_value
		ck(x.start_run().success,"map start")
		ck(x.map_state().rooms.size()==19,"19 rooms")
		ck(g.valid_save(g.state),"connected valid map")
		var mapped:Dictionary=x.map_state()
		var positions:Dictionary={}
		for point in mapped.rooms: positions[point.id]=Vector2(point.x,point.y)
		for a in range(mapped.rooms.size()):
			for b in range(a+1,mapped.rooms.size()): ck(positions[mapped.rooms[a].id].distance_to(positions[mapped.rooms[b].id])>0.12,"nodes separated")
		for edge in mapped.edges:
			var start:Vector2=positions[edge[0]];var end:Vector2=positions[edge[1]]
			ck(start.distance_to(end)<0.335,"only local passages")
			for id in positions:
				if id in edge:continue
				ck(positions[id].distance_to(Geometry2D.get_closest_point_to_segment(positions[id],start,end))>0.08,"passage misses other rooms")

		ck(x.retreat().success,"retreat")
	# One-time migration preserves both liquid and physical legacy assets.
	var old = g.state.duplicate(true)
	old.version=5
	old.resources.gold=100
	old.extraction.credits=321
	old.extraction.stash=[{"uid":"legacy","itemId":"medkit","x":0,"y":0,"rotated":false,"revealed":true}]
	g.state=g._normalize(old)
	ck(g.state.version==7 and g.state.resources.gold==421 and x.state().credits==0,"wallet migration")
	var legacy_value:int=x.item_value(x.state().stash[0])
	ck(legacy_value==int(x.item_def("medkit").legacyValue),"old physical value")
	g.state=g._normalize(g.state)
	ck(g.state.resources.gold==421,"idempotent migration")
	ck(x.sell_items(["legacy","legacy"]).success,"batch unique sale")
	ck(g.state.resources.gold==421+legacy_value,"sale gold")
	ck(not x.sell_items(["legacy"]).success,"sale replay rejected")
	g.state.resources.gold=50000
	ck(x.buy_supply("medkit").success,"buy original gold")
	ck(x.state().credits==0,"no second wallet")
	ck(x.start_run().success,"start growth")
	x.run().phase="room"
	x._prepare_room_actions("rest")
	x.run().party[0].currentHp=0
	ck(x.choose_room_action("recover").success,"active camp revive")
	ck(x.run().party[0].currentHp>0,"revive applied")
	ck(not x.choose_room_action("recover").success,"rest only once")
	var selected_count:=0
	for action in x.room_actions():
		selected_count+=int(action.selected)
		ck(action.selected==(action.id=="recover"),"selected action identity")
	ck(selected_count==1,"only chosen action marked")
	x._prepare_room_actions("shrine")
	ck(x.choose_room_action("insight").success,"shrine choice")
	ck(x.growth_choices().size()==3,"three choices")
	var choice:String=x.growth_choices()[0].choiceId
	ck(not x.advance_room().success,"growth cannot bypass")
	ck(x.choose_growth(choice).success,"choose growth")
	ck(not x.choose_growth(choice).success,"choice replay")
	ck(x.growth_summary().size()==1,"growth summary")
	ck(x.effects().size()>0,"effects connected")
	ck(g.state.abyss.rogue.selectedRewards.is_empty(),"abyss unaffected")
	x._container("fixture",1,0)
	var c=x._find_container(x.containers()[0].id)
	c.items=[x._make_item("medkit")]
	var uid:String=c.items[0].uid
	ck(not x.use_container_item(c.id,uid).success,"hidden use blocked")
	ck(x.reveal_next(c.id).success,"reveal")
	x.run().party[0].currentHp=1
	ck(x.use_container_item(c.id,uid).success,"direct use")
	ck(x.run().party[0].currentHp>1 and c.items.is_empty(),"direct use removes item")
	ck(not x.use_container_item(c.id,uid).success,"direct use replay")
	c.items=[x._make_item("blade")]
	c.items[0].revealed=true
	uid=c.items[0].uid
	ck(x.equip_container_item(c.id,uid).success,"direct equip")
	ck(x.run().equipped.size()==1 and c.items.is_empty(),"equipped not in bag")
	c.items=[x._make_item("vest")]
	c.items[0].revealed=true
	ck(x.equip_container_item(c.id,c.items[0].uid,uid).success,"direct replacement")
	ck(c.items.size()==1 and c.items[0].uid==uid,"old gear remains in box")
	ck(g.valid_save(g.state),"new features save valid")
	var snapshot=g.state.duplicate(true)
	g.state=g._normalize(snapshot)
	ck(g.valid_save(g.state) and x.growth_summary().size()==1,"features survive reload")
	# Failed persistence rolls back gold, physical transfers, and one-off actions.
	var before=g.state.duplicate(true)
	g.save_blocked=true
	ck(not x.choose_growth("stale").success,"stale mutation blocked")
	ck(g.state==before,"stale has no side effects")
	x._prepare_room_actions("rest")
	before=g.state.duplicate(true)
	ck(not x.choose_room_action("recover").success,"room save failure")
	ck(g.state==before,"room rollback")
	g.save_blocked=false
	ck(x.retreat().success,"end before batch")
	g.state.resources.gold=50000
	ck(x.buy_supply("medkit").success,"purchase fixture")
	var owned_uid:String=x.state().stash.back().uid
	before=g.state.duplicate(true)
	g.save_blocked=true
	ck(not x.sell_items([owned_uid]).success,"sale save failure")
	ck(g.state==before,"sale rollback")
	ck(not x.collect_items([owned_uid]).success,"collection save failure")
	ck(g.state==before,"collection rollback")
	g.save_blocked=false
	ck(x.collect_items([owned_uid]).success,"batch collection")
	ck(not x.collect_items([owned_uid]).success,"collection replay")
	# Canonical effects: changing saved UI text/effects cannot manufacture power.
	ck(x.start_run().success,"effects new run")
	x.run().phase="room"
	var canonical:Dictionary=x._growth_definition("common_hp_white").duplicate(true)
	canonical.instanceId="test_maxhp";canonical.pickedAtAct=1
	x.run().blessings=[canonical]
	var party:Array=x.battle_party()
	var base_hp:int=party[0].stats.maxHp
	x._generate_encounter("battle")
	var battle=Battle.new(g.catalog)
	ck(x.start_battle(battle).success,"hp battle")
	ck(battle.state.allies[0].maxHp==int(base_hp*1.1),"maxHp blessing applied once")
	var config:Dictionary=x.prepare_battle().config
	while battle.state.phase not in ["victory","defeat"]:battle.auto_step()
	ck(x.settle_battle(config,battle.state).success,"hp settlement")
	if x.active():
		while not x.growth_choices().is_empty():x.choose_growth(x.growth_choices()[0].choiceId)
		var earned_max:int=x.run().party[0].maxHp
		x.run().blessings=[canonical]
		x._generate_encounter("battle")
		battle=Battle.new(g.catalog);x.start_battle(battle)
		ck(battle.state.allies[0].maxHp==int(base_hp*1.1),"no multiplicative hp replay")
		ck(g.valid_save(g.state),"battle save with growth valid")
	# Every existing blessing is admitted for the matching five-star team and
	# survives canonical effect expansion, not merely the simple stat bonuses.
	g=Game.new("");x=g.extraction
	for id in ["kaldi","ayla","gus"]:g.state.ownedCharacters[id]=g.default_character()
	g.set_team(["kaldi","ayla","gus"]);x.start_run()
	ck(x._growth_pool().size()==26,"all 26 existing blessings available")
	for definition in g.catalog.AbyssData.rogue.rewards:
		var reward:Dictionary=definition.duplicate(true);reward.instanceId="test_"+str(reward.id);reward.pickedAtAct=1
		x.run().blessings=[reward]
		ck(x.effects().size()==reward.effects.size(),"canonical effects "+str(reward.id))
		ck(g.valid_save(g.state),"valid blessing "+str(reward.id))
	var invalid=g.state.duplicate(true)
	invalid.extraction.run.pendingChoices="bad"
	ck(not g.valid_save(invalid),"reject invalid growth state")
	# Real v5 model-produced fixture retains its existing map, encounter token,
	# enemy budget, party, bags and search progress through migration.
	g=Game.new("");x=g.extraction
	var legacy=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/extraction-v5-active.json"))
	ck(g.valid_save(legacy),"actual v5 fixture accepted")
	var old_encounter:Dictionary=legacy.extraction.run.activeEncounter.duplicate(true)
	var old_party:Array=legacy.extraction.run.party.duplicate(true)
	g.state=g._normalize(legacy)
	ck(g.valid_save(g.state),"v5 active migration valid")
	ck(x.run().map.rooms.size()==13,"legacy current map retained")
	ck(x.run().activeEncounter==old_encounter,"legacy encounter budget and seed retained")
	ck(x.run().party==old_party,"legacy party retained")
	ck(g.state.resources.gold==int(legacy.resources.gold)+2456,"legacy credits one-time transfer")
	var gold:int=g.state.resources.gold
	g.state=g._normalize(g.state)
	ck(g.state.resources.gold==gold,"active reloading cannot mint coins")
	var engine=Battle.new(g.catalog)
	ck(x.start_battle(engine).success,"legacy battle resumes")
	while engine.state.phase not in ["victory","defeat"]:engine.auto_step()
	ck(x.settle_battle(old_encounter,engine.state).success,"legacy battle settles")
	ck(g.valid_save(g.state),"legacy after settlement valid")
	# Medicines never disappear when nobody can benefit.
	g=Game.new("");x=g.extraction;x.start_run();x.run().phase="room"
	x._container("med",1,0)
	var box=x._find_container(x.containers()[0].id)
	box.items=[x._make_item("medkit")];box.items[0].revealed=true
	var med_uid:String=box.items[0].uid
	ck(not x.use_container_item(box.id,med_uid).success,"full hp direct use refused")
	ck(box.items.size()==1,"full hp potion preserved")
	ck(x.take_item(box.id,med_uid).success,"pick up medicine")
	ck(not x.use_item(med_uid).success,"full hp bag use refused")
	ck(x.run().bag.size()==1,"bag potion preserved")
	# Real 30/30 occupied bag: all direct actions bypass bag placement.
	g=Game.new("");x=g.extraction;x.start_run();x.run().phase="room"
	var single:=""
	for id in x.data.items:
		var definition:Dictionary=x.item_def(id)
		if definition.width==1 and definition.height==1:single=id;break
	ck(not single.is_empty(),"single cell fixture available")
	for cell in range(30):
		var filler:Dictionary=x._make_item(single);filler.revealed=true
		ck(x._place(x.run().bag,filler,x.dimensions("bag")),"pack cell")
	var bag_before:Array=x.run().bag.duplicate(true)
	ck(not x._place(x.run().bag,x._make_item(single),x.dimensions("bag")),"bag really full")
	x._container("full bag test",1,0)
	box=x._find_container(x.containers()[0].id)
	box.items=[x._make_item("medkit")];box.items[0].revealed=true
	med_uid=box.items[0].uid
	x.run().party[0].currentHp=1
	ck(x.use_container_item(box.id,med_uid).success,"full bag direct med")
	ck(x.run().bag==bag_before,"direct med bag unchanged")
	box.items=[x._make_item("blade")];box.items[0].revealed=true
	var equip_uid:String=box.items[0].uid
	ck(x.equip_container_item(box.id,equip_uid).success,"full bag direct equipment")
	ck(x.run().bag==bag_before,"direct equipment bag unchanged")
	box.items=[x._make_item("vest")];box.items[0].revealed=true
	var replace_in:String=box.items[0].uid
	ck(x.equip_container_item(box.id,replace_in,equip_uid).success,"full bag direct replace")
	ck(box.items.size()==1 and box.items[0].uid==equip_uid and box.items[0].revealed,"same container old equipment preserved")
	ck(x.run().bag==bag_before,"replacement bag unchanged")
	box.items.append(x._make_item("medkit"));box.items.back().revealed=true
	med_uid=box.items.back().uid
	for unit in x.run().party:unit.currentHp=0
	before=g.state.duplicate(true)
	ck(not x.use_container_item(box.id,med_uid).success,"dead party no consumption")
	ck(g.state==before,"dead party assets unchanged")
	for unit in x.run().party:unit.currentHp=1
	x._generate_encounter("battle")
	before=g.state.duplicate(true)
	ck(not x.use_container_item(box.id,med_uid).success,"battle direct use forbidden")
	ck(not x.equip_container_item(box.id,equip_uid).success,"battle direct equip forbidden")
	ck(g.state==before,"battle rejected no mutation")
	# JSON roundtrip is distinct from in-memory Dictionary reload (numbers parse
	# as floats), important for both old maps and new room/growth state.
	ck(g.valid_save(JSON.parse_string(JSON.stringify(g.state))),"v6 JSON roundtrip valid")
	x.run().activeEncounter.seed=2147483000
	ck(g.valid_save(g.state),"high 31-bit encounter seed valid")
	print("EXTRACTION V6: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
