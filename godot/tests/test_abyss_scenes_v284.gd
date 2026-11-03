extends "res://tests/test_lantern_journey_ui_v270.gd"
const OUT284="res://validation/v284-abyss-scenes/"
func fixture284(floor_no:int=11):
 var g=Game.new("");g.rng.seed=284;g._init_rogue_run();g.state.abyss.currentFloor=floor_no;g.state.abyss.rogue.floorsCleared=floor_no-1
 if floor_no>1:
  g.state.abyss.savedPartyState=[]
  for u in g.battle_party(false):g.state.abyss.savedPartyState.append({"id":u.id,"currentHp":u.stats.maxHp,"maxHp":u.stats.maxHp,"energy":0,"cooldowns":{}})
 return g
func capture(label:String)->void:
 if DisplayServer.get_name()=="headless":return
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(OUT284+label+".png")
func scene_checks()->void:
 var g=fixture284();var opts:Array=g.abyss_scene_options();ck(opts.size()==15,"15 equiprobable nondefault maps")
 for f in [1,10]:
  ck(g.abyss_scene_from_roll(f,.99).theme=="","first ten fixed "+str(f))
 ck(g.abyss_scene_from_roll(11,.249999).theme=="","default lower quarter")
 ck(g.abyss_scene_from_roll(11,.25).theme==opts[0].theme,"inclusive nondefault boundary")
 var unique:Dictionary={}
 for i in range(15):
  var s:Dictionary=g.abyss_scene_from_roll(11,.25+.75*(i+.5)/15.0)
  ck(s.theme==opts[i].theme and s.depth==opts[i].depth,"uniform bin "+str(i));unique[str(s.theme)+str(s.depth)]=true
  ck(ResourceLoader.exists(s.background),"scene texture exists "+str(i))
  for f in [11,15,20]:
   var pool:Array=g.abyss_scene_enemy_pool(f,s);ck(not pool.is_empty(),"scene pool nonempty "+str(i)+"/"+str(f))
   for id in pool:
    ck(g.catalog.EnemyData.has(id),"pool enemy registered "+str(id))
   if str(s.theme) in ["ruins","forest","sanctum"]:
    var allowed:Array=["wolf","goblin","fire_imp","ice_wolf","thunder_hawk"] if f==11 else ["dark_knight","stone_golem"] if f==15 else ["boss_flame_lord","boss_storm_witch"]
    ck(pool.all(func(id):return id in allowed),"old theme enemy union only")
   if f==20 and s.theme in ["lantern","windpass"]:ck(pool==["boss_hedor" if s.theme=="lantern" else "boss_highland_roc"],"single thematic boss")
  ck(g.abyss_boss_music_track(s)==({"lantern":"lantern_core","windpass":"windpass_road"}.get(s.theme,"determined_pursuit")),"preserved boss score")
 ck(unique.size()==15,"no missing or duplicate probability slot")
 var r:int=g.rng.state;g._ensure_abyss_scene(1);ck(g.rng.state==r,"first block consumes no rng")
 var calls={"count":0}
 g.random_source=func():calls.count+=1;return .81
 var a:Dictionary=g._ensure_abyss_scene(11);r=g.rng.state;var count_before:int=calls.count
 ck(g._ensure_abyss_scene(20)==a and g.rng.state==r and calls.count==count_before,"same block frozen")
 ck(g._ensure_abyss_scene(21).startFloor==21 and calls.count==count_before+2,"21 creates next block once")
 for f in [1,10,11,20,21]:
  g=fixture284(f);g.random_source=func():return .81
  var issued:Dictionary=g.prepare_abyss();ck(issued.get("success",false),"actual prepare "+str(f))
  if not issued.get("success",false):print(issued);continue
  var config:Dictionary=issued.config;r=g.rng.state
  ck(config.abyssScene.startFloor==1+10*int((f-1)/10),"issued block boundary")
  ck(config.background==config.abyssScene.background,"issued frozen background")
  ck(g.prepare_abyss().config==config and g.rng.state==r,"resume exact config no reroll")
  var decoded:Dictionary=JSON.parse_string(JSON.stringify(g.state));ck(g.valid_save(decoded),"serialized scene save valid")
  var restored=Game.new("");restored.state=restored._normalize(decoded.duplicate(true));restored.rng.state=r
  ck(JSON.parse_string(JSON.stringify(restored.prepare_abyss().config))==decoded.abyss.rogue.activeEncounter and restored.rng.state==r,"decoded save resumes same issued config")
  var legacy:Dictionary=decoded.duplicate(true);legacy.abyss.rogue.erase("sceneBlocks")
  for key in ["abyssScene","abyssMusic","abyssBossMusic"]:legacy.abyss.rogue.activeEncounter.erase(key)
  var old=Game.new("");old.state=legacy;r=old.rng.state
  ck(old.prepare_abyss().config==legacy.abyss.rogue.activeEncounter and old.rng.state==r,"legacy issued preserved")
  var plain:Dictionary=config.duplicate(true)
  for key in ["abyssScene","abyssMusic","abyssBossMusic","background"]:plain.erase(key)
  var b1=Battle.new(g.catalog);var b2=Battle.new(g.catalog);b1.start(config,g.battle_party(true));b2.start(plain,g.battle_party(true))
  ck(b1.state.enemies.size()==b2.state.enemies.size(),"same enemy quota")
  for j in range(b1.state.enemies.size()):ck(b1.state.enemies[j].stats==b2.state.enemies[j].stats,"scene metadata does not change combat stats")
func ui_checks()->void:
 app=load("res://main.tscn").instantiate();root.add_child(app);await frames(10);app.set_process(false)
 var opts:Array=app.model.abyss_scene_options()
 for i in range(15):
  fresh();app.model=fixture284(11);var s:Dictionary=app.model.abyss_scene_from_roll(11,.25+.75*(i+.5)/15.0);app.model.state.abyss.rogue.sceneBlocks={"11":s}
  app.current_screen="abyss";ck(app._music_track_for_context()==app.model.abyss_music_track(s),"actual abyss menu track "+str(i))
  var normal:String=app._music_track_for_context();app.current_screen="growth";ck(app._music_track_for_context()==normal,"functional page preserves scene score")
  app.current_screen="battle";app.battle_config={"isAbyss":true,"abyssScene":s,"abyssMusic":normal,"abyssBossMusic":app.model.abyss_boss_music_track(s),"isBoss":false,"enemies":["wolf"]}
  ck(app._music_track_for_context()==normal,"ordinary scene score")
  app.battle_config.isBoss=true;ck(app._music_track_for_context()==app.model.abyss_boss_music_track(s),"actual boss scene score")
 for size in [Vector2i(960,540),Vector2i(2048,945)]:
  root.size=size;await frames(5)
  for theme in ["","lantern","windpass"]:
   fresh();app.model=fixture284(11);var s:Dictionary=app.model.abyss_scene_from_roll(11,0)
   for i in range(opts.size()):
    if opts[i].theme==theme and int(opts[i].depth)==1:s=app.model.abyss_scene_from_roll(11,.25+.75*(i+.5)/15.0)
   app.model.state.abyss.rogue.sceneBlocks={"11":s};app.navigate("abyss");await frames(10)
   ck(app.model.abyss_background_path()==s.background,"actual menu scene background "+theme)
   await capture(str(size.x)+"-abyss-"+("default" if theme=="" else theme))
 app.queue_free();await frames(3)
func run()->void:
 DirAccess.make_dir_recursive_absolute(OUT284)
 scene_checks()
 if failures==0:await ui_checks()
 print("ABYSS SCENES V284: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
