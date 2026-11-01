extends SceneTree
const Game=preload("res://scripts/game_model.gd")
const Battle=preload("res://scripts/battle_model.gd")
var checks:=0
var failures:=0
func ck(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",label)
func at_abyss():
	var g=Game.new("");g.rng.seed=241900;g.prepare_abyss();g._issued_config={};g.state.abyss.rogue.activeEncounter={}
	return g
func attack_definition(g)->Dictionary:return g._reward_definition("common_atk_white")
func effect_sum(effects:Array)->float:
	var sum:=0.0
	for effect in effects:
		if effect.get("type")=="stat" and effect.get("stat")=="atkMult":sum+=float(effect.value)
	return sum
func actual_attack(g,raid:bool,copies:int)->void:
	var party:Array=g.extraction.battle_party() if raid else g.battle_party(true)
	var effects:Array=g.extraction.effects() if raid else g.rogue_effects()
	ck(is_equal_approx(effect_sum(effects),copies*.08),"every blessing instance reaches combat effects")
	var ids:Dictionary={}
	for effect in effects:
		if effect.get("rewardId")=="common_atk_white":
			ck(not ids.has(effect.rewardInstanceId),"combat receives a unique identity per stack")
			ids[effect.rewardInstanceId]=true
	var battle=Battle.new(g.catalog)
	battle.start({"id":"stack_probe","isAbyss":not raid,"isExtraction":raid,"enemies":["wolf"],"waves":[{"enemies":["wolf"]}],"scaleMult":1.0,"seed":81},party,effects)
	for index in range(party.size()):
		ck(battle.state.allies[index].stats.atk==int(float(party[index].stats.atk)*(1.0+effect_sum(effects))),"actual stack attack base=%s copies=%d expected=%d actual=%s"%[str(party[index].stats.atk),copies,int(float(party[index].stats.atk)*(1.0+effect_sum(effects))),str(battle.state.allies[index].stats.atk)])
func test_abyss()->void:
	for copies in [4,10,100,250]:
		var g=at_abyss();var reward:=attack_definition(g)
		for index in copies-1:g.state.abyss.rogue.selectedRewards.append(reward.duplicate(true))
		ck(g._available_abyss_rewards().any(func(entry):return entry.id==reward.id),"same blessing remains in abyss pool after earlier copies")
		var choice:Dictionary=reward.duplicate(true);choice.choiceId="choice_attack"
		g.state.abyss.rogue.nextStep={"type":"reward","floor":0};g.state.abyss.rogue.pendingChoices=[choice]
		var before:Dictionary=g.state.duplicate(true);g.save_blocked=true
		ck(not g.choose_abyss_reward(choice.choiceId).success and g.state==before,"large-stack choice rollback")
		g.save_blocked=false
		ck(g.choose_abyss_reward(choice.choiceId).success and g.state.abyss.rogue.selectedRewards.size()==copies,"repeat blessing chosen beyond former cap")
		actual_attack(g,false,copies)
		ck(g.valid_save(g.state),"unlimited abyss stack save validates")
		g.save_dir="/tmp/unlimited-blessings-v241/abyss_%d"%copies;ck(g.save_game(),"actual abyss file saved")
		var loaded=Game.new(g.save_dir)
		ck(not loaded.save_blocked and loaded.state.abyss.rogue.selectedRewards.size()==copies,"actual abyss file reload retains every stack")
		actual_attack(loaded,false,copies)
		# The shop exposes distinct definitions while permitting another owned copy.
		g.state.abyss.rogue.nextStep={"type":"shop","floor":0};g.state.abyss.rogue.pendingNode={"id":"shop_0","type":"shop"};g.state.abyss.rogue.temporaryCurrency=1000
		g._generate_abyss_shop();var offered:Dictionary={}
		for entry in g.abyss_shop_items():
			if entry.kind=="blessing":ck(not offered.has(entry.rewardId),"three shop choices stay distinct regardless of stacks");offered[entry.rewardId]=true
		ck(offered.size()==3,"three unique shop choices remain stocked")
		g.state.abyss.rogue.shopStock=[{"id":"repeat","kind":"blessing","rewardId":reward.id,"sold":false}]
		ck(g.purchase_abyss_item("repeat").success and g.state.abyss.rogue.selectedRewards.size()==copies+1,"shop can sell next copy at any owned stack count")
func test_extraction()->void:
	for copies in [4,10,100,250]:
		var g=Game.new("");g.rng.seed=241900;var x=g.extraction;x.start_run();x.run().phase="room"
		var reward:=attack_definition(g)
		for index in copies-1:
			var owned:Dictionary=reward.duplicate(true);owned.instanceId=x._uid("blessing");owned.pickedAtAct=1;x.run().blessings.append(owned)
		ck(x._growth_pool().any(func(entry):return entry.id==reward.id),"same blessing remains in extraction pool")
		var choice:Dictionary=reward.duplicate(true);choice.choiceId=x._uid("choice");x.run().pendingChoices=[choice]
		var before:Dictionary=g.state.duplicate(true);g.save_blocked=true
		ck(not x.choose_growth(choice.choiceId).success and g.state==before,"extraction large-stack choice rollback")
		g.save_blocked=false
		ck(x.choose_growth(choice.choiceId).success and x._growth_count(reward.id)==copies,"extraction repeated choice surpasses old cap")
		ck(x.growth_summary().size()==1 and x.growth_summary()[0].stacks==copies,"build summary reports all current stacks")
		actual_attack(g,true,copies)
		ck(g.valid_save(g.state),"extraction arbitrary stack count validates")
		g.save_dir="/tmp/unlimited-blessings-v241/extraction_%d"%copies;ck(g.save_game(),"actual extraction file saved")
		var loaded=Game.new(g.save_dir)
		ck(not loaded.save_blocked and loaded.extraction.run().blessings.size()==copies,"actual extraction file reload retains every unique instance")
		actual_attack(loaded,true,copies)
		x._offer_growth();var offered:Dictionary={}
		for entry in x.growth_choices():ck(not offered.has(entry.id),"single extraction choice screen remains distinct");offered[entry.id]=true
		ck(offered.size()==3,"stack counts do not exhaust three extraction choices")
		# UID duplication is still malformed, independently of legitimate same-id stacks.
		var bad:Dictionary=g.state.duplicate(true);bad.extraction.run.blessings[1].instanceId=bad.extraction.run.blessings[0].instanceId
		ck(not g.valid_save(bad),"duplicate physical blessing instance rejected without growth cap")
func test_legacy_fallback()->void:
	var g=at_abyss()
	for definition in g.catalog.AbyssData.rogue.rewards:
		for n in 3:g.state.abyss.rogue.selectedRewards.append(definition.duplicate(true))
	g.state.abyss.currentFloor=31;g.state.abyss.rogue.floorsCleared=30
	g.state.abyss.savedPartyState=[]
	for unit in g.battle_party(false):g.state.abyss.savedPartyState.append({"id":unit.id,"currentHp":unit.maxHp,"maxHp":unit.maxHp,"energy":0,"cooldowns":{}})
	g.state.abyss.rogue.nextStep={"type":"rest","floor":30};g.state.abyss.rogue.pendingNode={"id":"rest_30","type":"rest","exhausted":true}
	var legacy:Dictionary=g.state.duplicate(true);var seed_state:int=g.rng.state
	ck(g.valid_save(legacy),"old capped-pool fallback save accepted")
	g.state=g._normalize(legacy)
	ck(g.state.abyss.rogue.nextStep.type=="reward" and g.state.abyss.rogue.pendingChoices.size()==3,"old cap-exhausted node restores normal owed blessing choice")
	ck(g.state.abyss.rogue.selectedRewards==legacy.abyss.rogue.selectedRewards and g.state.resources==legacy.resources and g.rng.state==seed_state,"migration keeps all rewards assets and main RNG unchanged")
	for option in g.state.abyss.rogue.pendingChoices:ck(option.rarity=="gold","old milestone resumes its gold choice tier")
	var before:Dictionary=g.state.duplicate(true);g.state=g._normalize(g.state);ck(g.state==before,"unlimited fallback migration idempotent")
	var other=Game.new("");other.state=other._normalize(JSON.parse_string(JSON.stringify(legacy)))
	ck(other.state.abyss.rogue.pendingChoices==g.state.abyss.rogue.pendingChoices,"deterministic migration survives serialized numeric types")
	ck(g.valid_save(g.state),"restored choices produce valid save")
	var old_shop:Dictionary=legacy.duplicate(true)
	old_shop.abyss.rogue.nextStep={"type":"shop","floor":30};old_shop.abyss.rogue.pendingNode={"id":"shop_30","type":"shop"}
	old_shop.abyss.rogue.shopStock=[{"id":"heal","kind":"heal","sold":true},{"id":"energy","kind":"energy","sold":false}]
	other.state=other._normalize(old_shop)
	ck(other.state.abyss.rogue.shopStock.size()==5 and other.state.abyss.rogue.shopStock[0].sold,"previously cap-empty shop restores three repeatable offers without resetting sold stock")
	ck(other.state.abyss.rogue.selectedRewards==old_shop.abyss.rogue.selectedRewards and other.state.abyss.rogue.temporaryCurrency==old_shop.abyss.rogue.temporaryCurrency,"old empty shop top-up preserves every owned copy and wallet")
	# Only a genuinely empty definition pool falls back to a temporary supply choice.
	g=at_abyss();g.catalog.AbyssData.rogue.rewards=[];g._set_after_floor(30)
	ck(g.state.abyss.rogue.pendingChoices.is_empty() and g.state.abyss.rogue.pendingNode.poolUnavailable,"empty data pool uses safe fallback")
	ck(g.node_options().options.size()==2 and g.choose_abyss_node("echo_supply").success,"real empty pool offers usable continuation")
func _init()->void:
	test_abyss();test_extraction();test_legacy_fallback()
	print("UNLIMITED BLESSINGS V241 ",checks," checks ",failures," failures");quit(0 if failures==0 else 1)
