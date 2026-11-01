extends "res://tests/test_rogue_reward_gain.gd"

const GainV260=preload("res://scripts/ui/rogue_reward_gain.gd")
const RewardRarity=preload("res://scripts/ui/reward_rarity.gd")
const OUT="res://validation/mobile-polish-v260/"

func capture(label:String)->void:
	if DisplayServer.get_name()=="headless":return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT+label+".png")

func touch_at(point:Vector2)->void:
	for pressed in [true,false]:
		var event:=InputEventScreenTouch.new();event.index=0;event.position=point;event.pressed=pressed
		root.push_input(event,true);await frames(2)
	await frames(3)

func swipe(a:Vector2,b:Vector2)->void:
	var down:=InputEventScreenTouch.new();down.index=0;down.position=a;down.pressed=true;root.push_input(down,true);await frames(2)
	var previous:=a
	for i in range(1,7):
		var drag:=InputEventScreenDrag.new();drag.index=0;drag.position=a.lerp(b,float(i)/6.0);drag.relative=drag.position-previous
		root.push_input(drag,true);previous=drag.position;await frames()
	var up:=InputEventScreenTouch.new();up.index=0;up.position=b;root.push_input(up,true);await frames(4)

func reset_game()->void:
	app._clear_overlay();app.model=load("res://scripts/game_model.gd").new("");app.model.rng.seed=26031
	app.battle=load("res://scripts/battle_model.gd").new(app.model.catalog)
	for id in ["kaldi","ayla"]:
		app.model.state.ownedCharacters[id]=app.model.default_character()
	check(app.model.set_team(["kaldi","ember","ayla"]).success,"three-character presentation fixture")
	app.model.state.resources.gold=1000000
	app.extraction_panel="expedition";app.extraction_auto_pick=false;app.extraction_sound=false;app.extraction_reduced_motion=true

func fit_shell(label:String)->void:
	check(app.shell.size.x<=app.size.x+.5 and app.shell.size.y<=app.size.y+.5,label+" shell fits viewport")

func departure(label:String)->void:
	reset_game()
	var x=app.model.extraction
	for id in ["armor_5","pack_5"]:
		check(x.buy_supply(id).success,"real utility purchase")
		var item:Dictionary=x.state().stash.back()
		check(x.set_utility_slot(str(x.item_def(id).slot),str(item.uid)).success,"real utility equip")
	for i in 3:
		check(x.buy_supply("medkit").success,"real departure medicine purchase")
		check(x.bring_item(str(x.state().stash.back().uid)).success,"real departure carry slot")
	x.state().utility.armor.condition=.35
	app.navigate("extraction");await frames(12)
	fit_shell(label+" damaged shield")
	visible_control(target("ExtractionStart"),"departure start always visible")
	visible_control(target("ExtractionPreparationActions"),"departure fixed preparation links")
	var scroll=target("ExtractionPreparationScroll")
	check(scroll is ScrollContainer,"repair and loadout share a local preparation scroll")
	var repair=target("ExtractionRepair")
	check(repair!=null,"damaged shield exposes actual repair")
	if repair!=null and scroll is ScrollContainer:
		for attempt in 3:
			if app._visible_control_rect(repair).encloses(repair.get_global_rect()):break
			var r:Rect2=app._visible_control_rect(scroll)
			await swipe(r.position+Vector2(r.size.x*.7,r.size.y*.8),r.position+Vector2(r.size.x*.7,r.size.y*.2))
		visible_control(repair,"actual repair remains reachable")
	await capture(label+"-departure-damaged")
	var before_gold:int=app.model.state.resources.gold
	if repair==null:return
	await click_at(repair.get_global_rect().get_center())
	check(is_equal_approx(float(x.state().utility.armor.condition),1.0),"real repair restores shield")
	check(app.model.state.resources.gold<before_gold,"real repair uses quoted gold")
	visible_control(target("ExtractionPreparationActions"),"repair rerender keeps fixed links")

