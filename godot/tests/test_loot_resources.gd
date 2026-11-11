extends SceneTree
func _initialize() -> void:
 var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/extraction.json"))
 var failures := 0
 var count := 0
 for id in data.items:
  var d: Dictionary = data.items[id]
  if not str(d.icon).contains("v300") and not str(d.icon).contains("v310"): continue
  count+=1
  var tex = load(d.icon)
  if not tex is Texture2D or tex.get_width()<=0 or tex.get_height()<=0:
   printerr("FAIL texture ",id); failures+=1
  elif tex.get_image().is_empty():
   printerr("FAIL pixels ",id); failures+=1
 print("LOOT RESOURCES ",count," textures ",failures," failures")
 quit(1 if failures else 0)
