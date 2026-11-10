#!/usr/bin/env python3
"""Verify signed ZIP loading using real APK GDC remaps and imported texture bytes."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("content_release", ROOT / "tools/build/content_release.py")
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)
apk = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT.parents[1] / "android-delivery/universal.apk"
with tempfile.TemporaryDirectory(prefix="content-mount-test-") as directory:
    project = Path(directory)
    (project / "scripts").mkdir()
    (project / "data").mkdir()
    (project / "project.godot").write_text('[application]\nconfig/name="Content runtime test"\n')
    shutil.copyfile(ROOT / "scripts/content_store.gd", project / "scripts/content_store.gd")
    (project / "data/content_platform.json").write_text(json.dumps({"platform_id": "a" * 64}))
    (project / "data/version.json").write_text('{"version_code":1}')
    private = project / "test-private.pem"
    subprocess.run(["openssl", "genpkey", "-algorithm", "RSA", "-pkeyopt", "rsa_keygen_bits:2048", "-out", str(private)], check=True, capture_output=True)
    subprocess.run(["openssl", "pkey", "-in", str(private), "-pubout", "-out", str(project / "data/content_public_key.pem")], check=True, capture_output=True)
    with zipfile.ZipFile(apk) as archive:
        remap = archive.read("assets/assets/characters/ayla.png.import")
        texture_path = re.search(rb'path="res://([^"]+)"', remap).group(1).decode()
        texture = archive.read("assets/" + texture_path)
        # Include actual compiled scripts and remaps, allowing transitive preloads.
        logic = {name[7:]: archive.read(name) for name in archive.namelist() if name.startswith("assets/scripts/") and name.endswith((".gdc", ".remap"))}
        logic["assets/characters/ayla.png.import"] = remap
    user = project / "user-data" / "godot" / "app_userdata" / "Content runtime test"
    objects = user / "content/objects"
    objects.mkdir(parents=True)
    def make_object(entries):
        data = builder.pack(entries)
        digest = hashlib.sha256(data).hexdigest()
        (objects / (digest + ".zip")).write_bytes(data)
        return {"sha256": digest, "size": len(data), "url": "https://github.com/Catfish872/gachaWeb/releases/download/android-v2.9.3/obj-" + digest + ".zip"}
    image = make_object({texture_path: texture})
    image.update(path="res://" + texture_path, content_sha256=hashlib.sha256(texture).hexdigest(), content_size=len(texture))
    manifest = {"schema": 1, "repository": "Catfish872/gachaWeb", "version_name": "2.9.3", "version_code": 20903, "platform_id": "a" * 64, "entry_scene": "res://main.tscn", "logic": make_object(logic), "assets": [image]}
    (project / "manifest.json").write_bytes(builder.canonical(manifest))
    subprocess.run(["openssl", "dgst", "-sha256", "-sign", str(private), "-out", str(project / "manifest.sig"), str(project / "manifest.json")], check=True, capture_output=True)
    (project / "test.gd").write_text('''extends SceneTree
const Store = preload("res://scripts/content_store.gd")
func _initialize() -> void:
    var body := FileAccess.get_file_as_bytes("res://manifest.json")
    var signature := FileAccess.get_file_as_bytes("res://manifest.sig")
    var manifest := Store.verify_manifest(body, signature)
    assert(not manifest.is_empty(), "Real RSA signature verifies")
    var corrupted := body.duplicate()
    corrupted[0] = 0
    assert(Store.verify_manifest(corrupted, signature).is_empty(), "Tamper rejected")
    assert(Store.missing_objects(manifest).is_empty(), "Cached object hashes verify")
    assert(Store.mount(manifest), "ZIP resource packs mount")
    var script = load("res://scripts/update_checker.gd")
    assert(script != null and script.can_instantiate(), "Actual exported GDC remap loads")
    var texture = load("res://assets/characters/ayla.png")
    assert(texture != null and texture.get_width() > 0, "Actual exported imported texture loads")
    print("content_runtime_mount: PASS (signed ZIP, exported GDC remap, imported texture)")
    quit(0)
''')
    env = dict(os.environ, XDG_DATA_HOME=str(project / "user-data"), XDG_CACHE_HOME=str(project / "cache"))
    result = subprocess.run([os.environ.get("GODOT", "godot"), "--headless", "--path", str(project), "--script", "test.gd"], env=env, text=True, capture_output=True, timeout=30)
    print(result.stdout, end="")
    print(result.stderr, end="")
    if result.returncode or "SCRIPT ERROR" in result.stderr or "ERROR:" in result.stderr or "content_runtime_mount: PASS" not in result.stdout:
        raise SystemExit(result.returncode or 1)
