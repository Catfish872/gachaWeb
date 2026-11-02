extends "res://tests/test_lantern_journey_ui_v270.gd"
const ExtractionView=preload("res://scripts/ui/extraction_view.gd")
const OUT272="res://validation/v272-focused/"
func capture(label:String)->void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT272+label+".png")
func verify_headers()->void:
	var badges=app.find_children("RewardOwnedCount","Label",true,false)
	ck(badges.size()==3,"three actual ownership badges")
	var counts:Array=[]
	for badge in badges:counts.append(int(badge.get_meta("owned_count",-1)))
	ck(counts.count(2)==1 and counts.count(0)==2,"owned two layers and two unowned choices")
	var icons=app.find_children("RewardChoiceIcon","TextureRect",true,false)
	ck(icons.size()==3,"three reward art icons")
	for icon in icons:ck(icon.texture!=null,"actual reward texture bound")
func choices()->Array:
	var result:Array=[]
	for id in ["selin_burn_duration_white","selin_burn_energy_blue","selin_burn_amp_gold"]:
		var reward:Dictionary=app._abyss_reward(id).duplicate(true);reward.choiceId=id;reward.instanceId="fixture_"+id;result.append(reward)
	return result
func run()->void:
	if DisplayServer.get_name()=="headless":quit(2);return
	DirAccess.make_dir_recursive_absolute(OUT272)
	app=load("res://main.tscn").instantiate();root.add_child(app);await frames(12);app.set_process(false)
	for resolution in [Vector2i(2048,945),Vector2i(960,540)]:
		root.size=resolution;await frames(8);var label:=str(resolution.x)
		fresh();app.model.state.stageProgress.trial_selin={"cleared":true};app.selected_pool="limited_selin";app.navigate("summon");await frames(10)
		for name in ["SummonPull_1","SummonPull_10","SelinTrial"]:fits(app.find_child(name,true,false),name+" fully in viewport after trial")
		await capture(label+"-summon-after-trial")
		fresh();app.model.extraction.start_run();app.navigate("extraction");await frames(8)
		ExtractionView._confirm_abandon(app);await frames(8)
		var summary=app.find_child("ExtractionAbandonSummary",true,false);fits(summary,"abandon copy")
		ck(summary.size.x>250,"abandon copy has natural line width")
		fits(app.find_child("ExtractionAbandonCancel",true,false),"cancel fixed");fits(app.find_child("ExtractionAbandonConfirm",true,false),"confirm fixed")
		await capture(label+"-abandon")
		await tap(app.find_child("ExtractionAbandonCancel",true,false));ck(app.model.extraction.active(),"cancel preserves run")
		var options:=choices();app.model.extraction.run().pendingChoices=options;app.model.extraction.run().blessings=[options[0].duplicate(true),options[0].duplicate(true)];app.model.extraction.run().blessings[1].instanceId="second_fixture"
		app._render_screen();await frames(8);verify_headers();await capture(label+"-extraction-blessings")
		fresh();app.model.state.abyss.rogue.pendingChoices=choices();app.model.state.abyss.rogue.selectedRewards=[choices()[0],choices()[0]];app.abyss_panel="expedition";app.navigate("abyss");await frames(8);verify_headers();await capture(label+"-abyss-blessings")
		fresh();var ex=app.model.extraction;ex.start_run();ex.run().environmentOrder=["lantern","forest","ruins"];ex._generate_map();ex.run().room=ex.run().map.rooms[7].duplicate(true);ex.run().map.currentRoomId=ex.run().room.id
		ex._generate_encounter("elite");var prepared:Dictionary=ex.prepare_battle();app._start_battle(prepared.config);await frames(8)
		ck(app._background_path()==ex.run().room.background,"battle displays exact entered room scenery");await capture(label+"-room-battle-background")
	app.queue_free();await frames();print("MOBILE FIXES V272: %d checks, %d failures"%[checks,failures]);quit(0 if failures==0 else 1)
