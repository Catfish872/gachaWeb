extends SceneTree
const Game=preload("res://scripts/game_model.gd")
const Battle=preload("res://scripts/battle_model.gd")
const Balance=preload("res://scripts/abyss_balance.gd")
# Frozen independent direct transcription of original JS calcInflatedStats.
const EXPECTED = [[1, "boss_flame_lord", 3747, 155, 60, 85], [1, "boss_storm_witch", 5152, 181, 55, 105], [1, "wolf", 369, 56, 20, 90], [50, "boss_flame_lord", 44385, 4426, 1173, 230], [50, "boss_storm_witch", 61029, 5163, 1075, 285], [50, "wolf", 4720, 1482, 391, 244], [100, "boss_flame_lord", 89516, 18238, 3402, 379], [100, "boss_storm_witch", 123085, 21277, 3118, 468], [100, "wolf", 9629, 6092, 1134, 401], [150, "boss_flame_lord", 204423, 54806, 8946, 528], [150, "boss_storm_witch", 281082, 63941, 8200, 652], [150, "wolf", 19287, 20693, 2982, 559], [200, "boss_flame_lord", 844616, 247038, 38686, 677], [200, "boss_storm_witch", 1161347, 288212, 35462, 836], [200, "wolf", 66765, 114200, 12895, 716], [500, "boss_flame_lord", 124008941014, 764889341109, 13807036229, 1569], [500, "boss_storm_witch", 170512293895, 892370897960, 12656449876, 1938], [500, "wolf", 10803918444, 309953684047, 4602345409, 1661]]
var checks:=0
var failures:=0
func ck(value:bool,label:String)->void:
	checks+=1
	if not value:failures+=1;printerr("FAIL ",label)
func config_for(floor_number:int,eid:String,rank:int=3,version:int=3)->Dictionary:
	var config:Dictionary={"isAbyss":true,"difficulty":rank,"floor":floor_number,"enemies":[eid],"seed":42}
	if version>0:config.abyssGrowthVersion=version
	return config
func _init()->void:
	var game=Game.new("")
	for row in EXPECTED:
		var battle=Battle.new(game.catalog)
		battle.start(config_for(int(row[0]),str(row[1])),game.battle_party(true))
		var enemy:Dictionary=battle.state.enemies[0]
		ck([int(enemy.maxHp),int(enemy.stats.atk),int(enemy.stats.def),int(enemy.stats.spd)]==[int(row[2]),int(row[3]),int(row[4]),int(row[5])],"web exact spawn %s floor %d" %[row[1],row[0]])
	for rank in range(3):
		for eid in ["wolf","boss_flame_lord"]:
			var config:Dictionary=config_for(50,eid,rank)
			var battle=Battle.new(game.catalog);battle.start(config,game.battle_party(true))
			var mods:Dictionary=Balance.apply_difficulty(Balance.scale(50,game.catalog.EnemyData[eid]),rank)
			var base:Dictionary=game.catalog.EnemyData[eid].baseStats
			var expected:Array=[int(base.hp*mods.hpMod),int(base.atk*mods.atkMod),int(base.def*mods.defMod),minf(145.0,float(base.spd)*float(mods.spdMod))]
			var enemy:Dictionary=battle.state.enemies[0]
			ck([enemy.maxHp,enemy.stats.atk,enemy.stats.def,enemy.stats.spd]==expected,"bounded rank %d %s unchanged" %[rank,eid])
	var old_config:Dictionary=config_for(100,"boss_flame_lord",3,0)
	var old_battle=Battle.new(game.catalog);old_battle.start(old_config,game.battle_party(true))
	ck(old_battle.state.enemies[0].maxHp==90702 and old_battle.state.enemies[0].stats.def==142,"already-issued endless keeps original budget")
	var extraction:Dictionary={"isExtraction":true,"difficulty":3,"floor":100,"abyssGrowthVersion":3,"enemies":["boss_flame_lord"],"scaleMult":{"hpMod":2.0,"atkMod":3.0,"defMod":4.0,"spdMod":5.0}}
	var expedition=Battle.new(game.catalog);expedition.start(extraction,game.battle_party(true))
	ck(expedition.state.enemies[0].maxHp==8000 and expedition.state.enemies[0].stats.atk==360 and expedition.state.enemies[0].stats.def==240 and expedition.state.enemies[0].stats.spd==120,"extraction scale and speed cap unchanged")
	var active=Game.new("");active.state.abyss.meta.unlockedDifficulty=3;active.state.abyss.meta.selectedDifficulty=3
	var prepared:Dictionary=active.prepare_abyss()
	ck(prepared.success and prepared.config.get("abyssGrowthVersion")==3,"new actual endless issuance carries version")
	ck(active.valid_save(active.state),"new versioned encounter save valid")
	var first:Dictionary=prepared.config.duplicate(true)
	ck(active.prepare_abyss().config==first,"resume keeps exact issued config")
	active.state.abyss.rogue.activeEncounter.erase("abyssGrowthVersion")
	var legacy:Dictionary=active.prepare_abyss()
	ck(not legacy.config.has("abyssGrowthVersion") and active.valid_save(active.state),"legacy issued encounter resumes without migration")
	var bad:Dictionary=active.state.duplicate(true);bad.abyss.rogue.activeEncounter.abyssGrowthVersion=4
	ck(not active.valid_save(bad),"unknown curve marker rejected")
	ck(active.abyss_difficulty_options()[3].description=="50层后指数成长；记忆碎片收益 +75%。","endless card describes actual growth")
	# Faster web enemies participate in normal turn ordering and bounded stepping.
	var party:Array=game.battle_party(true)
	for unit in party:
		unit.stats.maxHp=10000000;unit.maxHp=10000000;unit.currentHp=10000000
	var fast=Battle.new(game.catalog);fast.start(config_for(100,"boss_storm_witch"),party)
	ck(fast.state.enemies[0].stats.spd==468 and fast.state.phase=="enemy_turn","uncapped web speed owns first turn")
	for step in range(12):
		if fast.state.phase in ["victory","defeat"]:break
		fast.auto_step()
	ck(int(fast.state.steps)>0 and fast.state.reason!="状态结算达到安全上限","high-speed short combat advances normally")
	print("WEB ENDLESS GROWTH V262: %d checks, %d failures" %[checks,failures])
	quit(0 if failures==0 else 1)
