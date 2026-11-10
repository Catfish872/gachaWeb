#!/usr/bin/env python3
"""Rebuild runtime PNGs from the generated source files retained by image_gen."""
from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--output-root", type=Path, default=ROOT / "godot/assets/content_v290/icons")
    args = parser.parse_args()
    manifest = json.loads((ROOT / "docs/art_v290/thunder-icons-manifest.json").read_text())
    for asset in manifest["assets"]:
        source = args.source_root / asset["source"]
        assert source.is_file(), f"Missing original generated source: {source}"
        assert hashlib.sha256(source.read_bytes()).hexdigest() == asset["sourceSha256"], f"Source hash mismatch: {source}"
        destination = args.output_root / asset["file"]
        destination.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(["magick", str(source), "-trim", "+repage", "-resize", "320x320", "-gravity", "center", "-background", "none", "-extent", "384x384", "-strip", str(destination)], check=True)
    print(f"Prepared {len(manifest['assets'])} transparent thunder icons.")


if __name__ == "__main__":
    main()
