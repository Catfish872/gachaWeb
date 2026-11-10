extends SceneTree
const Avatars = preload('res://scripts/ui/character_avatar.gd')
const Bust = preload('res://scripts/ui/character_bust.gd')
const OUT = 'res://validation/v293-avatar-review/'
const TORSO_X = {'raisa':630.0, 'vika':445.0, 'eve':515.0}
var app
var checks := 0
var failures := 0
func ck(ok: bool, label: String):
 checks += 1
 if not ok:
  failures += 1
  push_error(label)
func _initialize():call_deferred('run')
func frames(n=8):
 for i in n:await process_frame
func capture(label):
 if DisplayServer.get_name() == 'headless':return
 await RenderingServer.frame_post_draw
 ck(root.get_texture().get_image().save_png(OUT+label+'.png') == OK, 'capture '+label)
func run():
 DirAccess.make_dir_recursive_absolute(OUT)
 app=load('res://main.tscn').instantiate();root.add_child(app);await frames();app.set_process(false)
 app.model=load('res://scripts/game_model.gd').new('')
 for id in app.model.catalog.CharacterData:app.model.state.ownedCharacters[id]=app.model.default_character()
 app.model.state.team=['raisa','vika','eve']
 for id in TORSO_X:
  var texture = Avatars.get_texture(id,'bust')
  ck(texture.resource_path == Avatars.source_path(id),'full original artwork '+id)
  ck(texture.get_image().has_mipmaps(),'minification mipmaps '+id)
  for frame in [Vector2(190,110),Vector2(225,215),Vector2(350,320)]:
   var region = Avatars.region_for(id,'bust')
   var rects = Bust.composition_rects(Rect2(Vector2.ZERO,frame),texture.get_size(),region)
   var scale = rects[0].size.x/rects[1].size.x
   var torso_x = rects[0].position.x+(TORSO_X[id]-rects[1].position.x)*scale
   ck(absf(torso_x-frame.x*.5)<1.0,'torso centered in circular stage '+id+str(frame))
  for height in [24,38,58,74,138,180,270]:
   var fixture = Control.new();root.add_child(fixture)
   var portrait=app._portrait(fixture,id,height)
   var art=portrait.get_node('CharacterPortraitTexture')
   ck(art.texture_filter==CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS,'smooth small and full portrait '+id+str(height))
   ck(portrait.get_meta('portrait_mode')==('face' if height<=80 else 'full'),'portrait mode preserved '+id+str(height))
   fixture.queue_free()
 for resolution in [Vector2i(960,540),Vector2i(1440,810)]:
  root.size=resolution;await frames()
  app.character_filter='全部';app.navigate('party');await frames()
  for id in TORSO_X:
   var stage=app.find_child('PortraitEnvironment_'+id,true,false)
   ck(stage!=null,'party card exists '+id)
   var portrait=stage.find_child('CharacterPortraitTexture',true,false)
   ck(portrait.texture_filter==CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS,'party smoothing '+id)
   ck(portrait.composition_region==Avatars.region_for(id,'bust'),'party curated framing '+id)
  await capture(str(resolution.x)+'-party')
  for id in TORSO_X:
   app.selected_character=id;app.navigate('growth');await frames()
   var stage=app.find_child('PortraitEnvironment_'+id,true,false)
   ck(stage!=null,'growth card exists '+id)
   ck(stage.find_child('CharacterPortraitTexture',true,false).composition_region==Avatars.region_for(id,'bust'),'growth framing '+id)
   await capture(str(resolution.x)+'-growth-'+id)
   app._summon_character_preview(id);await frames()
   var preview=app.overlay.find_child('PortraitEnvironment_'+id,true,false)
   ck(preview!=null,'traveler archive preview exists '+id)
   ck(preview.find_child('CharacterPortraitTexture',true,false).composition_region==Avatars.region_for(id,'bust'),'archive preview framing '+id)
   await capture(str(resolution.x)+'-archive-'+id)
   app._clear_overlay();await frames(2)
 app.queue_free();await frames()
 print('THUNDER AVATAR FRAMING V293: %d checks, %d failures' % [checks,failures])
 quit(1 if failures else 0)
