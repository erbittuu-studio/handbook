#!/usr/bin/env bash
# adopt-xcconfig.sh — switch an app's Xcode project over to the shared build settings.
#
#   scripts/adopt-xcconfig.sh <app-dir>
#
# Sets `xcconfig: true` in project.yml, syncs App/Config/{Base,App}.xcconfig, points the project's
# Debug and Release configurations at App.xcconfig, and removes from the project file every setting that
# Base.xcconfig now provides with the same value. A setting that differs is kept (the project file wins)
# and listed, so a deliberate difference such as a Watch SDK or a newer deployment target survives.
# MARKETING_VERSION moves into App.xcconfig, where release builds stamp it.
#
# Compare `xcodebuild -showBuildSettings` before and after: this script does not commit anything.
set -euo pipefail

PES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="$(cd "${1:?usage: adopt-xcconfig.sh <app-dir>}" && pwd)"
[[ -f "$TARGET/project.yml" ]] || { echo "migrate to project.yml first: scripts/migrate-config.sh"; exit 1; }

python3 - "$TARGET/project.yml" <<'PY'
import re, sys
path = sys.argv[1]
text = open(path).read()
if re.search(r"^xcconfig:", text, re.M):
    text = re.sub(r"^xcconfig:.*$", "xcconfig: true", text, flags=re.M)
else:
    block = '# Opt in to the shared build settings (App/Config/Base.xcconfig). See PLAYBOOK "Shared build settings".\nxcconfig: true\n\n'
    marker = "# >>> sync manifest"
    text = text.replace(marker, block + marker, 1) if marker in text else text.rstrip("\n") + "\n\n" + block
open(path, "w").write(text)
PY

bash "$PES_ROOT/scripts/update.sh" "$TARGET" | grep -E "xcconfig|✗" || true
rm -rf "$TARGET/Hosting" "$TARGET/firebase.json"

python3 - "$TARGET" <<'PY'
import glob, random, re, sys
root = sys.argv[1]
pbx_path = glob.glob(f"{root}/App/*.xcodeproj/project.pbxproj")[0]
t = open(pbx_path).read()

base = {}
for line in open(f"{root}/App/Config/Base.xcconfig"):
    line = line.strip()
    if not line or line.startswith("//") or line.startswith("#"):
        continue
    m = re.match(r"^(\w+)(?:\[config=(\w+)\])?\s*=\s*(.+?)\s*(?://.*)?$", line)
    if m:
        base[(m.group(1), m.group(2))] = m.group(3).strip()

norm = lambda v: v.strip().strip('"').replace(" ", "").replace("$(inherited)", "")
versions, kept = set(), []
pattern = re.compile(r"(isa = XCBuildConfiguration;\s*(?:baseConfigurationReference[^\n]*\n\s*)?buildSettings = \{)(.*?)(\n\t\t\t\};\n\t\t\tname = \w+;)", re.S)

def wanted_for(key, name):
    return base.get((key, None), base.get((key, name)))

# A target-level setting overrides a project-level one, so deleting it because it equals the base is only
# safe if nothing else in the project sets a different value for the same key and configuration; otherwise
# the target would silently inherit that other value. Such keys are left alone everywhere.
differing = set()
for m in pattern.finditer(t):
    name = re.search(r"name = (\w+);", m.group(3)).group(1)
    for line in m.group(2).split("\n"):
        mm = re.match(r"^(\t+)(\w+) = (.+);$", line)
        if mm:
            wanted = wanted_for(mm.group(2), name)
            if wanted is not None and norm(wanted) != norm(mm.group(3)):
                differing.add((mm.group(2), name))

