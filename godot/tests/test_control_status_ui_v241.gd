extends SceneTree
var app
var checks:=0
var failures:Array=[]
func _initialize()->void:call_deferred('run')
func check(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures.append(label);push_error(label)
func frames(n:int=5)->void:
 for i in n:await process_frame
func text_under(node:Node)->String:
 var result:=str(node.text)+'\n' if node is Label or node is Button else ''
 for child in node.get_children():result+=text_under(child)
 return result
func visible(control:Control,label:String)->void:
 var clip:=Rect2(Vector2.ZERO,app.size)
 var parent=control.get_parent()
 while parent is Control:
  if parent.clip_contents:clip=clip.intersection(parent.get_global_rect())
  parent=parent.get_parent()
 check(control.is_visible_in_tree() and clip.encloses(control.get_global_rect()),label+' is fully inside viewport and all clipped ancestors')
func click_button(text:String)->void:
 var buttons=app.overlay.find_children('*','Button',true,false)
 for button in buttons:
  if button.text!=text:continue
  visible(button,text)
  var point:Vector2=button.get_global_rect().get_center()
  for pressed in [true,false]:
   var event=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.position=point;root.push_input(event,true);await process_frame
  await frames(5);return
 check(false,'actual close button exists: '+text)
func capture(label:String)->void:
 if DisplayServer.get_name()=='headless':return
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png('res://validation/v241-control-'+label+'.png')
func run()->void:
 root.size=Vector2i(2048,945)
 app=load('res://main.tscn').instantiate();root.add_child(app);await frames(12)
 app.set_process(false)
 var catalog:Dictionary=app.model.catalog.duplicate(true)
 var strip=load('res://scripts/ui/battle_status_strip.gd').new();root.add_child(strip)
 strip.size=Vector2(180,26)
 app.battle.start({'enemies':['boss_flame_lord'],'seed':241135},[{'id':'bolt'}])
 var enemy:Dictionary=app.battle.state.enemies[0]
 app.battle.apply_status(enemy,'electrify',7)
 var before_rng:int=app.battle.rng.state
 var before_state:Dictionary=app.battle.state.duplicate(true)
 for i in 100:
  check(is_equal_approx(app.battle.electrify_skip_chance(enemy),.35),'pure model probability query agrees with the status description')
  app.battle.control_decision(enemy)
 for id in ['electrify','shock']:
  strip.configure([{'id':id,'duration':7}],false,catalog)
  check(strip.tooltip_text.contains('35%') and strip.tooltip_text.contains('跳过'),'status and shock alias explain actual per-action skip probability')
  check(strip.tooltip_text.contains('7回合'),'full duration remains visible without boss truncation')
  check(not strip.tooltip_text.contains('无法行动'),'probabilistic electrify is not described as guaranteed hard control')
 var changed:Dictionary=catalog.duplicate(true);changed.CombatRules.electrifySkipChance=.42
 strip.configure([{'id':'electrify','duration':2}],false,changed)
 check(strip.tooltip_text.contains('42%'),'status description reads supplied combat configuration rather than a hard-coded percentage')
 strip.configure([{'id':'electrify','duration':2,'electrifySkipChanceBonus':.13}],false,changed)
 check(strip.tooltip_text.contains('55%'),'reserved per-status probability bonus is reflected by shared model query')
 strip.configure([{'id':'freeze','duration':7},{'id':'stun','duration':6}],false,catalog)
 check(strip.tooltip_text.contains('无法行动') and strip.tooltip_text.contains('7回合') and strip.tooltip_text.contains('6回合'),'freeze and stun remain complete hard control, distinct from electrify')
 check(app.battle.rng.state==before_rng and app.battle.state==before_state,'rendering and repeated probability queries never consume battle RNG or mutate combat state')
 var ultimate_text:String=catalog.SkillData.bolt_ult.description
 check(ultimate_text.contains('80%') and ultimate_text.contains('35%'),'actual ultimate description distinguishes application chance from per-action skip chance')
 var static_rewards:Array=catalog.AbyssData.rogue.rewards.filter(func(item):return item.id=='common_static_blue')
 check(static_rewards.size()==1,'locate actual static-conduction blessing without matching unrelated descriptions')
 var static_description:String=static_rewards[0].description
 check(static_description.contains('25%') and static_description.contains('35%'),'actual blessing catalog documents both application and skip chances')
 check(strip.size.y==26 and strip.mouse_filter==Control.MOUSE_FILTER_IGNORE,'dynamic description does not change strip geometry or block touch')
 strip.free()
 for resolution in [Vector2i(1920,1080),Vector2i(2340,1080),Vector2i(2048,945)]:
  root.size=resolution;await frames(12)
  app._show_unit_details(enemy);await frames(8)
  var detail=app.overlay.find_child('BattleStatusDetail_electrify',true,false)
  check(detail!=null and detail.text.contains('35%') and detail.text.contains('跳过'),'actual unit inspection explains per-action electrify probability')
  if detail!=null:visible(detail,'electrify effect detail '+str(resolution))
  check(text_under(app.overlay).contains('7 回合'),'actual inspection preserves complete seven-turn duration')
  await capture('details-'+str(resolution.x))
  await click_button('返回战场');check(app.overlay.get_child_count()==0,'actual inspection return closes overlay')
  app._show_abyss_rules();await frames(8)
  var rule=app.overlay.find_child('BattleRulesElectrify',true,false)
  check(rule!=null and rule.text.contains('35%'),'actual rules share configured skip probability')
  if rule!=null:visible(rule,'rules probability '+str(resolution))
  check(text_under(app.overlay).contains('冰冻、眩晕按完整持续时间'),'hard controls remain distinguished in actual rules')
  await capture('rules-'+str(resolution.x))
  await click_button('回到战斗');check(app.overlay.get_child_count()==0,'actual rules return closes overlay')
 var enhanced:Dictionary=enemy.duplicate(true)
 enhanced.statuses[0].electrifySkipChanceBonus=.13
 app._show_unit_details(enhanced);await frames(8)
 var enhanced_detail=app.overlay.find_child('BattleStatusDetail_electrify',true,false)
 check(enhanced_detail!=null and enhanced_detail.text.contains('48%'),'actual unit detail includes reserved status bonus rather than base probability only')
 if enhanced_detail!=null:visible(enhanced_detail,'bonus-enhanced status detail')
 await click_button('返回战场')
 check(app.battle.rng.state==before_rng and app.battle.state==before_state,'opening and closing actual detail/rule UI never roll or mutate battle')
 app.queue_free();await frames();await create_timer(.3).timeout
 print('CONTROL STATUS UI V241: %d checks, %d failures'%[checks,failures.size()]);quit(1 if failures else 0)
