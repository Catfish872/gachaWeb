extends SceneTree
const Rarity=preload('res://scripts/ui/reward_rarity.gd')
var app
var checks:=0
var failures:=0
func _initialize():call_deferred('run')
func frames():
 for i in 12:await process_frame
func ck(ok:bool,label:String):
 checks+=1
 if not ok:failures+=1;push_error(label)
func fits(control:Control,label:String):
 var clip:=Rect2(Vector2.ZERO,app.size);var p=control.get_parent()
 while p:
  if p is Control and (p.clip_contents or p is ScrollContainer):clip=clip.intersection(p.get_global_rect())
  p=p.get_parent()
 ck(clip.encloses(control.get_global_rect()),label)
func run():
 app=load('res://main.tscn').instantiate();root.add_child(app);await frames();app.set_process(false)
 for currency in ['rift_coin','memory_shard']:
  ck(app._icon_texture(currency).resource_path=='res://assets/ui/currency/'+currency+'.png','dedicated '+currency+' asset')
  ck(app._icon_texture(currency)!=app._icon_texture('coin') and app._icon_texture(currency)!=app._icon_texture('gem'),'currency distinct from general wallets')
 var choices:Array=[]
 for rarity in ['white','blue','gold']:
  for reward in app.model.catalog.AbyssData.rogue.rewards:
   if str(reward.get('rarity','white'))==rarity:choices.append(reward.duplicate(true));break
 ck(choices.size()==3,'three actual model rarity fixtures')
 var source:=JSON.stringify(choices)
 app.model.prepare_abyss();app.model.state.abyss.rogue.nextStep={'type':'reward'};app.model.state.abyss.rogue.pendingChoices=choices
 for resolution in [Vector2i(960,540),Vector2i(1170,540)]:
  root.size=resolution;await frames();app.navigate('abyss');await frames()
  var badges=app.main_body.find_children('RewardRarityLabel','Label',true,false)
  ck(badges.size()==3,'all choice cards carry explicit rarity badges')
  for i in range(3):
   ck(badges[i].text==['普通','稀有','传说'][i],'rarity title '+str(i))
   var panel=badges[i].get_parent().get_parent().get_parent()
   ck(panel.get_theme_stylebox('panel').border_width_left==i+1,'distinct contour weight '+str(i))
   fits(badges[i],'rarity label visible')
  for button in app.main_body.find_children('Blessing_*','Button',true,false):fits(button,'choice action fully visible')
  ck(JSON.stringify(choices)==source,'visual decoration preserves reward source')
  app.model.state.abyss.rogue.selectedRewards=choices
  app.AbyssView._build_modal(app,app.model.state.abyss.rogue);await frames()
  ck(app.overlay.find_children('RewardRarityLabel','Label',true,false).size()==3,'owned build cards retain rarity')
  app._clear_overlay();app._show_battle_echoes();await frames()
  ck(app.overlay.find_children('RewardRarityLabel','Label',true,false).size()==3,'battle build cards retain rarity')
  app._clear_overlay()
 app.queue_free();await frames();await create_timer(.3).timeout
 print('REWARD RARITY V24: %d checks, %d failures'%[checks,failures]);quit(1 if failures else 0)
