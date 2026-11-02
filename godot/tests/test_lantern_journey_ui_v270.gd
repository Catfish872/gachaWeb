extends SceneTree
const Game=preload("res://scripts/game_model.gd")
const Battle=preload("res://scripts/battle_model.gd")
var app
var checks:=0
var failures:=0
const OUT="res://validation/lantern-ui-v270/"
func _initialize()->void:call_deferred("run")
func ck(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func frames(n:int=6)->void:
	for i in n:await process_frame
func text_under(node:Node)->String:
	var result:=str(node.text) if node is Label or node is Button else ""
	for child in node.get_children():result+="\n"+text_under(child)
	return result
func capture(label:String)->void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT+label+".png")
func fresh()->void:
	app._clear_overlay();app.model=Game.new("");app.model.rng.seed=27031;app.battle=Battle.new(app.model.catalog)
	app.battle_settled=true;app.settlement_error=false;app.current_screen="home";app.battle_config={}
	app.sound_enabled=false;app.music_enabled=false;app.battle_auto=false;app.extraction_reduced_motion=false
func fits(control:Control,label:String)->void:
	ck(control!=null,label+" exists")
	if control==null:return
	var clip:=Rect2(Vector2.ZERO,app.size);var p=control.get_parent()
	while p!=null:
		if p is Control and p.clip_contents:clip=clip.intersection(p.get_global_rect())
		p=p.get_parent()
	ck(clip.encloses(control.get_global_rect()),label+" in mobile viewport")
func tap(control:Control)->void:
	if control==null:ck(false,"tap target exists");return
	var point:=control.get_global_rect().get_center()
	for down in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.position=point;event.global_position=point;event.pressed=down;root.push_input(event,true);await frames(2)
	await frames()
func check_new_resources(value)->void:
	if value is Dictionary:
		for key in value:check_new_resources(value[key])
	elif value is Array:
		for entry in value:check_new_resources(entry)
	elif value is String:
		var path:String=value
		if path.begins_with("assets/"):path="res://"+path
		if path.begins_with("res://assets/content_v270/") or path.begins_with("res://assets/audio/content_v270/"):
			ck(ResourceLoader.exists(path) and load(path)!=null,"new actual asset loads "+path)
func character_and_trial(label:String)->void:
	fresh();app.model.state.ownedCharacters.selin=app.model.default_character();app.selected_character="selin";app.growth_panel="skills";app.navigate("growth");await frames(10)
	ck("瑟琳" in text_under(app.main_body) and "万灯归烬" in text_under(app.main_body),"new roster and skills bound")
	fits(app.find_child("CharacterRecommendedRelics",true,false),"recommended new set")
	await capture(label+"-selin-skills")
	app.growth_panel="gear";app._render_screen();await frames();await capture(label+"-selin-recommended-set")
	app.selected_pool="limited_selin";app.navigate("summon");await frames(8)
	fits(app.find_child("SelinTrial",true,false),"actual trial entry")
	await capture(label+"-limited-banner")
	await tap(app.find_child("SelinTrial",true,false));await frames(8)
	ck(app.battle_config.get("isTrial",false) and app.battle.state.allies[0].id=="selin","real trial entry starts isolated party")
	await capture(label+"-trial-opening")
	# Retain targets for one active action, not a full combat simulation.
	for enemy in app.battle.state.enemies:enemy.currentHp=100000;enemy.maxHp=100000;enemy.stats.maxHp=100000
	ck(app.battle.state.currentActor==app.battle.state.allies[0].uid,"formation gives Selin first friendly action")
	var outcome:Dictionary=app.battle.act("selin_ult",app.battle.state.enemies[0].uid)
	ck(outcome.get("success",false),"actual trial ultimate resolves")
	ck(outcome.get("events",[]).any(func(e):return e.get("detonation",false)),"active action emits real detonation")
	ck(not app.battle.has_status(app.battle.state.allies[0],"ember_oath") and app.battle.has_status(app.battle.state.allies[1],"ember_oath"),"80 percent aura affects teammate not self")
	app._render_battle();await frames();await app._show_combat_events(outcome.get("events",[]));await frames(1)
	await capture(label+"-trial-detonation")
func prepared_summon(label:String)->void:
	fresh();app.selected_pool="limited_selin";app.navigate("summon");await frames()
	var state_before:Dictionary=app.model.state.duplicate(true)
	app.summon_results=[{"charId":"selin","rarity":5,"isNew":true,"shards":0}];app._reveal_summon();await frames(8)
	var sequence=app.summon_sequence
	ck(sequence.stage=="opening","prepared committed-result fixture starts visible animation")
	await capture(label+"-summon-opening")
	var deadline:=Time.get_ticks_msec()+7000
	while is_instance_valid(sequence) and sequence.stage!="result" and Time.get_ticks_msec()<deadline:await process_frame
	ck(sequence.stage=="result" and sequence.stage_history.size()>=6,"animation traverses stages rather than instant result")
	ck(app.model.state==state_before,"presentation fixture performs no RNG roll or reward mutation")
	await capture(label+"-summon-result");app._clear_overlay();await frames()
