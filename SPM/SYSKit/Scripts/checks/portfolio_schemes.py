"""Every app can tell which of the studio's other apps are installed.

The suggestion popup skips an app that is already on the phone. iOS only answers
"is this app installed?" for schemes the asking app lists in
`LSApplicationQueriesSchemes`, and that list cannot come from hosted data. A new
app, or an app missing from the list, would be suggested to people who have it.

So the schemes of the studio's apps are named here once (the same values as
`urlScheme` in the handbook's content/app.json), and each app must list all of
them except the ones it registers itself.
"""
import plistlib

PORTFOLIO = ["abclearning", "colorful", "drawingbook", "prarthana"]


def check(ctx):
    plist = ctx.root / "App" / "Resources" / "Info.plist"
    if not plist.is_file():
        return [f"{plist} does not exist"]

    info = plistlib.loads(plist.read_bytes())
    own = {scheme for entry in info.get("CFBundleURLTypes", []) for scheme in entry.get("CFBundleURLSchemes", [])}
    queried = set(info.get("LSApplicationQueriesSchemes", []))
    missing = [scheme for scheme in PORTFOLIO if scheme not in own and scheme not in queried]
    if not missing:
        return []
    return [
        f"Info.plist LSApplicationQueriesSchemes is missing {', '.join(missing)}: "
        "the suggestion popup would offer those apps to people who already have them. "
        "Add the schemes, and keep PORTFOLIO in this check equal to urlScheme in content/app.json."
    ]