def process(m):
    name = re.search(r"name = (\w+);", m.group(3)).group(1)
    out = []
    for line in m.group(2).split("\n"):
        mm = re.match(r"^(\t+)(\w+) = (.+);$", line)
        if mm:
            key, value = mm.group(2), mm.group(3)
            if key == "MARKETING_VERSION":
                versions.add(value.strip('"'))
                continue
            wanted = wanted_for(key, name)
            if wanted is not None:
                if (key, name) not in differing and norm(wanted) == norm(value):
                    continue
                kept.append(f"{name}: {key} = {value}   (base: {wanted})")
        out.append(line)
    return m.group(1) + "\n".join(out) + m.group(3)

t = pattern.sub(process, t)
# The linker flag Base.xcconfig already carries, written the long way.
t = re.sub(r'\t+OTHER_LDFLAGS = \(\n\t+"\$\(inherited\)",\n\t+"-ObjC",\n\t+\);\n', "", t)

if len(versions) > 1:
    sys.exit(f"MARKETING_VERSION differs between targets ({sorted(versions)}); make them one value first")

used = set(re.findall(r"\b([0-9A-F]{24})\b", t))
def new_id():
    while True:
        candidate = "".join(random.choice("0123456789ABCDEF") for _ in range(24))
        if candidate not in used:
            used.add(candidate); return candidate
app_ref, base_ref, group = new_id(), new_id(), new_id()

project_list = re.search(r"isa = PBXProject;.*?buildConfigurationList = (\w+)", t, re.S).group(1)
ids = re.search(project_list + r"[^=]*= \{\s*isa = XCConfigurationList;\s*buildConfigurations = \((.*?)\);", t, re.S).group(1)
config_ids = re.findall(r"(\w+) /\*", ids)
for config_id in config_ids:
    t = re.sub(r"(\t\t" + config_id + r" /\*[^*]*\*/ = \{\n\t\t\tisa = XCBuildConfiguration;\n)",
               r"\1\t\t\tbaseConfigurationReference = " + app_ref + " /* App.xcconfig */;\n", t, count=1)
# If the project's configurations were not all linked, stop before writing anything: an unlinked project
# would lose the settings removed above and quietly build for the wrong platform.
if t.count("baseConfigurationReference = " + app_ref) != len(config_ids) or not config_ids:
    sys.exit("could not link the project's build configurations to App.xcconfig; the project file was left unchanged")

t = t.replace("/* End PBXFileReference section */",
    f'\t\t{app_ref} /* App.xcconfig */ = {{isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = App.xcconfig; sourceTree = "<group>"; }};\n'
    f'\t\t{base_ref} /* Base.xcconfig */ = {{isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Base.xcconfig; sourceTree = "<group>"; }};\n'
    "/* End PBXFileReference section */", 1)

main_group = re.search(r"mainGroup = (\w+);", t).group(1)
group_block = (f"\t\t{group} /* Config */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n"
               f"\t\t\t\t{app_ref} /* App.xcconfig */,\n\t\t\t\t{base_ref} /* Base.xcconfig */,\n"
               "\t\t\t);\n\t\t\tpath = Config;\n\t\t\tsourceTree = \"<group>\";\n\t\t};\n")
t = t.replace("/* Begin PBXGroup section */\n", "/* Begin PBXGroup section */\n" + group_block, 1)
t = re.sub(r"(\t\t" + main_group + r"(?: /\*[^*]*\*/)? = \{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = \(\n)",
           r"\1\t\t\t\t" + group + " /* Config */,\n", t, count=1)
open(pbx_path, "w").write(t)

if versions:
    version = versions.pop()
    xc = open(f"{root}/App/Config/App.xcconfig").read()
    xc = re.sub(r"^MARKETING_VERSION *=.*$", f"MARKETING_VERSION = {version}", xc, flags=re.M)
    open(f"{root}/App/Config/App.xcconfig", "w").write(xc)
    print(f"MARKETING_VERSION = {version} now lives in App/Config/App.xcconfig")
print("Kept in the project file because they differ from Base.xcconfig:" if kept else "Nothing differs from Base.xcconfig.")
for line in kept:
    print("  ", line)
PY
echo "Done. Next: compare build settings, build Debug and Release, run scripts/validate.py."
