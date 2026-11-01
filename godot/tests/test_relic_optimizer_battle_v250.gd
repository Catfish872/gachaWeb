extends SceneTree
const Game=preload("res://scripts/game_model.gd")
const Optimizer=preload("res://scripts/relic_optimizer.gd")
var checks:=0
var failures: Array=[]
func _initialize() -> void: call_deferred("run")
func ck(value: bool,label: String) -> void:
	checks+=1
	if not value: failures.append(label); push_error(label)
func run() -> void:
	var game=Game.new("")
	for char_id in ["ember","zeph","bolt","gus","kaldi","cinder"]:
		game.state.ownedCharacters[char_id]=game.default_character()
		for critical in [0.0,1.0]:
			for energy_rate in [0.0,0.32,0.74]:
				var search=Optimizer.new(game,char_id)
				var stats: Dictionary=game.computed_stats_for_relic_loadout(char_id,[])
				stats.cri=critical;stats.critRate=critical;stats.energyRate=energy_rate
				var effects: Array=[{"type":"energyOnCrit","value":4},{"type":"damageVsStatus","statusId":"burn","value":0.2},{"type":"damageWhenFasterThanTarget","value":0.2}]
				var prediction: float=search._evaluate(stats,effects)
				var reference: Dictionary=search._reference(stats,effects)
				var battle=search._battle
				var actor: Dictionary=reference.actor
				var damage:=0.0
				for action in range(6):
					# The benchmark fixes targets' speed/status rather than pricing control.
					for target in battle.state.enemies:
						target.statuses=[]
						for status in search._context.targetStatuses: target.statuses.append({"id":status,"duration":99,"value":null,"stacks":1})
					var available: Array=battle._available(actor)
					var chosen: String=str(available[0])
					for sid in available:
						var kind: String=game.catalog.SkillData[sid].type
						if kind=="ultimate": chosen=sid;break
						if kind=="skill":chosen=sid
					battle._events=[]
					battle._execute_skill(actor,chosen)
					for event in battle._events:
						if event.type=="damage":damage+=int(event.amount)
					for sid in actor.cooldowns: actor.cooldowns[sid]=maxi(0,int(actor.cooldowns[sid])-1)
				ck(absf(prediction-damage)<0.000001,"six-auto predictor/live "+char_id+" crit="+str(critical)+" energy="+str(energy_rate))
	# A full-HP heal has zero actual HP gain while the declared potential remains positive.
	game.state.ownedCharacters.shana=game.default_character()
	var healer=Optimizer.new(game,"shana")
	var stats: Dictionary=game.computed_stats_for_relic_loadout("shana",[])
	var ref: Dictionary=healer._reference(stats,[])
	var battle=healer._battle
	battle._events=[]
	battle._execute_skill(ref.actor,"shana_skill")
	var actual:=0
	for event in battle._events:
		if event.type=="heal":actual+=int(event.amount)
	ck(actual==0 and healer.preview().before.objective>0,"full-HP actual zero and sufficient-missing-HP potential remain distinct")
	print("RELIC OPTIMIZER BATTLE V250: %d checks; %d failures"%[checks,failures.size()])
	quit(1 if not failures.is_empty() else 0)
