import subprocess
import tempfile
import unittest
from pathlib import Path
from release_preflight import decide, ReleaseConflict


class PreflightTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name)
        self.run_git("init", "-q")
        self.run_git("config", "user.email", "test@example.invalid")
        self.run_git("config", "user.name", "Fixture")
        self.write("godot/scripts/game.gd", "original")
        self.commit()
        self.base = self.run_git("rev-parse", "HEAD").strip()
        self.release = {"tag_name": "android-v2.1.0", "draft": False,
                        "prerelease": False, "published_at": "2026-11-01T00:00:00Z"}

    def run_git(self, *args):
        return subprocess.check_output(["git", "-C", str(self.repo), *args], text=True)

    def write(self, path, value):
        target = self.repo / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(value)

    def commit(self):
        self.run_git("add", ".")
        self.run_git("commit", "-qm", "fixture")

    def decision(self, release=None):
        return decide(self.repo, self.release if release is None else release,
                      "android-v2.1.0", released_commit=self.base)

    def test_identical_and_test_only_skip(self):
        self.assertEqual(self.decision(), "skip")
        for path in ["godot/tests/test.gd", "godot/validation/report.json",
                     "godot/tools/android/probe.gd", "godot/simulators/run.py",
                     "godot/tools/simulate_extraction.gd",
                     "godot/README.md", ".github/workflows/godot-android.yml"]:
            self.write(path, "test change")
        self.commit()
        self.assertEqual(self.decision(), "skip")

    def test_app_change_requires_version_bump(self):
        self.write("godot/scripts/game.gd", "changed")
        self.commit()
        with self.assertRaisesRegex(ReleaseConflict, "bump version"):
            self.decision()

    def test_build_tool_change_requires_bump(self):
        self.write("godot/tools/build/install_godot.sh", "changed engine")
        self.commit()
        with self.assertRaises(ReleaseConflict):
            self.decision()

    def test_deletion_requires_bump(self):
        (self.repo / "godot/scripts/game.gd").unlink()
        self.write("godot/project.godot", "config")
        self.commit()
        with self.assertRaises(ReleaseConflict):
            self.decision()

    def test_export_config_change_requires_bump(self):
        self.write("godot/project.godot", "renderer changed")
        self.commit()
        with self.assertRaises(ReleaseConflict):
            self.decision()

    def test_absent_release_publish(self):
        self.assertEqual(decide(self.repo, None, "android-v2.1.0"), "publish")

    def test_draft_preserved(self):
        with self.assertRaisesRegex(ReleaseConflict, "draft"):
            self.decision(dict(self.release, draft=True))

    def test_wrong_tag_rejected(self):
        with self.assertRaises(ReleaseConflict):
            self.decision(dict(self.release, tag_name="android-v1.0.0"))


if __name__ == "__main__":
    unittest.main()
