#!/usr/bin/env python3
"""Verify revised thunder art, immutable identities, and runtime references."""
import hashlib
import json
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
GODOT = ROOT / "godot"
manifest = json.loads((GODOT / "assets/content_v290/character_art_manifest.json").read_text())
assert manifest["revision"] == "approved-anime-review-v2"
assets = manifest["assets"]
assert len(assets) == 13 and len({a["sha256"] for a in assets}) == 13
paths = set()
for asset in assets:
    path = GODOT / asset["path"].removeprefix("res://")
    paths.add(asset["path"])
    assert hashlib.sha256(path.read_bytes()).hexdigest() == asset["sha256"], path
    with Image.open(path) as image:
        assert list(image.size) == asset["size"] and image.mode == asset["mode"], path
        if "alphaRange" in asset:
            assert list(image.getchannel("A").getextrema()) == asset["alphaRange"], path
            assert asset["alphaRange"][0] == 0 and asset["alphaRange"][1] >= 250, path
catalog = json.loads((GODOT / "data/catalog.json").read_text())
patch = json.loads((GODOT / "data/thunder_acquisition_patch.json").read_text())
for index, character in enumerate(["raisa", "vika", "eve"], 1):
    image = f"res://assets/content_v290/characters/{character}.png"
    banner = f"res://assets/content_v290/banner/{character}_layered_banner.png"
    assert image in paths and catalog["CharacterData"][character]["image"] == image
    assert banner in paths
    assert catalog["GachaPoolData"]["pools"]["limited_" + character]["bannerPath"] == banner
    assert patch["limited_" + character]["bannerPath"] == banner
    assert catalog["DialogueMeta"][f"ch5_interlude_{index}"]["illustration"] in paths
for action in ["normal", "skill", "ult"]:
    skill = "raisa_armor_" + action
    assert catalog["SkillData"][skill]["actionImage"] == f"res://assets/content_v290/actions/{skill}.png"
print("THUNDER ART V290: 13 unique approved assets, hashes, alpha, characters, actions, story CGs and banners PASS")
