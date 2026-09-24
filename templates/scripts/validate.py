#!/usr/bin/env python3
"""Runs every check in the project, or one of them by name.

    python3 scripts/validate.py            # everything
    python3 scripts/validate.py colors     # just that one
    python3 scripts/validate.py --list     # what there is

**A check is a file with a `check(ctx)` function in it.** Drop one into a
folder listed under `checks` in project.yml and it runs — there is no registry
to update here, and no line to add to CI. That is the whole convention, and it
is the reason this file can be copied into another app unchanged: everything
specific to *this* app is in project.yml, not in here.

    \"\"\"One line saying what this proves.\"\"\"

    def check(ctx):
        return ["what is wrong"]      # empty list means it passed

`ctx` carries the repo root and the parsed project.yml, so a check imports
nothing and never has to work out where it is on disk. That last part is not
theoretical: these checks each used to compute the repo root by counting
parent directories, and moving them one folder deeper silently pointed every
one of them at a directory that did not exist.

**An app can decline a shared check, on the record.** `"skip": {"name": "why"}` in
project.yml leaves that check out of the run and prints it, with the reason, so
a deliberate exception is visible in every log instead of quietly missing. A skip
with no reason is refused, and so is one naming a check that does not exist.

**A check that cannot run is a failure, not a crash.** An exception inside one
is caught and reported against that check, so the rest still run and the
summary is still honest — a validator that quietly stops checking is the exact
failure this repo has already been bitten by once.
"""
import argparse
import ast
import importlib.util
import json
import os
import subprocess
import sys
import traceback
from pathlib import Path


def find_root() -> Path:
    """Walk up until the project file turns up. Depth-independent on purpose."""
    for folder in [Path(__file__).resolve(), *Path(__file__).resolve().parents]:
        if (folder / "project.yml").is_file() or (folder / "Project.json").is_file():
            return folder
    sys.exit("error: no project.yml (or project.yml) in any parent directory")


def load_project(root: Path) -> dict:
    """The app's facts as a dict, from project.yml or the older Project.json.

    Python's standard library reads no YAML, and a checkout should need nothing installed, so the
    YAML is converted by Ruby, which every Mac and CI runner already has.
    """
    yml = root / "project.yml"
    if yml.is_file():
        converted = subprocess.run(
            ["ruby", "-ryaml", "-rjson", "-e", "puts JSON.generate(YAML.safe_load(File.read(ARGV[0]), aliases: true))", str(yml)],
            capture_output=True, text=True,
        )
        if converted.returncode != 0:
            sys.exit(f"error: project.yml is not valid YAML:\n{converted.stderr.strip()}")
        return json.loads(converted.stdout)
    return json.loads((root / "Project.json").read_text())


class Context:
    """What every check is handed. Read-only, and the same for all of them."""

    def __init__(self, root: Path, project: dict):
        self.root = root
        self.project = project

    def get(self, path: str):
        """`ctx.get("app.bundleId")` — dotted lookup into project.yml.

        Raises rather than returning None. A check reading a key that is not
        there is a broken check, and it should say so loudly instead of
        quietly passing because it compared against nothing.
        """
        value = self.project
        for key in path.split("."):
            if not isinstance(value, dict) or key not in value:
                raise KeyError(f"project.yml has no {path!r}")
            value = value[key]
        return value


def discover(root: Path, project: dict) -> dict:
    """Every check, by name, in the folders project.yml points at.

    Sorted so a run reports in the same order every time — a diff between two
    CI logs should be about what failed, not about what order things ran in.
    """
    found = {}
    for folder in project.get("checks", []):
        directory = root / folder
        if not directory.is_dir():
            sys.exit(f"error: project.yml lists {folder!r}, which does not exist")
        for path in sorted(directory.glob("*.py")):
            if path.stem.startswith("_"):
                continue
            if path.stem in found:
                sys.exit(f"error: two checks are both named {path.stem!r}")
            found[path.stem] = path
    return found


