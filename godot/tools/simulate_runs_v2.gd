extends SceneTree
## Genuine twenty-floor expeditions: Model prepares/settles each actual battle,
## XP and HP/energy/cooldowns carry forward, and choices use the public node APIs.
const Game = preload("res://scripts/game_model.gd")
const Battle = preload("res://scripts/battle_model.gd")
var errors: Array = []
const PROFILES = [
	{"id":"starter_lv1","team":["ember","zeph"],"level":1,"difficulty":0,"style":"balanced","gear":false},
	{"id":"starter_lv5","team":["ember","zeph"],"level":5,"difficulty":0,"style":"balanced","gear":false},
	{"id":"three_star_lv1","team":["ember","tide","bolt"],"level":1,"difficulty":0,"style":"shield","gear":false},
	{"id":"balanced_lv1","team":["kaldi","ayla","gus"],"level":1,"difficulty":0,"style":"balanced","gear":false},
	{"id":"rank3_offense_lv10","team":["kaldi","cinder","gus"],"level":10,"difficulty":3,"style":"balanced","gear":false},
	{"id":"rank3_shield_lv10","team":["ember","tide","bolt"],"level":10,"difficulty":3,"style":"shield","gear":false},
	{"id":"rank3_shana_lv10","team":["kaldi","shana","gus"],"level":10,"difficulty":3,"style":"balanced","gear":false},
	{"id":"rank3_equipped_lv10","team":["kaldi","ayla","gus"],"level":10,"difficulty":3,"style":"balanced","gear":true}
]

func _init() -> void:
	var samples := 12
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--samples="): samples = clampi(int(arg.trim_prefix("--samples=")), 1, 128)
	var rows: Array = []
	var total_battles := 0
	for profile in PROFILES:
		for sample in range(samples):
			var seed_value := 720000 + sample
			var m = Game.new("")
			m.rng.seed = seed_value
			for id in profile.team:
				m.state.ownedCharacters[id] = m.default_character()
				m.state.ownedCharacters[id].level = profile.level
			m.set_team(profile.team)
			# A replay-rank save fixture, not a simulated unlock accomplishment.
			m.state.abyss.meta.unlockedDifficulty = profile.difficulty
			must(m.set_abyss_difficulty(profile.difficulty), "set rank")
			if profile.gear:
				m.state.resources.gold = 1000000
				for id in profile.team:
					for slot in m.catalog.RelicSlots:
						var relic = m.generate_relic(4, slot.id)
						must(m.add_relic(relic), "add legal generated relic")
						must(m.equip_relic(relic.uid, id), "equip")
						for upgrade in range(10): must(m.upgrade_relic(relic.uid), "upgrade")
			var battles := 0
			var rounds := 0
			var actions := 0
			var safety_ends := 0
			var finished := false
			for floor_number in range(1, 21):
				if not resolve_nodes(m, profile.style): break
				var prep = m.prepare_abyss()
				if not must(prep, "prepare floor%d" % floor_number): break
				var b = Battle.new(m.catalog)
				b.start(prep.config, m.battle_party(true), m.rogue_effects())
				while b.state.phase not in ["victory", "defeat"]: b.auto_step()
				battles += 1
				total_battles += 1
				rounds += b.state.turn
				actions += b.state.steps
				safety_ends += int(str(b.state.reason).contains("上限"))
				var settled = m.finish_battle(prep.config, b.state)
				if not must(settled, "settle floor%d" % floor_number): break
				if b.state.phase == "defeat" or floor_number == 20:
					finished = true
					break
			var last: Dictionary = m.state.abyss.lastRun
			var row := {"profile": profile.id, "seed": seed_value, "finished": finished,
				"outcome": last.get("outcome", "error"), "floorsCleared": last.get("floorsCleared", -1),
				"battles": battles, "rounds": rounds, "actions": actions, "safetyEnds": safety_ends,
				"blessings": last.get("blessings", 0), "metaEarned": last.get("metaEarned", 0), "finalLevels": {}}
			for id in profile.team: row.finalLevels[id] = m.state.ownedCharacters[id].level
			rows.append(row)
			print(JSON.stringify(row))
	var report := {"method":"Real public Model/BattleModel run loop. Initial save fixtures C0, no meta upgrades. All starts use seeded random encounters and offered rewards. HP, energy, cooldowns and XP carry between fights. Policy prioritizes survival, enters rest/shop routes, buys heal then preferred blessings; equipped fixture has five randomly generated 4-star +10 relics per hero. Other fixtures do not equip drops. Difficulty3 unlock is a starting-save fixture.",
		"profiles": PROFILES, "samplesPerProfile": samples, "totalRuns": rows.size(), "totalBattles": total_battles, "errors": errors, "rows": rows}
	var file := FileAccess.open("res://validation/balance-v2-runs.json", FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report, "\t"))
	print("FULL RUN SIMULATIONS: %d runs, %d real battles, %d errors" % [rows.size(), total_battles, errors.size()])
	quit(0 if errors.is_empty() else 1)

func must(result: Dictionary, label: String) -> bool:
	if not result.get("success", false):
		errors.append(label + ": " + str(result))
		printerr("FAIL: ", errors.back())
		return false
	return true

func resolve_nodes(m: Variant, style: String) -> bool:
	for safe in range(20):
		var kind := str(m.state.abyss.rogue.nextStep.type)
		match kind:
			"none": return true
			"reward":
				var choices: Array = m.state.abyss.rogue.pendingChoices.duplicate(true)
				choices.sort_custom(func(a,b): return reward_score(str(a.id), style) > reward_score(str(b.id), style))
				if not must(m.choose_abyss_reward(choices[0].choiceId), "choose offered reward"): return false
			"route":
				var choices: Array = m.node_options().options
				var selected := str(choices[0].id)
				for choice in choices:
					if choice.id in ["rest", "shop"]: selected = choice.id
				if not must(m.choose_abyss_node(selected), "choose route"): return false
			"rest":
				if not must(m.choose_abyss_node("recover"), "rest recover"): return false
			"event":
				var choices: Array = m.node_options().options
				var picked := false
				for choice in choices:
					if choice.enabled:
						picked = must(m.choose_abyss_node(choice.id), "event")
						break
				if not picked: return false
			"shop":
				var items: Array = m.abyss_shop_items()
				items.sort_custom(func(a,b): return (1000 if a.id == "heal" else reward_score(str(a.get("rewardId", "")), style)) > (1000 if b.id == "heal" else reward_score(str(b.get("rewardId", "")), style)))
				for item in items:
					for current in m.abyss_shop_items():
						if current.id == item.id and current.enabled:
							if not must(m.purchase_abyss_item(current.id), "shop purchase"): return false
				if not must(m.leave_abyss_shop(), "leave shop"): return false
			_:
				errors.append("unknown node: " + kind)
				return false
	errors.append("node resolution exceeded bound")
	return false

func reward_score(id: String, style: String) -> int:
	var preferred: Array = ["common_victory_heal_blue", "common_vampiric_blue", "common_overdrive_gold", "common_open_energy_gold", "common_atk_white", "common_crit_blue"]
	if style == "shield": preferred = ["common_victory_heal_blue", "common_shield_edge_white", "common_open_shield_blue", "common_vampiric_blue", "common_guard_gold", "common_atk_white"]
	var index := preferred.find(id)
	return 100 - index if index >= 0 else 1
