extends SceneTree
var app
var checks:=0
var failures:=0
func _initialize():call_deferred('run')
func frames():
 for i in 10:await process_frame
func ck(ok:bool,label:String):
 checks+=1
 if not ok:failures+=1;push_error(label)
func all_nodes(n:Node)->Array:
 var list:Array=[]
 for child in n.get_children():list.append(child);list.append_array(all_nodes(child))
 return list
func modes(n:Node,kind:String)->Array:
 return all_nodes(n).filter(func(c):return c.has_meta('portrait_mode') and c.get_meta('portrait_mode')==kind)
func capture(key:String):
 if DisplayServer.get_name()=='headless':return
 await RenderingServer.frame_post_draw
 var folder='/workspace/scratch/8f1fc457a062/avatar-ui-v24'
 DirAccess.make_dir_recursive_absolute(folder)
 root.get_texture().get_image().save_png(folder+'/'+key+'-'+str(root.size.x)+'.png')
func run():
 app=load('res://main.tscn').instantiate();root.add_child(app);await frames();app.set_process(false)
 var fixture:=Control.new();root.add_child(fixture)
 for id in app.model.catalog.CharacterData:
  for height in [24,38,58,74]:
   var c=app._portrait(fixture,str(id),height)
   ck(c.get_meta('portrait_mode')=='face','small '+str(id)+' uses curated face')
   ck(c.get_node('CharacterPortraitTexture').texture is AtlasTexture,'atlas-backed avatar')
   c.queue_free()
  for height in [138,180,270]:
   var c=app._portrait(fixture,str(id),height)
   ck(c.get_meta('portrait_mode')=='full','large '+str(id)+' stays full body')
   ck(not c.get_node('CharacterPortraitTexture').texture is AtlasTexture,'large texture unchanged')
   c.queue_free()
 fixture.queue_free();await frames()
 for resolution in [Vector2i(960,540),Vector2i(1170,540)]:
  root.size=resolution;await frames()
  for screen in ['home','party','growth','extraction']:
   app.navigate(screen);await frames()
   ck(modes(app.main_body,'face').size()>=2,screen+' visible portraits are readable faces')
   if screen=='party':ck(modes(app.main_body,'bust').size()==10,'candidate roster has ten bust portraits')
   if screen=='growth':ck(modes(app.main_body,'full').size()==1,'growth showcase remains full body')
   ck(Rect2(Vector2.ZERO,app.size).encloses(app.shell.get_global_rect()),screen+' layout fits')
   await capture(screen)
  app.model.mark_dialogue_seen('ch1_1_pre')
  var prepared:Dictionary=app.model.prepare_stage('ch1_1')
  app._start_battle(prepared.config);app.set_process(false);await frames()
  ck(modes(app.main_body,'face').size()>=2,'turn order uses ally faces')
  ck(modes(app.main_body,'full').size()>=app.battle.state.allies.size(),'combat actor art remains full body')
  for actor in app.unit_cards.values():
   ck(modes(actor,'face').is_empty(),'battle actor never switches to face art')
  await capture('battle')
  app.model.abandon_battle(app.battle_config,app.battle.state);app.battle_settled=true
 app.queue_free();await frames();await create_timer(.3).timeout
 print('AVATAR UI V24: %d checks, %d failures'%[checks,failures]);quit(1 if failures else 0)
