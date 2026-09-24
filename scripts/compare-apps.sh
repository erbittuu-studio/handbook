#!/usr/bin/env bash
# compare-apps.sh — the apps side by side, read from each one's project.yml.
#
#   scripts/compare-apps.sh [apps-dir]      (default: the directory containing PES)
#
# Read-only. What differs between apps is written in project.yml (adoption, validation, overrides), so this
# table is a diff of those files and cannot be out of date.
set -euo pipefail
PES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPS_DIR="${1:-$(dirname "$PES_ROOT")}"

python3 - "$APPS_DIR" "$PES_ROOT/templates/scripts/ci/project_value.sh" <<'PY'
import glob, json, os, subprocess, sys
apps_dir, reader = sys.argv[1], sys.argv[2]
apps = sorted(d for d in glob.glob(f"{apps_dir}/*") if os.path.isfile(f"{d}/project.yml"))
def load(d):
    out = subprocess.run(["ruby", "-ryaml", "-rjson", "-e", "puts JSON.generate(YAML.safe_load(File.read(ARGV[0]), aliases: true))", f"{d}/project.yml"], capture_output=True, text=True)
    return json.loads(out.stdout)
data = {os.path.basename(d): load(d) for d in apps}
names = list(data)
w = max(len(n) for n in names) + 2
def row(label, values):
    print(f"{label:<26}" + "".join(f"{str(v)[:w+14]:<{w+16}}" for v in values))
def section(title): print(f"\n{title}\n" + "-" * (26 + (w + 16) * len(names)))
row("", names)
section("Config")
row("PES version", [data[n].get("pes", {}).get("version", "-") for n in names])
row("Schemes", [",".join(data[n]["app"].get("schemes", [])) for n in names])
row("Shared xcconfig", [data[n].get("xcconfig", False) for n in names])
row("Interface languages", [len(data[n]["languages"]["interface"]) if isinstance(data[n]["languages"], dict) else len(data[n]["languages"]) for n in names])
row("Build overrides", [len(data[n].get("overrides") or {}) or "-" for n in names])
row("App scripts in validation", [len((data[n].get("validation") or {}).get("own", [])) or "-" for n in names])
row("Checks expected", [len((data[n].get("validation") or {}).get("expected", [])) or "-" for n in names])
section("SYSKit adoption (yes, or the app declined with a reason)")
features = list(next(iter(data.values())).get("adoption", {}))
for f in features:
    row(f, ["yes" if (data[n].get("adoption") or {}).get(f) is True else "no" for n in names])
section("Reasons an app does not use a feature")
for n in names:
    for f, v in (data[n].get("adoption") or {}).items():
        if v is not True: print(f"  {n}: {f} — {v}")
section("Build settings that differ from Base.xcconfig")
any_override = False
for n in names:
    for k, v in (data[n].get("overrides") or {}).items():
        any_override = True; print(f"  {n}: {k} — {v}")
if not any_override: print("  none")
PY
