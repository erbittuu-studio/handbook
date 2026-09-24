#!/usr/bin/env bash
# project_value.sh — print one fact from the app's project.yml (or the older Project.json).
#
#   scripts/ci/project_value.sh app.bundleId
#   scripts/ci/project_value.sh ownedPackages        # a list prints one item per line
#
# The one place shell reads the project file, so a workflow or hook never parses it itself.
# YAML is read with Ruby, which is on every Mac and every CI runner; JSON with Python.
set -euo pipefail

KEY="${1:?usage: project_value.sh <dotted.key> [root]}"
ROOT="${2:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

if [[ -f "$ROOT/project.yml" ]]; then
  ruby -ryaml -e '
    value = YAML.safe_load(File.read(ARGV[0]), aliases: true)
    ARGV[1].split(".").each { |part| value = value.is_a?(Hash) ? value[part] : nil }
    value.is_a?(Array) ? puts(value) : (puts value unless value.nil?)
  ' "$ROOT/project.yml" "$KEY"
elif [[ -f "$ROOT/Project.json" ]]; then
  python3 - "$ROOT/Project.json" "$KEY" <<'PY'
import json, sys
value = json.load(open(sys.argv[1]))
for part in sys.argv[2].split("."):
    value = value.get(part) if isinstance(value, dict) else None
if isinstance(value, list):
    print("\n".join(str(v) for v in value))
elif isinstance(value, bool):
    print("true" if value else "false")
elif value is not None:
    print(value)
PY
else
  echo "no project.yml or Project.json in $ROOT" >&2
  exit 1
fi
