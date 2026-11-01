extends "res://tests/test_rogue_reward_gain.gd"

func capture(label:String)->void:
 if DisplayServer.get_name()=="headless":return
 await RenderingServer.frame_post_draw
 var suffix:String="before" if "--capture-before" in OS.get_cmdline_user_args() else "after"
 root.get_texture().get_image().save_png("res://validation/abyss-active-footer-v250/"+label+"-"+suffix+".png")

func run()->void:
 if "--require-gl" in OS.get_cmdline_user_args() and DisplayServer.get_name()=="headless":
  push_error("Active footer verification requires a real GL window");quit(2);return
 DirAccess.make_dir_recursive_absolute("res://validation/abyss-active-footer-v250")
 app=load("res://main.tscn").instantiate();root.add_child(app);await frames(12);app.set_process(false)
 app.extraction_reduced_motion=true
 for resolution in [Vector2i(1280,720),Vector2i(2340,1080),Vector2i(2048,945)]:
  root.size=resolution;await frames(12)
  for phase in ["reward","route","shop","event","rest","none"]:
   prepare(phase)
   var rogue:Dictionary=app.model.state.abyss.rogue
   if phase=="reward":
    var reward:Dictionary=app.model.catalog.AbyssData.rogue.rewards[0].duplicate(true)
    reward.choiceId="footer-choice";rogue.pendingChoices=[reward]
   elif phase=="shop":app.model._generate_abyss_shop()
   app._render_screen();await frames(8)
   var target_name:Control=target("AbyssRunTargetName")
   visible_control(target_name,"active target name fully visible "+phase)
   for item_name in ["AbyssDailyCard","AbyssDailyMilestone","AbyssDailyPaid","AbyssDailyNext"]:
    visible_control(target(item_name),"daily information remains visible "+phase+" "+item_name)
   var footer_buttons:Array=[]
   var build:Button
   for button in app.main_body.find_children("*","Button",true,false):
    if button.text.begins_with("构筑 "):build=button;footer_buttons.append(button)
    elif button.text.begins_with("连续挑战") or button.text in ["队伍","归营"]:footer_buttons.append(button)
   check(footer_buttons.size()==4,"all four fixed run footer actions exist "+phase)
   for button in footer_buttons:
    visible_control(button,"fixed footer fully visible "+phase+" "+button.text)
    check(button.size.y>=44,"footer touch target at least 44 logical pixels")
    var parent=button.get_parent();var scrolled:=false
    while parent!=app and parent!=null:
     if parent is ScrollContainer and parent.vertical_scroll_mode!=ScrollContainer.SCROLL_MODE_DISABLED:scrolled=true
     parent=parent.get_parent()
    check(not scrolled,"footer action is outside scrolling content")
   var before:Dictionary=app.model.state.duplicate(true)
   await capture(str(resolution.x)+"-"+phase)
   await click(build)
   check(app.overlay.get_child_count()>0,"actual build tap opens overlay "+phase)
   var close:Button
   for button in app.overlay.find_children("*","Button",true,false):
    if button.text=="返回":close=button;break
   await click(close)
   check(app.overlay.get_child_count()==0 and app.model.state==before,"build open/close preserves run and target")
 app.queue_free();await frames();await create_timer(.3).timeout
 print("ABYSS ACTIVE FOOTER V250: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
