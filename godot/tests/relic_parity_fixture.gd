extends RefCounted
const Battle = preload("res://scripts/battle_model.gd")
static func fingerprints(catalog: Dictionary) -> Dictionary:
	var output: Dictionary = {}
	for id in catalog.CharacterData:
		for stars in [0, 6]:
			for seeded in [1, 71, 25001]:
				var b = Battle.new(catalog)
				var input: Array = []
				for cid in [id, "ayla", "lorin"]:
					var stats: Dictionary = catalog.CharacterData[cid].baseStats.duplicate(true)
					stats.hp *= 12; stats.maxHp = stats.hp; stats.atk *= 2
					input.append({"id":cid,"stats":stats,"constellation":stars,"energy":100})
				b.start({"isAbyss":true,"floor":15,"difficulty":1,"seed":seeded,"maxSteps":250,"enemies":["boss_flame_lord","thunder_hawk","wolf"]},input,[{"type":"healMult","value":0.32},{"type":"damageTakenMult","value":-0.1},{"type":"extraDamageVsStatus","statusId":"burn","multiplier":0.3},{"type":"energyOnHitStatus","statusId":"burn","value":5.0},{"type":"battleStartStatus","statusId":"shield","duration":2,"value":0.22},{"type":"statusAfterHeal","statusId":"regen","duration":1}])
				var actions: Array = []
				for step in 80:
					if b.state.phase in ["victory","defeat"]: break
					actions.append(b.auto_step().events)
				var units: Array = []
				for u in b.state.allies + b.state.enemies:
					units.append({"uid":u.uid,"hp":u.currentHp,"maxHp":u.maxHp,"stats":u.stats,"energy":u.energy,"shield":u.shield,"statuses":u.statuses,"cooldowns":u.cooldowns})
				output["%s:%d:%d" % [id,stars,seeded]] = JSON.stringify({"events":actions,"units":units,"phase":b.state.phase,"turn":b.state.turn,"rng":str(b.rng.state)}).sha256_text()
	return output
