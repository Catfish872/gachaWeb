extends SceneTree
const Game=preload("res://scripts/game_model.gd")
var errors:Array=[]
func must(r:Dictionary,label:String):
 if not r.get("success",false):errors.append(label+str(r))
func _init():
 var g=Game.new("");var x=g.extraction
 var rows:Array=[];var summaries:Array=[]
 var hashes:Dictionary={}
 for p in ["scripts/extraction_model.gd","scripts/game_model.gd","data/extraction.json","tools/simulate_key_rooms_v8.gd"]:hashes[p]=FileAccess.get_sha256("res://"+p)
 var args:=OS.get_cmdline_user_args()
 var samples:=int(args[0]) if args.size()>0 else 256
 var seed_base:=int(args[1]) if args.size()>1 else 25800000
 var output:=args[2] if args.size()>2 else "res://validation/key-rooms-v8-calibration.json"
 for rank in [0,5]:
  for act in [1,2,3]:
   for bag_kind in ["empty","half_materials","full_materials","full_mixed"]:
    var group:={"rank":rank,"act":act,"bag":bag_kind,"runs":samples,"gross":0,"marginalValue":0,"netResale":0,"netRecycle":0,"positiveResale":0,"positiveRecycle":0,"remainingItems":0,"remainingCells":0}
    for n in range(samples):
     g.state=g.default_state();g.rng.seed=seed_base+n
     x.state().unlockedDifficulty=rank;must(x.buy_keys("key_ruins",1),"key buy");must(x.start_run(rank),"start")
     x.run().phase="room";x.run().act=act;x.run().room.type="key_vault";x.run().map.districts[0].theme="ruins";x.run().room.districtId=x.run().map.districts[0].id
     var ids:Array=[]
     if bag_kind=="half_materials":ids.resize(15);ids.fill("wire")
     elif bag_kind=="full_materials":ids.resize(30);ids.fill("wire")
     elif bag_kind=="full_mixed":ids=["medkit","medkit","medkit","medkit","medkit","medkit","wire","wire","wire","wire","wire","wire"]
     var before_value:=0
     for id in ids:
      var item:Dictionary=x._make_item(id);item.revealed=true;item.originAct=1
      if not x._place(x.run().bag,item,x.dimensions("bag")):errors.append("fixture pack")
      before_value+=x.item_value(item)
     x._prepare_room_actions("key_vault");must(x.choose_room_action("unlock"),"key open")
     var gross:=0
     for c in x.containers():
      for item in c.items:gross+=x.item_value(item)
      while x.reveal_next(c.id).get("success",false):pass
      must(x.take_all_revealed(c.id),"pickup")
      var plan:Dictionary=x.plan_smart_loot(c.id)
      if plan.success:must(x.apply_smart_loot(c.id,plan.planHash),"smart swap")
     var after_value:=0
     for item in x.run().bag:after_value+=x.item_value(item)
     var left:=0;var left_cells:=0
     for c in x.containers():
      left+=c.items.size()
      for item in c.items:left_cells+=x._size(item).x*x._size(item).y
     var gain:=after_value-before_value
     var cost:int=x.item_def("key_ruins").buyPrice
     var net:=gain-cost;var recycle:=int(floor(gain*0.6))-cost
     var row:={"rank":rank,"act":act,"bag":bag_kind,"seed":seed_base+n,"gross":gross,"marginalValue":gain,"netResale":net,"netRecycle":recycle,"remainingItems":left,"remainingCells":left_cells}
     rows.append(row)
     for k in ["gross","marginalValue","netResale","netRecycle","remainingItems","remainingCells"]:group[k]+=row[k]
     group.positiveResale+=int(net>=0);group.positiveRecycle+=int(recycle>=0)
    summaries.append(group);print(JSON.stringify(group))
 for p in hashes:
  if hashes[p]!=FileAccess.get_sha256("res://"+p):errors.append("source changed "+p)
 var report:={"rows":rows,"groups":summaries,"errors":errors,"hashes":hashes,"method":"Conditional on reaching and opening independently generated themed key room. Actual purchased key consumed, actual 30-cell capacity, six generated items, reveal/take-all/protected smart-swap APIs. Marginal bag value subtracts original contents. 100% sale or60% field-recycling less150 key price reported separately, no survival/time claims. Four capacity profiles; same seeds paired by room rank/act. Mixed fixture protects six2x2 medicine kits, making capacity opportunity cost visible."}
 var f=FileAccess.open(output,FileAccess.WRITE);f.store_string(JSON.stringify(report,"\t"))
 print("KEY ROOM SIM ",rows.size()," rooms ",rows.size()*2," boxes ",errors.size()," errors");quit(0 if errors.is_empty() else 1)
