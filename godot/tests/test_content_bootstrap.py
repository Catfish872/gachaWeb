#!/usr/bin/env python3
"""Run real bootstrap/save guard with deterministic stores in an isolated Godot project."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="content-bootstrap-test-") as directory:
    project = Path(directory)
    (project / "scripts").mkdir()
    (project / "data").mkdir()
    (project / "project.godot").write_text('[application]\nconfig/name="Content bootstrap test"\n')
    (project / "data/version.json").write_text('{"version_code":1}')
    for name in ("content_bootstrap.gd", "content_save_guard.gd"):
        shutil.copyfile(ROOT / "scripts" / name, project / "scripts" / name)
    (project / "scripts/content_store.gd").write_text('''extends RefCounted
const ROOT = "user://content"
static var state: Dictionary = {}
static var garbage_collection_calls := 0
static func _hash(s: String) -> bool:
    return s.length() == 64 and s.is_valid_hex_number()
static func read_state() -> Dictionary:
    return state.duplicate(true)
static func write_state(value: Dictionary) -> Error:
    state = value.duplicate(true)
    return OK
static func load_manifest(identifier: String) -> Dictionary:
    return {"version_code": 2 if identifier == "a".repeat(64) else 3} if _hash(identifier) else {}
static func compatible(_manifest: Dictionary) -> bool:
    return true
static func missing_objects(_manifest: Dictionary) -> Array:
    return []
static func mount(_manifest: Dictionary) -> bool:
    return true
static func collect_garbage() -> Dictionary:
    assert(not state.get("booting", false), "GC follows committed healthy activation/recovery")
    garbage_collection_calls += 1
    return {"removed": 0}

''')
    (project / "scripts/main.gd").write_text('extends Node\nvar _ready_done := true\n')
    (project / "main.tscn").write_text('''[gd_scene load_steps=2 format=3]
[ext_resource type="Script" path="res://scripts/main.gd" id="1"]
[node name="Game" type="Node"]
script = ExtResource("1")
''')
    (project / "test.gd").write_text('''extends SceneTree
const Store = preload("res://scripts/content_store.gd")
const Guard = preload("res://scripts/content_save_guard.gd")
const Bootstrap = preload("res://scripts/content_bootstrap.gd")
var failures := 0
func check(value: bool, label: String) -> void:
    if not value:
        push_error(label)
        failures += 1
func write_save(value: String) -> void:
    DirAccess.make_dir_recursive_absolute("user://saves")
    var file := FileAccess.open("user://saves/slot1.json", FileAccess.WRITE)
    file.store_string(value)
    file.close()
func boot() -> void:
    var bootstrap := Bootstrap.new()
    root.add_child(bootstrap)
    for index in range(6):
        await process_frame
    if current_scene != null:
        current_scene.queue_free()
        current_scene = null
    if is_instance_valid(bootstrap):
        bootstrap.queue_free()
    await process_frame
func _initialize() -> void:
    run.call_deferred()
func run() -> void:
    write_save("original")
    Store.state = {"pending": "a".repeat(64)}
    await boot()
    check(Store.state.get("active") == "a".repeat(64), "Activate first snapshot")
    check(not Store.state.has("booting"), "Health checkpoint clears pending boot")
    check(Store.garbage_collection_calls == 1, "GC follows first healthy activation")
    check(DirAccess.get_directories_at(Store.ROOT + "/save-backups").size() == 1, "First activation has backup")
    Store.state["pending"] = "b".repeat(64)
    await boot()
    check(Store.state.get("active") == "b".repeat(64), "Activate second snapshot")
    check(Store.garbage_collection_calls == 2, "GC follows second healthy activation")
    check(DirAccess.get_directories_at(Store.ROOT + "/save-backups").size() == 2, "Second backup is unique")
    var backup_id := "c".repeat(64)
    check(Guard.capture(Store.ROOT + "/save-backups/" + backup_id) == OK, "Prepare crash snapshot")
    write_save("incompatible-migrated-save")
    Store.state = {"booting": true, "save_backup": backup_id, "active": "b".repeat(64), "previous": "a".repeat(64), "active_version": 3, "previous_version": 2}
    await boot()
    check(Store.state.get("active") == "a".repeat(64), "Rollback content version")
    check(Store.state.get("rejected_version") == 3, "Reject failed version")
    check(FileAccess.get_file_as_string("user://saves/slot1.json") == "original", "Restore pre-migration save")
    check(not Store.state.has("booting"), "Recovery committed")
    check(Store.garbage_collection_calls == 3, "GC follows committed recovery")
    Store.state = {"active": "d".repeat(64), "active_version": 1, "previous": "a".repeat(64), "previous_version": 0}
    await boot()
    check(not Store.state.has("active"), "Newer native APK supersedes cached content")
    check(Store.garbage_collection_calls == 4, "GC follows native superseding")
    check(FileAccess.get_file_as_string("user://saves/slot1.json") == "original", "Native superseding preserves saves")
    print("content_bootstrap recovery: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures)")
    quit(0 if failures == 0 else 1)
''')
    env = dict(os.environ, XDG_DATA_HOME=str(project / "user-data"), XDG_CACHE_HOME=str(project / "cache"))
    result = subprocess.run([os.environ.get("GODOT", "godot"), "--headless", "--path", str(project), "--script", "test.gd"], env=env, text=True, capture_output=True, timeout=30)
    print(result.stdout, end="")
    print(result.stderr, end="")
    if result.returncode or "SCRIPT ERROR" in result.stderr or "ERROR:" in result.stderr:
        raise SystemExit(result.returncode or 1)
