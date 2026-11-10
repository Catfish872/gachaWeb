extends "res://tests/test_lantern_journey_ui_v270.gd"

func run() -> void:
 app = load("res://main.tscn").instantiate()
 root.add_child(app)
 await frames(10)
 app.set_process(false)
 fresh()
 var cg_keys: Array = []
 for key in app.model.catalog.get("DialogueMeta", {}):
  if app.model.catalog.DialogueMeta[key].has("illustration"):
   cg_keys.append(key)
 cg_keys.append_array(["ch3_4_post", "ch3_8_post"])
 for resolution in [Vector2i(864,540), Vector2i(960,540), Vector2i(2048,945), Vector2i(540,960)]:
  root.size = resolution
  await frames(8)
  for key in cg_keys + ["ch5_1_pre", "ch4_1_pre"]:
   app._play_dialogue(key, func(): pass)
   await frames(5)
   var art = app.find_child("DialogueBackdrop", true, false)
   ck(art != null and art.texture != null, "dialogue artwork loads " + key)
   ck(art.texture.resource_path == app._dialogue_background_path(), "scene asset retained " + key)
   if key in cg_keys:
    ck(art.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED, "CG full composition " + key)
    var texture_size: Vector2 = art.texture.get_size()
    var scale: float = minf(art.size.x / texture_size.x, art.size.y / texture_size.y)
    var drawn := Rect2(art.global_position + (art.size - texture_size * scale) / 2.0, texture_size * scale)
    ck(Rect2(Vector2.ZERO, app.size).grow(0.1).encloses(drawn), "full CG source rectangle inside viewport " + key)
    ck(app.find_child("DialoguePortrait", true, false) == null, "CG keeps portrait overlay suppressed " + key)
   else:
    ck(art.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_COVERED, "ordinary background remains full bleed " + key)
   fits(app.find_child("DialogueNext", true, false), "dialogue next " + key)
   fits(app.find_child("DialogueSkip", true, false), "dialogue skip " + key)
   app._finish_dialogue()
 app.queue_free()
 await frames(10)
 # Allow the threaded audio mixer to release a final dialogue stream.
 await create_timer(0.3).timeout
 print("DIALOGUE CG LAYOUT V290: %d checks, %d failures" % [checks, failures])
 quit(1 if failures else 0)