func story(label:String)->void:
	fresh()
	for stage in app.model.stage_list():
		if stage.id!="ch3_8":app.model.state.stageProgress[stage.id]={"cleared":true}
	var prepared:Dictionary=app.model.prepare_stage("ch3_8");ck(prepared.success,"new chapter boss encounter prepares")
	app._start_battle(prepared.config);await frames(10)
	ck(app.battle.state.enemies.size()==3 and app.battle.state.enemies[0].id=="boss_hedor","actual boss with side lanterns")
	await capture(label+"-chapter3-boss")
	var boss:Dictionary=app.battle.state.enemies[0];boss.currentHp=int(boss.maxHp*.4)
	app.battle._cursor=app.battle._queue.find(boss);app.battle._seek_actor()
	ck(boss.inPhase2,"real Hedor threshold activates phase two")
	app._render_battle();await frames();await capture(label+"-chapter3-phase2")
	# Exercise the existing settlement boundary once, without playing eight stages.
	app.battle.state.phase="victory";await app._finish_battle();await frames()
	ck(not app.settlement_error,"chapter reward settlement commits")
	ck(app.last_reward.get("relic",{}).get("setId","")=="ember_lantern","actual fixed new-set reward")
	fits(app.find_child("SettlementRelic",true,false),"new set settlement reward")
	await capture(label+"-chapter3-reward")
func abyss_new_enemy(label:String)->void:
	fresh()
	app._start_battle({"isAbyss":true,"floor":30,"difficulty":1,"enemies":["furnace_guard"],"background":app.model.abyss_encounter_background(["furnace_guard"],27030),"seed":27030})
	await frames(10)
	ck(app.battle.state.enemies[0].id=="furnace_guard","prepared abyss encounter uses new monster")
	await capture(label+"-abyss-new-enemy")
func expedition(label:String)->void:
	fresh();var ex=app.model.extraction;ck(ex.start_run().success,"three-act sampled-theme expedition starts")
	ex.run().environmentOrder=["lantern","ruins","forest"];ex.run().act=1;ex._generate_map();ex._routes()
	app.navigate("extraction");await frames(8)
	ck(ex.map_state().districts.size()==3,"lantern map has three subdistricts")
	await capture(label+"-lantern-map")
	var room:Dictionary=ex.run().map.rooms[1];ex.run().room=room.duplicate(true);ex.run().room.type="cache";ex.run().room.guardPending=false
	ex.run().map.currentRoomId=room.id;ex.run().phase="room";ex.run().activeEncounter={};ex.run().roomActions=[];ex.run().pendingChoices=[];ex.run().containers=[]
	for kind in ex.data.environmentThemes.lantern.containers.slice(0,3):
		var definition:Dictionary=ex.data.environmentContainers[kind];ex._container(definition.name,0,0)
		var box:Dictionary=ex.run().containers.back();box.kind=kind;box.sprite=definition.sprite;box.sceneX=.2+.3*(ex.run().containers.size()-1);box.sceneY=.65
	ex.run().bag=[];var count:=0
	for id in ex.data.items:
		var definition:Dictionary=ex.data.items[id]
		if definition.get("environmentTheme","")!="lantern" or definition.get("kind","")!="loot":continue
		var item:Dictionary=ex._make_item(id);item.revealed=true
		if ex._place(ex.run().bag,item,ex.dimensions("bag")):count+=1
		if count>=6:break
	ck(count==6,"new theme loot icons use actual bag renderer")
	app._render_screen();await frames(8);await capture(label+"-lantern-room-loot")
func run()->void:
	if DisplayServer.get_name()=="headless":quit(2);return
	DirAccess.make_dir_recursive_absolute(OUT)
	app=load("res://main.tscn").instantiate();root.add_child(app);await frames(12);app.set_process(false)
	if "--delta-ui" in OS.get_cmdline_user_args():
		root.size=Vector2i(960,540);await frames(8);await character_and_trial("delta960")
		app.queue_free();await frames();print("LANTERN DELTA UI: %d checks, %d failures"%[checks,failures]);quit(0 if failures==0 else 1);return
	check_new_resources(app.model.catalog);check_new_resources(app.model.extraction.data)
	if failures>0:print("Missing new resources; visual checks stopped");app.queue_free();quit(1);return
	for resolution in [Vector2i(960,540),Vector2i(2048,945)]:
		root.size=resolution;await frames(8);var label:=str(resolution.x)
		await character_and_trial(label);await prepared_summon(label);await story(label);await expedition(label)
		if resolution.x==960:await abyss_new_enemy(label)
	app.queue_free();await frames();print("LANTERN JOURNEY UI V270: %d checks, %d failures"%[checks,failures]);quit(0 if failures==0 else 1)
