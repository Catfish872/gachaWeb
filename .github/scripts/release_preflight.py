#!/usr/bin/env python3
"""Fail closed when reusing an immutable Android version; never alter releases."""
import base64
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import urllib.error
import urllib.request


class ReleaseConflict(RuntimeError):
    pass


def git(repo, *args, env=None):
    return subprocess.check_output(["git", "-C", str(repo), *args], env=env)


def production_path(path):
    # Build scripts/toolchain pins affect the APK and deliberately remain included.
    return (path.startswith("godot/")
            and not path.startswith(("godot/tests/", "godot/validation/",
                                     "godot/tools/android/", "godot/simulators/",
                                     "godot/tools/simulate_"))
            and not path.lower().endswith(".md"))


def production_tree(repo, commit):
    entries = {}
    for entry in git(repo, "ls-tree", "-rz", commit, "--", "godot/").split(b"\0"):
        if entry:
            identity, path = entry.split(b"\t", 1)
            name = path.decode("utf-8")
            if production_path(name):
                entries[name] = identity
    if not entries:
        raise ReleaseConflict("Production tree is empty; refusing release reuse")
    return entries


def decide(repo, release, tag, current="HEAD", released_commit=None):
    if release is None:
        return "publish"
    if release.get("draft") or not release.get("published_at"):
        raise ReleaseConflict("Existing draft/unpublished release preserved; resolve it explicitly")
    if release.get("tag_name") != tag or release.get("prerelease"):
        raise ReleaseConflict("Existing release identity/channel mismatch")
    if released_commit is None:
        raise ReleaseConflict("Exact release tag commit is required")
    old, new = production_tree(repo, released_commit), production_tree(repo, current)
    changed = sorted(p for p in old.keys() | new.keys() if old.get(p) != new.get(p))
    if changed:
        raise ReleaseConflict("Published version has different production inputs; bump version_name and version_code: " + ", ".join(changed[:15]))
    return "skip"


def fetch_release(repository, tag, token):
    request = urllib.request.Request(
        f"https://api.github.com/repos/{repository}/releases/tags/{tag}",
        headers={"Authorization": f"Bearer {token}", "Accept": "application/vnd.github+json",
                 "X-GitHub-Api-Version": "2022-11-28"})
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        if error.code == 404:
            return None
        raise ReleaseConflict(f"Release metadata request failed: HTTP {error.code}") from None


def main():
    tag = os.environ["RELEASE_TAG"]
    repository = os.environ["GITHUB_REPOSITORY"]
    token = os.environ["GH_TOKEN"]
    if not re.fullmatch(r"android-v[0-9]+\.[0-9]+\.[0-9]+", tag) or not re.fullmatch(r"[\w.-]+/[\w.-]+", repository):
        raise ReleaseConflict("Invalid release identity")
    release = fetch_release(repository, tag, token)
    commit = None
    if release is not None and not release.get("draft"):
        # Resolve the tag itself, never GitHub's mutable target_commitish field.
        env = os.environ.copy()
        auth = base64.b64encode(("x-access-token:" + token).encode()).decode()
        env.update(GIT_CONFIG_COUNT="1", GIT_CONFIG_KEY_0="http.https://github.com/.extraheader",
                   GIT_CONFIG_VALUE_0="AUTHORIZATION: basic " + auth, GIT_TERMINAL_PROMPT="0")
        git(".", "fetch", "--no-tags", "--depth=1", f"https://github.com/{repository}.git",
            f"refs/tags/{tag}", env=env)
        commit = git(".", "rev-parse", "FETCH_HEAD^{commit}").decode().strip()
    decision = decide(".", release, tag, os.environ["GITHUB_SHA"], commit)
    with Path(os.environ["GITHUB_OUTPUT"]).open("a") as output:
        output.write("publish=" + ("true" if decision == "publish" else "false") + "\n")
    print("Publish new immutable release" if decision == "publish" else
          f"Existing {tag} production inputs match exactly; preserving published APK ({commit})")


if __name__ == "__main__":
    try:
        main()
    except (ReleaseConflict, subprocess.CalledProcessError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
