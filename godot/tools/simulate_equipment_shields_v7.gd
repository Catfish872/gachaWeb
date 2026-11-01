extends SceneTree
const Game=preload("res://scripts/game_model.gd")
const Battle=preload("res://scripts/battle_model.gd")
var errors:Array=[]
var fixtures:Dictionary={}
func must(r:Dictionary,label:String)->bool:
	if not r.get("success",false):errors.append(label+str(r));return false
	return true
func fixture(profile:String,seed_value:int):
	var key:=profile+str(seed_value)
	var g=Game.new("")
	if fixtures.has(key):g.state=fixtures[key].state.duplicate(true);g.rng.state=fixtures[key].rng;return g
	g.rng.seed=seed_value
	var team:Array=["ember","zeph"] if profile=="starter" else (["kaldi","ayla","gus"] if profile=="graduate" else ["kaldi","cinder","gus"])
	for id in team:
		g.state.ownedCharacters[id]=g.default_character()
		g.state.ownedCharacters[id].level=1 if profile=="starter" else 10
		g.state.ownedCharacters[id].constellation=0 if profile=="starter" else 6
	g.set_team(team);g.state.resources.gold=1000000
	if profile!="starter":
		for id in team:
			for slot in g.catalog.RelicSlots:
				var relic:Dictionary=g.generate_relic(5,slot.id)
				must(g.add_relic(relic),"relic");must(g.upgrade_relic_to_max(relic.uid),"upgrade");must(g.equip_relic(relic.uid,id),"equip")
	fixtures[key]={"state":g.state.duplicate(true),"rng":g.rng.state}
	return g
func shield_by_unit(b)->Dictionary:
	var result:Dictionary={}
	for unit in b.state.allies:
		var amount:=0
		for s in unit.statuses:
			if s.get("source","")=="expedition_equipment" and s.duration>0:amount+=int(s.shieldHp)
		result[unit.uid]=amount
	return result
func course(profile:String,tier:int,act:int,repair:bool,seed_value:int)->Dictionary:
	var g=fixture(profile,seed_value);var x=g.extraction
	var rank:=0 if profile=="starter" else 5
	x.state().unlockedDifficulty=rank
	must(x.buy_supply("armor_"+str(tier)),"armor buy");must(x.set_utility_slot("armor",x.state().stash.back().uid),"armor equip")
	must(x.start_run(rank),"start");x.run().act=act
	var row:={"profile":profile,"risk":rank,"tier":tier,"act":act,"repair":repair,"seed":seed_value,"battles":[],"normalRemaining":1.0,"bossEntered":false}
	for n in range(4):
		if not x.active():break
		if not x.growth_choices().is_empty():must(x.choose_growth(x.growth_choices()[0].choiceId),"growth")
		if n==3:
			row.normalRemaining=float(x.state().utility.armor.condition)
			if repair:
				x.run().phase="room"
				x._container("repair fixture",1,0)
				var c:Dictionary=x.run().containers.back();var item:Dictionary=x._make_item("repair_core");item.revealed=true;c.items=[item]
				if x.can_use_consumable("repair_core"):must(x.use_container_item(c.id,item.uid),"field repair")
			row.bossEntered=true
		x.run().node=mini(n+1,4);x.run().phase="room"
		x._generate_encounter("boss" if n==3 else "battle")
		var b=Battle.new(g.catalog);var started:Dictionary=x.start_battle(b)
		if not must(started,"battle"):break
		var record:={"kind":"boss" if n==3 else "normal","start":int(b.state.equipmentShieldRemaining),"max":int(started.config.equipmentShieldMax),"end":0,"hits":0,"absorbed":0,"firstMemberBreakHit":-1,"allBreakHit":-1,"won":false,"steps":0}
		var guard:=0
		var target_hits:Dictionary={}
		while b.state.phase not in ["victory","defeat"] and guard<2500:
			guard+=1
			var before:=shield_by_unit(b)
			var result:Dictionary=b.auto_step()
			for event in result.get("events",[]):
				if event.type=="damage" and str(event.actor).begins_with("enemy_") and str(event.target).begins_with("ally_"):
					record.hits+=1
					target_hits[event.target]=int(target_hits.get(event.target,0))+1
				if event.type=="shield" and event.get("source","")=="expedition_equipment":record.absorbed+=int(event.amount)
			var after:=shield_by_unit(b)
			for id in before:
				if before[id]>0 and after[id]==0 and record.firstMemberBreakHit<0:record.firstMemberBreakHit=int(target_hits.get(id,0))
			if int(b.state.equipmentShieldRemaining)==0 and record.start>0 and record.allBreakHit<0:record.allBreakHit=record.hits
		record.end=int(b.state.equipmentShieldRemaining);record.won=b.state.phase=="victory";record.steps=int(b.state.steps)
		if record.start-record.end!=record.absorbed:errors.append("shield accounting")
		row.battles.append(record)
		must(x.settle_battle(started.config,b.state),"settle")
	return row
func _init()->void:
	var samples:=16
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--samples="):samples=int(a.trim_prefix("--samples="))
	var hashes:Dictionary={}
	for p in ["scripts/extraction_model.gd","scripts/battle_model.gd","scripts/game_model.gd","data/extraction.json"]:hashes[p]=FileAccess.get_sha256("res://"+p)
	var rows:Array=[]
	for profile in ["starter","graduate","offense"]:
		for tier in [0,1,2,3,4,5]:
			for act in [1]:
				for repair in [false,true]:
					for n in range(samples):rows.append(course(profile,tier,act,repair,14300000+n))
		print("SHIELD PROFILE ",profile," done")
	for p in hashes:
		if hashes[p]!=FileAccess.get_sha256("res://"+p):errors.append("source changed: "+p)
	var report:={"rows":rows,"errors":errors,"hashes":hashes,"samples":samples,"method":"Fixed real encounter course: three ordinary encounters then boss at act1. Full legal C6 five-star+25 random relics; same paired seeds; first offered earned blessings; no optional room healing. Actual damage/shield events. Source shielding uses existing shield status. This is a combat boundary course, not full map player win rate."}
	var f=FileAccess.open("res://validation/equipment-shields-v7-final.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"\t"))
	print("SHIELD COURSES ",rows.size()," errors ",errors.size());quit(0 if errors.is_empty() else 1)
