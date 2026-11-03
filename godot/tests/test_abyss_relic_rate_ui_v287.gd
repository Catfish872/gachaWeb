extends "res://tests/test_lantern_journey_ui_v270.gd"
const View=preload("res://scripts/ui/abyss_view.gd")
func run()->void:
 app=load("res://main.tscn").instantiate();root.add_child(app);await frames(10);app.set_process(false)
 root.size=Vector2i(960,540);await frames(5);fresh()
 app.model.state.abyss.meta.unlockedDifficulty=3
 app.model.set_abyss_difficulty(3);app.model.set_abyss_relic_set("aurora_prayer")
 app.navigate("abyss");await frames(6)
 var rate=app.find_child("AbyssRelicDropRate",true,false)
 ck(rate!=null and rate.text.contains("22") and rate.text.contains("51层起仅五星"),"camp total and post51 five star rule explicit")
 View._target_set_picker(app);await frames(6)
 var found:bool=false
 for node in app.find_child("AbyssSetPickerContent",true,false).find_children("*","Label",true,false):
  if node.text.contains("每50层约22件") and node.text.contains("51层起仅五星"):found=true;fits(node,"post51 text within viewport")
 ck(found,"picker separates pre50 and post51 rules")
 ck(app.model.abyss_relic_drop_info().expectedFiveStarPer50<app.model.abyss_relic_drop_info().expectedPer50,"five star expectation is subset")
 DirAccess.make_dir_recursive_absolute("res://validation/v287-abyss-relic-audit")
 await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png("res://validation/v287-abyss-relic-audit/960-drop-rate.png")
 app.queue_free();await frames(5)
 print("ABYSS RELIC RATE UI V287: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
