#!/usr/bin/env bash
# rename-project.sh — give an app the standard project and scheme name: App/App.xcodeproj, scheme "App".
#
#   scripts/rename-project.sh <app-dir>
#
# Only the Xcode project and its main scheme are renamed. The product name, bundle ID, targets and the
# display name do not change, so the store identity is untouched. Commits nothing; review the diff.
#
# One thing this cannot do: the Xcode Cloud workflow lives in App Store Connect and still names the old
# project path and scheme. Open each workflow in Xcode (Product > Xcode Cloud > Manage Workflows) and point
# it at App/App.xcodeproj and the scheme "App" before the next release branch is pushed.
set -euo pipefail

PES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="$(cd "${1:?usage: rename-project.sh <app-dir>}" && pwd)"
[[ -f "$TARGET/project.yml" ]] || { echo "migrate to project.yml first: scripts/migrate-config.sh"; exit 1; }
value() { bash "$PES_ROOT/templates/scripts/ci/project_value.sh" "$1" "$TARGET"; }

OLD_PROJECT="$(basename "$(value app.project)" .xcodeproj)"
OLD_SCHEME="$(value app.scheme)"
[[ "$OLD_PROJECT" != "App" || "$OLD_SCHEME" != "App" ]] || { echo "already App/App.xcodeproj, scheme App"; exit 0; }

cd "$TARGET/App"
move() { if git ls-files --error-unmatch "$1" >/dev/null 2>&1; then git mv "$1" "$2"; else mv "$1" "$2"; fi; }

if [[ "$OLD_PROJECT" != "App" ]]; then
  [[ -d "$OLD_PROJECT.xcodeproj" ]] || { echo "no App/$OLD_PROJECT.xcodeproj"; exit 1; }
  [[ ! -e App.xcodeproj ]] || { echo "App/App.xcodeproj already exists"; exit 1; }
  move "$OLD_PROJECT.xcodeproj" App.xcodeproj
  # Untracked leftovers (user state) stay in the old folder; carry them over so Xcode keeps its window state.
  if [[ -d "$OLD_PROJECT.xcodeproj" ]]; then
    cp -R "$OLD_PROJECT.xcodeproj/." App.xcodeproj/ 2>/dev/null || true
    rm -rf "$OLD_PROJECT.xcodeproj"
  fi
  # The project name appears in the project file only as comments Xcode regenerates; keep them accurate.
  sed -i '' "s/PBXProject \"$OLD_PROJECT\"/PBXProject \"App\"/g" App.xcodeproj/project.pbxproj
  # Every scheme in the project points back at its container by file name.
  for scheme in App.xcodeproj/xcshareddata/xcschemes/*.xcscheme; do
    [[ -f "$scheme" ]] && sed -i '' "s|container:$OLD_PROJECT.xcodeproj|container:App.xcodeproj|g" "$scheme"
  done
fi

if [[ "$OLD_SCHEME" != "App" && -f "App.xcodeproj/xcshareddata/xcschemes/$OLD_SCHEME.xcscheme" ]]; then
  move "App.xcodeproj/xcshareddata/xcschemes/$OLD_SCHEME.xcscheme" "App.xcodeproj/xcshareddata/xcschemes/App.xcscheme"
fi

cd "$TARGET"
python3 - "$OLD_PROJECT" "$OLD_SCHEME" <<'PY'
import re, sys
old_project, old_scheme = sys.argv[1], sys.argv[2]
text = open("project.yml").read()
text = re.sub(r"(^\s+project:\s*)\S+", r"\1App/App.xcodeproj", text, count=1, flags=re.M)
text = re.sub(r"(^\s+scheme:\s*)\S+", r"\1App", text, count=1, flags=re.M)
text = re.sub(r"(^  schemes:.*)", lambda m: re.sub(r"(?<![\w-])" + re.escape(old_scheme) + r"(?![\w-])", "App", m.group(1)), text, count=1, flags=re.M)
open("project.yml", "w").write(text)
# Human docs that spell the old names out.
for doc in ("README.md", "CLAUDE.md", "CONTRIBUTING.md"):
    try: body = open(doc).read()
    except FileNotFoundError: continue
    body = body.replace(f"App/{old_project}.xcodeproj", "App/App.xcodeproj").replace(f"{old_project}.xcodeproj", "App.xcodeproj")
    body = body.replace(f"-scheme {old_scheme}", "-scheme App").replace(f"scheme `{old_scheme}`", "scheme `App`")
    open(doc, "w").write(body)
PY

bash "$PES_ROOT/scripts/sync-schemes.sh" "$TARGET" >/dev/null

# Re-render everything that carries the project path (workflow filters, the version-stamp fallback, ...).
bash "$PES_ROOT/scripts/update.sh" "$TARGET" | grep -E "UPDATE|ADD|✗" || true
rm -rf "$TARGET/Hosting" "$TARGET/firebase.json"

echo
echo "Renamed: App/App.xcodeproj, scheme App. Product name and bundle ID are unchanged."
echo "Now: build Debug and Release, run scripts/validate.py, and re-point the Xcode Cloud workflow (see the top of this script)."
