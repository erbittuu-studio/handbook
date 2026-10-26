#!/usr/bin/env python3
"""The content pipeline. One command, one step at a time.

    python3 Hosting/build.py site --clean      # stage Hosting/Content/ for deploy
    python3 Hosting/build.py --list            # what the pipeline can do

**A step is a file with a `main()` in it**, under Hosting/steps/ — the same
convention `scripts/validate.py` uses for checks, so there is one idea to learn
rather than two. Adding a step is adding a file; nothing here needs editing.

Each step keeps its own flags: this dispatcher hands the rest of the command
line straight to it, so `build.py site --clean --verbose` reaches site.py
exactly as it always did.
"""
import argparse
import ast
import importlib.util
import sys
from pathlib import Path

STEPS = Path(__file__).resolve().parent / "steps"


def available() -> dict:
    return {p.stem: p for p in sorted(STEPS.glob("*.py")) if not p.stem.startswith("_")}


def load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(f"step_{name}", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def summary(path: Path) -> str:
    """First docstring line, read WITHOUT importing the file.

    Listing what a step does must not run it. One of these does its work at
    import time, so importing it just to read its docstring went looking for a
    file named `--list`.
    """
    try:
        doc = ast.get_docstring(ast.parse(path.read_text())) or ""
    except SyntaxError:
        return "(unreadable)"
    return doc.strip().split("\n")[0] or "(no description)"


def main() -> int:
    steps = available()

    parser = argparse.ArgumentParser(
        description=__doc__.split("\n")[0],
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("step", nargs="?", choices=list(steps), help="which step to run")
    parser.add_argument("--list", action="store_true", help="list the steps and stop")
    args, rest = parser.parse_known_args()

    if args.list or not args.step:
        print("steps:")
        for name, path in steps.items():
            print(f"  {name:<14} {summary(path)}")
        return 0 if args.list else 2

    module = load(args.step, steps[args.step])
    # The step parses its own flags, so hand it a command line that looks like
    # the one it would have had as a standalone script.
    sys.argv = [f"build.py {args.step}", *rest]
    return module.main()


if __name__ == "__main__":
    sys.exit(main())
