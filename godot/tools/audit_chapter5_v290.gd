extends "res://tools/audit_thunder_natural_v290.gd"
func run() -> void:
	var start:=Time.get_ticks_msec();var rows:Array=[]
	for seed_value in [290051,290052]:
		var basis:Dictionary=natural_basis(seed_value,4,12)
		for team in ["fire","wind","thunder"]:
			var game=natural_game(basis,0,team,5)
			for stage in game.catalog.StageData.chapters.back().stages:
				var config:Dictionary=stage.duplicate(true);config.enemies=stage.waves[0].enemies;config.seed=seed_value
				var battle=Battle.new(game.catalog);battle.start(config,game.battle_party(false))
				var steps:=0
				while battle.state.phase not in ["victory","defeat"] and steps<600:
					var result:Dictionary=battle.auto_step();check(result.get("success",false),"chapter battle action");steps+=1
				var alive:=0;var hp:=0.0;var maximum:=0.0
				for ally in battle.state.allies:alive+=int(ally.currentHp>0);hp+=ally.currentHp;maximum+=ally.maxHp
				check(battle.state.phase in ["victory","defeat"],"battle terminates")
				rows.append({"seed":seed_value,"team":team,"stage":stage.id,"result":battle.state.phase,"turn":battle.state.turn,"alive":alive,"hpRatio":hp/maxf(1.0,maximum)})
	var file=FileAccess.open("res://validation/v290-story/development-balance.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"scope":"96 independent full-health story battles; two fixed seeds; C0 level5; legal four-star +12 relics chosen from four candidates per slot, equal per-role budget, each signature set; no blessings; auto combat. No reward/XP carry-over. A bounded fixture, not a player-population win rate.","rows":rows,"checks":checks,"failures":failures,"elapsedMs":Time.get_ticks_msec()-start},"  "))
	print("CHAPTER5 BALANCE: ",rows.size()," battles; ",checks," checks; ",failures.size()," failures; ms=",Time.get_ticks_msec()-start)
	quit(1 if not failures.is_empty() else 0)
