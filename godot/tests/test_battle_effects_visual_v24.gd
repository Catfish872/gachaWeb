extends SceneTree
func _initialize() -> void: call_deferred("run")
func label_at(text: String, at: Vector2, width: float = 220) -> void:
 var label := Label.new()
 label.text = text
 label.position = at
 label.size.x = width
 label.add_theme_font_override("font",load("res://assets/fonts/NotoSansSC.otf"))
 label.add_theme_font_size_override("font_size",16)
 root.add_child(label)
func run() -> void:
 root.size = Vector2i(1100,760)
 root.content_scale_size = Vector2i(1100,760)
 label_at("状态图标 · 固定26高 · 层数/回合 · 装备盾耐久",Vector2(24,12),900)
 var strip_script = load("res://scripts/ui/battle_status_strip.gd")
 var index := 0
 for id in strip_script.DEFINITIONS:
  var x := 24+(index%7)*150
  var y := 50+(index/7)*70
  label_at(strip_script.DEFINITIONS[id][0],Vector2(x,y),140)
  var strip = strip_script.new()
  root.add_child(strip)
  strip.position=Vector2(x,y+27);strip.size=Vector2(140,26)
  strip.configure([{"id":id,"duration":3,"stacks":2}])
  index+=1
 var narrow = strip_script.new()
 root.add_child(narrow);narrow.position=Vector2(24,205);narrow.size=Vector2(150,26)
 narrow.configure([{"id":"shield","persistent":true,"shieldHp":834},{"id":"burn","duration":2},{"id":"poison","duration":3},{"id":"taunt","duration":1},{"id":"freeze","duration":1}])
 label_at("150px窄栏：常驻∞、3图标与+2；耐久见详情；固定26高",Vector2(235,205),800)
 var fx = load("res://scripts/ui/battle_fx.gd").new()
 root.add_child(fx);fx.size=Vector2(1100,760)
 index=0
 for kind in ["slash","blunt","fire","water","ice","thunder","wind","shield_break","poison","bleed","vulnerable","atk_up","spd_down","taunt","stun"]:
  var p := Vector2(110+(index%5)*215,325+(index/5)*145)
  fx.impact(kind,p-Vector2(40,0),p)
  label_at(kind,p+Vector2(-65,50),170)
  index+=1
 for effect in fx.impacts: effect.life=0.31
 fx.set_process(false);fx.queue_redraw()
 await process_frame
 await process_frame
 await RenderingServer.frame_post_draw
 var path := "/workspace/scratch/8f1fc457a062/battle-status-effects-v24.png"
 var result := root.get_texture().get_image().save_png(path)
 print("VISUAL ATLAS: ",path," result=",result)
 quit(result)
