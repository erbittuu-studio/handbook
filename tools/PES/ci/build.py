#!/usr/bin/env python3
"""Starts the Xcode Cloud build for the release branch you are on, on purpose.

    ./build              check, then start the build
    ./build --dry-run    only the checks

Nothing else starts a build: pushing never does. The Xcode Cloud workflow it starts is named manual_release and has no
start condition of its own (settings in PLAYBOOK.md §12). The checks come first because a wasted build costs more than a
minute of looking: you are on release/X.Y.Z, the tree is clean and pushed, the changelog has the section, the tag is
free, and the project checks pass. The Apple key is read from the secrets folder next to the app repos
(PES_Apps/secrets, or PES_SECRETS): AuthKey_<id>.p8 for the key, and the ASC_ISSUER_ID row of APPLE.md.
"""
import glob
import os
import re
import subprocess
import sys
from pathlib import Path

WORKFLOW = "manual_release"


def find_root():
    for folder in [Path(__file__).resolve(), *Path(__file__).resolve().parents]:
        if (folder / "project.yml").is_file():
            return folder
    sys.exit("no project.yml above this script")


ROOT = find_root()
failed = False


def git(*args):
    result = subprocess.run(["git", "-C", str(ROOT), *args], capture_output=True, text=True)
    return result.stdout.strip() if result.returncode == 0 else ""


def step(ok, text, hint=""):
    global failed
    print(("  ✓ " if ok else "  ✗ ") + text + (f"\n      {hint}" if hint and not ok else ""))
    failed = failed or not ok


def credentials():
    folder = Path(os.environ.get("PES_SECRETS") or ROOT.parent / "secrets")
    key = next(iter(sorted(glob.glob(str(folder / "AuthKey_*.p8")))), None)
    notes = folder / "APPLE.md"
    issuer = re.search(r"ASC_ISSUER_ID`?\s*\|\s*`?([0-9a-f-]{36})", notes.read_text(), re.I) if notes.is_file() else None
    if not key or not issuer:
        return None
    return {"ASC_KEY_ID": re.search(r"AuthKey_(\w+)\.p8", key).group(1), "ASC_ISSUER_ID": issuer.group(1),
            "ASC_KEY_CONTENT": Path(key).read_text()}


def main():
    dry = "--dry-run" in sys.argv
    branch = git("rev-parse", "--abbrev-ref", "HEAD")
    version = branch[len("release/"):] if branch.startswith("release/") else ""
    step(bool(re.fullmatch(r"\d+\.\d+\.\d+", version)), f"on a release branch ({branch})", "switch to release/X.Y.Z first")
    step(not git("status", "--porcelain"), "working tree is clean", "commit or stash your changes")
    pushed = bool(git("rev-parse", "@{u}")) and git("rev-parse", "HEAD") == git("rev-parse", "@{u}")
    step(pushed, "branch is pushed and up to date", "git push, so Apple builds the same code you checked")
    if version:
        free = not git("tag", "--list", f"v{version}") and not git("ls-remote", "--tags", "origin", f"refs/tags/v{version}")
        step(free, f"tag v{version} is free", "that version is already shipped; use the next number")
    checked = subprocess.run(["python3", str(ROOT / "App/Packages/PES/validate.py")], cwd=ROOT, capture_output=True, text=True,
                             env={**os.environ, "PES_BRANCH": branch})
    step(checked.returncode == 0, "project checks pass", "\n      ".join(checked.stdout.strip().splitlines()[-6:]))
    creds = credentials()
    step(creds is not None or dry, "Apple key found in the secrets folder", "put AuthKey_<id>.p8 and APPLE.md in PES_Apps/secrets")
    if failed:
        sys.exit("\nNot started. Fix the lines marked ✗.")
    if dry:
        sys.exit(print("\nAll checks pass. (dry run: nothing started)") or 0)
    print(f"\nStarting {WORKFLOW} for {branch} ...")
    start = subprocess.run(["ruby", str(ROOT / "App/Packages/PES/ci/start_xcode_cloud_build.rb"), WORKFLOW, branch], cwd=ROOT,
                           env={**os.environ, **creds})
    sys.exit(start.returncode)


main()
