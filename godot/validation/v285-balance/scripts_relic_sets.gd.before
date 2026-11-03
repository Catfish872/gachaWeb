extends RefCounted
## Pure loadout calculations. Each physical slot and UID contributes at most once.
## Permanent stat bonuses and owner-scoped combat effects remain separate.

static func empty_stat_bonuses() -> Dictionary:
	return {"hp_flat":0.0,"atk_flat":0.0,"def_flat":0.0,"hp_pct":0.0,"atk_pct":0.0,"def_pct":0.0,"spd":0.0,"spd_pct":0.0,"cri_rate":0.0,"cri_dmg":0.0,"energy_rate":0.0}

static func unique_relics(catalog: Dictionary, relics: Array) -> Array:
	var result: Array = []
	var slots: Dictionary = {}
	var uids: Dictionary = {}
	for relic in relics:
		if not relic is Dictionary or not catalog.RelicMainStatPool.has(relic.get("slotId", "")):
			continue
		var uid: String = str(relic.get("uid", ""))
		if uid.is_empty() or uids.has(uid) or slots.has(relic.slotId):
			continue
		uids[uid] = true
		slots[relic.slotId] = true
		result.append(relic)
	return result

static func attribute_bonuses(catalog: Dictionary, relics: Array) -> Dictionary:
	var result := empty_stat_bonuses()
	for relic in unique_relics(catalog, relics):
		var main: Dictionary = relic.get("mainStat", {})
		if result.has(main.get("stat", "")):
			result[main.stat] += float(main.get("base", 0)) + float(main.get("perLevel", 0)) * int(relic.get("level", 0))
		for sub in relic.get("subStats", []):
			if sub is Dictionary and result.has(sub.get("stat", "")):
				result[sub.stat] += float(sub.get("value", 0))
	return result

static func evaluate(catalog: Dictionary, relics: Array) -> Dictionary:
	var counts: Dictionary = {}
	var active: Array = []
	var bonuses := empty_stat_bonuses()
	var owner_effects: Array = []
	var definitions: Dictionary = catalog.get("RelicSets", {})
	for relic in unique_relics(catalog, relics):
		var set_id: String = str(relic.get("setId", ""))
		if definitions.has(set_id):
			counts[set_id] = int(counts.get(set_id, 0)) + 1
	# Catalog order keeps previews and combat snapshots deterministic.
	for set_id in definitions:
		var count := int(counts.get(set_id, 0))
		var seen_thresholds: Dictionary = {}
		for bonus in definitions[set_id].get("bonuses", []):
			var pieces := int(bonus.get("pieces", 0))
			if pieces <= 0 or count < pieces or seen_thresholds.has(pieces):
				continue
			seen_thresholds[pieces] = true
			active.append({"setId":set_id,"name":definitions[set_id].name,"pieces":pieces,"count":count,"description":str(bonus.get("description", "")),"effects":bonus.get("effects", []).duplicate(true)})
			for effect in bonus.get("effects", []):
				if effect.get("type", "") == "stat":
					if bonuses.has(effect.get("stat", "")):
						bonuses[effect.stat] += float(effect.get("value", 0))
				else:
					var owned: Dictionary = effect.duplicate(true)
					owned.setId = set_id
					owned.pieces = pieces
					owner_effects.append(owned)
	return {"counts":counts,"activeBonuses":active,"statBonuses":bonuses,"ownerEffects":owner_effects}
