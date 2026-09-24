#!/usr/bin/env bash
# migrate-config.sh — fold Project.json, .pes-version and .pes-sync-manifest into one project.yml.
#
#   scripts/migrate-config.sh <app-dir>
#
# The "//key": "text" entries in Project.json become real YAML comments above the next key. The result
# is parsed back and compared with the original before anything is removed, so a mistake stops here
# instead of losing a setting. Nothing is committed; review `git diff` and commit it yourself.
set -euo pipefail

TARGET="$(cd "${1:?usage: migrate-config.sh <app-dir>}" && pwd)"
[[ -f "$TARGET/Project.json" ]] || { echo "no Project.json in $TARGET (already migrated?)"; exit 1; }
[[ ! -f "$TARGET/project.yml" ]] || { echo "$TARGET already has a project.yml"; exit 1; }

ruby -ryaml -rjson - "$TARGET" <<'RUBY'
root = ARGV[0]
source = JSON.parse(File.read(File.join(root, "Project.json")))
version = File.exist?(File.join(root, ".pes-version")) ? File.read(File.join(root, ".pes-version")).strip : nil

wrap = lambda do |text|
  text.gsub(/\s+/, " ").scan(/\S.{0,96}(?=\s|\z)|\S+/).map { |line| "# #{line.strip}" }.join("\n")
end

out = +"# project.yml — the facts about this app that more than one tool needs, stated once.\n"
out << "# scripts/shared/project.py fails the build if anything restates them.\n\n"
out << "# What PES version this app was last synced to. update.sh keeps this line current.\n"
out << "pes:\n  version: #{version || "0.0.0"}\n\n"

pending = []
source.each do |key, value|
  if key.start_with?("//")
    pending << value.to_s
  else
    pending.each { |text| out << wrap.call(text) << "\n" }
    pending = []
    out << YAML.dump({ key => value }).sub(/\A---\n/, "") << "\n"
  end
end

manifest = File.join(root, ".pes-sync-manifest")
if File.exist?(manifest)
  out << "# >>> sync manifest - written by update.sh, do not edit\n"
  File.readlines(manifest).each { |line| out << "# #{line}" }
  out << "# <<<\n"
end

File.write(File.join(root, "project.yml"), out.gsub(/\n{3,}/, "\n\n"))

# The new file must say exactly what the old one did.
wanted = source.reject { |key, _| key.start_with?("//") }
parsed = YAML.safe_load(File.read(File.join(root, "project.yml")), aliases: true)
parsed.delete("pes")
unless parsed == wanted
  File.delete(File.join(root, "project.yml"))
  abort "migration stopped: project.yml does not match Project.json, nothing was changed"
end
RUBY

bash "$(dirname "${BASH_SOURCE[0]}")/sync-schemes.sh" "$TARGET" || true

cd "$TARGET"
if git rev-parse --git-dir >/dev/null 2>&1; then
  git rm -q -f Project.json
  [[ -f .pes-version ]] && git rm -q -f .pes-version
  [[ -f .pes-sync-manifest ]] && git rm -q -f .pes-sync-manifest
else
  rm -f Project.json .pes-version .pes-sync-manifest
fi
echo "Migrated: project.yml written; Project.json, .pes-version and .pes-sync-manifest removed."
echo "Next: run the PES update (it now reads project.yml), then scripts/validate.py, then commit."
