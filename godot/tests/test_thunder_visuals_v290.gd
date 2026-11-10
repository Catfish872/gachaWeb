extends "res://tests/test_redesign_layout.gd"
const Avatars=preload("res://scripts/ui/character_avatar.gd")
const OUT="res://validation/v290-focused/"

func capture(label: String) -> void:
	if DisplayServer.get_name()=="headless":return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT+label+".png")

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	app=load("res://main.tscn").instantiate();root.add_child(app);await frames();app.set_process(false)
	app.model=load("res://scripts/game_model.gd").new("")
	app.battle=load("res://scripts/battle_model.gd").new(app.model.catalog)
	for id in ["raisa","vika","eve"]:
		check(app.model.catalog.CharacterData.has(id),"catalog character "+id)
		check(Avatars.get_texture(id,"face")!=null,"curated face crop "+id)
		check(Avatars.get_texture(id,"bust")!=null,"full-source bust "+id)
		app.model.state.ownedCharacters[id]=app.model.default_character()
	app.model.state.team=["raisa","vika","eve"]
	app.preferred_battle_auto=false
	var config:Dictionary=app.model.prepare_stage("ch1_1").config
	for resolution in [Vector2i(1440,810),Vector2i(960,540)]:
		root.size=resolution;await frames(6)
		app._start_battle(config);app.battle_auto=false
		var raisa:Dictionary=app.battle.state.allies[0]
		app.battle._queue=[raisa];app.battle._cursor=0;app.battle.state.phase="player_turn"
		app._render_battle();await frames(5)
		var normal=app.unit_cards[raisa.uid].find_child("CharacterPortraitTexture",true,false)
		check(normal.texture.resource_path.ends_with("/raisa.png"),"normal battle source")
		app.battle._enter_thunder_armor(raisa)
		app._render_battle();await frames(5)
		var idle=app.unit_cards[raisa.uid].find_child("CharacterPortraitTexture",true,false)
		check(idle.texture.resource_path.ends_with("/raisa_armor.png"),"armor battle source")
		var badge=app.unit_cards[raisa.uid].find_child("ThunderArmorBadge",true,false)
		check(badge!=null and badge.text.contains("4"),"remaining duration visible")
		for stage in range(3):
			raisa.thunderArmor.unlockStage=stage;app._render_battle();await frames(4)
			var skill=app.main_body.find_child("BattleSkill_raisa_armor_skill",true,false)
			var ult=app.main_body.find_child("BattleSkill_raisa_armor_ult",true,false)
			check(skill.disabled==(stage<1),"armor skill lock "+str(stage))
			check(ult.disabled==(stage<2),"armor ultimate lock "+str(stage))
			check(not skill.get_meta("armor_lock_reason","").is_empty() if stage<1 else skill.get_meta("armor_lock_reason","").is_empty(),"visible prerequisite state")
			fits(app.main_body.find_child("BattleArena",true,false),"thunder arena "+str(resolution))
			fits(app.main_body.find_child("BattleActions",true,false),"thunder controls "+str(resolution))
			for control in app.main_body.find_children("BattleSkill_*","Button",true,false):fits(control,"thunder skill "+control.name)
			await capture("armor-lock-"+str(stage)+"-"+str(resolution.x))
		for action in ["raisa_armor_normal","raisa_armor_skill","raisa_armor_ult"]:
			app._show_battle_action_art({"actor":raisa.uid,"skill_id":action,"actionImage":app.model.catalog.SkillData[action].actionImage})
			await frames(1)
			var effect=app.unit_cards[raisa.uid].find_child("ThunderActionIllustration",true,false)
			check(effect!=null and effect.get_meta("action_image").ends_with(action+".png"),"distinct action "+action)
			check(not app.unit_cards[raisa.uid].find_child("CharacterPortraitTexture",true,false).visible,"idle hidden during action")
			await capture(action+"-"+str(resolution.x))
			await create_timer(.8).timeout
			check(app.unit_cards[raisa.uid].find_child("CharacterPortraitTexture",true,false).visible,"idle restored after action")
		app._show_unit_details(raisa);await frames(3)
		check(app.find_child("ThunderArmorDetails",true,false)!=null,"armor inspection")
		app._clear_overlay()
		app.battle._leave_thunder_armor(raisa);app._render_battle();await frames(3)
		check(app.unit_cards[raisa.uid].find_child("CharacterPortraitTexture",true,false).texture.resource_path.ends_with("/raisa.png"),"normal restored after expiry")
		app.battle_settled=true;app.battle.state={};app.navigate("growth");app.selected_character="raisa";app._render_screen();await frames(5)
		check(app.current_screen=="growth" and app.model.catalog.CharacterData.raisa.image.ends_with("/raisa.png"),"outside battle catalog remains normal")
		await capture("raisa-growth-"+str(resolution.x))
	for id in ["raisa","vika","eve"]:
		app.selected_pool="limited_"+id;app.navigate("summon");await frames(4)
		check(app.main_body.find_child("ThunderTrial_"+id,true,false)!=null,"solo trial entry "+id)
		check(app.main_body.find_child("ThunderTrial_trio",true,false)!=null,"joint trial entry "+id)
		var reward=app.main_body.find_child("ThunderTrialReward",true,false)
		check(reward!=null and reward.text.contains("160"),"solo trial reward "+id)
	check(app._character_skill_ids(app.model.catalog.CharacterData.raisa).size()==6,"all six Raisa skills available in character pages")
	var scorer=load("res://scripts/relic_optimizer.gd").new(app.model,"eve")
	var snapshot:Dictionary=scorer.evaluate_loadout([])
	var box=app._modal("雷队评价核对",720,480)
	load("res://scripts/ui/relic_loadout_view.gd")._thunder_breakdown(app,box,{"evaluationMode":"steady"},snapshot,snapshot)
	await frames(4)
	check(box.find_child("RelicLoadoutRecoveryBreakdown",true,false)!=null,"Eve HP breakdown separate")
	check(box.find_child("RelicLoadoutTeamDamageBreakdown",true,false)!=null,"team damage separate")
	for key in ["activeHealing","shieldSupply","passiveHealing","regeneration"]:check(box.find_child("RelicBreakdown_"+key,true,false)!=null,"recovery component "+key)
	check(box.find_child("RelicLoadoutThunderCoverage",true,false)!=null,"coverage assumptions visible")
	scorer=null
	app._clear_overlay()
	app.queue_free();await frames(3);await create_timer(.4).timeout
	print("THUNDER VISUALS V290: %d checks, %d failures"%[checks,failures.size()]);quit(0 if failures.is_empty() else 1)
