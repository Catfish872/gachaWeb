extends SceneTree
const Game=preload("res://scripts/game_model.gd")
var checks:=0
var failures:=0
func ck(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;printerr("FAIL ",label)
func make(x,id:String,value:int=-1)->Dictionary:
 var item:Dictionary=x._make_item(id);item.revealed=true
 if value>=0:item.legacyValue=value
 return item
func setup():
 var g=Game.new("");g.rng.seed=24800000;g.extraction.start_run();g.extraction.run().phase="room";return g
func box(x)->Dictionary:
 x.run().containers=[];x._container("fixture",0,0);return x.run().containers[0]
func _init()->void:
 var g=setup();var x=g.extraction
 ck(g.state.version==9 and g.valid_save(g.state),"v8 valid")
 # An actual valid 25-cell arrangement was falsely rejected by greedy packing.
 for pos in [Vector2i(4,3),Vector2i(1,0),Vector2i(3,0),Vector2i(2,2)]:
  var item:=make(x,"medkit");item.x=pos.x;item.y=pos.y;x.run().bag.append(item)
 var c:=box(x);var egg:=make(x,"dragon_egg");c.items=[egg]
 ck(x.take_item(c.id,egg.uid).success,"legal complex repack succeeds")
 ck(x.run().bag.size()==5 and c.items.is_empty(),"repack conserves five instances")
 for item in x.run().bag:ck(x._fits(x.run().bag,item,x.dimensions("bag")),"repacked cells disjoint")
 # Real one-cell vacancies across every bag size and position.
 for height in range(5,11):
  for hole in range(height*6):
   g=setup();x=g.extraction
   if height>5:x.state().utility.backpack={"uid":"pack","itemId":"pack_"+str(height-5),"x":0,"y":0,"rotated":false,"revealed":true}
   for cell in range(height*6):
    if cell==hole:continue
    var item:=make(x,"bandage");item.x=cell%6;item.y=int(cell/6);x.run().bag.append(item)
   c=box(x);var gold:=make(x,"gold_watch");c.items=[gold]
   ck(x.take_item(c.id,gold.uid).success,"one cell gold pickup")
   ck(x.run().bag.size()==height*6 and c.items.is_empty(),"one cell conservation")
 # Manual choice may replace protected cheap supplies or choose lower value.
 g=setup();x=g.extraction
 for n in range(30):x._place(x.run().bag,make(x,"bandage"),x.dimensions("bag"))
 for supply in x.run().bag:x.set_consumable_exchange_lock(supply.uid,true)
 c=box(x);var gold:=make(x,"gold_watch");c.items=[gold]
 ck(not x.plan_smart_loot(c.id).success,"automatic keeps protected supplies")
 var outgoing:String=x.run().bag[12].uid
 var plan:Dictionary=x.preview_exchange(c.id,gold.uid,[outgoing])
 ck(plan.success,"manual can explicitly trade protected supply")
 var before:Dictionary=g.state.duplicate(true);g.save_blocked=true
 ck(not x.exchange_items(c.id,gold.uid,[outgoing],plan.planHash).success and g.state==before,"manual exchange rollback")
 g.save_blocked=false
 ck(x.exchange_items(c.id,gold.uid,[outgoing],plan.planHash).success,"manual exchange commits")
 ck(not x.exchange_items(c.id,gold.uid,[outgoing],plan.planHash).success,"manual replay refused")
 c=x._find_container(c.id)
 ck(c.items.size()==1 and c.items[0].uid==outgoing,"old supply remains same container")
 plan=x.preview_exchange(c.id,outgoing,[gold.uid])
 ck(plan.success and plan.gain<0,"lower-price manual trade permitted")
 ck(x.exchange_items(c.id,outgoing,[gold.uid],plan.planHash).success,"intentional lower-value trade commits")
 # Consuming an item truly frees its slot; explicit coordinates stay explicit.
 x.run().party[0].currentHp=1
 var consumed:String=x.run().bag[0].uid
 ck(x.use_item(consumed).success,"consume one-cell medicine")
 c=x._find_container(c.id)
 ck(x.take_item(c.id,gold.uid).success,"one-cell pickup after actual consumption")
 x.run().bag=[];c=box(x);var scope:=make(x,"scope");c.items=[scope]
 before=g.state.duplicate(true)
 ck(not x.take_item_at(c.id,scope.uid,5,4,true).success and g.state==before,"out-of-bounds atomic")
 ck(x.take_item_at(c.id,scope.uid,5,3,true).success,"explicit rotated placement")
 ck(x.run().bag[0].x==5 and x.run().bag[0].y==3 and x.run().bag[0].rotated,"coordinates retained")
 # Full tactical slots can swap directly from the bag atomically.
 x.run().equipped=[make(x,"vest"),make(x,"blade"),make(x,"shield")]
 var old_uid:String=x.run().equipped[0].uid
 ck(x.equip_item(scope.uid,old_uid).success,"bag tactical swap")
 var found:=false
 for item in x.run().bag:
  if item.uid==old_uid:found=true
 ck(found,"old tactical item goes to bag")
 # Keys stack separately while every physical UID and price remains intact.
 x.retreat();var gold_before:int=g.state.resources.gold
 ck(x.buy_keys("key_ruins",3).success,"bulk key purchase")
 ck(x.state().keyring.size()==3 and x.state().stash.is_empty() and g.state.resources.gold==gold_before-1500,"key purchase independent storage")
 var first:String=x.state().keyring[0].uid
 ck(x.keyring()[0].count==3,"stack display")
 ck(x.start_run().success,"keyring departure")
 x.run().phase="room";x.run().room.type="key_vault";x.run().room.districtId=x.run().map.districts[0].id;x.run().map.districts[0].theme="ruins"
 x._prepare_room_actions("key_vault")
 before=g.state.duplicate(true);g.save_blocked=true
 ck(not x.choose_room_action("unlock").success and g.state==before,"FIFO unlock rollback")
 g.save_blocked=false
 ck(x.choose_room_action("unlock").success and x.state().keyring.size()==2,"one ring key consumed")
 ck(x.state().keyring[0].uid!=first,"FIFO exact UID")
 ck(not x.choose_room_action("unlock").success,"key opening once")
 x.run().bag=[]
 for n in range(30):x._place(x.run().bag,make(x,"wire"),x.dimensions("bag"))
 c=box(x);var key:=make(x,"key_forest");c.items=[key]
 ck(x.take_item_at(c.id,key.uid,0,0).success and x.run().bag.size()==30,"full bag key redirected to ring")
 ck(x.state().keyring.size()==3,"picked key independent count")
 ck(x.retreat().success and x.state().keyring.size()==3,"keys persist retreat")
 before=g.state.duplicate(true);g.save_blocked=true
 ck(not x.sell_keys("key_ruins",2).success and g.state==before,"batch key sale rollback")
 g.save_blocked=false
 ck(x.sell_keys("key_ruins",2).success and x.keyring()[0].count==0,"batch key sale exact")
 # Migration moves only owned keys; untouched container keys stay in the world.
 g=setup();x=g.extraction;c=box(x)
 x.state().stash=[make(x,"key_ruins",77)];x.state().loadout=[make(x,"key_forest",88)];x.state().mailbox=[make(x,"key_sanctum",99)]
 x.run().bag=[make(x,"key_ruins",111),make(x,"gold_watch")];c.items=[make(x,"key_forest")]
 var old:Dictionary=g.state.duplicate(true);old.version=7;old.extraction.erase("keyring")
 var container_key:String=c.items[0].uid
 var loot_price:int=x.item_def("gold_watch").v7Value
 g.state=g._normalize(old)
 ck(x.state().keyring.size()==4 and x.state().stash.is_empty() and x.state().loadout.is_empty() and x.state().mailbox.is_empty(),"all owned key scopes migrate")
 ck(x.run().bag.size()==1 and x.item_value(x.run().bag[0])==loot_price,"old loot appraisal retained")
 ck(x.run().containers[0].items[0].uid==container_key,"world key remains unclaimed")
 var ring_values:Array=[]
 for item in x.state().keyring:ring_values.append(x.item_value(item))
 ck(ring_values==[77,88,99,111],"legacy key values exact")
 before=g.state.duplicate(true);g.state=g._normalize(g.state)
 ck(g.state==before,"v8 migration idempotent")
 # Deep provenance is fixed at generation, not changed by carrying through acts.
 g=setup();x=g.extraction
 var shallow:=make(x,"gold_watch");var shallow_value:int=x.item_value(shallow)
 x.run().act=3
 ck(x.item_value(shallow)==shallow_value,"carrying deeper cannot reappraise")
 var deep:=make(x,"gold_watch")
 ck(deep.originAct==3 and x.item_value(deep)>shallow_value,"new deep loot premium")
 # Legacy proceeds remain; all in-run recycling entry points now fail closed.
 x.run().bag=[];x._place(x.run().bag,shallow,x.dimensions("bag"));x._place(x.run().bag,deep,x.dimensions("bag"))
 x.run().salvageGold=123;g.state.resources.gold+=123
 gold_before=g.state.resources.gold
 for kind in ["cache","workshop","relay","boss"]:
  x.run().room.type=kind
  x.run().phase="boss_exit" if kind=="boss" else "room"
  before=g.state.duplicate(true)
  ck(not x.can_salvage() and not x.salvage_quote([shallow.uid]).success,"run recycling disabled "+kind)
  ck(not x.salvage_items([shallow.uid],"legacy-plan").success and g.state==before,"old recycling API preserves assets "+kind)
 ck(x.retreat().success and g.state.resources.gold==gold_before,"legacy proceeds survive retreat")
 ck(x.state().lastRun.salvageGold==123,"historical recycling summary retained")
 ck(g.valid_save(g.state),"final valid")
 # Only gold/red enter new collections; legacy low-rarity records survive.
 x.state().collection=["wire"]
 var entries:Array=[]
 for pair in [["wire","low"],["gold_watch","gold_a"],["gold_watch","gold_b"],["dragon_egg","red"]]:
  var entry:Dictionary={"uid":pair[1],"itemId":pair[0],"x":0,"y":0,"rotated":false,"revealed":true}
  ck(x._place(x.state().stash,entry,x.dimensions("stash")),"collection fixture")
  entries.append(entry)
 ck(not x.collect_item("low").success,"ordinary collection rejected")
 before=g.state.duplicate(true);g.save_blocked=true
 ck(not x.collect_items(["low","gold_a","gold_b","red"]).success and g.state==before,"collection batch atomic rollback")
 g.save_blocked=false
 var collected:Dictionary=x.collect_items(["low","gold_a","gold_b","red"])
 ck(collected.success and collected.count==2,"only gold/red distinct types collected")
 ck("wire" in x.state().collection and x.state().collection.size()==3,"legacy low rarity record retained")
 var survivors:Array=[]
 for entry in x.state().stash:survivors.append(entry.uid)
 ck("low" in survivors and "gold_b" in survivors,"ordinary and duplicate items retained")
 ck(not x.collect_items(["gold_b"]).success,"duplicate collectible not consumed")
 # Actual fixture exported and validated by the preserved released v7 model.
 var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/extraction-v7-active.json"))
 g=Game.new("");x=g.extraction
 ck(g.valid_save(fixture.save),"released v7 fixture accepted before migration")
 g.state=g._normalize(fixture.save)
 ck(g.valid_save(g.state) and g.state.version==9,"released v7 fixture normalizes valid")
 ck(x.state().keyring.size()==4 and x.run().bag.size()==29,"released physical keys migrate from full bag")
 ck(x.state().utility.armor.uid==fixture.armorUid and is_equal_approx(float(x.state().utility.armor.condition),.37),"released equipment identity and wear retained")
 var actual:Dictionary={}
 for list in [x.state().stash,x.state().loadout,x.state().mailbox,x.state().keyring,x.run().bag,x.run().equipped,x.run().containers[0].items,[x.state().utility.armor]]:
  for entry in list:
   ck(not actual.has(entry.uid),"released asset unique after migration")
   actual[entry.uid]=x.item_value(entry)
 for uid in actual:
  ck(fixture.prices.has(uid) and actual[uid]==int(fixture.prices.get(uid,-1)),"released asset price retained "+str(uid))
 ck(actual.size()==fixture.prices.size(),"released asset count retained")
 ck(x.run().containers[0].items[0].uid==fixture.worldKey and x.run().containers[0].items[0].revealed,"released revealed world key not claimed")
 before=g.state.duplicate(true);g.state=g._normalize(g.state)
 ck(g.state==before,"released v7 migration idempotent")
 print("EXTRACTION V8 ",checks," checks ",failures," failures");quit(0 if failures==0 else 1)
