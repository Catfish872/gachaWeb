extends SceneTree
const Game=preload("res://scripts/game_model.gd")
const Battle=preload("res://scripts/battle_model.gd")
const TEAMS={"fire":["kaldi","selin","ayla"],"wind":["tiya","lumi","ayla"],"thunder_duo":["raisa","vika","ayla"],"thunder":["raisa","vika","eve"],"kaldi":["kaldi"],"tiya":["tiya"],"raisa":["raisa"]}
func _init() -> void:
	var rows:Array=[]
	var basis_game=Game.new("");basis_game.rng.seed=29041
	var basis:Array=[]
	for slot in ["helmet","chest","belt","boots","necklace"]:
		var item:Dictionary=basis_game.generate_relic(5,slot,"")
		while int(item.level)<25:basis_game._upgrade_relic_one(item)
		basis.append(item)
	for rank in [0,6]:
		for count in [1,3]:
			for defense in [100,1000,35000]:
				for name in TEAMS:
					var game=Game.new("")
					for id in TEAMS[name]:
						game.state.ownedCharacters[id]=game.default_character();game.state.ownedCharacters[id].level=10;game.state.ownedCharacters[id].constellation=rank
						var sets:Dictionary={"kaldi":"flame_oath","selin":"ember_lantern","ayla":"aurora_prayer","tiya":"wind_blades","lumi":"wind_strings","raisa":"storm_armor","vika":"storm_tracer","eve":"storm_shelter"}
						for original in basis:
							var item:Dictionary=original.duplicate(true);item.uid=id+str(original.slotId);item.setId=sets[id];item.equippedBy=id
							game.state.relics.append(item);game.state.ownedCharacters[id].equippedRelics[item.slotId]=item.uid
					game.state.team=TEAMS[name]
					var b=Battle.new(game.catalog)
					var enemies:Array=[]
					for i in count:enemies.append("boss_flame_lord")
					b.start({"enemies":enemies,"seed":29041},game.battle_party(false))

					for enemy in b.state.enemies:enemy.stats.def=defense;enemy.maxHp=100000000;enemy.currentHp=enemy.maxHp;enemy.element="neutral"
					var total:=0.0;var out:Dictionary={};var by_actor:Dictionary={}
					for turn in range(48):
						for actor in b.state.allies:
							var available:Array=b._available(actor);var sid:String=available[0]
							for skill in available:
								if b._hold_healing_skill(actor,b.skill_data(skill)):continue
								if b.skill_data(skill).type=="ultimate":sid=skill;break
								if b.skill_data(skill).type=="skill":sid=skill
							b._events=[];b._execute_skill(actor,sid);b._after_active_action(actor)
							for event in b._events:
								if event.type=="damage" and not b.get_unit(event.target).isAlly:
									total+=event.amount
									var owner:String=b.get_unit(event.get("actor","")).get("id","dot");by_actor[owner]=float(by_actor.get(owner,0))+event.amount
						b._events=[];b._end_round()
						for event in b._events:
							if event.type=="damage" and not b.get_unit(event.target).isAlly:total+=event.amount
						b._build_queue()
						if turn+1 in [6,12,24,48]:out[str(turn+1)]=total
					rows.append({"team":name,"rank":rank,"targets":count,"defense":defense,"output":out,"byActor":by_actor})
	DirAccess.make_dir_recursive_absolute("res://validation/v290-thunder")
	var f=FileAccess.open("res://validation/v290-thunder/calibration.json",FileAccess.WRITE);f.store_string(JSON.stringify(rows,"  "))
	print("THUNDER_CALIBRATION ",rows.size()," rows");quit()
