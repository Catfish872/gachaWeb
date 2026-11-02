extends SceneTree
const GameModel = preload("res://scripts/game_model.gd")
var failed := 0
var passed := 0
func check(ok: bool, label: String) -> void:
	if ok: passed += 1; print("PASS: " + label)
	else: failed += 1; push_error("FAIL: " + label)
func item(uid: String, id: String) -> Dictionary:
	return {"uid":uid,"itemId":id,"x":0,"y":0,"rotated":false,"revealed":true}
func _initialize() -> void:
	call_deferred("run_tests")
func run_tests() -> void:
	var model = GameModel.new("")
	var ex = model.extraction
	var gold: int = model.state.resources.gold
	ex.state().stash = ex._packed_copy([item("guard_a","guardian_seal"),item("guard_b","guardian_seal"),item("blade_a","blade"),item("scope_a","scope")],Vector2i(10,12))
	check(ex.equip_item("guard_a").success,"camp equips independent UID")
	check(ex.state().tactical.size()==1 and ex.state().stash.size()==3,"equipped leaves stash")
	check(not ex.equip_item("guard_b").success,"same ID rejected with empty slots")
	check(ex.equip_item("blade_a").success and ex.equip_item("scope_a").success,"three distinct tactical effects coexist")
	check(not ex.sell_item("guard_a").success,"single sell protects worn UID")
	check(ex.sell_items(["guard_a","blade_a","scope_a","guard_b"]).success,"batch sell skips all worn UIDs")
	check(ex.state().tactical.size()==3 and ex.state().stash.is_empty(),"bulk sale preserves all three slots")
	check(model.state.resources.gold==gold+ex.item_value(item("guard_b","guardian_seal")),"bulk pays only idle item")
	check(model.valid_save(model.state),"camp save validates unique UID ownership")
	var saved: Dictionary = model.state.duplicate(true)
	model.state = model._normalize(saved)
	check(ex.equipped_items()[0].uid=="guard_a","reload preserves worn identity")
	check(ex.start_run().success,"start with persistent gear")
	check(ex.state().tactical.is_empty() and ex.run().equipped.size()==3 and ex.run().bag.is_empty(),"departure transfers gear to equipped, not bag")
	check(model.valid_save(model.state),"departure save validates")
	check(ex.sort_grid("bag").success and ex.run().equipped.size()==3,"automatic packing keeps worn inventory separate")
	ex.run().phase="room"
	ex.run().containers=[{"id":"gear_crate","width":6,"height":8,"items":[item("container_guard","guardian_seal")],"name":"gear","kind":"supply","revealed":1,"quality":0}]
	check(not ex.equip_container_item("gear_crate","container_guard","blade_a").success,"container direct equip enforces same-family rule")
	check(ex.equip_container_item("gear_crate","container_guard","guard_a").success,"container replacement preserves displaced item")
	check(ex.run().containers[0].items[0].uid=="guard_a","container receives exact replaced UID")
	check(ex.equip_container_item("gear_crate","guard_a","container_guard").success,"container swap roundtrip restores UID")
	ex.run().containers=[]
	ex.run().phase="boss_exit"
	check(ex.extract().success,"extract with gear")
	check(ex.state().tactical.size()==3 and ex.state().stash.is_empty(),"extraction preserves equipment separate from loot")
	check(ex.unequip_item("guard_a").success and ex.sell_item("guard_a").success,"explicit unequip allows sale")
	check(ex.equip_item("missing").success==false,"missing equip fails")
	check(ex.state().tactical.size()==2,"failed operation preserves slots")
	# Synthetic future rarity variant checks the effect family without broad buff exclusion.
	ex.data.items.future_guard = ex.data.items.guardian_seal.duplicate(true)
	ex.data.items.future_guard.effects[0].value=-0.2
	ex.state().stash=ex._packed_copy([item("g1","guardian_seal"),item("g2","future_guard")],Vector2i(10,12))
	check(ex.equip_item("g1").success,"equip reduction family")
	check(not ex.equip_item("g2","blade_a").success,"different reduction ID cannot replace unrelated slot")
	check(ex.equip_item("g2","g1").success,"explicit same-family replacement succeeds")
	check(ex.state().stash.size()==1 and ex.state().stash[0].uid=="g1","replacement returns old UID")
	var legacy = GameModel.new("")
	var le = legacy.extraction
	check(le.start_run().success,"legacy fixture starts")
	le.run().equipped=[item("old_a","guardian_seal"),item("old_b","guardian_seal"),item("old_c","blade")]
	le.state().erase("equipmentRules")
	var before_gold: int = legacy.state.resources.gold
	check(legacy.valid_save(legacy.state),"legacy duplicates accepted before migration")
	legacy.state=legacy._normalize(legacy.state)
	check(le.run().equipped.size()==2 and le.run().bag.size()==1,"legacy duplicate returned to bag")
	check(legacy.state.resources.gold==before_gold and legacy.valid_save(legacy.state),"migration preserves wallet and valid save")
	var migrated: Dictionary=legacy.state.duplicate(true)
	legacy.state=legacy._normalize(legacy.state)
	check(legacy.state==migrated,"migration idempotent")
	# Issued battle remains unchanged; migration happens at the safe transaction boundary.
	le.run().equipped.append(le.run().bag.pop_back())
	le.run().phase="battle"
	le.state().erase("equipmentRules")
	legacy.state=legacy._normalize(legacy.state)
	check(le.run().equipped.size()==3 and int(le.state().equipmentRules)==0,"issued battle retains original equipment")
	le.run().phase="route"
	check(le._commit(legacy.state.duplicate(true)).success and le.run().equipped.size()==2,"next safe commit resolves duplicate")
	# Overflow uses existing mailbox and keeps every physical UID.
	le.run().equipped.append(le.run().bag.pop_back())
	le.run().bag=[]
	for n in 30: le.run().bag.append(item("fill_%d"%n,"healer_charm"))
	le.run().bag=le._packed_copy(le.run().bag,Vector2i(6,5))
	le.state().equipmentRules=0
	le._migrate_equipment(le.state())
	check(le.run().equipped.size()==2 and le.state().mailbox.size()==1,"full bag sends migrated duplicate to mailbox")
	check(legacy.valid_save(legacy.state),"overflow migration validates")
	print("EQUIPMENT V276: %d passed, %d failed" % [passed,failed])
	quit(1 if failed else 0)
