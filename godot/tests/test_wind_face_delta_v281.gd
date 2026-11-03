extends "res://tests/test_wind_portraits_v281.gd"
func run() -> void:
 app=load("res://main.tscn").instantiate();root.add_child(app);await frames(12);app.set_process(false);fresh()
 for id in app.model.catalog.CharacterData:app.model.state.ownedCharacters[id]=app.model.default_character()
 root.size=Vector2i(960,540);await frames(8)
 var holder=Control.new();app.add_child(holder)
 for id in ["tiya","lumi"]:
  var face=Avatars.get_texture(id,"face")
  ck(face is AtlasTexture,"dedicated face crop "+id)
  ck(face.atlas.resource_path=="res://assets/content_v280/portraits/%s.png"%id,"face source "+id)
  ck(face.region==Avatars.FACE_REGIONS[id],"exact curated crop "+id)
  for height in [24,36,38,44,45,58,66,73,74]:
   var p=app._portrait(holder,id,height)
   ck(p.get_node("CharacterPortraitTexture").texture==face,"face caller "+id+str(height));p.free()
  ck(Avatars.get_texture(id,"bust").resource_path==Avatars.source_path(id),"bust source unchanged "+id)
 ck(Avatars.get_texture("selin","face").resource_path=="res://assets/content_v270/portraits/selin_face.png","legacy face unchanged")
 holder.free();app.model.state.team=["tiya","lumi","selin"]
 for id in ["tiya","lumi"]:
  app.selected_character=id;app.growth_panel="stats";app.navigate("growth");await frames(8)
  var roster=app.find_child("GrowthSelect_"+id,true,false)
  ck(roster.find_child("CharacterPortraitTexture",true,false).texture==Avatars.get_texture(id,"face"),"real roster crop "+id)
  await capture("960-face-delta-"+id)
 app.queue_free();await frames(4)
 print("WIND FACE DELTA V281: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
