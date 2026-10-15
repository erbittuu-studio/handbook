"""The system launch screen is the one SYSKit's splash hands off from.

SYSKit starts every splash on the `LaunchBackground` colour and fades it away, so
the move from the system's launch screen to the app's own never jumps. That only
works while the app's launch screen really is that flat colour: a logo drawn at
its natural size cannot match a splash that scales with the device, and a colour
under another name leaves the first frame a different colour from the last.

So every app declares `UILaunchScreen` with `UIColorName` set to `LaunchBackground`
and no image, and ships that colour in its asset catalog.
"""
import json
import plistlib

NAME = "LaunchBackground"


def check(ctx):
    problems = []
    plist = ctx.root / "App" / "Resources" / "Info.plist"
    if not plist.is_file():
        return [f"{plist} does not exist"]

    launch = plistlib.loads(plist.read_bytes()).get("UILaunchScreen")
    if not isinstance(launch, dict):
        problems.append("Info.plist has no UILaunchScreen dictionary")
    else:
        if launch.get("UIColorName") != NAME:
            problems.append(f"UILaunchScreen.UIColorName must be {NAME}, not {launch.get('UIColorName')!r}")
        if "UIImageName" in launch:
            problems.append("UILaunchScreen must not draw an image: it cannot match the splash at every screen size")

    colorset = ctx.root / "App" / "Resources" / "Assets.xcassets" / f"{NAME}.colorset" / "Contents.json"
    if not colorset.is_file():
        problems.append(f"Assets.xcassets has no {NAME}.colorset")
    elif not json.loads(colorset.read_text()).get("colors"):
        problems.append(f"{NAME}.colorset declares no colour")

    if problems:
        problems.append("See Startup/SYSLaunchHandoff.swift for why the launch screen is a flat colour.")
    return problems
