extends "res://tests/test_mobile_layout_v283.gd"
func run()->void:
 app=load("res://main.tscn").instantiate();root.add_child(app);await frames(10);app.set_process(false);fresh()
 for id in app.model.catalog.CharacterData:app.model.state.ownedCharacters[id]=app.model.default_character()
 app.model.state.team=["selin","kaldi","ayla"]
 for res in [Vector2i(960,540),Vector2i(2048,945)]:
  root.size=res;await frames(6);app.character_list_positions.erase("party");app.navigate("party");await frames(8)
  for id in ["selin","kaldi","ayla"]:
   var card=named283("PartyCard_"+id)
   for b in card.get_parent().find_children("*","Button",true,false):fits(b,"first row action "+id)
  await capture(str(res.x)+"-party-final")
  var scroll=named283("PartyRosterScroll")
  var before=scroll.scroll_vertical
  var team_before=app.draft_team.duplicate()
  var point=scroll.get_global_rect().get_center()
  var down=InputEventScreenTouch.new();down.index=0;down.pressed=true;down.position=point;root.push_input(down,true);await frames(2)
  var drag=InputEventScreenDrag.new();drag.index=0;drag.position=point-Vector2(0,110);drag.relative=Vector2(0,-110);root.push_input(drag,true);await frames(2)
  var up=InputEventScreenTouch.new();up.index=0;up.pressed=false;up.position=drag.position;root.push_input(up,true);await frames(3)
  ck(app.draft_team==team_before,"touch scroll does not toggle team")
  ck(scroll.scroll_vertical>before,"real screen touch drag scrolls roster")
  scroll.scroll_vertical=int(scroll.get_v_scroll_bar().max_value);await frames(5)
  ck(scroll.scroll_vertical>before,"roster scroll reaches later characters")
  var cards=app.find_children("PartyCard_*","",true,false)
  var last=cards.back()
  for b in last.get_parent().find_children("*","Button",true,false):fits(b,"last row action")
  await capture(str(res.x)+"-party-scrolled")
 app.queue_free();await frames(5);print("PARTY DELTA V283: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