func container_scene(label:String)->void:
	reset_game()
	var x=app.model.extraction
	check(x.start_run(0).success,"scene run starts")
	for option in x.route_options():
		if option.type=="cache":check(x.enter_room(str(option.id)).success,"real reachable cache");break
	x.run().phase="room";x.run().room.type="cache";x.run().room.guardPending=false
	x.run().activeEncounter={};x.run().pendingChoices=[];x.run().roomActions=[];x.run().containers=[]
	for i in 4:
		x._container("物资箱 %d"%(i+1),1,0)
		var box:Dictionary=x.run().containers.back();box.sceneX=.5;box.sceneY=.68
	app.navigate("extraction");await frames(10)
	var scene=target("ExtractionRoomScene")
	check(scene!=null,"actual room canvas exists")
	if scene==null:return
	var boxes:Array=x.containers().duplicate(true)
	for i in boxes.size():
		for j in range(i+1,boxes.size()):
			check(not scene.container_visual_rect(boxes[i]).intersects(scene.container_visual_rect(boxes[j])),"full box sprite label and badge rectangles separated")
	fit_shell(label+" containers")
	visible_control(target("ExtractionPersistentActions"),"fixed room action bar")
	await capture(label+"-containers-left")
	for box in boxes:
		var rect:Rect2=scene.container_visual_rect(box)
		for attempt in 4:
			if Rect2(Vector2.ZERO,scene.size).encloses(rect):break
			var dx:float=clampf(scene.size.x*.5-rect.get_center().x,-scene.size.x*.35,scene.size.x*.35)
			await swipe(scene.global_position+scene.size*.5,scene.global_position+scene.size*.5+Vector2(dx,0))
			rect=scene.container_visual_rect(box)
		check(Rect2(Vector2.ZERO,scene.size).encloses(rect),"every full container reachable by room pan")
		var before:Array=x.containers().duplicate(true)
		await click_at(scene.global_position+Vector2(rect.get_center().x,rect.end.y-8))
		check(target("ExtractionContainer_"+str(box.id))!=null,"visible name opens exact container")
		var close_button=target("ExtractionCloseContainer")
		if close_button==null:break
		await click_at(close_button.get_global_rect().get_center())
		check(x.containers().size()==before.size(),"closing preserves containers")
		scene=target("ExtractionRoomScene")
		if scene==null:break
	if scene!=null:await capture(label+"-containers-right")

func shop_and_gain(label:String)->void:
	prepare("shop");app.model.state.abyss.rogue.temporaryCurrency=10000
	var old_reward:Dictionary={"id":"common_static_blue","name":"静电传导","description":"全队造成直接伤害后，有25%概率使目标感电2回合。感电期间每次行动有35%概率跳过，重复施加只延长持续，首领同样生效。","rarity":"blue","effects":{"shockChance":.25},"choiceId":"old-choice"}
	var raw_before:Dictionary=old_reward.duplicate(true)
	var presented:Dictionary=app._present_abyss_reward(old_reward)
	check(old_reward==raw_before and presented.effects==old_reward.effects and presented.choiceId==old_reward.choiceId,"legacy text cleanup leaves reward mechanics and choice untouched")
	check(not "35%" in str(presented.description) and not "首领" in str(presented.description),"legacy electroshock blessing has concise display text")
	var stock:Array=[]
	for rarity in ["white","blue","gold"]:
		for reward in app.model._available_abyss_rewards():
			if str(reward.get("rarity","white"))==rarity:
				stock.append({"id":"qa_"+rarity,"kind":"blessing","rewardId":str(reward.id),"sold":false});break
	check(stock.size()==3,"one actual reward per tier")
	app.model.state.abyss.rogue.shopStock=stock
	app._render_screen();await frames(10)
	for item in app.model.abyss_shop_items():
		var card=target("RunShopCard_"+str(item.id));var action=target("RunShop_"+str(item.id))
		check(card!=null and card.get_meta("reward_rarity","")==str(item.rarity),"shop uses actual model rarity")
		if card==null or action==null:continue
		check(card.find_child("RewardRarityLabel",true,false)!=null,"shop rarity has textual badge")
		check(str(RewardRarity.tier(str(item.rarity)).label) in action.text,"purchase action repeats compact tier")
	fit_shell(label+" shop")
	visible_control(target("RunShopLeave"),"shop leave fixed")
	await capture(label+"-shop-three-rarities")
	var buy=target("RunShop_qa_white")
	check(buy!=null,"white actual shop action exists")
	if buy==null:return
	await reveal_shop_action(buy);await click_at(buy.get_global_rect().get_center())
	var card=target("RogueRewardGain")
	check(card!=null,"real purchase creates reward feedback")
	if card==null:return
	var before:Dictionary=app.model.state.duplicate(true)
	var scroll=target("AbyssShopScroll");var old_scroll:int=scroll.scroll_vertical
	var presses:Array=[]
	var spy:=Button.new();spy.name="QABehindGain";spy.position=Vector2(8,app.size.y-52);spy.size=Vector2(70,44);spy.z_index=79
	app.add_child(spy);spy.pressed.connect(func():presses.append(true))
	await capture(label+"-blessing-gain")
	await touch_at(spy.get_global_rect().get_center())
	check(target("RogueRewardGain")==null,"touch outside card dismisses")
	check(presses.is_empty() and app.model.state==before,"dismiss does not trigger underlying action or alter assets")
	check(scroll.scroll_vertical==old_scroll,"dismiss does not scroll underneath")
	spy.queue_free();await frames()
	var reward:Dictionary=app.model.state.abyss.rogue.selectedRewards.back()
	GainV260.show_gain(app,reward,1);await frames(3)
	await click_at(Vector2(app.size.x-12,app.size.y-12))
	check(target("RogueRewardGain")==null and app.model.state==before,"mouse blank-area dismiss is equally safe")

