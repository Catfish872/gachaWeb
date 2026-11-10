#!/usr/bin/env python3
"""Verify the complete v2.9 thunder icon set and optionally produce QA sheets."""
from __future__ import annotations

import argparse
import hashlib
import json
from collections import Counter
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "docs/art_v290/thunder-icons-manifest.json"


def icon_paths(value):
    if isinstance(value, dict):
        for nested in value.values():
            yield from icon_paths(nested)
    elif isinstance(value, list):
        for nested in value:
            yield from icon_paths(nested)
    elif isinstance(value, str) and value.startswith("res://assets/content_v290/icons/"):
        yield value


def validate():
    manifest = json.loads(MANIFEST.read_text())
    assets = manifest["assets"]
    assert len(assets) == 42, "Expected 42 thunder icons"
    assert Counter(a["category"] for a in assets) == {"skills": 15, "blessings": 12, "relics": 15}
    assert len({a["id"] for a in assets}) == 42, "Duplicate icon ID"
    assert len({a["sha256"] for a in assets}) == 42, "Reused runtime artwork"
    assert len({a["sourceSha256"] for a in assets}) == 42, "Reused source artwork"
    patch = json.loads((ROOT / "godot/data/thunder_combat_patch.json").read_text())
    expected = set(icon_paths(patch))
    supplied = {manifest["runtimeRoot"] + a["file"] for a in assets}
    assert expected == supplied, f"Reference mismatch: missing={expected-supplied}, unused={supplied-expected}"
    catalog = json.loads((ROOT / "godot/data/catalog.json").read_text())
    catalog_paths = set(icon_paths(catalog))
    assert catalog_paths == supplied, f"Catalog mismatch: missing={catalog_paths-supplied}, unused={supplied-catalog_paths}"
    results = []
    for asset in assets:
        path = ROOT / "godot" / (manifest["runtimeRoot"] + asset["file"]).removeprefix("res://")
        raw = path.read_bytes()
        assert hashlib.sha256(raw).hexdigest() == asset["sha256"], f"Changed image: {path}"
        with Image.open(path) as image:
            assert image.format == "PNG" and image.mode == "RGBA", f"PNG/RGBA required: {path}"
            assert image.size == (384, 384), f"Unexpected dimensions: {path}"
            alpha = image.getchannel("A")
            alpha_range = alpha.getextrema()
            assert alpha_range[0] == 0 and alpha_range[1] >= 250, f"Transparent/opaque range required: {path}"
            bbox = alpha.getbbox()
            assert bbox is not None and min(bbox[0], bbox[1], 384-bbox[2], 384-bbox[3]) >= 30, f"Insufficient padding: {path}"
            assert max(bbox[2]-bbox[0], bbox[3]-bbox[1]) <= 322, f"Unbounded art: {path}"
            histogram = alpha.histogram()
            coverage = 1.0 - histogram[0] / (384 * 384)
            assert 0.08 < coverage < 0.70, f"Unexpected alpha coverage: {path}"
            results.append({"id": asset["id"], "size": list(image.size), "mode": image.mode, "alphaRange": list(alpha_range), "alphaBounds": bbox, "coverage": round(coverage, 4), "sha256": asset["sha256"]})
    return manifest, {"status": "passed", "count": len(results), "referenceCount": len(expected), "catalogReferenceCount": len(catalog_paths), "categories": dict(Counter(a["category"] for a in assets)), "checks": ["exact patch and runtime catalog reference closure", "42 unique runtime and source hashes", "PNG RGBA decoding", "384x384 size", "transparent and opaque alpha", "centered transparent margins"], "assets": results}


def contact_sheets(manifest, output):
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 12)
    title = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 22)
    for category in ("skills", "blessings", "relics"):
        assets = [a for a in manifest["assets"] if a["category"] == category]
        cols = 4 if category == "blessings" else 5
        cell_w, cell_h = 240, 260
        sheet = Image.new("RGB", (cols*cell_w, 60+3*cell_h), "#151c2a")
        draw = ImageDraw.Draw(sheet)
        draw.text((18, 15), f"THUNDER TRIO / {category.upper()} / 192px + 64px preview", fill="#e3dcc8", font=title)
        for i, asset in enumerate(assets):
            x, y = (i % cols)*cell_w, 60+(i // cols)*cell_h
            draw.rounded_rectangle((x+6,y+6,x+cell_w-6,y+cell_h-6), radius=9, fill="#202a3b", outline="#34415b")
            path = ROOT / "godot/assets/content_v290/icons" / asset["file"]
            with Image.open(path) as image:
                preview = image.resize((192,192), Image.Resampling.LANCZOS)
                sheet.paste(preview, (x+24,y+10), preview)
                small = image.resize((64,64), Image.Resampling.LANCZOS)
                sheet.paste(small, (x+166,y+176), small)
            draw.text((x+13,y+222), asset["id"], fill="#e3e9f4", font=font)
        sheet.save(output / f"{category}-contact-sheet.png")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sheets", action="store_true", help="Write diagnostic contact sheets")
    parser.add_argument("--output", type=Path, default=ROOT / "godot/validation/v290-thunder/icons")
    args = parser.parse_args()
    manifest, report = validate()
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / "verification.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    if args.sheets:
        contact_sheets(manifest, args.output)
    print(f"PASS: {report['count']} unique RGBA thunder icons; all {report['referenceCount']} patch references resolve.")


if __name__ == "__main__":
    main()