def load(name: str, path: Path):
    """Import a check from its file, without it needing to be on sys.path."""
    spec = importlib.util.spec_from_file_location(f"check_{name}", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    if not hasattr(module, "check"):
        raise AttributeError(f"{path.name} has no check(ctx) function")
    return module


def summary(path: Path) -> str:
    """First docstring line, read WITHOUT importing the file.

    Listing the checks must not run them — importing is not free and a check
    is allowed to do work at import time.
    """
    try:
        doc = ast.get_docstring(ast.parse(path.read_text())) or ""
    except SyntaxError:
        return "(unreadable)"
    return doc.strip().split("\n")[0] or "(no description)"


def run_one(name: str, path: Path, ctx: Context) -> list[str]:
    try:
        problems = load(name, path).check(ctx)
    except Exception:
        # The check itself broke. That is a failure of the check, reported
        # like any other, so one bad file cannot take down the whole run.
        return [f"the check itself raised:\n{traceback.format_exc().rstrip()}"]
    return list(problems or [])


def main() -> int:
    root = find_root()
    project = load_project(root)
    ctx = Context(root, project)
    checks = discover(root, project)
    validation = project.get("validation") or {}
    skipped = validation.get("skip") or project.get("skip", {})
    for name, reason in skipped.items():
        if name not in checks:
            sys.exit(f"error: project.yml skips {name!r}, which is not a check here")
        if not str(reason).strip():
            sys.exit(f"error: project.yml skips {name!r} without saying why")

    parser = argparse.ArgumentParser(
        description=__doc__.split("\n")[0],
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("name", nargs="?", help="run only this check")
    parser.add_argument("--list", action="store_true", help="list the checks and stop")
    args = parser.parse_args()

    if args.list:
        for name, path in checks.items():
            print(f"  {name:<18} {summary(path)}")
        return 0

    # The checks this app must run, named in project.yml, so one cannot quietly go missing when a folder
    # is edited or a file is deleted. A declared skip counts as run.
    expected = validation.get("expected")
    if expected is not None and not args.name:
        missing = sorted(set(expected) - set(checks) - set(skipped))
        extra = sorted(set(checks) - set(expected))
        if missing or extra:
            for name in missing:
                print(f"FAIL  validation.expected lists {name!r}, which this app does not have")
            for name in extra:
                print(f"FAIL  {name!r} runs here but is not in validation.expected")
            return 1

    if args.name:
        if args.name in skipped:
            print(f"skip  {args.name}: {skipped[args.name]}")
            return 0
        if args.name not in checks:
            print(f"error: no check named {args.name!r}", file=sys.stderr)
            print(f"       have: {', '.join(checks)}", file=sys.stderr)
            return 2
        checks = {args.name: checks[args.name]}

    # GitHub folds these, so a green run stays one line and a red one opens
    # on the check that failed.
    on_ci = bool(os.environ.get("GITHUB_ACTIONS"))
    failed = {}

    for name, reason in skipped.items():
        if name in checks:
            print(f"skip  {name}: {reason}")
            del checks[name]

    for name, path in checks.items():
        if on_ci:
            print(f"::group::{name}")
        problems = run_one(name, path, ctx)
        for problem in problems:
            print(f"  {problem}")
        print(f"{'FAIL' if problems else 'ok  '}  {name}")
        if on_ci:
            print("::endgroup::")
        if problems:
            failed[name] = problems

    if failed:
        print()
        for name, problems in failed.items():
            for problem in problems:
                # One annotation per problem, so GitHub shows them inline on
                # the PR rather than only inside the log.
                if on_ci:
                    print(f"::error title={name}::{problem.splitlines()[0]}")
        print(f"{len(failed)} of {len(checks)} checks failed: {', '.join(failed)}")
        return 1

    # Scripts the app owns that belong in validation but are not one of the shared checks: run after
    # them and reported apart, so every app still counts the same checks.
    own_failed = []
    for script in ([] if args.name else validation.get("own", [])):
        path = root / script
        ran = subprocess.run([sys.executable, str(path)], cwd=root, capture_output=True, text=True) if path.is_file() else None
        ok = ran is not None and ran.returncode == 0
        output = (ran.stdout + ran.stderr).strip() if ran else f"{script} does not exist"
        if output:
            print("\n".join(f"  {line}" for line in output.splitlines()))
        print(f"{'ok  ' if ok else 'FAIL'}  own: {script}")
        if not ok:
            own_failed.append(script)
    if own_failed:
        return 1

    own_count = len([] if args.name else validation.get("own", []))
    print(f"\nall {len(checks)} checks passed" + (f" (+ {own_count} app script{'s' if own_count != 1 else ''})" if own_count else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
