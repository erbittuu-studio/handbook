#!/usr/bin/env bash
# setup.sh — copy the PES parts box into an app repo.
#
# Usage: setup.sh [target-dir]      (default: current directory)
#
# Copies everything for a full app product (app + data + store automation).
# Never overwrites existing files — safe to re-run. Afterwards: replace
# {{PLACEHOLDER}}s, DELETE what the app doesn't use, follow MIGRATE.md.
set -euo pipefail

PES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="$(cd "${1:-.}" && pwd)"
copied=0; skipped=0

copy() { # <template-relative-src> <target-relative-dest>
  local src="$PES_ROOT/templates/$1" dest="$TARGET/$2"
  if [[ -e "$dest" ]]; then echo "  skip   $2"; skipped=$((skipped+1)); return; fi
  mkdir -p "$(dirname "$dest")"
  cp "$src" "$dest"
  echo "  create $2"; copied=$((copied+1))
}

echo "PES v$(cat "$PES_ROOT/VERSION") → $TARGET"

# Record the version so scripts/update.sh knows where this app started.
if [[ ! -e "$TARGET/.pes-version" ]]; then
  mkdir -p "$TARGET"
  tr -d '[:space:]' < "$PES_ROOT/VERSION" > "$TARGET/.pes-version"
  echo "  create .pes-version"
fi

# dotfiles
copy assets/gitignore      .gitignore
copy assets/gitattributes  .gitattributes
copy assets/editorconfig   .editorconfig
copy assets/swiftlint.yml  .swiftlint.yml
copy assets/env.example    .env.example

# The facts every check reads. validate.py exits without this file, so an app
# that skips it cannot run a single check.
copy app/Project.json      Project.json
copy app/config.json       Hosting/config.json
copy app/build.py          Hosting/build.py
copy app/site.py           Hosting/steps/site.py

# The public pages the App Store listing points at — privacy, terms, support,
# front page. Self-hosted from day one so there is never an external URL to
# forget about. {{PLACEHOLDER}}s need filling by hand: what the app actually
# collects is not something this script can know.
for page in index privacy terms support 404; do
  copy "hosting-web/$page.html" "Hosting/Web/$page.html"
done
copy hosting-web/style.css    Hosting/Web/style.css
copy hosting-web/robots.txt   Hosting/Web/robots.txt
copy hosting-web/sitemap.xml  Hosting/Web/sitemap.xml

# docs
copy docs/README.template.md    README.md
copy docs/CLAUDE.template.md    CLAUDE.md

# github
copy github/PULL_REQUEST_TEMPLATE.md           .github/PULL_REQUEST_TEMPLATE.md
copy github/ISSUE_TEMPLATE/bug-report.yml      .github/ISSUE_TEMPLATE/bug-report.yml
copy github/ISSUE_TEMPLATE/feature-request.yml .github/ISSUE_TEMPLATE/feature-request.yml
copy github/ISSUE_TEMPLATE/config.yml          .github/ISSUE_TEMPLATE/config.yml
copy github/dependabot.yml                     .github/dependabot.yml

# workflows (delete the ones the app doesn't use)
for wf in pr main release diagnose xcode-cloud; do
  copy "workflows/$wf.yml" ".github/workflows/$wf.yml"
done

# Xcode Cloud scripts (must live beside the .xcodeproj)
for cs in ci_post_clone ci_pre_xcodebuild ci_post_xcodebuild; do
  copy "ci_scripts/$cs.sh" "App/ci_scripts/$cs.sh"
done
chmod +x "$TARGET"/App/ci_scripts/*.sh 2>/dev/null || true

# Git hooks. Committed in .githooks and activated via core.hooksPath, because
# .git/hooks is not versioned — otherwise every clone silently has no hooks.
copy githooks/pre-commit  .githooks/pre-commit
copy githooks/pre-push    .githooks/pre-push
copy githooks/commit-msg  .githooks/commit-msg
chmod +x "$TARGET"/.githooks/* 2>/dev/null || true
if git -C "$TARGET" rev-parse --git-dir >/dev/null 2>&1; then
  git -C "$TARGET" config core.hooksPath .githooks
  echo "  config core.hooksPath=.githooks"
fi

# The checks scripts/validate.py runs — scripts/shared/ is PES's tier, never
# hand-edited; scripts/ci/*.rb are the Xcode Cloud + App Store Connect helpers
# the workflows above call by name.
copy scripts/validate.py                    scripts/validate.py
for shared in README.md analytics_events.py build_settings.py color_assets.py \
              localization.py project.py urls.py; do
  copy "scripts/shared/$shared" "scripts/shared/$shared"
done
for rb in asc_builds start_xcode_cloud_build \
          verify_routing xcode_cloud_workflow; do
  copy "scripts/ci/$rb.rb" "scripts/ci/$rb.rb"
done

# What this app is served over Firebase Hosting.
copy app/firebase.json    firebase.json

# The app's analytics vocabulary. Fixed path — the PR check greps it, so a
# scaffolded app without this file fails analytics-event-guard on its first PR.
copy app/AnalyticsManager.swift  App/Source/Shared/AnalyticsManager.swift

# SYSKit — the shared layer. Vendored as local packages, never fetched.
#
# An app that can't vendor FirebaseAnalytics (Kids Category, or no
# measurement SDK) swaps this for SYSFirebaseCrashlytics by hand afterward:
# rsync SPM/SYSFirebaseCrashlytics over App/Packages/SYSFirebase, link that
# product in Xcode instead, and set "firebaseVariant": "crashlytics-only"
# under "app" in Project.json so update.sh keeps syncing the right one.
for pkg in SYSKit SYSFirebase; do
  if [[ -e "$TARGET/App/Packages/$pkg" ]]; then
    echo "  skip   App/Packages/$pkg"; skipped=$((skipped+1))
  else
    mkdir -p "$TARGET/App/Packages"
    rsync -a --exclude '.build' --exclude '.swiftpm' "$PES_ROOT/SPM/$pkg/" "$TARGET/App/Packages/$pkg/"
    echo "  create App/Packages/$pkg"; copied=$((copied+1))
  fi
done

echo
echo "Done: $copied created, $skipped skipped."
echo "Next: scripts/update.sh <dir>   → fills the placeholders PES owns"
echo "                                    (project name, owner/repo, firebase id)"
echo "      git grep -n '{{'          → fill the rest by hand (docs)"
echo "      delete unused parts (no Data/ → remove the data jobs, etc.)"
echo "      then follow MIGRATE.md"
