#!/usr/bin/env python3
"""Apply only the thunder combat fragment to the latest catalog."""
import json
from pathlib import Path
root = Path(__file__).resolve().parents[1]
path = root / "godot/data/catalog.json"
patch = json.loads((root / "godot/data/thunder_combat_patch.json").read_text())
catalog = json.loads(path.read_text())
for section in ["CharacterData", "SkillData", "ConstellationC6", "RelicSets"]:
    catalog[section].update(patch[section])
ids = {reward["id"] for reward in patch["AbyssRewards"]}
catalog["AbyssData"]["rogue"]["rewards"] = [r for r in catalog["AbyssData"]["rogue"]["rewards"] if r["id"] not in ids] + patch["AbyssRewards"]
path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n")
