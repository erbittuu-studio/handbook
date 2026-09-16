#!/usr/bin/env bash
# status.sh — one table showing where every app stands.
#
# Read-only. Everything here is already discoverable, just never in one place:
# after a week of not looking, "which apps are behind?" takes eight commands
# across three tools, so nobody asks. This is the difference between drift being
# discoverable and drift being visible.
#
# Usage: status.sh [apps-dir]     (default: the directory containing PES)
set -uo pipefail

PES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PES_VERSION="$(tr -d '[:space:]' < "$PES_ROOT/VERSION")"
APPS_DIR="$(cd "${1:-$PES_ROOT/..}" && pwd)"

printf '%-14s %-8s %-11s %-9s %-8s %-10s %s\n' APP LIVE TESTFLIGHT TAG PES DRIFT PR
printf '%.0s-' {1..76}; echo

for dir in "$APPS_DIR"/*/; do
  app="$(basename "$dir")"
  # An app is a repo with an App/ folder and a git remote.
  [[ -d "$dir/App" ]] || continue
  remote="$(git -C "$dir" remote get-url origin 2>/dev/null)" || continue
  repo="${remote#https://github.com/}"; repo="${repo%.git}"

  bundle_id="$(sed -n 's/.*app_identifier *"\([^"]*\)".*/\1/p' "$dir/fastlane/Appfile" 2>/dev/null | head -1)"

  # Live on the App Store — Apple's public lookup, no key required.
  live="-"
  if [[ -n "$bundle_id" ]]; then
    live="$(curl -s --max-time 8 "https://itunes.apple.com/lookup?bundleId=$bundle_id" \
      | python3 -c "
import json,sys
try:
    r = json.load(sys.stdin).get('results') or []
    print(r[0]['version'] if r else '-')
except Exception:
    print('?')" 2>/dev/null)"
  fi

  # Highest version that reached main. Release branches are deleted on merge,
  # so ref names miss them — merged PR head refs are the reliable source.
  testflight="$(gh pr list --repo "$repo" --state merged --limit 100 \
      --json headRefName --jq '.[].headRefName' 2>/dev/null \
    | grep -oE '^release/[0-9]+\.[0-9]+(\.[0-9]+)?' | sed 's|release/||' | sort -V | tail -1)"
  [[ -z "$testflight" || "$testflight" == "$live" ]] && testflight="-"

  tag="$(git -C "$dir" tag -l 'v*' 2>/dev/null | sed 's/^v//' | sort -V | tail -1)"
  [[ -n "$tag" ]] && tag="v$tag" || tag="none"

  pes="-"
  [[ -f "$dir/.pes-version" ]] && pes="$(tr -d '[:space:]' < "$dir/.pes-version")"

  # Drift, from the same check update.sh uses.
  drift="$(bash "$PES_ROOT/scripts/update.sh" --check "$dir" 2>/dev/null \
    | grep -cE '^  (ADD|UPDATE|EXTRA|HOOKS|VENDOR)')"
  [[ "$drift" == "0" ]] && drift="clean" || drift="$drift item"

  prs="$(gh pr list --repo "$repo" --state open --json number 2>/dev/null \
    | python3 -c "import json,sys; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "?")"
  [[ "$prs" == "0" ]] && prs="0" || prs="$prs ⚠"

  # Flag apps behind the current PES version.
  marker=""; [[ "$pes" != "$PES_VERSION" ]] && marker="←"

  printf '%-14s %-8s %-11s %-9s %-8s %-10s %s %s\n' \
    "$app" "$live" "$testflight" "$tag" "$pes" "$drift" "$prs" "$marker"
done

echo
echo "PES $PES_VERSION   ← = behind"
