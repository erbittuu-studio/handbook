"""A target's own files are named for their role, not for the app.

`Info.plist`, `App.entitlements`, `LaunchScreen.storyboard`, `config.json`: the same name in every app, and the same
as the Watch and Widget targets already use. An app's name in a resource file name (`MyApp-Info.plist`) makes every
app's project a little different for no reason, and every script that wants the file has to guess the name.

The app's name belongs in the `@main` file (`<Name>App.swift`) and in extension entry files that declare types named
for it; this check looks only at `App/Resources` and `App/Config`, where nothing should carry it.
"""
from pathlib import Path

ROLE_FOLDERS = ("App/Resources", "App/Config")


def check(ctx):
    name = (ctx.project.get("app") or {}).get("name", "")
    if not name:
        return []

    problems = []
    for folder in ROLE_FOLDERS:
        directory = ctx.root / folder
        if not directory.is_dir():
            continue
        for path in sorted(directory.iterdir()):
            if name.lower() in path.name.lower():
                role = path.name.lower().replace(name.lower(), "").strip("-_. ") or "the role"
                problems.append(
                    f"{path.relative_to(ctx.root)}: named for the app — name it for its role "
                    f"(for example Info.plist, App.entitlements), not {name}"
                    + (f"-{role}" if role != "the role" else "")
                )
    if not problems:
        print("  resource files are named for their role")
    return problems
