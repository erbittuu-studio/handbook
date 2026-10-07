"""No large files by accident: audio, video, zips and the like belong in the handbook's content, not in an app repo.

Looks at tracked files over 10 MB. Vendored code (App/Vendor, App/Packages) is left out: frameworks are big by nature.
"""
import subprocess

LIMIT = 10 * 1024 * 1024
VENDORED = ("App/Vendor/", "App/Packages/")


def check(ctx):
    listed = subprocess.run(["git", "-C", str(ctx.root), "ls-files", "-z"], capture_output=True, text=True)
    problems = []
    for name in listed.stdout.split("\0"):
        if not name or name.startswith(VENDORED):
            continue
        path = ctx.root / name
        if path.is_file() and path.stat().st_size > LIMIT:
            problems.append(f"{name}: {path.stat().st_size / 1048576:.1f} MB, over {LIMIT // 1048576} MB; keep large files out of the app repo")
    return problems
