extends SceneTree
var app
var checks:=0
var failures:Array=[]
func _initialize()->void:call_deferred("run")
func ck(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func frames(n:int=8)->void:
	for i in n:await process_frame
func tap(control:Control)->void:
	var at:=control.get_global_rect().get_center()
	var down:=InputEventMouseButton.new();down.button_index=MOUSE_BUTTON_LEFT;down.pressed=true;down.position=at;down.global_position=at
	root.push_input(down,true);await process_frame
	var up:=InputEventMouseButton.new();up.button_index=MOUSE_BUTTON_LEFT;up.pressed=false;up.position=at;up.global_position=at
	root.push_input(up,true);await frames()
func descendants(node:Node)->Array:
	var all:Array=[]
	for child in node.get_children():all.append(child);all.append_array(descendants(child))
	return all
func run()->void:
	root.size=Vector2i(2340,1080)
	app=load("res://main.tscn").instantiate();root.add_child(app);await frames(15)
	app.set_process(false)
	app.model=load("res://scripts/game_model.gd").new("")
	var ids:Array=app.model.catalog.CharacterData.keys()
	var target:String=ids.back()
	app.model.state.ownedCharacters[target]=app.model.default_character()
	for resolution in [Vector2i(2340,1080),Vector2i(1920,1080)]:
		root.size=resolution;await frames()
		app.navigate("growth");await frames()
		var scroll:ScrollContainer=app.main_body.find_child("GrowthRosterScroll",true,false)
		ck(scroll!=null,"stable named character list")
		scroll.scroll_vertical=99999;await frames()
		var remembered:int=scroll.scroll_vertical
		ck(remembered>0,"fixture really scrolls to lower characters")
		var button:Button=app.main_body.find_child("GrowthSelect_"+target,true,false)
		ck(button!=null and scroll.get_global_rect().has_point(button.get_global_rect().get_center()),"lower character actually visible for input")
		await tap(button)
		ck(app.selected_character==target,"real click selects lower character")
		scroll=app.main_body.find_child("GrowthRosterScroll",true,false)
		ck(abs(scroll.scroll_vertical-remembered)<=1,"selection preserves scroll instead of jumping")
		for node in descendants(app.main_body):
			if node is Button and node.text=="技能":await tap(node);break
		scroll=app.main_body.find_child("GrowthRosterScroll",true,false)
		ck(abs(scroll.scroll_vertical-remembered)<=1,"detail tab preserves roster scroll")
		app.navigate("home");await frames();app.navigate("growth");await frames()
		scroll=app.main_body.find_child("GrowthRosterScroll",true,false)
		ck(abs(scroll.scroll_vertical-remembered)<=1,"return to character page preserves roster scroll")
		ck(app.main_body.find_child("CharacterOwned_*",true,false)!=null,"owned character has dedicated state UI")
		ck(app.main_body.find_child("CharacterLocked_*",true,false)!=null,"unowned character has lock state UI")
		ck(app.main_body.find_child("PortraitEnvironment*",true,false)!=null,"character uses environmental presentation")
		app.navigate("party");await frames()
		scroll=app.main_body.find_child("PartyRosterScroll",true,false)
		scroll.scroll_vertical=99999;await frames();remembered=scroll.scroll_vertical
		var card:Control=app.main_body.find_child("PartyCard_"+target,true,false)
		if scroll.get_global_rect().has_point(card.get_global_rect().get_center()):
			await tap(card)
			scroll=app.main_body.find_child("PartyRosterScroll",true,false)
			ck(abs(scroll.scroll_vertical-remembered)<=1,"team toggle preserves scrolled roster before=%s after=%s max=%s" % [remembered,scroll.scroll_vertical,scroll.get_v_scroll_bar().max_value-scroll.get_v_scroll_bar().page])
	app.navigate("shop");await frames()
	for entry in app.model.catalog.ShopData.rechargeItems:
		var price:Label=app.main_body.find_child("ShopPrice_"+entry.id,true,false)
		ck(price!=null and price.text==entry.priceDisplay,"original displayed price "+str(entry.id))
		var buy:Button=app.main_body.find_child("ShopPurchase_"+entry.id,true,false)
		ck(buy!=null and buy.text=="购买","concise purchase action")
	var shop_scroll:ScrollContainer=app.main_body.find_child("ShopScroll_recharge",true,false)
	shop_scroll.scroll_vertical=0;await frames()
	var before:Dictionary=app.model.state.resources.duplicate(true)
	await tap(app.main_body.find_child("ShopPurchase_recharge_traveler",true,false))
	ck(app.model.state.resources.gold==before.gold,"displayed RMB purchase never deducts gold")
	ck(app.model.state.resources.diamonds==before.diamonds+60,"purchase directly grants original reward")
	ck(app.overlay.get_child_count()==0,"no payment or defensive confirmation modal")
	app.queue_free();await process_frame;await create_timer(0.3).timeout
	print("CHARACTER NAVIGATION: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
