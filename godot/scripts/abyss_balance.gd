extends RefCounted
## Abyss v2 budget. Story enemies continue to use the original catalog values.
## The catalog already contains elite/boss base-stat budgets. Their tier is
## accounted for here once; floor, tier and encounter modifiers never recurse.

const VERSION := 2
const MAX_ENEMY_SPEED := 145.0
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
	var n := float(maxi(floor_number, 1) - 1)
	var first_act := minf(n, 19.0)
	var later := maxf(0.0, n - 19.0)
	# In the first twenty floors, HP drives encounter length; attack
	# grows more slowly, defense slower still. Endless floors extend linearly.
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

## Original web calcInflatedStats: additive linear/exponential blend, with
## a deterministic floor/enemy bias. Only newly issued endless encounters use it.
static func uses_web_endless(config: Dictionary) -> bool:
	return bool(config.get("isAbyss", false)) and not bool(config.get("isExtraction", false)) and int(config.get("difficulty", 0)) == 3 and int(config.get("abyssGrowthVersion", 0)) == 3

static func web_endless_scale(floor_number: int, enemy_id: String) -> Dictionary:
	var floor_value := float(maxi(floor_number, 1))
	var n := floor_value - 1.0
	var exponent_floor := maxf(0.0, floor_value - 50.0)
	var multiplier := (1.0 + n * 0.33) * 0.70 + pow(1.062, exponent_floor) * 0.30
	var first_character := enemy_id.unicode_at(0) if not enemy_id.is_empty() else 1
	var random_bias := (sin(floor_value * float(first_character)) + 1.0) / 2.0
	return {
		"hpMod": multiplier * (0.86 + random_bias * 0.36),
		"atkMod": multiplier * (0.92 + (1.0 - random_bias) * 0.48) * (n * 0.025 + pow(1.011, exponent_floor)),
		"defMod": multiplier * (1.0 + n * 0.012),
		"spdMod": 1.0 + n * 0.035,
		"scaleMult": multiplier, "curveVersion": 3}

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
