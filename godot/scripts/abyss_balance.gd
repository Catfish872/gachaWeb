extends RefCounted
## Abyss v2 budget. Story enemies continue to use the original catalog values.
## The catalog already contains elite/boss base-stat budgets. Their tier is
## accounted for here once; floor, tier and encounter modifiers never recurse.

const VERSION := 2
const MAX_ENEMY_SPEED := 145.0
const MAX_SAFE_FLOOR := 10000
const MODIFIERS := {
	"bulwark": {"id": "bulwark", "name": "铁甲阵", "description": "生命 +15%，防御 +20%，速度 −10%。",
		"statMult": {"hp": 1.15, "atk": 1.0, "def": 1.20, "spd": 0.90}},
	"frenzy": {"id": "frenzy", "name": "狂战阵", "description": "攻击 +18%，生命 −12%，防御 −10%。",
		"statMult": {"hp": 0.88, "atk": 1.18, "def": 0.90, "spd": 1.0}},
	"swift": {"id": "swift", "name": "疾行阵", "description": "速度 +15%，生命 −8%，攻击 −5%。",
		"statMult": {"hp": 0.92, "atk": 0.95, "def": 1.0, "spd": 1.15}}
}

static func modifier(id: String) -> Dictionary:
	return MODIFIERS.get(id, {}).duplicate(true)

static func scale(floor_number: int, enemy_data: Dictionary = {}) -> Dictionary:
	var n := float(clampi(floor_number, 1, MAX_SAFE_FLOOR) - 1)
	var first_act := minf(n, 19.0)
	var later := maxf(0.0, n - 19.0)
	# Within the twenty-floor expedition, HP drives encounter length; attack
	# grows more slowly, defense slower still. Beyond it, growth stays linear.
	var hp := 0.90 + first_act * 0.11 + later * 0.14
	var attack := 0.85 + first_act * 0.045 + later * 0.060
	var defense := minf(3.0, 0.85 + first_act * 0.018 + later * 0.008)
	var speed := minf(1.35, 1.0 + n * 0.008)
	var tier := str(enemy_data.get("type", "normal"))
	if tier == "boss" or enemy_data.get("isBoss", false):
		# Story bosses have 4,000–5,500 HP before scaling. This conversion gives
		# expedition milestones a budget appropriate to one three-unit party.
		hp *= 0.68
		attack *= 0.95
	return {"hpMod": hp, "atkMod": attack, "defMod": defense,
		"spdMod": speed, "scaleMult": 0.90 + first_act * 0.11 + later * 0.14,
		"curveVersion": VERSION}

static func apply_modifier(mods: Dictionary, encounter: Variant) -> Dictionary:
	var id := str(encounter.get("id", "")) if encounter is Dictionary else str(encounter)
	var profile := modifier(id)
	var result := mods.duplicate(true)
	for pair in [["hpMod", "hp"], ["atkMod", "atk"], ["defMod", "def"], ["spdMod", "spd"]]:
		result[pair[0]] = float(result.get(pair[0], 1.0)) * float(profile.get("statMult", {}).get(pair[1], 1.0))
	return result

static func apply_difficulty(mods: Dictionary, difficulty: int) -> Dictionary:
	var rank := clampi(difficulty, 0, 3)
	var result := mods.duplicate(true)
	result.hpMod *= 1.0 + 0.45 * rank
	result.atkMod *= [1.0, 2.0, 4.0, 10.0][rank]
	result.defMod *= 1.0 + 0.10 * rank
	return result
