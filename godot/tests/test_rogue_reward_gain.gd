extends "res://tests/test_loot_v24_interactions.gd"
const AbyssView=preload('res://scripts/ui/abyss_view.gd')
func prepare(kind:String='event')->void:
 app.model=load('res://scripts/game_model.gd').new('');app.model.rng.seed=24119
 app.battle=load('res://scripts/battle_model.gd').new(app.model.catalog)
 check(app.model.prepare_abyss().success,'real abyss run starts')
 app.model._issued_config={}
 var rogue:Dictionary=app.model.state.abyss.rogue
 rogue.activeEncounter={};rogue.nextStep={'type':kind,'floor':2};rogue.pendingNode={'type':kind,'id':kind+'_2','eventId':'blood_altar'};rogue.temporaryCurrency=1000
 app.model.state.abyss.savedPartyState=[]
 for unit in app.model.battle_party(true):app.model.state.abyss.savedPartyState.append({'id':unit.id,'currentHp':unit.maxHp,'maxHp':unit.maxHp,'energy':0,'cooldowns':{}})
 app.abyss_auto_continue=false;app.abyss_panel='expedition';app.navigate('abyss')
func inspect_card(reward:Dictionary,count:int)->void:
 var card=target('RogueRewardGain')
 check(card!=null,'committed actual reward has an identification card')
 if card==null:return
 check(card.get_meta('reward_id')==reward.id and card.get_meta('stack_count')==count,'feedback identifies precise awarded ID and actual total stack count')
 check(target('RogueRewardGainName').text==reward.name and target('RogueRewardGainDescription').text==reward.description,'actual name and complete effect match model reward')
 check(target('RogueRewardGainIcon')!=null,'actual effect icon accompanies reward')
 check(target('RogueRewardGainStacks').text=='累计 %d 层'%count,'stack count displayed explicitly')
 check(card.find_child('RewardRarityLabel',true,false)!=null,'actual rarity badge shown')
 visible_control(card,'whole reward card')
 for name in ['RogueRewardGainName','RogueRewardGainDescription','RogueRewardGainHint']:visible_control(target(name),'readable '+name)
func reveal_shop_action(button:Control)->void:
 var scroll=button.get_parent()
 while scroll!=null and not scroll is ScrollContainer:scroll=scroll.get_parent()
 check(scroll is ScrollContainer,'shop action belongs to a local scroll region')
 if not scroll is ScrollContainer:return
 for attempt in 12:
  if app._visible_control_rect(button).encloses(button.get_global_rect()):break
  var r:Rect2=app._visible_control_rect(scroll)
  var old:int=scroll.scroll_vertical
  await touch_drag_between(Vector2(r.position.x+r.size.x*.8,r.end.y-12),Vector2(r.position.x+r.size.x*.8,r.position.y+12))
  await create_timer(.15).timeout
  check(scroll.scroll_vertical>old,'actual finger gesture reveals lower shop merchandise')
 visible_control(button,'last shop merchandise action')
