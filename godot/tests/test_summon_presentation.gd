extends SceneTree
var app
var checks:=0
var failures:=0
func _initialize():call_deferred('run')
func frames(n:int=10):
 for i in n:await process_frame
func ck(ok:bool,label:String):
 checks+=1
 if not ok:failures+=1;push_error('SUMMON: '+label)
func find(name:String):return app.find_child(name,true,false)
func visible(control:Control)->Rect2:
 var rect:=control.get_global_rect();var p=control.get_parent()
 while p!=null:
  if p is Control and (p.clip_contents or p is ScrollContainer):rect=rect.intersection(p.get_global_rect())
  p=p.get_parent()
 return rect.intersection(Rect2(Vector2.ZERO,app.size))
func fits(control:Control,label:String):
 ck(control!=null,label+' exists')
 if control:ck(visible(control).size.is_equal_approx(control.size),label+' fully visible')
func click(control:Control):
 var pos:=visible(control).get_center()
 for pressed in [true,false]:
  var ev:=InputEventMouseButton.new();ev.button_index=MOUSE_BUTTON_LEFT;ev.position=pos;ev.global_position=pos;ev.pressed=pressed;root.push_input(ev);await frames(2)
 await frames()
func run():
 app=load('res://main.tscn').instantiate();root.add_child(app);await frames(16);app.set_process(false)
 for resolution in [Vector2i(1170,540),Vector2i(960,540)]:
  root.size=resolution;await frames(16)
  app.model.state.resources.diamonds=10000;app.selected_pool='limited_kaldi';app.navigate('summon');await frames()
  fits(find('SummonPull_1'),'single action');fits(find('SummonPull_10'),'ten action')
  fits(find('SummonRules'),'rules tool')
  await click(find('SummonRules'))
  var rules_text:=''
  for label in app.overlay.find_children('*','Label',true,false):rules_text+=label.text+'\n'
  for probability in ['1.6%','15%','83.4%','75%']:ck(rules_text.contains(probability),'rules displays '+probability)
  var pity=app.model.catalog.GachaPoolData.pools[app.selected_pool].pity
  ck(rules_text.contains('第 %d 次开始' % [int(pity.soft)+1]),'rules displays actual soft pity')
  ck(rules_text.contains('第 %d 次' % [int(pity.hard)]),'rules displays actual hard pity')
  fits(find('SummonRulesClose'),'rules close')
  await click(find('SummonRulesClose'));ck(app.overlay.get_child_count()==0,'rules closes through actual click')
  var owned=JSON.stringify(app.model.state.ownedCharacters)
  await click(find('SummonPreview'));fits(find('SummonPreviewClose'),'preview return')
  ck(JSON.stringify(app.model.state.ownedCharacters)==owned and app.model.state.resources.diamonds==10000,'preview is read-only')
  await click(find('SummonPreviewClose'))
  await click(find('SummonPull_1'))
  ck(app.summon_results.size()==1 and app.model.state.resources.diamonds==9840,'single pull commits once')
  fits(find('SummonReveal'),'reveal action');fits(find('SummonSkip'),'skip action')
  await click(find('SummonReveal'));fits(find('SummonNext'),'revealed next')
  await click(find('SummonSkip'));fits(find('SummonAccept'),'single summary accept')
  await click(find('SummonAccept'))
  await click(find('SummonPull_10'))
  ck(app.summon_results.size()==10 and app.model.state.resources.diamonds==8240,'ten pull commits exact cost')
  await click(find('SummonSkip'));fits(find('SummonAccept'),'ten summary accept')
  var cards=app.overlay.find_children('SummonResult_*','PanelContainer',true,false)
  ck(cards.size()==10,'all ten results retained')
  for card in cards:fits(card,'result card')
  await click(cards[0]);fits(find('SummonPreviewClose'),'result preview return')
  await click(find('SummonPreviewClose'));ck(app.overlay.find_children('SummonResult_*','PanelContainer',true,false).size()==10,'preview returns to all results')
  await click(find('SummonAccept'));ck(app.overlay.get_child_count()==0,'accept clears overlay')
 app.queue_free();await frames();await create_timer(.3).timeout
 print('SUMMON PRESENTATION: %d checks, %d failures' % [checks,failures]);quit(1 if failures else 0)
