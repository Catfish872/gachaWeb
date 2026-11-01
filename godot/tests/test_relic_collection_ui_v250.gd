extends SceneTree
var app
var checks:=0
var failures:Array=[]
func _initialize()->void:call_deferred("run")
func ck(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);printerr("FAIL ",label)
func frames(n:int=8)->void:
	for i in n:await process_frame
func fits(control:Control,label:String)->void:
	ck(control!=null,label+" exists")
	if control==null:return
	var clip:=Rect2(Vector2.ZERO,app.size);var p=control.get_parent()
	while p!=null:
		if p is Control and (p.clip_contents or p is ScrollContainer):clip=clip.intersection(p.get_global_rect())
		p=p.get_parent()
	ck(clip.encloses(control.get_global_rect()),label+" fully visible")
	if control is BaseButton:ck(control.size.y>=44,label+" touch size")
func tap(control:Control)->void:
	if control==null:ck(false,"tap target exists");return
	fits(control,"tap "+str(control.name))
	var point:=control.get_global_rect().get_center()
	for down in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;event.position=point;event.global_position=point
		root.push_input(event,true);await frames(2)
	await frames()
func capture(label:String)->void:
	if DisplayServer.get_name()=="headless":return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://validation/relic-ui-v250")
	root.get_texture().get_image().save_png("res://validation/relic-ui-v250/"+label+".png")
func run()->void:
	if "--require-gl" in OS.get_cmdline_user_args() and DisplayServer.get_name()=="headless":printerr("FAIL real GL display required");quit(1);return
	root.size=Vector2i(960,540)
	app=load("res://main.tscn").instantiate();root.add_child(app);await frames(15);app.set_process(false)
	app.model=load("res://scripts/game_model.gd").new("")
	var unowned:String=""
	for id in app.model.catalog.CharacterData:
		if not app.model.state.ownedCharacters.has(id):unowned=str(id);break
	for resolution in [Vector2i(960,540),Vector2i(1170,540),Vector2i(2048,945)]:
		root.size=resolution;await frames()
		for character in ["ember",unowned]:
			app.selected_character=character;app.growth_panel="gear";app.navigate("growth");await frames()
			fits(app.main_body.find_child("CharacterRecommendedRelics",true,false),"codex recommendation entry")
			var prior:Dictionary=app.model.state.duplicate(true)
			await tap(app.main_body.find_child("CharacterRecommendedRelics",true,false))
			var entries:Array=app.model.relic_set_recommendations(character)
			for entry in entries:
				ck(app.overlay.find_child("CharacterRecommendedSet_"+str(entry.setId),true,false)!=null,"actual catalog recommendation "+str(entry.setId))
				ck(app.overlay.find_child("CharacterSetReason_"+str(entry.setId),true,false).text==entry.reason,"exact mechanism reason from data")
			ck((app.overlay.find_child("CharacterRecommendationsAuto",true,false)!=null)==app.model.state.ownedCharacters.has(character),"equip available only to owned characters")
			fits(app.overlay.find_child("CharacterRecommendationsClose",true,false),"recommendation close footer")
			fits(app.overlay.find_child("CharacterRecommendationsAbyss",true,false),"recommendation farming footer")
			await capture("recommendations-"+character+"-"+str(resolution.x))
			await tap(app.overlay.find_child("CharacterRecommendationsClose",true,false))
			ck(app.model.state==prior,"reading owned or unowned recommendations is pure")
	# An unowned character may plan farming; this grants no ownership or equipment.
	app.selected_character=unowned;app._render_screen();await frames()
	await tap(app.main_body.find_child("CharacterRecommendedRelics",true,false))
	var chosen:Dictionary=app.model.relic_set_recommendations(unowned)[0]
	var wallet:Dictionary=app.model.state.resources.duplicate(true)
	if app.model.state.abyss.meta.selectedRelicSetId!=chosen.setId:
		var button=app.overlay.find_child("CharacterSetTarget_"+str(chosen.setId),true,false)
		var scroll:ScrollContainer=app.overlay.find_child("CharacterRelicRecommendations",true,false).get_parent()
		scroll.ensure_control_visible(button);await frames();await tap(button)
	ck(app.model.state.abyss.meta.selectedRelicSetId==chosen.setId and not app.model.state.ownedCharacters.has(unowned) and app.model.state.resources==wallet,"unowned target selection preserves ownership and wallet")
	app._clear_overlay()
	# Full save-limit inventory: all UIDs stay addressable, with bounded controls.
	root.size=Vector2i(960,540);await frames()
	app.model=load("res://scripts/game_model.gd").new("")
	var template:Dictionary=app.model.generate_relic(5,"helmet","star_watch")
	for i in 100000:
		var relic:Dictionary=template.duplicate(true);relic.uid="large_ui_"+str(i);relic.rarity=3 if i%2==0 else 5;app.model.state.relics.append(relic)
	app.relic_filter="全部";app.relic_slot_filter="全部";app.selected_relic="large_ui_0"
	var start:int=Time.get_ticks_msec();app.navigate("relics");var elapsed:int=Time.get_ticks_msec()-start;await frames()
	print("100K WORKSHOP BUILD MS: ",elapsed)
	ck(app.main_body.find_children("RelicCard_*","PanelContainer",true,false).size()==60,"100k creates only60 item cards")
	fits(app.main_body.find_child("RelicAutoEquip",true,false),"100k auto equip remains accessible")
	fits(app.main_body.find_child("RelicNextPage",true,false),"page next fixed action")
	var page:SpinBox=app.main_body.find_child("RelicPageNumber",true,false)
	ck(page.max_value==1667,"all100000 entries represented by page count")
	page.value=page.max_value;await frames()
	ck(app.selected_relic=="large_ui_0","page switching preserves selected UID")
	var sc:ScrollContainer=app.main_body.find_child("RelicRosterScroll",true,false)
	sc.scroll_vertical=999999;await frames();var offset:int=sc.scroll_vertical
	await tap(app.main_body.find_child("RelicCard_large_ui_99999",true,false))
	ck(app.selected_relic=="large_ui_99999","last item at100k is really tappable")
	ck(abs(app.main_body.find_child("RelicRosterScroll",true,false).scroll_vertical-offset)<=1,"selecting last UID retains page scroll")
	await capture("inventory-100000-last")
	await tap(app.main_body.find_child("RelicPreviousPage",true,false))
	await tap(app.main_body.find_child("RelicNextPage",true,false))
	ck(app.selected_relic=="large_ui_99999" and abs(app.main_body.find_child("RelicRosterScroll",true,false).scroll_vertical-offset)<=1,"returning to last page retains UID and scroll")
	app.relic_filter="五星";app._render_screen();await frames()
	page=app.main_body.find_child("RelicPageNumber",true,false)
	ck(page.max_value==834 and app.selected_relic=="large_ui_99999","filter preserves matching selected UID and all50000 items")
	ck(app.main_body.find_children("RelicCard_*","PanelContainer",true,false).size()==60,"filtered controls stay bounded")
	for resolution in [Vector2i(1170,540),Vector2i(2048,945)]:
		root.size=resolution;await frames()
		fits(app.main_body.find_child("RelicNextPage",true,false),"large inventory resized page action")
		fits(app.main_body.find_child("RelicAutoEquip",true,false),"large inventory resized auto action")
	app._clear_overlay();app.queue_free();await frames();await create_timer(.35).timeout
	print("RELIC COLLECTION UI V250: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
