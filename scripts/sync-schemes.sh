#!/usr/bin/env bash
# sync-schemes.sh — write the project's shared schemes into project.yml (`app.schemes`).
#
#   scripts/sync-schemes.sh <app-dir>
#
# The list is what the `build_settings` check holds the project to: a scheme that exists but is not
# listed, or one that is listed but gone, fails the run. Run this after adding or renaming a scheme.
set -euo pipefail

TARGET="$(cd "${1:?usage: sync-schemes.sh <app-dir>}" && pwd)"
[[ -f "$TARGET/project.yml" ]] || { echo "no project.yml in $TARGET"; exit 1; }

python3 - "$TARGET" <<'PY'
import glob, os, re, sys
root = sys.argv[1]
projects = glob.glob(f"{root}/App/*.xcodeproj")
if not projects:
    sys.exit("no .xcodeproj under App/")
schemes = sorted(os.path.basename(p)[:-len(".xcscheme")] for p in glob.glob(f"{projects[0]}/xcshareddata/xcschemes/*.xcscheme"))
if not schemes:
    sys.exit("the project has no shared schemes")

path = f"{root}/project.yml"
text = open(path).read()
main = re.search(r"^\s+scheme:\s*(\S+)", text, re.M)
if main and main.group(1) in schemes:      # the main scheme first, the rest as they are found
    schemes.remove(main.group(1)); schemes.insert(0, main.group(1))
line = "  schemes: [" + ", ".join(schemes) + "]"

# Replace an existing list (flow or block style), or add it straight after `scheme:`.
text = re.sub(r"^  schemes:.*(?:\n  - .*|\n    - .*)*", line, text, count=1, flags=re.M) if re.search(r"^  schemes:", text, re.M) \
    else re.sub(r"(^  scheme:[^\n]*\n)", r"\1" + line + "\n", text, count=1, flags=re.M)
open(path, "w").write(text)
print("schemes:", ", ".join(schemes))
PY