func themed_scenes()->void:
	reset_game();var x=app.model.extraction;check(x.start_run(0).success,"themed scene run")
	if not x.run().has("environmentOrder"):check(false,"new run persists environment order");return
	for act in range(1,4):
		x.run().act=act;x._generate_map()
		var theme:=str(x.run().map.theme)
		for depth in [0,2]:
			for room in x.run().map.rooms:
				if int(room.get("depth",-1))!=depth:continue
				x.run().room=room.duplicate(true);x.run().room.type="cache";x.run().room.guardPending=false;x.run().phase="room"
				x.run().map.currentRoomId=room.id;x.run().containers=[];x.run().roomActions=[];x.run().activeEncounter={};x.run().pendingChoices=[]
				for kind in x.data.environmentThemes[theme].containers:
					var def:Dictionary=x.data.environmentContainers[kind]
					x._container(str(def.name),1,0)
					x.run().containers.back().kind=kind;x.run().containers.back().sprite=def.sprite
					x.run().containers.back().sceneX=.25+.35*(x.run().containers.size()-1)
					check(load(str(def.sprite))!=null,"actual new container atlas loads")
				x.run().bag=[]
				for id in x.data.items:
					if not str(id).begins_with(theme+"_") or not x.data.items[id].has("variantOf"):continue
					var item:Dictionary=x._make_item(str(id));item.revealed=true
					check(x._place(x.run().bag,item,x.dimensions("bag")),"new theme loot placed in actual bag")
					check(load(str(x.data.items[id].icon))!=null,"actual new loot atlas loads")
				app.navigate("extraction");await frames(8)
				var scene=target("ExtractionRoomScene")
				check(scene!=null and scene.backdrop!=null,"new depth backdrop loads")
				await capture("theme-"+theme+"-depth-"+str(depth));break

func run()->void:
	if DisplayServer.get_name()=="headless":push_error("V260 visual fixture requires actual GL");quit(2);return
	DirAccess.make_dir_recursive_absolute(OUT)
	app=load("res://main.tscn").instantiate();root.add_child(app);await frames(12);app.set_process(false)
	for resolution in ([] if "--art-only" in OS.get_cmdline_user_args() else [Vector2i(2048,945),Vector2i(1280,720),Vector2i(960,540)]):
		root.size=resolution;await frames(12)
		var label:=str(resolution.x)+"x"+str(resolution.y)
		await departure(label);await container_scene(label);await shop_and_gain(label)
	root.size=Vector2i(2048,945);await frames(10);await themed_scenes()
	app.queue_free();await frames();await create_timer(.2).timeout
	print("MOBILE POLISH V260: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
