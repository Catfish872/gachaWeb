extends SceneTree

const BattleModel = preload("res://scripts/battle_model.gd")
var failures := 0

func _initialize() -> void:
	var model = _fixture([200, 300, 400], [100])
	_expect(model, ["ally_0", "ally_1", "ally_2", "enemy_0"], "all allies use formation order")
	model = _fixture([400, 200, 500], [300])
	_expect(model, ["ally_0", "ally_2", "enemy_0", "ally_1"], "enemy separates ally segments")
	model = _fixture([600, 700, 300, 400, 100, 200], [500, 250])
	_expect(model, ["ally_0", "ally_1", "enemy_0", "ally_2", "ally_3", "enemy_1", "ally_4", "ally_5"], "three independent segments")
	model = _fixture([300, 100], [200, 400])
	_expect(model, ["enemy_1", "ally_0", "enemy_0", "ally_1"], "singleton segments and enemy speed order")
	model = _fixture([100, 100], [100])
	_expect(model, ["ally_0", "ally_1", "enemy_0"], "existing ally before enemy speed tie")
	model = _fixture([400, 500, 200], [300])
	model.state.allies[1].statuses.append({"id":"spd_down", "duration":2, "value":0.8})
	model._cursor = model._queue.size() - 1
	model._build_queue()
	_expect(model, ["ally_0", "enemy_0", "ally_1", "ally_2"], "speed modifiers rebuild boundaries each round")
	_check(model._cursor == 0 and model.state.turn == 2, "round rebuild resets cursor")
	model.state.allies[1].currentHp = 0
	model._build_queue()
	_expect(model, ["ally_0", "enemy_0", "ally_2"], "dead allies excluded")
	model = _fixture([200, 300], [100])
	model.state.allies[0].statuses.append({"id":"freeze", "duration":1, "value":0.0})
	model._seek_actor()
	_expect(model, ["ally_0", "ally_1", "enemy_0"], "control preserves published formation queue")
	_check(model.state.currentActor == "ally_1" and model._cursor == 1, "frozen formation leader skips its own action")
	_check(not model.has_status(model.state.allies[0], "freeze"), "control duration consumed once")
	model = _fixture([100, 300], [200])
	model.state.allies[0].currentHp = 500
	model.state.allies[0].statuses.append({"id":"regen", "duration":2, "value":0.0})
	model.state.allies[1].statuses.append({"id":"burn", "duration":2, "value":0.0, "dotAttack":100})
	model._cursor = model._queue.size()
	model._seek_actor()
	_expect(model, ["ally_1", "enemy_0", "ally_0"], "round tail and next round head remain separate")
	_check(model.state.turn == 2 and model.state.currentActor == "ally_1", "next round starts at its fresh speed segment")
	_check(model.state.allies[0].currentHp == 580, "regeneration settles once at round end")
	_check(model.state.allies[1].currentHp == 982, "burn settles once at round end")
	print("party_order_segments: %s" % ("PASS" if failures == 0 else "%d FAILURES" % failures))
	quit(0 if failures == 0 else 1)

func _fixture(ally_speeds: Array, enemy_speeds: Array):
	var model = BattleModel.new()
	model.state = {"allies":[], "enemies":[], "turn":0, "wave":1, "config":{}, "phase":"player_turn", "currentActor":"", "turnOrder":[], "steps":0}
	for i in range(ally_speeds.size()):
		model.state.allies.append(model._make_ally({"id":"test_ally", "stats":{"spd":ally_speeds[i], "maxHp":1000}}, i))
	for i in range(enemy_speeds.size()):
		var enemy = model._make_ally({"id":"test_enemy", "stats":{"spd":enemy_speeds[i], "maxHp":1000}}, i)
		enemy.isAlly = false
		enemy.uid = "enemy_%d" % i
		model.state.enemies.append(enemy)
	model._build_queue()
	return model

func _expect(model, expected: Array, label: String) -> void:
	_check(model.state.turnOrder == expected, label + ": " + str(model.state.turnOrder))
	_check(model._queue.map(func(unit): return unit.uid) == expected, label + " actual action queue")

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error(label)
