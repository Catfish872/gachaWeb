extends RefCounted
## Collection guidance comes from the same character and set catalog as combat.
## Inventory-specific choices remain the separate optimizer's responsibility.
static func show_for(app,char_id:String)->void:
	var recommendations:Array=app.model.relic_set_recommendations(char_id)
	var box=app._modal(app._char_name(char_id)+" · 推荐套装",900,620)
	box.name="CharacterRelicRecommendations"
	box.add_theme_constant_override("separation",10)
	var heading=app._hbox(box,10)
	var portrait=app._portrait(heading,char_id,66);portrait.custom_minimum_size.x=54;portrait.size_flags_horizontal=Control.SIZE_FILL
	var identity=app._vbox(heading,4);identity.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	app._label(identity,"契合角色技能的收集方向",17,app.GOLD,true)
	var grid=app._grid(box,1 if app.size.x<760 else mini(2,maxi(1,recommendations.size())))
	for recommendation in recommendations:
		var set_id:String=str(recommendation.get("setId",recommendation.get("id","")))
		var color:Color=Color(str(recommendation.get("color","dfb779")))
		var panel=app._panel(grid,color.darkened(.4),12);panel.name="CharacterRecommendedSet_"+set_id
		var card=app._vbox(panel,8)
		var row=app._hbox(card,10)
		var icon=app._relic_art(row,"helmet",64,set_id);icon.custom_minimum_size.x=64;icon.size_flags_horizontal=Control.SIZE_FILL
		var copy=app._vbox(row,5);copy.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		app._label(copy,str(recommendation.get("name","")),22,color,true)
		var slots=app._hbox(copy,3)
		for slot in app.model.catalog.RelicSlots:
			var art=app._relic_art(slots,str(slot.id),24,set_id);art.custom_minimum_size.x=24;art.size_flags_horizontal=Control.SIZE_FILL
		app._label(card,str(recommendation.get("reason","")),14,app.TEXT,true).name="CharacterSetReason_"+set_id
		app._relic_set_details(card,set_id)
		var info:Dictionary=app.model.abyss_relic_drop_info()
		var locked:bool=bool(info.get("locked",false))
		var selected:bool=str(info.get("targetSetId",""))==set_id
		var choose=app._button(card,"本轮目标已锁定" if locked else ("已设为目标套装" if selected else "设为深渊目标"),func():_target(app,char_id,set_id),not selected and not locked)
		choose.name="CharacterSetTarget_"+set_id;choose.disabled=locked or selected
	var footer=app._hbox(app._modal_footer(box),8)
	app._button(footer,"返回图鉴",app._clear_overlay).name="CharacterRecommendationsClose"
	var gap:=Control.new();gap.size_flags_horizontal=Control.SIZE_EXPAND_FILL;footer.add_child(gap)
	if app.model.state.ownedCharacters.has(char_id):
		var equip=app._button(footer,"自动搭配",func():app._auto_relic_loadout(char_id),true);equip.name="CharacterRecommendationsAuto";app._button_icon(equip,"gear",true)
	app._button(footer,"前往深渊",func():app._clear_overlay();app.navigate("abyss")).name="CharacterRecommendationsAbyss"
	app._restore_character_list(box.get_parent(),"character_relic_recommendations_"+char_id)

static func _target(app,char_id:String,set_id:String)->void:
	var result:Dictionary=app.model.set_abyss_relic_set(set_id)
	if not app._check(result):return
	app._toast("目标套装 · "+str(app.model.catalog.RelicSets[set_id].name),app.CYAN)
	show_for(app,char_id)
