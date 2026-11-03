extends "res://tests/test_lantern_journey_ui_v270.gd"
const OUT289="res://validation/v289-relic-steady/"
func setup_game()->void:
 fresh();app.model.rng.seed=288031
 for id in ["lumi","tiya","ayla"]:app.model.state.ownedCharacters[id]=app.model.default_character()
 app.model.state.team=["ember","tiya","ayla"];app.model.state.relics=[]
 for index in range(5):
  var base:Dictionary=app.model.generate_relic(5,app.model.catalog.RelicSlots[index].id,"")
  for set_id in (["wind_strings","wind_blades","ember_lantern"] if index<4 else [""]):
   var item:Dictionary=base.duplicate(true);item.uid=str(index)+set_id;item.setId=set_id;app.model.state.relics.append(item)
 app.selected_character="lumi";app.growth_panel="gear";app.navigate("growth")
func run()->void:
 app=load("res://main.tscn").instantiate();root.add_child(app);await frames(10);app.set_process(false)
 DirAccess.make_dir_recursive_absolute(OUT289)
 for resolution in [Vector2i(960,540),Vector2i(2048,945)]:
  root.size=resolution;await frames(5);setup_game();await frames(5)
  var before:Dictionary=app.model.state.duplicate(true);var started:int=Time.get_ticks_msec();app._auto_relic_loadout("lumi");await frames(18)
  var label=app.find_child("RelicLoadoutReferenceTeam",true,false)
  fits(label,"reference team label "+str(resolution));ck(label.text.contains("露弥") and label.text.contains("缇娅"),"visible real synergistic reference")
  ck(app.model.state==before,"preview does not alter inventory or team")
  var plan:Dictionary={}
  for node in app.find_children("*","Control",true,false):
   if node.has_meta("relic_displayed_plan"):plan=node.get_meta("relic_displayed_plan")
  ck(plan.get("evaluationMode","")=="steady","UI default uses steady objective")
  var has_label:bool=false
  for node in app.find_children("*","Label",true,false):
   if node.text.begins_with("长期每行动"):has_label=true
  ck(has_label,"per-action long-run label visible")
  print("UI_STEADY_ELAPSED ",resolution," ",Time.get_ticks_msec()-started,"ms")
  var apply=app.find_child("RelicLoadoutApply",true,false);fits(apply,"apply action");ck(not apply.disabled,"real search completes with applicable plan")
  await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(OUT289+str(resolution.x)+"-reference-team.png")
  await tap(apply);ck(app.model.state.ownedCharacters.lumi.equippedRelics.size()==5,"real apply equips all five UIDs")
  ck(app.model.state.team==before.team and app.model.state.resources==before.resources,"applying keeps live team and currency")
 app.queue_free();await frames(5)
 print("RELIC STEADY UI V289: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
