extends SceneTree
## Seeded, real combat snapshots. Every result comes from BattleModel.auto_step;
## no unit HP, damage, phase or outcome is edited after start().
const Game = preload("res://scripts/game_model.gd")
const Battle = preload("res://scripts/battle_model.gd")
const Balance = preload("res://scripts/abyss_balance.gd")
const FLOORS = [1, 3, 5, 10, 15, 20]
var profiles := [
	{"id": "starter_lv1", "team": ["ember", "zeph"], "level": 1, "constellation": 0, "build": "none"},
	{"id": "starter_lv5", "team": ["ember", "zeph"], "level": 5, "constellation": 0, "build": "none"},
	{"id": "low_rarity_lv5", "team": ["ember", "tide", "bolt"], "level": 5, "constellation": 0, "build": "none"},
	{"id": "balanced_lv5", "team": ["kaldi", "ayla", "gus"], "level": 5, "constellation": 0, "build": "none"},
	{"id": "balanced_lv10", "team": ["kaldi", "ayla", "gus"], "level": 10, "constellation": 0, "build": "none"},
	{"id": "fire_lv10", "team": ["kaldi", "ayla", "cinder"], "level": 10, "constellation": 0, "build": "fire"},
	{"id": "shield_lv5", "team": ["ember", "tide", "bolt"], "level": 5, "constellation": 0, "build": "shield"},
	{"id": "poison_lv5", "team": ["ember", "tide", "bolt"], "level": 5, "constellation": 0, "build": "poison"}
]

func _init() -> void:
	var samples := 32
	var rank_sweep := OS.get_cmdline_user_args().has("--rank-sweep")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--samples="): samples = clampi(int(arg.trim_prefix("--samples=")), 1, 512)
	if rank_sweep:
		profiles = profiles.filter(func(p): return p.id in ["balanced_lv5", "balanced_lv10", "fire_lv10", "shield_lv5", "poison_lv5"])
		profiles.append({"id": "low_rarity_lv10", "team": ["ember", "tide", "bolt"], "level": 10, "constellation": 0, "build": "none"})
		profiles.append({"id": "shield_lv10", "team": ["ember", "tide", "bolt"], "level": 10, "constellation": 0, "build": "shield"})
		profiles.append({"id": "shana_lv10", "team": ["kaldi", "shana", "gus"], "level": 10, "constellation": 0, "build": "none"})
		profiles.append({"id": "offense_lv10", "team": ["kaldi", "cinder", "gus"], "level": 10, "constellation": 0, "build": "none"})
		profiles.append({"id": "mature_c6_lv10", "team": ["kaldi", "ayla", "gus"], "level": 10, "constellation": 6, "build": "none"})
	var rows: Array = []
	var total := 0
	for profile in profiles:
		var m = Game.new("")
		for id in profile.team:
			m.state.ownedCharacters[id] = m.default_character()
			m.state.ownedCharacters[id].level = profile.level
			m.state.ownedCharacters[id].constellation = profile.constellation
		m.set_team(profile.team)
		var party := m.battle_party(false)
		for floor_number in ([10, 20] if rank_sweep else FLOORS):
			for difficulty in ([0, 1, 2, 3] if rank_sweep else [0]):
				var wins := 0
				var turns := 0
				var actions := 0
				var safety_ends := 0
				var opening_hit_pct := 0.0
				var max_hit_pct := 0.0
				var min_turns := 100000
				var max_turns := 0
				var effects := build_effects(m.catalog, profile.build, floor_number)
				for sample in range(samples):
					var encounter := encounter_config(floor_number, 170000 + sample)
					encounter.difficulty = difficulty
					var b = Battle.new(m.catalog)
					b.start(encounter, party, effects)
					while b.state.phase not in ["victory", "defeat"]:
						var round_before := int(b.state.turn)
						var result = b.auto_step()
						for event in result.events:
							if event.type == "damage" and str(event.target).begins_with("ally_"):
								var target = b.get_unit(event.target)
								var pct := float(event.amount) / float(target.maxHp)
								max_hit_pct = maxf(max_hit_pct, pct)
								if round_before == 1: opening_hit_pct = maxf(opening_hit_pct, pct)
					wins += int(b.state.phase == "victory")
					turns += b.state.turn
					actions += b.state.steps
					safety_ends += int(str(b.state.reason).contains("上限"))
					min_turns = mini(min_turns, b.state.turn)
					max_turns = maxi(max_turns, b.state.turn)
					total += 1
				var row := {"profile": profile.id, "floor": floor_number, "difficulty": difficulty, "samples": samples, "wins": wins,
					"meanRounds": snappedf(float(turns) / samples, 0.01), "minRounds": min_turns, "maxRounds": max_turns,
					"meanActions": snappedf(float(actions) / samples, 0.01), "safetyEnds": safety_ends, "effectCount": effects.size(), "maxOpeningHitPct": snappedf(opening_hit_pct * 100.0, 0.01), "maxIncomingHitPct": snappedf(max_hit_pct * 100.0, 0.01)}
				rows.append(row)
				print(JSON.stringify(row))
	var report := {"curveVersion": Balance.VERSION, "seedStart": 170000, "samplesPerCell": samples,
		"totalBattles": total, "method": "Independent full-HP, zero-energy snapshots; genuine auto_step outcomes; no relics; no XP gain between samples. Build effects use available prior reward-floor count; eight selections by floor20.",
		"profiles": profiles, "rows": rows}
	var file := FileAccess.open("res://validation/balance-v2-ranks.json" if rank_sweep else "res://validation/balance-v2.json", FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report, "\t"))
	print("BALANCE SIMULATIONS: %d genuine battles; %d rows" % [total, rows.size()])
	quit()

