extends SceneTree
const Game = preload("res://scripts/game_model.gd")
const Battle = preload("res://scripts/battle_model.gd")
var passed := 0
var failed := 0
func _initialize() -> void:
	call_deferred("run_tests")
func check(value: bool, label: String) -> void:
	if value: passed+=1
	else: failed+=1;push_error(label)
func spawn(game, id: String, config: Dictionary) -> Dictionary:
	var b = Battle.new(game.catalog)
	var settings := config.duplicate(true)
	settings.enemies=[id]
	b.start(settings,[{"id":"kaldi","stats":{"maxHp":1000000,"atk":100,"def":100,"spd":1000,"cri":0.0,"criDmg":1.5}}])
	return b.state.enemies[0]
func run_tests() -> void:
	var g = Game.new("")
	check(g.catalog.EnemyData.boss_hedor.has("abyssBaseStats"),"Hedor explicit abyss budget")
	for config in [{"isAbyss":true,"floor":20,"difficulty":0},{"isAbyss":true,"floor":100,"difficulty":3,"abyssGrowthVersion":3}]:
		var old: Dictionary=spawn(g,"boss_flame_lord",config)
		var fresh: Dictionary=spawn(g,"boss_hedor",config)
		check(absf(float(fresh.maxHp)/float(old.maxHp)-4500.0/4000.0)<.002,"same-floor boss HP budget")
		check(absf(float(fresh.stats.atk)/float(old.stats.atk)-125.0/120.0)<.012,"same-floor boss ATK budget")
		check(int(fresh.maxHp)<int(old.maxHp)*2,"story HP does not leak into abyss")
	var story: Dictionary=spawn(g,"boss_hedor",{})
	var expedition: Dictionary=spawn(g,"boss_hedor",{"isExtraction":true,"scaleMult":1.0})
	check(int(story.maxHp)==16000,"story base unchanged")
	check(int(expedition.maxHp)==16000,"expedition uses own base")
	print("LANTERN_ABYSS_BUDGET ",passed," passed / ",failed," failed")
	quit(1 if failed else 0)