func run()->void:
 app=load('res://main.tscn').instantiate();root.add_child(app);await frames(12);app.set_process(false)
 for resolution in [Vector2i(1920,1080),Vector2i(2340,1080),Vector2i(2048,945)]:
  root.size=resolution;await frames(12)
  for reduced in [false,true]:
   app.extraction_reduced_motion=reduced;prepare();await frames(12)
   await click(target('NodeChoice_offering'))
   var selected:Array=app.model.state.abyss.rogue.selectedRewards
   check(selected.size()==1,'random event commits one actual reward')
   inspect_card(selected.back(),1)
   var card=target('RogueRewardGain');var before:Dictionary=app.model.state.duplicate(true)
   check(card.remaining>2.8,'reduced and ordinary animation both retain meaningful reading time')
   var point:Vector2=card.get_global_rect().get_center()
   var down:=InputEventScreenTouch.new();down.index=0;down.position=point;down.pressed=true;root.push_input(down,true);await frames(2)
   var remaining:float=card.remaining
   await create_timer(.25).timeout
   check(card._held and absf(card.remaining-remaining)<.03,'holding reward card pauses expiry through actual touch dispatch')
   await capture('v241-reward-event-'+str(resolution.x)+'-'+str(reduced))
   var released:=InputEventScreenTouch.new();released.index=0;released.position=point;root.push_input(released,true);await frames(4)
   check(target('RogueRewardGain')==null and app.model.state==before,'release dismisses without awarding a second reward or altering run')
 # Selecting an already-owned actual reward shows its real second stack.
 prepare('reward');await frames()
 var reward:Dictionary=app.model.catalog.AbyssData.rogue.rewards[0].duplicate(true)
 app.model.state.abyss.rogue.selectedRewards=[reward.duplicate(true)]
 reward.choiceId='stack-choice';app.model.state.abyss.rogue.pendingChoices=[reward]
 app._render_screen();await frames();await click(target('Blessing_stack-choice'))
 inspect_card(reward,2)
 var card=target('RogueRewardGain');var before:Dictionary=app.model.state.duplicate(true)
 var spy:=Button.new();spy.position=card.position;spy.size=card.size;spy.z_index=79;app.add_child(spy);app.move_child(spy,card.get_index())
 var presses:Array=[];spy.pressed.connect(func():presses.append(true))
 await click_at(card.get_global_rect().get_center())
 check(presses.is_empty(),'dismissing reward never clicks the underlying button')
 check(app.model.state==before,'dismissal retains exactly the two real stacks')
 spy.queue_free();await frames()
 # All three real shop blessings remain reachable in every target mobile aspect ratio.
 for resolution in [Vector2i(1920,1080),Vector2i(2340,1080),Vector2i(2048,945)]:
  root.size=resolution;await frames(12)
  prepare('shop');app.model.state.abyss.rogue.temporaryCurrency=10000;app.model._generate_abyss_shop();app._render_screen();await frames()
  check(target('AbyssShopScroll').scroll_vertical==0,'new store starts at the top rather than inheriting previous store offset')
  var stock:Array=app.model.abyss_shop_items()
  var blessings:Array=stock.filter(func(item):return item.kind=='blessing')
  check(stock.size()==5 and blessings.size()==3,'new shop offers three run-long blessings plus heal and energy supplies')
  for shop_item in blessings:
   var coins:int=app.model.state.abyss.rogue.temporaryCurrency
   var button=target('RunShop_'+str(shop_item.id))
   await reveal_shop_action(button)
   var offset_before:int=target('AbyssShopScroll').scroll_vertical
   await click(button)
   check(absi(target('AbyssShopScroll').scroll_vertical-offset_before)<=1,'same-store purchase preserves actual locally scrolled position')
   visible_control(target('RunShop_'+str(shop_item.id)),'just-purchased lower-row item remains visible in place')
   inspect_card(app.model.state.abyss.rogue.selectedRewards.back(),1)
   check(app.model.state.abyss.rogue.temporaryCurrency==coins-int(shop_item.cost),'real shop charges the currently quoted doubled price exactly once')
   check(target('RunShop_'+str(shop_item.id)).disabled,'purchased actual blessing immediately becomes sold out')
   await capture('v241-shop-reward-'+str(resolution.x)+'-'+str(shop_item.id))
   await click_at(target('RogueRewardGain').get_global_rect().get_center())
  check(app.model.state.abyss.rogue.selectedRewards.size()==3,'three purchases yield exactly three genuine run-long rewards')
  app.model.state.abyss.rogue.temporaryCurrency=0;app.model._generate_abyss_shop();app._render_screen();await frames()
  for item in app.model.abyss_shop_items():check(target('RunShop_'+str(item.id)).disabled,'insufficient currency disables every real shop purchase')
  check(target('RogueRewardGain')==null,'mere stock rendering never fabricates an award')
 # A second genuine purchase can arrive while the first feedback remains open.
 prepare('shop');app.model.state.abyss.rogue.temporaryCurrency=10000;app.model._generate_abyss_shop();app._render_screen();await frames()
 var successive:Array=app.model.abyss_shop_items().filter(func(item):return item.kind=='blessing')
 for index in 2:
  var button=target('RunShop_'+str(successive[index].id))
  await reveal_shop_action(button);await click(button)
  inspect_card(app.model.state.abyss.rogue.selectedRewards.back(),1)
 check(app.model.state.abyss.rogue.selectedRewards.size()==2,'successive purchases commit exactly one reward each')
 check(app.get_children().filter(func(node):return node.name=='RogueRewardGain').size()==1,'successive awards retain one stable current reward card')
 app.navigate('home');await frames()
 # A real reward is removed when changing screen, retaining its committed model grant.
 prepare();await frames();await click(target('NodeChoice_offering'))
 app.navigate('home');await frames()
 check(target('RogueRewardGain')==null,'changing screen clears old reward card')
 # No reward and failed transactions never fabricate a gain card.
 prepare();await frames();await click(target('NodeChoice_leave'))
 check(target('RogueRewardGain')==null,'currency-only event does not show a blessing card')
 prepare();await frames();before=app.model.state.duplicate(true);app.model.save_blocked=true
 await click(target('NodeChoice_offering'))
 check(target('RogueRewardGain')==null and app.model.state==before,'failed persistence neither shows nor grants a reward')
 app.model.save_blocked=false
 # Opening a modal or replacing the run clears the old card without firing its callback.
 prepare();await frames();app.abyss_auto_continue=true
 await click(target('NodeChoice_offering'))
 app._modal('独立弹层',400,240);await frames()
 check(target('RogueRewardGain')==null and app.current_screen=='abyss','modal opening cancels gain card and pending automatic continuation')
 app._clear_overlay();app.abyss_auto_continue=false
 prepare();await frames();await click(target('NodeChoice_offering'))
 var original_run:String=str(app.model.state.abyss.rogue.runId)
 app.model.state.abyss.rogue.runId=original_run+'-replaced';await frames()
 check(target('RogueRewardGain')==null,'reward card cannot survive a changed run identity')
 # Countdown uses real elapsed presentation time, including under reduced motion.
 prepare();await frames();await click(target('NodeChoice_offering'))
 var expiry_before:Dictionary=app.model.state.duplicate(true)
 var duration:float=target('RogueRewardGain').remaining
 await create_timer(duration+.2).timeout;await frames()
 check(target('RogueRewardGain')==null and app.model.state==expiry_before,'natural expiration clears feedback without mutating committed rewards')
 # Context changes cancel old automatic callbacks before a later real continuation test.
 prepare();await frames();app.abyss_auto_continue=true
 await click(target('NodeChoice_offering'))
 app.abyss_panel='meta';app._render_screen();await frames()
 check(target('RogueRewardGain')==null and app.current_screen=='abyss','panel change cancels old automatic continuation')
 app.abyss_auto_continue=false
 # Auto-continue waits for identification, then the still-current run resumes once.
 prepare();await frames();app.abyss_auto_continue=true
 await click(target('NodeChoice_offering'))
 check(app.current_screen=='abyss' and target('RogueRewardGain')!=null,'auto-continue waits while real reward remains readable')
 await click_at(target('RogueRewardGain').get_global_rect().get_center());await frames(8)
 check(app.current_screen=='battle','dismissal resumes actual next battle once')
 app.abyss_auto_continue=false
 app.queue_free();await frames();await create_timer(.3).timeout
 print('ROGUE REWARD GAIN: %d checks, %d failures'%[checks,failures]);quit(1 if failures else 0)
