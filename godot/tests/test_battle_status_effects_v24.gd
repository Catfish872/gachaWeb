extends SceneTree
var failures: Array[String] = []
var checks := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
 checks += 1
 if not ok: failures.append(label); push_error(label)
func run() -> void:
 var strip = load("res://scripts/ui/battle_status_strip.gd").new()
 root.add_child(strip)
 strip.size = Vector2(180,26)
 strip.configure([])
 check(strip.get_combined_minimum_size().y==26,"empty status row preserves height")
 var states: Array = []
 for id in strip.DEFINITIONS:
  states.append({"id":id,"duration":3,"stacks":2})
 strip.configure(states)
 check(strip.get_combined_minimum_size()==Vector2(0,26),"many statuses preserve layout minimum")
 check(strip.visible_count==4 and strip.hidden_count==10,"compact status row reserves overflow count")
 for width in [110,120,150]:
  strip.size.x=width;strip._refresh_capacity()
  check(strip.visible_count >= (3 if width==150 else 2),"compact cards expose multiple icons at %dpx"%width)
  check(strip.visible_count*strip.cell_width+22<=width,"compact overflow stays in card at %dpx"%width)
 strip.size.x=360;strip._refresh_capacity()
 check(not strip.compact_mode and strip.cell_width==58 and strip.visible_count==5,"wide strip retains full counters with five-icon cap")
 check(strip.compact_counter_text({"id":"shield","persistent":true,"shieldHp":834})=="∞","compact equipment shield shows permanent mark")
 strip.size.x=150;strip.configure([{"id":"shield","persistent":true,"shieldHp":834}])
 check(strip.tooltip_text.contains("834"),"compact permanent shield retains exact durability in detail")
 strip.configure(states)
 check(strip.mouse_filter==Control.MOUSE_FILTER_IGNORE and strip.clip_contents,"status overlay clips and passes taps")
 check(not strip.is_processing(),"status strip remains idle")
 check(strip.DEFINITIONS.burn[1].contains("回合末") and not strip.DEFINITIONS.poison[1].contains("5%"),"status descriptions match current engine timing and boss scaling")
 check(strip.tooltip_text.contains("燃烧") and strip.tooltip_text.contains("3回合"),"full descriptions available for details")
 check(strip.counter_text({"id":"shield","persistent":true,"duration":1,"shieldHp":834})=="834","equipment shield shows durability rather than a turn")
 check(strip.counter_text({"id":"invincible","persistent":true})=="∞","persistent effect shows infinity")
 check(strip.counter_text({"id":"poison","stacks":3,"duration":2})=="3·2","stack count and remaining turns visible")
 check(strip.status_id({"statusId":"shock"})=="electrify","shock alias retains web electrify semantic")
 for id in strip.DEFINITIONS: check(load("res://assets/ui/status/%s.svg"%id) is Texture2D,"status vector loads: "+id)
 strip.configure([{"id":"poison","stacks":1,"duration":2},{"id":"poison","stacks":1,"duration":3}])
 check(strip.states.size()==1 and strip.states[0].stacks==2,"independent poison instances aggregate into readable layers")
 check(strip.counter_text(strip.states[0])=="2·2+" and strip.tooltip_text.contains("3回合"),"mixed poison duration stays explicit in full details")
 var fx = load("res://scripts/ui/battle_fx.gd").new()
 root.add_child(fx)
 for kind in ["slash","blunt","fire","water","ice","thunder","wind","shield_break","poison","bleed","vulnerable","atk_up","spd_down","taunt","stun"]:
  fx.impact(kind,Vector2(10,10),Vector2(80,80),true)
  check(fx.impacts.back().kind==kind,"distinct semantic shape: "+kind)
 for i in range(100): fx.impact("slash",Vector2.ZERO,Vector2.ONE)
 check(fx.impacts.size()==24,"impact count bounded")
 check(fx.mouse_filter==Control.MOUSE_FILTER_IGNORE and fx.clip_contents,"impact overlay clips and passes taps")
 fx._process(1.0)
 check(fx.impacts.is_empty() and not fx.is_processing(),"impacts expire and stop idle processing")
 fx.reduced_motion=true
 fx.impact("fire",Vector2.ZERO,Vector2.ONE);fx.impact("heal",Vector2.ZERO,Vector2.ONE);fx.impact("shield",Vector2.ZERO,Vector2.ONE)
 check(fx.impacts.is_empty() and fx.rings.is_empty() and not fx.is_processing(),"reduced motion suppresses semantic effects")
 fx.reduced_motion=false;fx.impact("fire",Vector2.ZERO,Vector2.ONE);fx.clear_effects()
 check(fx.impacts.is_empty() and not fx.is_processing(),"navigation clears impacts")
 strip.free();fx.free()
 print("BATTLE STATUS EFFECTS V24: %d checks, %d failures"%[checks,failures.size()])
 quit(0 if failures.is_empty() else 1)
