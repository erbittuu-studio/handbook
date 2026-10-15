"""A release branch is ready: named X.Y.Z, newer than the last shipped tag, with a changelog section.

A tag means shipped: release.yml creates `vX.Y.Z` only when the release branch is merged, and you merge only after
Apple approves the build. So the newest tag is the newest version that went out, and nothing else has to record it.

Runs only on a branch named `release/...`; on any other branch it passes. CI passes the branch in PES_BRANCH,
locally it is the branch you are on.
"""
import os
import re
import subprocess


def _git(root, *args):
    result = subprocess.run(["git", "-C", str(root), *args], capture_output=True, text=True)
    return result.stdout.strip() if result.returncode == 0 else ""


def _numbers(version):
    return tuple(int(part) for part in version.split("."))


def check(ctx):
    branch = os.environ.get("PES_BRANCH") or _git(ctx.root, "rev-parse", "--abbrev-ref", "HEAD")
    if not branch.startswith("release/"):
        return []

    version = branch[len("release/"):]
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        return [f"'{branch}' must be release/X.Y.Z: no leading v, three numbers (release.yml takes the tag from the name)"]

    problems = []
    shipped = [t[1:] for t in _git(ctx.root, "tag", "--list", "v*").split() if re.fullmatch(r"v\d+\.\d+\.\d+", t)]
    if shipped:
        latest = max(shipped, key=_numbers)
        if _numbers(version) <= _numbers(latest):
            problems.append(f"{version} is not newer than the latest shipped version, v{latest}")

    changelog = ctx.root / "CHANGELOG.md"
    text = changelog.read_text(encoding="utf-8") if changelog.is_file() else ""
    if not re.search(rf"^## \[{re.escape(version)}\]", text, re.M):
        problems.append(f"CHANGELOG.md has no '## [{version}]' section")
    return problems
