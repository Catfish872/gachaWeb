extends "res://tests/test_lantern_journey_ui_v270.gd"
const View283=preload("res://scripts/ui/extraction_view.gd")
const OUT283="res://validation/v283-ui/"
func capture(label:String)->void:
 if DisplayServer.get_name()=="headless":return
 DirAccess.make_dir_recursive_absolute(OUT283)
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(OUT283+label+".png")
func named283(id:String)->Node:return app.find_child(id,true,false)
func event_fixture283()->void:
 fresh();app.model.rng.seed=278;app.model.extraction.start_run()
 var ex=app.model.extraction
 ex.run().phase="room";ex.run().activeEncounter={};ex.run().pendingChoices=[];ex.run().containers=[]
 for unit in ex.run().party:unit.currentHp=100;unit.maxHp=1000;unit.energy=0
 ex.run().room.type="rest";ex.run().room.name="留灯休憩处";ex.run().room.guardPending=false
 ex._prepare_room_actions("rest")
 app.extraction_panel="expedition";app.navigate("extraction");await frames(10)
var callbacks283:=0
func done283()->void:callbacks283+=1
func story283(label:String)->void:
 fresh()
 for stage in app.model.stage_list():
  if str(stage.id).begins_with("ch1_") or str(stage.id).begins_with("ch2_") or str(stage.id).begins_with("ch3_") or (str(stage.id).begins_with("ch4_") and int(str(stage.id).trim_prefix("ch4_"))<=9):app.model.state.stageProgress[stage.id]={"cleared":true}
 app.navigate("story");await frames(10)
 ck(app.selected_chapter==3 and app.selected_stage_id=="ch4_10","story opens next unlocked destination")
 fits(named283("StoryChapter_3"),"chapter4 tab")
 ck(named283("StoryChapter_3").icon.resource_path.ends_with("wind.svg"),"chapter4 wind icon")
 await capture(label+"-story-next")
 for key in ["ch4_9_pre","ch4_12_post"]:
  app._play_dialogue(key,done283);await frames(4)
  if key=="ch4_9_pre":app.dialogue_index=5;app._render_dialogue();await frames(4)
  if app.dialogue_tween:app.dialogue_tween.kill()
  app.dialogue_prose.visible_characters=-1;await frames(3)
  fits(app.dialogue_prose,"story prose");fits(named283("DialogueNext"),"next action");fits(named283("DialogueSkip"),"skip action")
  ck(app.dialogue_prose.get_line_count()==app.dialogue_prose.get_visible_line_count(),"dialogue lines not clipped")
  if key=="ch4_9_pre":
   ck(named283("DialogueBackdrop").modulate.r>.8,"brighter backdrop")
   ck(named283("DialoguePanel").size.y<app.size.y*.48,"compact translucent prose panel")
  await capture(label+"-"+key)
  var before=app.dialogue_index;await tap(named283("DialogueNext"));ck(app.dialogue_index==before+1,"next one line")
  var callbacks_before=callbacks283;await tap(named283("DialogueSkip"));ck(callbacks283==callbacks_before+1,"skip callback once")
func party283(label:String)->void:
 fresh()
 for id in app.model.catalog.CharacterData:app.model.state.ownedCharacters[id]=app.model.default_character()
 app.model.state.team=["selin","kaldi","ayla"];app.navigate("party");await frames(8)
 fits(named283("TeamPresetRename"),"rename");fits(named283("TeamPresetSave"),"save team")
 for i in 5:fits(named283("TeamPreset_%d"%i),"preset%d"%i)
 var tabs=named283("TeamPresetTabs");var row=named283("PartyFormationRow")
 ck(row!=null and row.position.y<=tabs.position.y+tabs.size.y+24,"formation follows tabs without blank row")
 await capture(label+"-party")
func extraction283(label:String)->void:
 await event_fixture283()
 var ex=app.model.extraction
 ex.run().room.type="hospital";ex.run().room.name="守灯药店";ex._prepare_room_actions("hospital")
 ex._container("灰烬供台",2,0);ex._container("灰烬供台",2,0)
 for box in ex.run().containers:box.sprite=ex.data.environmentContainers.lantern_ash_altar.sprite
 app._render_screen();await frames(10)
 var cards=app.find_children("ExtractionEventCard_*","",true,false);ck(cards.size()==3,"hospital3 choices")
 for card in cards:
  for button in card.find_children("ExtractionRoomAction_*","Button",true,false):fits(button,"hospital action")
 fits(named283("ExtractionPersistentActions"),"fixed backpack actions");await capture(label+"-hospital-two-boxes")
 ex.run().roomActions=[];ex.run().pendingChoices=[];ex.run().room.type="cache"
 ex.run().room.background="res://assets/content_v280/backgrounds/wind_outpost.png"
 ex.run().containers=[{"id":"qa_wind_box","name":"风庭宝匣","kind":"safe","width":6,"height":8,"revealed":0,"items":[],"quality":2,"sprite":ex.data.environmentContainers.windpass_treasury.sprite,"sceneX":.5,"sceneY":.6}]
 app._render_screen();await frames(6)
 var scene=named283("ExtractionRoomScene");scene.selected="qa_wind_box";scene.queue_redraw();await frames(3)
 ck(scene.selected=="qa_wind_box","selected empty container remains shown")
 await capture(label+"-selected-container")
func run()->void:
 if DisplayServer.get_name()=="headless":quit(2);return
 app=load("res://main.tscn").instantiate();root.add_child(app);await frames(12);app.set_process(false)
 for resolution in [Vector2i(2048,945),Vector2i(960,540)]:
  root.size=resolution;await frames(6)
  await story283(str(resolution.x));await party283(str(resolution.x));await extraction283(str(resolution.x))
 app.queue_free();await frames(6)
 print("MOBILE LAYOUT V283: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
