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
import re
# Files that legitimately spell the bundle id out: Xcode and Firebase own their
# own formats and cannot read Project.json.
BUNDLE_ID_ALLOWED = (
    "project.yml",
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


# --- adoption: which SYSKit features the app uses, declared and held to ------------------------------
ADOPTION = {
    "bootstrap": r"\bSYSBootstrappedApp\b",
    "analytics": r"\bSYSAnalytics\b",
    "firebase": r"\bSYSFirebase\w*Backend\b",
    "logging": r"\bSYSLogger\b",
    "logFile": r"\bSYSLogFile\b",
    "haptics": r"\bSYSHaptics\b",
    "settings": r"\bSYS(Settings|Stored)\b",
    "network": r"\bSYSNetwork\b",
    "share": r"\bSYSShare\w*\b",
    "notifications": r"\bSYSNotifications\b",
    "quickActions": r"\bSYSQuickActions\b",
    "spotlight": r"\bSYSSpotlight\b",
    "deepLinks": r"\bSYSDeepLink\b",
    "review": r"\bSYS(Review|Rating)\b",
    "about": r"\bSYSAbout\b|\bsysSupportMail\b",
    "assets": r"\bSYSAssets\b",
    "remoteConfig": r"\bSYSConfig\b|requiresConfig:\s*true",
    "crossPromo": r"\bSYSAppCatalog\b|\bSYSMoreAppsSection\b",
}
SOURCE_DIRS = ("App/Source", "App/Watch", "App/Widget")


def used_features(root) -> set[str]:
    text = ""
    for folder in SOURCE_DIRS:
        directory = root / folder
        if directory.is_dir():
            text += "\n".join(p.read_text(errors="replace") for p in directory.rglob("*.swift"))
    return {name for name, pattern in ADOPTION.items() if re.search(pattern, text)}


def adoption_problems(ctx) -> list[str]:
    """`adoption:` says, for each SYSKit feature, `true` (used) or a reason it is not. Declared and actual
    must agree, so a difference between apps is a written decision and a feature cannot go unused, or be
    used without being declared, unnoticed."""
    if ctx.project.get("sys") is False:
        return []
    declared = ctx.project.get("adoption")
    if not isinstance(declared, dict):
        return ["project.yml has no `adoption:` section — declare each SYSKit feature as true, or the reason it is not used"]
    used = used_features(ctx.root)
    problems = []
    for name in ADOPTION:
        value = declared.get(name)
        if value is None:
            problems.append(f"adoption.{name} is not declared — write true, or the reason this app does not use it")
        elif value is True and name not in used:
            problems.append(f"adoption.{name} is true, but the code never uses it")
        elif value is not True and name in used:
            problems.append(f"the code uses {name} but adoption.{name} does not say true")
        elif value is not True and not (isinstance(value, str) and value.strip()):
            problems.append(f"adoption.{name} must be true or a reason, not {value!r}")
    for name in sorted(set(declared) - set(ADOPTION)):
        problems.append(f"adoption.{name} is not a known feature ({', '.join(ADOPTION)})")
    return problems


# --- overrides: build settings that deliberately differ from Base.xcconfig --------------------------
def differing_settings(root) -> set[str]:
    """Keys the project file sets to something other than what Base.xcconfig says."""
    base_file = root / "App/Config/Base.xcconfig"
    projects = sorted((root / "App").glob("*.xcodeproj"))
    if not base_file.is_file() or not projects:
        return set()
    base = {}
    for line in base_file.read_text().splitlines():
        m = re.match(r"^(\w+)(?:\[config=(\w+)\])?\s*=\s*(.+?)\s*(?://.*)?$", line.strip())
        if m and not line.strip().startswith(("//", "#")):
            base[(m.group(1), m.group(2))] = m.group(3).strip()
    norm = lambda v: v.strip().strip('"').replace(" ", "").replace("$(inherited)", "")
    text = (projects[0] / "project.pbxproj").read_text()
    differing = set()
    pattern = re.compile(r"isa = XCBuildConfiguration;.*?buildSettings = \{(.*?)\n\t\t\t\};\n\t\t\tname = (\w+);", re.S)
    for body, name in pattern.findall(text):
        for key, value in re.findall(r"\n\t+(\w+) = (.+);", body):
            wanted = base.get((key, None), base.get((key, name)))
            if wanted is not None and norm(wanted) != norm(value):
                differing.add(key)
    return differing


def override_problems(ctx) -> list[str]:
    """`overrides:` names every build setting this app sets differently from Base.xcconfig, with the
    reason. An unexplained difference is how the apps drifted apart in the first place."""
    if ctx.project.get("xcconfig") is not True:
        return []
    declared = ctx.project.get("overrides") or {}
    actual = differing_settings(ctx.root)
    problems = []
    for key in sorted(actual - set(declared)):
        problems.append(f"the project sets {key} differently from Base.xcconfig, and overrides does not say why")
    for key in sorted(set(declared) - actual):
        problems.append(f"overrides lists {key}, but the project no longer differs from Base.xcconfig on it — remove it")
    for key, reason in declared.items():
        if not (isinstance(reason, str) and reason.strip()):
            problems.append(f"overrides.{key} needs a reason")
    return problems


def check(ctx):
    problems: list[str] = []
    problems += adoption_problems(ctx)
    problems += override_problems(ctx)

    # The bundle id: everything that needs it can read JSON.
    problems += restated(ctx, ctx.get("app.bundleId"), BUNDLE_ID_ALLOWED)

    if not problems:
        print("  bundle id stated once")
    return problems
