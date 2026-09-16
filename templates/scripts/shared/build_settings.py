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


def check(ctx):
    pbx_dir = xcodeproj(ctx.root)
    if pbx_dir is None:
        return [f"no .xcodeproj found under {ctx.root / 'App'}"]
    pbx = (pbx_dir / "project.pbxproj").read_text()

    problems = literal_version_keys(ctx.root)

    # Firebase's manual integration needs -ObjC. Without it nothing fails to
    # build; categories just do not load and it breaks at runtime.
    firebase_kit = (ctx.root / "App/Vendor/FirebaseKit").is_dir() or (ctx.root / "App/Packages/FirebaseKit").is_dir()
    if firebase_kit and '"-ObjC"' not in pbx:
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
