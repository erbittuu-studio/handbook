"""Xcode build settings that compile fine and still ship broken.

Each of these passed CI green and only showed up later — a placeholder
version in TestFlight, Firebase categories silently not loading, SYSKit
vendored but never actually used. The compiler cannot catch any of them,
which is why this exists: scripts/lint-project.sh checked this by hand,
for whoever remembered to run it, across the whole portfolio. This runs
it on every PR, for the one app that matters right now.
"""
import plistlib
import re
from pathlib import Path


def xcodeproj(root: Path):
    matches = sorted((root / "App").glob("*.xcodeproj"))
    return matches[0] if matches else None


def literal_version_keys(root: Path) -> list[str]:
    """A literal CFBundleShortVersionString/CFBundleVersion beats the value
    ci_pre_xcodebuild.sh stamps via sed on the pbxproj — silently. Every
    Info.plist under App/ is a candidate, not just the main target's:
    an extension with its own committed Info.plist can carry the same trap.
    """
    problems = []
    for plist in sorted((root / "App").rglob("*.plist")):
        if "/Vendor/" in str(plist) or "/Packages/" in str(plist):
            continue
        if plist.name != "Info.plist" and not plist.name.endswith("-Info.plist"):
            continue
        try:
            with plist.open("rb") as f:
                data = plistlib.load(f)
        except Exception:
            continue
        for key in ("CFBundleShortVersionString", "CFBundleVersion"):
            value = data.get(key)
            if value is not None and not str(value).startswith("$("):
                rel = plist.relative_to(root)
                problems.append(
                    f"{rel}: {key} is a literal {value!r} — CI stamps this via the "
                    "pbxproj at archive time, and a literal value here silently wins"
                )
    return problems


def xcconfig_problems(root: Path, pbx: str) -> list[str]:
    """An app that has opted in (`"xcconfig": true` in Project.json) must actually use the shared
    settings: the files exist, the project points at them, and the version is not also kept in the
    project file, where it would quietly win over the one CI stamps."""
    problems = []
    for name in ("Base.xcconfig", "App.xcconfig"):
        if not (root / "App/Config" / name).is_file():
            problems.append(f"App/Config/{name} is missing — run the PES update")
    if "App.xcconfig" not in pbx or "baseConfigurationReference" not in pbx:
        problems.append(
            "the project does not use App/Config/App.xcconfig — add it in Xcode (Project > Info > "
            "Configurations) so the shared build settings apply"
        )
    if re.search(r"MARKETING_VERSION = ", pbx):
        problems.append(
            "MARKETING_VERSION is still set in the project file — it overrides Config/App.xcconfig, "
            "which is the line CI stamps. Delete it from the project so the xcconfig wins."
        )
    return problems


def scheme_problems(ctx, pbx_dir: Path) -> list[str]:
    """project.yml lists every shared scheme, and nothing else. A scheme added in Xcode has to be written
    down, so the facts about the project are in one place; `scripts/sync-schemes.sh` fills the list in."""
    actual = sorted(p.name[: -len(".xcscheme")] for p in (pbx_dir / "xcshareddata/xcschemes").glob("*.xcscheme"))
    declared = ctx.project.get("app", {}).get("schemes")
    if declared is None:
        return [f"project.yml has no app.schemes — list the project's schemes ({', '.join(actual)}): scripts/sync-schemes.sh"]
    problems = []
    for name in sorted(set(actual) - set(declared)):
        problems.append(f"the project has a shared scheme {name!r} that project.yml app.schemes does not list")
    for name in sorted(set(declared) - set(actual)):
        problems.append(f"project.yml app.schemes lists {name!r}, but the project has no such shared scheme")
    main = ctx.project.get("app", {}).get("scheme")
    if main and main not in declared:
        problems.append(f"app.scheme {main!r} is not in app.schemes")
    return problems


def check(ctx):
    pbx_dir = xcodeproj(ctx.root)
    if pbx_dir is None:
        return [f"no .xcodeproj found under {ctx.root / 'App'}"]
    pbx = (pbx_dir / "project.pbxproj").read_text()

    problems = literal_version_keys(ctx.root)
    problems += scheme_problems(ctx, pbx_dir)

    if ctx.project.get("xcconfig") is True:
        problems += xcconfig_problems(ctx.root, pbx)

    # Firebase's manual integration needs -ObjC. Without it nothing fails to
    # build; categories just do not load and it breaks at runtime.
    firebase_kit = (ctx.root / "App/Vendor/FirebaseKit").is_dir() or (ctx.root / "App/Packages/FirebaseKit").is_dir()
    # Where the flag lives: the project file, or the shared xcconfig for an app that has opted in.
    xcconfig_text = "".join(f.read_text() for f in sorted((ctx.root / "App/Config").glob("*.xcconfig"))) \
        if (ctx.root / "App/Config").is_dir() else ""
    has_objc = '"-ObjC"' in pbx or "-ObjC" in xcconfig_text
    if firebase_kit and not has_objc:
        problems.append(
            "FirebaseKit is vendored but -ObjC is missing from OTHER_LDFLAGS "
            "— it will compile and fail silently at runtime instead"
        )

    # SYSKit on disk but not linked — update.sh copies the package; wiring it
    # into the target is a manual Xcode step, and skipping it compiles fine
    # while using none of it.
    if (ctx.root / "App/Packages/SYSKit").is_dir() and "SYSKit" not in pbx:
        problems.append(
            "SYSKit is vendored at App/Packages/SYSKit but not linked in Xcode — "
            "File > Add Package Dependencies > Add Local… > App/Packages/SYSKit"
        )

    return problems
