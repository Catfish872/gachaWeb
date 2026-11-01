extends "res://tests/test_mobile_polish_v260.gd"
func run()->void:
	if DisplayServer.get_name()=="headless":quit(2);return
	DirAccess.make_dir_recursive_absolute(OUT)
	app=load("res://main.tscn").instantiate();root.add_child(app);await frames(10);app.set_process(false)
	root.size=Vector2i(2048,945);await frames(8);reset_game()
	var x=app.model.extraction;check(x.start_run(0).success,"new loot binding run")
	var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/extraction/v260/loot_expansion/manifest.json"))
	var bg:=ColorRect.new();bg.color=Color("101827");bg.position=Vector2(10,10);bg.size=app.size-Vector2(20,20);app.add_child(bg)
	var grid:=GridContainer.new();grid.columns=6;grid.scale=app.size/Vector2(2048,945);grid.position=Vector2(12,12);grid.add_theme_constant_override("h_separation",8);grid.add_theme_constant_override("v_separation",8);app.add_child(grid)
	for entry in manifest.items:
		var def:Dictionary=x.data.items[entry.id];var texture=load(str(def.icon));check(texture!=null,"new icon binds "+str(entry.id))
		var item:Dictionary=x._make_item(str(entry.id));check(x._place([],item,Vector2i(6,10)),"real dimensions fit bag "+str(entry.id))
		var card:=PanelContainer.new();card.custom_minimum_size=Vector2(326,140);grid.add_child(card)
		var style:=StyleBoxFlat.new();style.bg_color=Color("151f2d");style.border_color=[Color.GRAY,Color.SEA_GREEN,Color.CORNFLOWER_BLUE,Color.MEDIUM_PURPLE,Color.GOLD,Color.INDIAN_RED][int(entry.rarity)];style.set_border_width_all(2);style.content_margin_left=8;style.content_margin_right=8;card.add_theme_stylebox_override("panel",style)
		var row:=HBoxContainer.new();card.add_child(row)
		var icon:=TextureRect.new();icon.texture=texture;icon.custom_minimum_size=Vector2(138,132);icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;row.add_child(icon)
		var label:=Label.new();label.text=str(entry.name)+"\n"+str(entry.size[0])+" × "+str(entry.size[1])+" 格\n"+str(entry.value)+" 金币";label.add_theme_font_size_override("font_size",18);row.add_child(label)
	await frames(10);await capture("loot-expansion-catalog")
	app.queue_free();await frames();print("LOOT EXPANSION GL V260: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
