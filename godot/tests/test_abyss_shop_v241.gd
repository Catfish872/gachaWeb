extends SceneTree
const Game=preload("res://scripts/game_model.gd")
var checks:=0
var failures:=0
func ck(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",label)
func fresh(floor_number:int=5,seed_value:int=241550):
	var g=Game.new("");g.rng.seed=seed_value;g.prepare_abyss();g._issued_config={};g.state.abyss.rogue.activeEncounter={}
	g.state.abyss.currentFloor=floor_number+1;g.state.abyss.rogue.floorsCleared=floor_number
	g.state.abyss.savedPartyState=[]
	for u in g.battle_party(false):g.state.abyss.savedPartyState.append({"id":u.id,"currentHp":int(u.maxHp*.5),"maxHp":u.maxHp,"energy":0,"cooldowns":{"flame_strike":2}})
	g.state.abyss.rogue.temporaryCurrency=2000;g._set_after_floor(floor_number)
	return g
func prices(g)->void:
	var prior:Dictionary=g.state.duplicate(true)
	var seen:Dictionary={};var blessings:=0
	for entry in g.abyss_shop_items():
		if entry.kind=="heal":ck(entry.cost==70,"healing price doubles 35 to 70")
		elif entry.kind=="energy":ck(entry.cost==60,"energy price doubles 30 to 60")
		else:
			blessings+=1
			ck(entry.cost==int({"white":55,"blue":85,"gold":140}[entry.rarity])*2,"blessing exact double cost "+entry.rarity)
			ck(not seen.has(entry.rewardId),"three distinct blessing definitions")
			seen[entry.rewardId]=true
	ck(blessings==3 and g.abyss_shop_items().size()==5,"three ongoing blessings plus two existing supplies")
	ck(g.state==prior,"shop price view stays read only")
func _init()->void:
	for seed_value in range(30):
		for floor_number in [5,15,25,45]:
			var g=fresh(floor_number,241550+seed_value);prices(g)
			ck(g.valid_save(g.state),"five-item generated shop save valid")
	var g=fresh()
	var original:Dictionary=g.state.duplicate(true)
	for entry in g.abyss_shop_items():
		g.state=original.duplicate(true);g.state.abyss.rogue.temporaryCurrency=entry.cost-1
		var before:Dictionary=g.state.duplicate(true)
		ck(not g.purchase_abyss_item(entry.id).success and g.state==before,"new insufficient price blocks atomically")
		g.state=original.duplicate(true);before=g.state.duplicate(true);g.save_blocked=true
		ck(not g.purchase_abyss_item(entry.id).success and g.state==before,"failed shop purchase restores currency sold and effects")
		g.save_blocked=false;var amount:int=g.state.abyss.rogue.temporaryCurrency
		var result:Dictionary=g.purchase_abyss_item(entry.id)
		ck(result.success and result.cost==entry.cost and g.state.abyss.rogue.temporaryCurrency==amount-entry.cost,"purchase charges new exact displayed amount")
		before=g.state.duplicate(true);ck(not g.purchase_abyss_item(entry.id).success and g.state==before,"sold entry cannot be repurchased")
	# Legacy pending stock keeps every original item identity, purchase flag and payment.
	g=fresh(15);g.state.abyss.rogue.shopStock.pop_back()
	g.state.abyss.rogue.shopStock[0].sold=true;g.state.abyss.rogue.shopStock[2].sold=true
	var sold_reward:Dictionary=g._reward_definition(g.state.abyss.rogue.shopStock[2].rewardId).duplicate(true)
	sold_reward.pickedAtFloor=15;g.state.abyss.rogue.selectedRewards.append(sold_reward)
	g.state.abyss.rogue.temporaryCurrency=137
	var legacy:Dictionary=g.state.duplicate(true);var original_stock:Array=legacy.abyss.rogue.shopStock.duplicate(true)
	ck(g.valid_save(legacy),"released four-entry pending shop accepted")
	var rng_before:int=g.rng.state;g.state=g._normalize(legacy)
	ck(g.rng.state==rng_before,"legacy top-up consumes no live RNG")
	ck(g.state.abyss.rogue.shopStock.size()==5 and g.state.abyss.rogue.shopStock.slice(0,4)==original_stock,"migration only appends third blessing")
	ck(g.state.abyss.rogue.temporaryCurrency==137 and g.state.abyss.rogue.selectedRewards==legacy.abyss.rogue.selectedRewards and g.state.resources==legacy.resources,"old purchases and wallet retain exact value without extra charge")
	ck(not g.purchase_abyss_item("heal").success and not g.purchase_abyss_item("blessing_0").success,"previously sold entries remain sold")
	var migrated:Dictionary=g.state.duplicate(true);g.state=g._normalize(g.state)
	ck(g.state==migrated and g.rng.state==rng_before,"shop migration idempotent with stable RNG")
	var other=Game.new("");other.rng.seed=9999;var other_rng:int=other.rng.state;other.state=other._normalize(legacy)
	ck(other.state.abyss.rogue.shopStock==g.state.abyss.rogue.shopStock and other.rng.state==other_rng,"same old run adds deterministic item regardless of runtime RNG")
	other.state=other._normalize(JSON.parse_string(JSON.stringify(legacy)))
	ck(other.state.abyss.rogue.shopStock==g.state.abyss.rogue.shopStock,"serialized numeric floor representation keeps migration selection stable")
	for entry in g.abyss_shop_items():
		if entry.kind=="energy":ck(entry.cost==60,"old unsold supply uses new price")
		if entry.kind=="blessing":ck(entry.cost in [110,170,280],"old blessing uses new rarity price")
	ck(g.valid_save(g.state),"migrated five-item shop validates")
	# Existing copies never deplete the pool; same-shop uniqueness is independent.
	for copies in [3,10,100]:
		g=fresh();var definitions:Array=g._available_abyss_rewards();g.state.abyss.rogue.selectedRewards=[]
		for definition in definitions:
			for n in copies:g.state.abyss.rogue.selectedRewards.append(definition.duplicate(true))
		g._generate_abyss_shop()
		var stock:Array=g.abyss_shop_items().filter(func(entry):return entry.kind=="blessing")
		ck(stock.size()==3,"owned stacks leave three distinct store blessings available")
		for entry in stock:ck(g.purchase_abyss_item(entry.id).success,"existing stacks remain purchasable")
		g._generate_abyss_shop();ck(g.abyss_shop_items().size()==5,"new shop remains fully stocked after repeat purchases")
		var before:Dictionary=g.state.duplicate(true);g.state=g._normalize(g.state)
		ck(g.state==before and g.valid_save(g.state),"large repeated blessing inventory persists")
	g=fresh();var blessing:Dictionary=g.abyss_shop_items()[2]
	for n in 3:g.state.abyss.rogue.selectedRewards.append(g._reward_definition(blessing.rewardId).duplicate(true))
	ck(g.purchase_abyss_item(blessing.id).success,"fourth copy of unsold blessing is purchasable")
	# Actual shop leave and next shop generation refresh stock once for a new floor.
	g=fresh();g.purchase_abyss_item("heal");ck(g.leave_abyss_shop().success and g.state.abyss.rogue.shopStock.is_empty(),"leaving clears this floor stock")
	g.state.abyss.currentFloor=16;g.state.abyss.rogue.floorsCleared=15;g._set_after_floor(15)
	ck(g.abyss_shop_items().size()==5 and g.abyss_shop_items().all(func(entry):return not entry.sold),"next floor shop is fresh with three blessings")
	var before:Dictionary=g.state.duplicate(true);rng_before=g.rng.state
	for n in 10:g.abyss_shop_items()
	ck(g.state==before and g.rng.state==rng_before,"repeated display does not refresh or advance RNG")
	g.reset_abyss();g.state.abyss.meta.currency=1000
	ck(g.meta_upgrade_list()[0].cost==12 and g.purchase_meta_upgrade("vitality").cost==12,"camp permanent memory shop retains original prices")
	print("ABYSS SHOP V241 ",checks," checks ",failures," failures");quit(0 if failures==0 else 1)
