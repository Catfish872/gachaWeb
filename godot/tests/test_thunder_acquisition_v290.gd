extends SceneTree
const Game=preload("res://scripts/game_model.gd")
const Battle=preload("res://scripts/battle_model.gd")
var checks:=0
var failures:Array=[]
func ck(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func _init()->void:
	for kind in ["raisa","vika","eve","trio"]:
		var game=Game.new("")
		var original:Dictionary=game.state.duplicate(true)
		var start:Dictionary=game.prepare_thunder_trial(kind)
		ck(start.success,"trial prepare "+kind)
		ck(game.state==original,"trial preserves roster and property "+kind)
		var battle=Battle.new(game.catalog)
		battle.start(start.config,start.config.partySnapshot)
		var steps:=0;var forms:=0;var actions:Array=[]
		while battle.state.phase not in ["victory","defeat"] and steps<500:
			var result:Dictionary=battle.auto_step()
			ck(result.success,"trial auto action "+kind)
			for event in result.get("events",[]):
				if event.type=="state_change" and event.get("form","")=="armor":forms+=1
				if event.type=="skill":actions.append(event.skill_id)
			steps+=1
		ck(battle.state.phase=="victory","trial winnable "+kind)
		if kind in ["raisa","trio"]:
			ck(forms>0 and actions.has("raisa_armor_normal") and actions.has("raisa_armor_skill") and actions.has("raisa_armor_ult"),"trial demonstrates entire armor rotation "+kind)
		var result:Dictionary=game.finish_battle(start.config,battle.state)
		ck(result.success and int(result.rewards.diamonds)==(0 if kind=="trio" else 160),"first trial reward "+kind)
		ck(not game.finish_battle(start.config,battle.state).success,"repeated settlement rejected "+kind)
		var again:Dictionary=game.prepare_thunder_trial(kind)
		var repeat:Dictionary=game.finish_battle(again.config,{"phase":"victory","turn":5,"config":again.config})
		ck(repeat.success and int(repeat.rewards.diamonds)==0,"repeat trial gives no reward "+kind)
		ck(game.state.ownedCharacters==original.ownedCharacters and game.state.relics==original.relics and game.state.team==original.team,"trial items and party never leak "+kind)
	for id in ["raisa","vika","eve"]:
		var game=Game.new("");var pool_id:String="limited_"+id
		game.state.pityCounters.limited_tiya={"count":72,"count4":8,"guaranteedFeatured":true}
		game.state.pityCounters[pool_id]={"count":89,"count4":9,"guaranteedFeatured":true}
		var old:Dictionary=game.state.pityCounters.limited_tiya.duplicate(true)
		var balance:int=game.state.resources.diamonds
		var pulled:Dictionary=game.pull(pool_id,1)
		ck(pulled.success,"limited pull "+id)
		ck(game.state.ownedCharacters.has(id),"hard featured guarantee "+id)
		ck(game.state.resources.diamonds==balance-160,"exact pull currency "+id)
		ck(game.state.pityCounters.limited_tiya==old,"old limited pity retained "+id)
		ck(game.state.pityCounters[pool_id].count==0 and not game.state.pityCounters[pool_id].guaranteedFeatured,"new pity reset after featured "+id)
	print("THUNDER_ACQUISITION_V290 ",checks," checks / ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
