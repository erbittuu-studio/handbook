#!/usr/bin/env python3
"""Photographs every screen an app can show, so a UI change can be looked at in one place.

    python3 App/Packages/PES/ci/screenshot_sweep.py --build              # build, then photograph
    python3 App/Packages/PES/ci/screenshot_sweep.py --app path/to/X.app  # photograph a build you have
    python3 App/Packages/PES/ci/screenshot_sweep.py --update-baseline    # keep this run as the reference
    python3 App/Packages/PES/ci/screenshot_sweep.py --only settings,quiz # just those screens

What to photograph is the `sweep:` section of project.yml:

    sweep:
      device: iPhone 17 Pro        # simulator name or UDID
      wait: 14                     # seconds a screen gets to settle
      orientation: portrait
      defaults: {sys_notifications_asked: true}   # written to the app's defaults first
      screens:
        home:                      # no route: a plain launch
        settings: settings         # -debugRoute settings
        reader: reader/some_id     # -debugRoute reader/some_id
        offline: state:offline     # -debugState offline

Each screen is launched with the debug arguments SYSKit reads (`SYSDebugRoute`), so an app needs
no extra code. Output goes to `.screenshots/current/`, with an `index.html` that puts each screen
beside its baseline in `.screenshots/baseline/` and says how much of it changed. The status bar is
ignored in that comparison, since the clock is never the same twice. Comparing needs Pillow
(`pip install pillow`); without it the pictures are still taken and shown side by side.

Exits 1 when a screen changed by more than --threshold percent, or could not be photographed.
Simulators are driven one at a time: two sweeps on one device corrupt each other's pictures.
"""
import argparse
import html
import json
import shutil
import subprocess
import sys
import time
from pathlib import Path

STATUS_BAR_FRACTION = 0.06
CHANGED_PIXEL_DELTA = 24


def find_root() -> Path:
    for folder in [Path(__file__).resolve(), *Path(__file__).resolve().parents]:
        if (folder / "project.yml").is_file():
            return folder
    sys.exit("error: no project.yml in any parent directory")


def load_project(root: Path) -> dict:
    converted = subprocess.run(
        ["ruby", "-ryaml", "-rjson", "-e", "puts JSON.generate(YAML.safe_load(File.read(ARGV[0]), aliases: true))",
         str(root / "project.yml")],
        capture_output=True, text=True,
    )
    if converted.returncode != 0:
        sys.exit(f"error: project.yml is not valid YAML:\n{converted.stderr.strip()}")
    return json.loads(converted.stdout)


def run(command: list, timeout: int = 120, check: bool = True) -> subprocess.CompletedProcess:
    result = subprocess.run(command, capture_output=True, text=True, timeout=timeout)
    if check and result.returncode != 0:
        sys.exit(f"error: {' '.join(command[:4])} failed:\n{(result.stderr or result.stdout).strip()}")
    return result


def resolve_device(wanted: str) -> str:
    devices = json.loads(run(["xcrun", "simctl", "list", "devices", "available", "-j"]).stdout)["devices"]
    matches = [d for runtime in devices.values() for d in runtime if wanted in (d["udid"], d["name"])]
    if not matches:
        sys.exit(f"error: no available simulator named {wanted!r} (xcrun simctl list devices available)")
    booted = [d for d in matches if d["state"] == "Booted"]
    return (booted or matches)[0]["udid"]


def build_app(root: Path, project: dict) -> Path:
    scheme = project["app"].get("scheme", "App")
    xcodeproj = next((root / "App").glob("*.xcodeproj"), None)
    if xcodeproj is None:
        sys.exit("error: no .xcodeproj under App/")
    derived = root / ".screenshots" / "build"
    print(f"building scheme {scheme} ...")
    result = subprocess.run(
        ["xcodebuild", "-project", str(xcodeproj), "-scheme", scheme,
         "-destination", "generic/platform=iOS Simulator", "CODE_SIGNING_ALLOWED=NO",
         "-derivedDataPath", str(derived), "build"],
        capture_output=True, text=True,
    )
    if "BUILD SUCCEEDED" not in result.stdout:
        sys.exit("error: the build failed:\n" + "\n".join(
            line for line in result.stdout.splitlines() if "error:" in line)[:2000])
    apps = sorted((derived / "Build" / "Products" / "Debug-iphonesimulator").glob("*.app"))
    if not apps:
        sys.exit("error: the build produced no .app")
    return apps[0]


def write_defaults(udid: str, bundle_id: str, defaults: dict) -> None:
    for key, value in defaults.items():
        if isinstance(value, bool):
            kind, text = "-bool", "true" if value else "false"
        elif isinstance(value, int):
            kind, text = "-int", str(value)
        else:
            kind, text = "-string", str(value)
        run(["xcrun", "simctl", "spawn", udid, "defaults", "write", bundle_id, key, kind, text], check=False)


def launch_arguments(route, orientation: str) -> list:
    arguments = ["-debugOrientation", orientation] if orientation else []
    if route:
        if str(route).startswith("state:"):
            arguments += ["-debugState", str(route).split(":", 1)[1]]
        else:
            arguments += ["-debugRoute", str(route)]
    return arguments


def photograph(udid: str, bundle_id: str, route, orientation: str, wait: float, target: Path) -> bool:
    run(["xcrun", "simctl", "terminate", udid, bundle_id], check=False)
    launched = run(["xcrun", "simctl", "launch", udid, bundle_id, *launch_arguments(route, orientation)], check=False)
    if launched.returncode != 0:
        print(f"      launch failed: {launched.stderr.strip()}")
        return False
    time.sleep(wait)
    shot = run(["xcrun", "simctl", "io", udid, "screenshot", str(target)], check=False)
    return shot.returncode == 0 and target.is_file()