static func encounter_config(floor_number: int, sample_seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = sample_seed * 100 + floor_number
	var tier := "boss" if floor_number % 10 == 0 else ("elite" if floor_number % 5 == 0 else "normal")
	var pool: Array = ["wolf", "goblin", "fire_imp"]
	var count := 2
	if floor_number >= 4: pool.append_array(["ice_wolf", "thunder_hawk"])
	if floor_number >= 7: count = rng.randi_range(2, 3)
	if tier == "elite":
		pool = ["stone_golem", "dark_knight"]
		count = 1 if floor_number <= 5 else 2
	elif tier == "boss":
		pool = ["boss_flame_lord", "boss_storm_witch"]
		count = 1
	var enemies: Array = []
	for i in range(count): enemies.append(pool[rng.randi_range(0, pool.size() - 1)])
	var modifier: Dictionary = {}
	if floor_number >= 6 and tier != "boss" and rng.randf() < 0.45:
		modifier = Balance.modifier(["bulwark", "frenzy", "swift"][rng.randi_range(0, 2)])
	return {"isAbyss": true, "floor": floor_number, "encounterTier": tier, "encounterModifier": modifier,
		"enemies": enemies, "seed": sample_seed * 100 + floor_number, "maxSteps": 3000}

static func build_effects(catalog: Dictionary, build: String, floor_number: int) -> Array:
	var paths := {
		"fire": ["kaldi_burn_spread_blue", "kaldi_burn_amp_white", "common_vampiric_blue", "kaldi_ult_burn_blue", "kaldi_start_burn_gold", "kaldi_burn_execute_gold", "common_overdrive_gold", "common_open_energy_gold"],
		"shield": ["common_shield_edge_white", "common_open_shield_blue", "common_vampiric_blue", "common_atk_white", "common_shield_edge_white", "common_victory_heal_blue", "common_guard_gold", "common_open_energy_gold"],
		"poison": ["common_venom_white", "common_vampiric_blue", "common_static_blue", "common_venom_white", "common_guard_gold", "common_execute_blue", "common_venom_white", "common_open_energy_gold"]}
	if not paths.has(build): return []
	var earned := 0
	for reward_floor in [1, 3, 6, 9, 10, 13, 16, 19]:
		if reward_floor < floor_number: earned += 1
	var result: Array = []
	for id in paths[build].slice(0, earned):
		for reward in catalog.AbyssData.rogue.rewards:
			if reward.id == id: result.append_array(reward.effects.duplicate(true))
	return result
