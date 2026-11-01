extends "res://tests/test_rogue_reward_gain.gd"
func run()->void:
 app=load('res://main.tscn').instantiate();root.add_child(app);await frames(12);app.set_process(false)
 app.extraction_reduced_motion=true
 for resolution in [Vector2i(1280,720),Vector2i(2048,945)]:
  root.size=resolution;await frames(12)
  for owned in [3,9,99,999]:
   prepare('reward');await frames()
   var reward:Dictionary=app.model.catalog.AbyssData.rogue.rewards[0].duplicate(true)
   var rogue:Dictionary=app.model.state.abyss.rogue
   rogue.selectedRewards=[]
   for i in owned:rogue.selectedRewards.append(reward.duplicate(true))
   check(app.model._available_abyss_rewards().any(func(item):return item.id==reward.id),'already-owned reward remains in actual draw pool at '+str(owned)+' stacks')
   reward.choiceId='unlimited-choice';rogue.pendingChoices=[reward]
   app._render_screen();await frames()
   await click(target('Blessing_unlimited-choice'))
   check(rogue.selectedRewards.size()==owned+1,'actual fourth tenth and hundredth reward choices all succeed')
   inspect_card(reward,owned+1)
   var count:Label=target('RogueRewardGainStacks')
   check(count.get_theme_font('font').get_string_size(count.text,HORIZONTAL_ALIGNMENT_LEFT,-1,count.get_theme_font_size('font_size')).x<=count.size.x,'large exact stack count remains fully readable')
   await capture('v241-unlimited-reward-'+str(resolution.x)+'-'+str(owned+1))
   await click_at(target('RogueRewardGain').get_global_rect().get_center())
   check(rogue.selectedRewards.size()==owned+1,'acknowledgement preserves the entire repeated reward inventory')
   var build:Button
   for button in app.main_body.find_children('*','Button',true,false):
    if button.text.begins_with('构筑 '):build=button;break
   await click(build)
   var summary:Label
   for label in app.overlay.find_children('*','Label',true,false):
    if label.text==str(reward.name)+' ×%d'%(owned+1):summary=label;break
   visible_control(summary,'actual build modal retains complete large stack label')
   if owned==999:await capture('v241-unlimited-build-'+str(resolution.x)+'-1000')
   var close:Button
   for button in app.overlay.find_children('*','Button',true,false):
    if button.text=='返回':close=button;break
   await click(close)
   check(app.overlay.get_child_count()==0 and rogue.selectedRewards.size()==owned+1,'closing build preserves all repeated reward instances')
 # Extraction build uses its actual summary formatter with uniquely identified instances.
 for resolution in [Vector2i(1280,720),Vector2i(2048,945)]:
  root.size=resolution;await frames(12)
  app.model=load('res://scripts/game_model.gd').new('')
  var x=app.model.extraction
  check(x.start_run(0).success,'real extraction run for large build presentation')
  var reward:Dictionary=x._growth_pool()[0].duplicate(true)
  for copies in [100,1000]:
   x.run().blessings=[]
   for i in copies:
    var instance:Dictionary=reward.duplicate(true);instance.instanceId=x._uid('blessing');instance.pickedAtAct=1;x.run().blessings.append(instance)
   app.extraction_panel='build';app.navigate('extraction');await frames(12)
   var summary:Label
   for label in app.main_body.find_children('*','Label',true,false):
    if label.text=='叠加 %d 层'%copies:summary=label;break
   visible_control(summary,'extraction build shows actual '+str(copies)+' stacks')
   if summary!=null:check(summary.get_theme_font('font').get_string_size(summary.text,HORIZONTAL_ALIGNMENT_LEFT,-1,summary.get_theme_font_size('font_size')).x<=summary.size.x,'large extraction stack label stays readable')
   check(x.growth_summary()[0].stacks==copies,'summary retains every distinct repeated instance')
   await capture('v241-unlimited-extraction-build-'+str(resolution.x)+'-'+str(copies))
 app.queue_free();await frames();await create_timer(.3).timeout
 print('UNLIMITED REWARD UI V241: %d checks, %d failures'%[checks,failures]);quit(1 if failures else 0)
