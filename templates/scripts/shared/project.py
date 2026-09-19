"""Nothing keeps its own copy of a fact that Project.json already states.

Project.json is only a single source of truth while everything actually reads
it. Nothing stops someone typing the bundle id into a workflow, or the locale
list into a lane — it works, it is one line, and the copies drift apart
silently from then on. That is not hypothetical: values kept in several files held together by
comments saying "must match" drifted silently, and one of the drift-checks
guarding them had been pointing at a moved file and quietly passing.

Two kinds of rule:

  - **Re-stated values.** A fact from Project.json typed out again in a file
    that could have read it. Ruby, Python and the workflows can all read JSON,
    so for them there is no excuse.

  - **The copies that cannot be avoided.** A compile-time constant in Swift
    cannot read JSON. Those are checked rather than generated, in a check the
    app owns in `scripts/checks/` beside this one — RealAIApp's
    `catalog_constants.py` holds its pages-per-category to Project.json that
    way.
"""
# Files that legitimately spell the bundle id out: Xcode and Firebase own their
# own formats and cannot read Project.json.
BUNDLE_ID_ALLOWED = (
    "Project.json",
    "App/Resources/GoogleService-Info.plist",
    "CLAUDE.md",
)

SEARCH_DIRS = (".github/workflows", "scripts", "Hosting")

def restated(ctx, value: str, allowed: tuple, folders: tuple = SEARCH_DIRS) -> list[str]:
    """Every place `value` appears literally that is not on the allow-list."""
    problems = []
    for folder in folders:
        directory = ctx.root / folder
        if not directory.is_dir():
            continue
        for path in sorted(directory.rglob("*")):
            if not path.is_file() or path.suffix in {".png", ".jpg", ".svg"}:
                continue
            rel = str(path.relative_to(ctx.root))
            if any(rel == a or rel.startswith(a) for a in allowed):
                continue
            try:
                text = path.read_text(errors="replace")
            except OSError:
                continue
            if value in text:
                line = next(
                    (n for n, l in enumerate(text.splitlines(), 1) if value in l), 0
                )
                problems.append(
                    f"{rel}:{line} spells out {value!r}, which Project.json already "
                    f"states — read it from there instead"
                )
    return problems


def check(ctx):
    problems: list[str] = []

    # The bundle id: everything that needs it can read JSON.
    problems += restated(ctx, ctx.get("app.bundleId"), BUNDLE_ID_ALLOWED)

    if not problems:
        print("  bundle id stated once")
    return problems
