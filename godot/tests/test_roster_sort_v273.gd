extends "res://tests/test_summon_polish_v273.gd"
func run()->void:
	if DisplayServer.get_name()=="headless":quit(2);return
	app=load("res://main.tscn").instantiate();root.add_child(app);await frames(12);app.set_process(false);fresh();root.size=Vector2i(960,540);await frames(8)
	for id in app.model.catalog.CharacterData:app.model.state.ownedCharacters[id]=app.model.default_character()
	app.model.state.team=["shana","zeph"]
	var ordered:Array=app._sorted_character_ids(app.model.state.team)
	ck(ordered.slice(0,2)==["shana","zeph"],"saved formation retains priority and seat order")
	var previous:=99
	for id in ordered.slice(2):
		var rarity:int=app.model.catalog.CharacterData[id].rarity;ck(rarity<=previous,"remaining rarity descending");previous=rarity
	var before:Dictionary=app.model.state.duplicate(true)
	var draft:Array=app._sorted_character_ids(["selin","cinder"])
	ck(draft.slice(0,2)==["selin","cinder"] and app.model.state==before,"draft ordering leaves saved team untouched")
	app.selected_character="selin";app.growth_panel="stats";app.navigate("growth");await frames(8)
	var buttons=app.find_children("GrowthSelect_*","Button",true,false)
	ck(buttons[0].name=="GrowthSelect_shana" and buttons[1].name=="GrowthSelect_zeph","growth uses saved formation")
	var chosen=app.find_child("GrowthSelect_selin",true,false);var gold=app.find_child("GrowthSelect_kaldi",true,false)
	ck(chosen.get_theme_stylebox("normal").border_color!=gold.get_theme_stylebox("normal").border_color,"selection distinct from five-star gold")
	ck(gold.get_theme_stylebox("normal").border_width_left==2,"five-star persistent gold frame")
	await capture("960-growth-rarity-selection")
	app.navigate("party");await frames(8);app.draft_team=["selin","cinder"];app._render_screen();await frames(8)
	var cards=app.find_children("PartyCard_*","PanelContainer",true,false);ck(cards[0].name=="PartyCard_selin" and cards[1].name=="PartyCard_cinder","party uses unsaved draft")
	app.find_child("PartyRosterScroll",true,false).scroll_vertical=180;await frames(4)
	var scroll:int=app.find_child("PartyRosterScroll",true,false).scroll_vertical
	app._toggle_team("selin");await frames(8);ck(app.find_child("PartyRosterScroll",true,false).scroll_vertical==scroll,"remove preserves scroll")
	app._toggle_team("selin");await frames(8);ck(app.find_child("PartyRosterScroll",true,false).scroll_vertical==scroll,"re-add preserves scroll")
	ck(app.model.state.team==["shana","zeph"],"draft edits leave saved formation untouched")
	app.queue_free();await frames();print("ROSTER SORT V273: %d checks, %d failures"%[checks,failures]);quit(0 if failures==0 else 1)
