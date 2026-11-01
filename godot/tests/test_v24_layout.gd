extends SceneTree
var app
var checks:=0
var failures:=0
func _initialize():call_deferred('run')
func frames(n:int=12):
 for i in n:await process_frame
func ck(ok:bool,label:String):
 checks+=1
 if not ok:failures+=1;push_error(label)
func fits(control:Control,label:String):
 ck(control!=null,label+' exists')
 if control==null:return
 var rect:=Rect2(Vector2.ZERO,app.size);var parent=control.get_parent()
 while parent:
  if parent is Control and (parent.clip_contents or parent is ScrollContainer):rect=rect.intersection(parent.get_global_rect())
  parent=parent.get_parent()
 ck(rect.encloses(control.get_global_rect()),label+' fully visible')
func run():
 app=load('res://main.tscn').instantiate();root.add_child(app);await frames();app.set_process(false)
 var relic=app.model.generate_relic(5,'belt')
 relic.subStats=[{'stat':'hp_pct','name':'生命加成','value':.06},{'stat':'atk_pct','name':'攻击加成','value':.06},{'stat':'cri_rate','name':'暴击率','value':.04},{'stat':'spd','name':'速度','value':5}]
 app.model.add_relic(relic);app.selected_relic=relic.uid
 for resolution in [Vector2i(1170,540),Vector2i(960,540),Vector2i(960,480)]:
  root.size=resolution;await frames();app.navigate('relics');await frames()
  var detail=app.find_child('RelicDetailPanel',true,false);var collection=app.find_child('RelicCollectionColumn',true,false)
  ck(abs(detail.global_position.y-collection.global_position.y)<1,'detail starts at column top independently from filters')
  for stat in relic.subStats:fits(app.find_child('RelicSubstat_'+stat.stat,true,false),'all four substats '+stat.stat)
  fits(app.find_child('RelicUpgrade',true,false),'upgrade');fits(app.find_child('RelicEquip',true,false),'equip')
  var prepared=app.model.prepare_stage('ch1_1');app._start_battle(prepared.config);app.set_process(false);app.battle_settled=true
  var result={'rewards':{'gold':12500,'exp':900,'diamonds':160,'runCoins':350,'meta':28},'relic':relic,'firstClear':true,'gift':{'charName':'焰龙 · 卡尔迪'},'progression':[{'charId':'ember','leveledUp':2,'newLevel':5},{'charId':'zeph','leveledUp':1,'newLevel':4}]}
  for abyss in [false,true]:
   app.battle_config.isAbyss=abyss;app._render_battle_settlement(result,true,abyss);await frames()
   fits(app.find_child('BattleSettlementContinue',true,false),'settlement continuation')
   for key in ['exp','diamonds']:fits(app.find_child('SettlementReward_'+key,true,false),'reward '+key)
   if abyss:ck(app.find_child('SettlementReward_gold',true,false)==null,'abyss never presents direct gold reward')
   else:
    fits(app.find_child('SettlementReward_gold',true,false),'ordinary gold reward')
    ck(app.find_child('SettlementReward_gold',true,false).text=='+12500','exact ordinary gold gain')
   var sc:ScrollContainer=app.find_child('SettlementRewardScroll',true,false);sc.scroll_vertical=99999;await frames()
   fits(app.find_child('BattleSettlementContinue',true,false),'continue after reward scrolling')
   app._clear_overlay()
  app.battle_config.isAbyss=false;app._render_battle_settlement({},false,false);await frames();fits(app.find_child('BattleSettlementContinue',true,false),'defeat continuation');app._clear_overlay()
  app.model._issued_config.clear()
 app.queue_free();await frames();await create_timer(.3).timeout
 print('V24 LAYOUT: %d checks, %d failures'%[checks,failures]);quit(1 if failures else 0)
