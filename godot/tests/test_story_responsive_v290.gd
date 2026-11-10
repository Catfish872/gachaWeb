extends "res://tests/test_lantern_journey_ui_v270.gd"

func horizontal_fit(control: Control, label: String) -> void:
 var rect := control.get_global_rect()
 ck(rect.position.x >= 0 and rect.end.x <= app.size.x, label + " retains full width")

func run() -> void:
 app = load("res://main.tscn").instantiate()
 root.add_child(app)
 await frames(10)
 app.set_process(false)
 fresh()
 for stage in app.model.stage_list():
  app.model.state.stageProgress[stage.id] = {"cleared": true}
 for resolution in [Vector2i(800,540), Vector2i(844,390), Vector2i(864,540), Vector2i(960,540), Vector2i(1168,730), Vector2i(2048,945)]:
  root.size = resolution
  await frames(10)
  app.navigate("story")
  await frames(10)
  print("LAYOUT ", resolution, " app ", app.size, " body ", app.main_body.size)
  for i in app.model.catalog.StageData.chapters.size():
   var tab = app.find_child("StoryChapter_" + str(i), true, false)
   fits(tab, "chapter tab " + str(i) + " " + str(resolution))
   ck(tab.size.y >= 44, "chapter tab touch height")
   await tap(tab)
   ck(app.selected_chapter == i, "actual chapter click selects " + str(i))
   var stage_scroll = app.find_child("StoryStageScroll", true, false)
   fits(stage_scroll, "stage list " + str(i) + " " + str(resolution))
   for stage in [app.model.catalog.StageData.chapters[i].stages.front(), app.model.catalog.StageData.chapters[i].stages.back()]:
    var card = app.find_child("StageCard_" + str(stage.id), true, false)
    stage_scroll.ensure_control_visible(card)
    await frames(5)
    var offset: int = stage_scroll.scroll_vertical
    await tap(card)
    ck(app.selected_stage_id == str(stage.id), "actual stage click selects " + str(stage.id))
    stage_scroll = app.find_child("StoryStageScroll", true, false)
    ck(abs(stage_scroll.scroll_vertical - offset) <= 1, "stage selection keeps scroll position")
    var enter = app.find_child("StoryEnter", true, false)
    fits(enter, "chapter action " + str(stage.id) + " " + str(resolution))
    fits(app.find_child("StoryReplay", true, false), "chapter replay " + str(stage.id))
    ck(enter.size.y >= 44, "story action touch height")
    var detail_scroll = app.find_child("StoryDetailScroll", true, false)
    if detail_scroll != null:
     fits(detail_scroll, "detail viewport")
     var button_y: float = enter.global_position.y
     detail_scroll.scroll_vertical = int(detail_scroll.get_v_scroll_bar().max_value)
     await frames(5)
     ck(enter.global_position.y == button_y, "detail scroll retains fixed actions")
     for control in detail_scroll.find_children("*", "Control", true, false):
      if control is Label or control is Button:
       horizontal_fit(control, "detail text " + str(stage.id))
   await tap(app.find_child("StoryChapter_" + str(i), true, false))
   ck(app.selected_stage_id == str(app.model.catalog.StageData.chapters[i].stages.back().id), "repeat chapter click retains selection")
  app.navigate("home")
  await frames(5)
  app.navigate("story")
  await frames(8)
  fits(app.find_child("StoryEnter", true, false), "story re-entry action")
 app.queue_free()
 await frames(10)
 print("STORY RESPONSIVE V290: %d checks, %d failures" % [checks, failures])
 quit(1 if failures else 0)