def changed_percent(current: Path, baseline: Path):
    try:
        from PIL import Image, ImageChops
    except ImportError:
        return None
    with Image.open(current) as a, Image.open(baseline) as b:
        a, b = a.convert("RGB"), b.convert("RGB")
        if a.size != b.size:
            return 100.0
        top = int(a.height * STATUS_BAR_FRACTION)
        a, b = a.crop((0, top, a.width, a.height)), b.crop((0, top, b.width, b.height))
        difference = ImageChops.difference(a, b).convert("L").point(lambda v: 255 if v > CHANGED_PIXEL_DELTA else 0)
        changed = sum(1 for v in difference.getdata() if v)
        return 100.0 * changed / (a.width * a.height)


def write_report(out: Path, baseline: Path, rows: list) -> None:
    cells = []
    for name, status, percent in rows:
        before = f'<img src="../baseline/{name}.png">' if (baseline / f"{name}.png").is_file() else "<p>no baseline</p>"
        after = f'<img src="{name}.png">' if status != "failed" else "<p>could not be photographed</p>"
        note = "failed" if status == "failed" else ("" if percent is None else f"{percent:.2f}% changed")
        cells.append(
            f'<section class="{status}"><h2>{html.escape(name)} <small>{note}</small></h2>'
            f"<div>{before}{after}</div></section>"
        )
    (out / "index.html").write_text(
        "<!doctype html><meta charset=utf-8><title>Screenshot sweep</title>"
        "<style>body{font:14px system-ui;margin:24px;background:#222;color:#eee}"
        "section{margin:0 0 32px}h2{font-size:15px}small{color:#aaa;font-weight:400}"
        "section.changed h2 small,section.failed h2 small{color:#ff9f0a}"
        "div{display:flex;gap:16px}img{height:560px;border-radius:12px}</style>"
        "<h1>Left: baseline. Right: this run.</h1>" + "".join(cells)
    )


def main() -> None:
    parser = argparse.ArgumentParser(description="Photograph every screen the app can show.")
    parser.add_argument("--app", help="a built .app to install")
    parser.add_argument("--build", action="store_true", help="build the app first")
    parser.add_argument("--device", help="simulator name or UDID (default: sweep.device)")
    parser.add_argument("--only", help="comma-separated screen names")
    parser.add_argument("--wait", type=float, help="seconds each screen settles (default: sweep.wait)")
    parser.add_argument("--orientation", help="portrait or landscape (default: sweep.orientation)")
    parser.add_argument("--threshold", type=float, default=1.0, help="percent changed that counts as a change")
    parser.add_argument("--update-baseline", action="store_true", help="keep this run as the baseline")
    arguments = parser.parse_args()

    root = find_root()
    project = load_project(root)
    sweep = project.get("sweep") or sys.exit("error: project.yml has no `sweep:` section")
    screens = sweep.get("screens") or sys.exit("error: sweep.screens is empty")
    bundle_id = project["app"]["bundleId"]

    chosen = {name: screens[name] for name in (arguments.only.split(",") if arguments.only else screens)
              if name in screens}
    unknown = [n for n in (arguments.only.split(",") if arguments.only else []) if n not in screens]
    if unknown:
        sys.exit(f"error: not in sweep.screens: {', '.join(unknown)}")

    app = Path(arguments.app).resolve() if arguments.app else build_app(root, project) if arguments.build else None
    if app is None:
        sys.exit("error: pass --build or --app <path to .app>")
    if not app.is_dir():
        sys.exit(f"error: {app} is not a built app")

    udid = resolve_device(arguments.device or sweep.get("device") or "iPhone 17 Pro")
    run(["xcrun", "simctl", "boot", udid], check=False)
    run(["xcrun", "simctl", "bootstatus", udid, "-b"], timeout=300, check=False)
    run(["xcrun", "simctl", "install", udid, str(app)])
    write_defaults(udid, bundle_id, sweep.get("defaults") or {})

    out = root / ".screenshots" / "current"
    baseline = root / ".screenshots" / "baseline"
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)

    wait = arguments.wait if arguments.wait is not None else float(sweep.get("wait", 14))
    orientation = arguments.orientation or sweep.get("orientation", "portrait")
    rows, worst, failed = [], 0.0, False
    for name, route in chosen.items():
        print(f"  {name:<14}", end="", flush=True)
        target = out / f"{name}.png"
        if not photograph(udid, bundle_id, route, orientation, wait, target):
            rows.append((name, "failed", None))
            failed = True
            print("FAILED")
            continue
        reference = baseline / f"{name}.png"
        percent = changed_percent(target, reference) if reference.is_file() else None
        status = "changed" if percent is not None and percent > arguments.threshold else "ok"
        worst = max(worst, percent or 0.0)
        rows.append((name, status, percent))
        print("no baseline" if not reference.is_file() else
              ("compare needs Pillow" if percent is None else f"{percent:.2f}% changed"))
    run(["xcrun", "simctl", "terminate", udid, bundle_id], check=False)

    if arguments.update_baseline:
        baseline.mkdir(parents=True, exist_ok=True)
        for name, status, _ in rows:
            if status != "failed":
                shutil.copy(out / f"{name}.png", baseline / f"{name}.png")
        print(f"\nbaseline updated: {baseline}")
    write_report(out, baseline, rows)
    print(f"\nreport: {out / 'index.html'}")

    changed = [name for name, status, _ in rows if status == "changed"]
    if changed:
        print(f"over {arguments.threshold}%: {', '.join(changed)}")
    sys.exit(1 if failed or changed else 0)


if __name__ == "__main__":
    main()
