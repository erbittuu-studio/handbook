#!/usr/bin/env bash
# update.sh — bring an app repo up to the current PES version.
#
# Usage:
#   update.sh --check <app-dir>    report drift, change nothing
#   update.sh <app-dir>            rewrite the managed files
#
# setup.sh creates an app and never overwrites anything; this is the other
# half — it owns a fixed set of files and replaces them outright, leaving
# everything the app customises alone. Placeholders are re-rendered from the
# app itself.
set -euo pipefail

PES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PES_VERSION="$(tr -d '[:space:]' < "$PES_ROOT/VERSION")"

CHECK=0
if [[ "${1:-}" == "--check" ]]; then CHECK=1; shift; fi
TARGET="$(cd "${1:?usage: update.sh [--check] <app-dir>}" && pwd)"

# Whole directories PES owns, copied wholesale.
MANAGED_DIRS=(
  "App/Packages/SYSKit"
  "App/Packages/SYSFirebase"
)

# App-owned files PES only *seeds*: added when absent, never overwritten.
# Files an earlier PES owned that the current one replaces — removed on
# update, since carrying both means some checks run twice and some not at all.
RETIRED=(
  "scripts/ci/validate_analytics_events.py"
  "scripts/ci/validate_config.py"
  "scripts/ci/validate_urls.py"
  "scripts/ci/validate_sys_adoption.py"
  "scripts/ci/validate_screenshots.py"
  # Store content left the app repos (PLAYBOOK §6): the listing lives in Firebase
  # and fastlane exists only in the website repo.
  "scripts/shared/screenshots.py"
  "scripts/ci/asc_release_state.rb"
  # An older generation of nine separate workflow files, since consolidated:
  # pr.yml absorbs the first six, main.yml the rest.
  ".github/workflows/lint.yml"
  ".github/workflows/pr-guards.yml"
  ".github/workflows/validate-metadata.yml"
  ".github/workflows/validate-screenshots.yml"
  ".github/workflows/validate-release.yml"
  ".github/workflows/ci-data.yml"
  ".github/workflows/deploy-data.yml"
  ".github/workflows/store-metadata.yml"
  ".github/workflows/store-screenshots.yml"
  ".github/workflows/release-merge.yml"
)

SEEDED=(
  "Project.json|app/Project.json"
  "App/Source/Shared/AnalyticsManager.swift|app/AnalyticsManager.swift"
  "firebase.json|app/firebase.json"
  "Hosting/config.json|app/config.json"
  "Hosting/build.py|app/build.py"
  "Hosting/steps/site.py|app/site.py"
)

# Files PES owns. Anything not listed here belongs to the app.
MANAGED=(
  ".github/workflows/pr.yml"
  ".github/workflows/main.yml"
  ".github/workflows/release.yml"
  ".github/workflows/diagnose.yml"
  ".github/workflows/xcode-cloud.yml"
  ".github/dependabot.yml"
  ".github/PULL_REQUEST_TEMPLATE.md"
  ".github/ISSUE_TEMPLATE/bug-report.yml"
  ".github/ISSUE_TEMPLATE/feature-request.yml"
  ".github/ISSUE_TEMPLATE/config.yml"
  "App/ci_scripts/ci_post_clone.sh"
  "App/ci_scripts/ci_pre_xcodebuild.sh"
  "App/ci_scripts/ci_post_xcodebuild.sh"
  "scripts/validate.py"
  "scripts/shared/README.md"
  "scripts/shared/analytics_events.py"
  "scripts/shared/build_settings.py"
  "scripts/shared/color_assets.py"
  "scripts/shared/localization.py"
  "scripts/shared/project.py"
  "scripts/shared/urls.py"
  "scripts/ci/asc_builds.rb"
  "scripts/ci/start_xcode_cloud_build.rb"
  "scripts/ci/verify_routing.rb"
  "scripts/ci/xcode_cloud_workflow.rb"
  ".editorconfig"
  ".gitattributes"
  ".githooks/pre-commit"
  ".githooks/pre-push"
  ".githooks/commit-msg"
)

# Where each managed file comes from in templates/.
src_for() {
  case "$1" in
    .github/workflows/*)     echo "workflows/$(basename "$1")" ;;
    .github/ISSUE_TEMPLATE/*) echo "github/ISSUE_TEMPLATE/$(basename "$1")" ;;
    .github/*)               echo "github/$(basename "$1")" ;;
    App/ci_scripts/*)        echo "ci_scripts/$(basename "$1")" ;;
    scripts/shared/*)        echo "scripts/shared/$(basename "$1")" ;;
    scripts/ci/*)            echo "scripts/ci/$(basename "$1")" ;;
    scripts/validate.py)     echo "scripts/validate.py" ;;
    .editorconfig)           echo "assets/editorconfig" ;;
    .gitattributes)          echo "assets/gitattributes" ;;
    .githooks/*)             echo "githooks/$(basename "$1")" ;;
    *) return 1 ;;
  esac
}

# Values come from the app, never from a file you have to maintain.
detect() {
  PROJECT_NAME="$(find "$TARGET/App" -maxdepth 1 -name '*.xcodeproj' -exec basename {} .xcodeproj \; 2>/dev/null | head -1)"
  OWNER_REPO="$(git -C "$TARGET" remote get-url origin 2>/dev/null \
                 | sed -E 's|.*github\.com[:/]||; s|\.git$||')"
  OWNER="${OWNER_REPO%%/*}"
  REPO="${OWNER_REPO##*/}"
  FIREBASE_PROJECT_ID="$(python3 -c "
import json,sys
try:    print(json.load(open('$TARGET/.firebaserc'))['projects']['default'])
except Exception: print('')" 2>/dev/null)"

  BUNDLE_ID="$(sed -n 's/.*"bundleId": *"\([^"]*\)".*/\1/p' "$TARGET/Project.json" 2>/dev/null | head -1)"
  CONFIG_URL=""
  [[ -n "$FIREBASE_PROJECT_ID" ]] && CONFIG_URL="https://$FIREBASE_PROJECT_ID.web.app/config.json"

  # Absent means the standard SYSFirebase (Analytics + Crashlytics). An app
  # whose vendored FirebaseKit carries Crashlytics only (Kids Category forbids
  # third-party measurement SDKs) states this so it gets SYSFirebaseCrashlytics
  # instead — SPM resolves every target a manifest declares, so vendoring the
  # standard SYSFirebase without FirebaseAnalytics fails the whole package graph.
  FIREBASE_VARIANT="$(python3 -c "
import json,sys
try:    print(json.load(open('$TARGET/Project.json'))['app'].get('firebaseVariant', ''))
except Exception: print('')" 2>/dev/null)"

  [[ -n "$PROJECT_NAME" ]] || { echo "FAIL: no .xcodeproj under $TARGET/App" >&2; exit 1; }
  [[ -n "$OWNER_REPO"   ]] || { echo "FAIL: no github origin remote in $TARGET" >&2; exit 1; }
}

render() { # <template-src> -> stdout
  sed -e "s|{{PROJECT_NAME}}|$PROJECT_NAME|g" \
      -e "s|{{OWNER}}|$OWNER|g" \
      -e "s|{{REPO}}|$REPO|g" \
      -e "s|{{FIREBASE_PROJECT_ID}}|$FIREBASE_PROJECT_ID|g" \
      -e "s|{{BUNDLE_ID}}|$BUNDLE_ID|g" \
      -e "s|{{CONFIG_URL}}|$CONFIG_URL|g" \
      "$PES_ROOT/templates/$1"
}

detect
current="$(cat "$TARGET/.pes-version" 2>/dev/null | tr -d '[:space:]' || true)"

echo "$(basename "$TARGET"): PES ${current:-unknown} -> $PES_VERSION"
echo "  project=$PROJECT_NAME  repo=$OWNER/$REPO  firebase=${FIREBASE_PROJECT_ID:-none}"
echo

# One manifest fingerprinting every MANAGED file, so `shasum -c` can read it
# directly. Bootstraps itself: an app with no manifest yet gets the old
# behaviour once (overwritten unconditionally if the render differs). Only
# once a file has a recorded baseline does a mismatch mean "the app changed
# this" rather than "PES moved on".
MANIFEST="$TARGET/.pes-sync-manifest"
MANIFEST_NEW="$TARGET/.pes-sync-manifest.new"
[[ $CHECK -eq 0 ]] && : > "$MANIFEST_NEW"

file_hash() { shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'; }

manifest_get() { # <relpath> -> baseline hash on stdout, or nothing + failure
  [[ -f "$MANIFEST" ]] || return 1
  awk -v p="$1" '$2 == p { print $1; f=1 } END { exit !f }' "$MANIFEST"
}

changed=0 missing=0
for rel in "${MANAGED[@]}"; do
  src="$(src_for "$rel")" || continue
  [[ -f "$PES_ROOT/templates/$src" ]] || continue

  if [[ ! -f "$TARGET/$rel" ]]; then
    echo "  ADD     $rel"; missing=$((missing+1))
  elif ! render "$src" | diff -q - "$TARGET/$rel" >/dev/null 2>&1; then
    baseline="$(manifest_get "$rel" || true)"
    if [[ -n "$baseline" ]] && [[ "$(file_hash "$TARGET/$rel")" != "$baseline" ]]; then
      echo "  ✗ $rel has local changes that are not in PES."
      echo "    Overwriting would delete them. Move the change into PES and"
      echo "    re-sync, or discard it first:  git checkout -- $rel"
      exit 1
    fi
    echo "  UPDATE  $rel"; changed=$((changed+1))
  fi

  if [[ $CHECK -eq 0 ]]; then
    mkdir -p "$TARGET/$(dirname "$rel")"
    render "$src" > "$TARGET/$rel"
    [[ "$rel" == *.sh ]] && chmod +x "$TARGET/$rel"
    printf '%s  %s\n' "$(file_hash "$TARGET/$rel")" "$rel" >> "$MANIFEST_NEW"
  fi
done

# Swapped in only after every MANAGED file has processed without a refusal —
# otherwise a half-written manifest would record baselines for files never
# actually re-synced this run.
[[ $CHECK -eq 0 ]] && mv "$MANIFEST_NEW" "$MANIFEST"

for rel in "${RETIRED[@]}"; do
  [[ -e "$TARGET/$rel" ]] || continue
  echo "  REMOVE  $rel  (superseded)"; changed=$((changed+1))
  [[ $CHECK -eq 0 ]] && rm -f "$TARGET/$rel"
done

# Seed anything the app is missing, then leave it alone forever after.
for entry in "${SEEDED[@]}"; do
  rel="${entry%%|*}"; src="${entry##*|}"
  [[ -f "$PES_ROOT/templates/$src" ]] || continue
  [[ -f "$TARGET/$rel" ]] && continue

  echo "  SEED    $rel"; missing=$((missing+1))
  if [[ $CHECK -eq 0 ]]; then
    mkdir -p "$TARGET/$(dirname "$rel")"
    render "$src" > "$TARGET/$rel"
  fi
done

# SYSKit and its Firebase adapter: ours, replaced wholesale — except when the
# app has edited them (promoted back via scripts/promote.sh). A fingerprint of
# what was last synced tells "PES moved on" from "the app changed this"; only
# the second is dangerous to overwrite.
for rel in "${MANAGED_DIRS[@]}"; do
  if [[ "$rel" == "App/Packages/SYSFirebase" && "$FIREBASE_VARIANT" == "crashlytics-only" ]]; then
    rel="App/Packages/SYSFirebaseCrashlytics"
  fi
  src="$PES_ROOT/SPM/$(basename "$rel")"
  [[ -d "$src" ]] || continue

  # SYSFirebase/SYSFirebaseCrashlytics depend on FirebaseKit via a relative
  # path pointing at App/Vendor/FirebaseKit — refuse if the app still vendors
  # it at the pre-split App/Packages/FirebaseKit, or Xcode can't resolve it.
  if [[ "$(basename "$rel")" == SYSFirebase* ]] \
    && [[ ! -d "$TARGET/App/Vendor/FirebaseKit" ]] \
    && [[ -d "$TARGET/App/Packages/FirebaseKit" ]]; then
    echo "  ✗ $rel needs FirebaseKit at App/Vendor/FirebaseKit, but it's still"
    echo "    at App/Packages/FirebaseKit. Move it first (git mv, then update"
    echo "    the XCLocalSwiftPackageReference relativePath in project.pbxproj"
    echo "    and .swiftlint.yml's excluded list), then re-run."
    exit 1
  fi

  stamp="$TARGET/$rel/.pes-sync"
  fingerprint_of() {
    # Content hash of the tracked tree, artefacts excluded, sorted so the
    # result doesn't depend on directory traversal order.
    find "$1" -type f \
      ! -path '*/.build/*' ! -path '*/.swiftpm/*' \
      ! -name '.pes-sync' ! -name '.DS_Store' \
      -exec shasum -a 256 {} \; 2>/dev/null \
      | awk '{print $1}' | sort | shasum -a 256 | awk '{print $1}'
  }

  if [[ ! -d "$TARGET/$rel" ]]; then
    echo "  ADD     $rel/"; missing=$((missing+1))
  elif ! diff -rq --exclude '.build' --exclude '.swiftpm' --exclude '.pes-sync' \
         --exclude '.DS_Store' \
         "$src" "$TARGET/$rel" >/dev/null 2>&1; then

    if [[ -f "$stamp" ]] && [[ "$(fingerprint_of "$TARGET/$rel")" != "$(cat "$stamp")" ]]; then
      echo "  ✗ $rel/ has local changes that are not in PES."
      echo "    Overwriting would delete them. Promote them first:"
      echo "      $PES_ROOT/scripts/promote.sh $TARGET --apply"
      echo "    Or discard them:  rm -rf $TARGET/$rel  and re-run."
      exit 1
    fi
    echo "  UPDATE  $rel/"; changed=$((changed+1))
  fi

  if [[ $CHECK -eq 0 ]]; then
    mkdir -p "$TARGET/$(dirname "$rel")"
    rm -rf "$TARGET/$rel"
    rsync -a --exclude '.build' --exclude '.swiftpm' --exclude '.DS_Store' \
      "$src/" "$TARGET/$rel/"
    fingerprint_of "$TARGET/$rel" > "$stamp"
  fi
done

# Third-party packages: report version drift, never touch contents — apps
# deliberately vendor different product subsets (RealAIApp excludes Analytics
# for the Kids Category), so copying contents could break store compliance.
# App/Vendor/ is checked before the pre-split App/Packages/<Name>, so a
# migrated app's SYSKit/SYSFirebase copy is never mistaken for a third-party
# package sharing App/Packages/ with them.
if [[ -f "$PES_ROOT/vendor.json" ]]; then
  while IFS='|' read -r name want; do
    [[ -n "$name" ]] || continue
    dir="$TARGET/App/Vendor/$name"
    [[ -d "$dir" ]] || dir="$TARGET/App/Packages/$name"
    [[ -d "$dir" ]] || continue          # app does not use this package

    have=""
    [[ -f "$dir/.vendor-version" ]] && have="$(tr -d '[:space:]' < "$dir/.vendor-version")"
    if [[ -z "$have" ]]; then
      if [[ $CHECK -eq 1 ]]; then
        echo "  VENDOR  $name — no .vendor-version (would record $want)"
      else
        printf '%s\n' "$want" > "$dir/.vendor-version"
        echo "  VENDOR  $name — recorded $want"
      fi
    elif [[ "$have" != "$want" ]]; then
      echo "  VENDOR  $name  $have -> $want  (re-vendor by hand, then update .vendor-version)"
    fi
  done < <(python3 -c "
import json,sys
data = json.load(open('$PES_ROOT/vendor.json'))
for name, meta in data['packages'].items():
    print(f\"{name}|{meta['version']}\")
")
fi

# Workflow files PES no longer ships. Left in place, but called out —
# deleting a workflow is the app owner's call, not this script's.
if [[ -d "$TARGET/.github/workflows" ]]; then
  for f in "$TARGET/.github/workflows"/*.yml; do
    [[ -e "$f" ]] || continue
    name="$(basename "$f")"
    case "$name" in pr.yml|main.yml|release.yml|diagnose.yml|xcode-cloud.yml) ;;
      *) echo "  EXTRA   .github/workflows/$name  (not part of PES $PES_VERSION — review and delete)" ;;
    esac
  done
fi

# Files the app owns but that started from a template: report only.
for rel in .gitignore .swiftlint.yml; do
  case "$rel" in
    .gitignore)     src="assets/gitignore" ;;
    .swiftlint.yml) src="assets/swiftlint.yml" ;;
  esac
  if [[ -f "$TARGET/$rel" ]] && ! diff -q "$PES_ROOT/templates/$src" "$TARGET/$rel" >/dev/null 2>&1; then
    echo "  DIFFERS $rel  (app-owned — check intentionally, not overwritten)"
  fi
done

# SYSKit lands on disk here, but adding it to the Xcode target is a pbxproj
# edit — deliberately not automated, since a bad edit breaks the project.
if [[ -d "$TARGET/App/Packages/SYSKit" ]]; then
  pbx="$(ls "$TARGET/App/"*.xcodeproj/project.pbxproj 2>/dev/null | head -1)"
  if [[ -f "$pbx" ]] && ! grep -q "SYSKit" "$pbx"; then
    echo "  XCODE   SYSKit vendored but not linked — add it in Xcode:"
    echo "          File > Add Package Dependencies > Add Local… > App/Packages/SYSKit"
  fi
fi

# core.hooksPath is per-clone git config, not a file — can't be copied, has
# to be set. A repo with .githooks/ but no hooksPath looks protected and isn't.
if git -C "$TARGET" rev-parse --git-dir >/dev/null 2>&1; then
  hooks_path="$(git -C "$TARGET" config core.hooksPath 2>/dev/null || true)"
  if [[ "$hooks_path" != ".githooks" ]]; then
    echo "  HOOKS   core.hooksPath is '${hooks_path:-unset}' — hooks are NOT active"
    if [[ $CHECK -eq 0 ]]; then
      git -C "$TARGET" config core.hooksPath .githooks
      chmod +x "$TARGET"/.githooks/* 2>/dev/null || true
      echo "  HOOKS   set core.hooksPath=.githooks"
    fi
  fi
fi

echo
if [[ $CHECK -eq 1 ]]; then
  echo "Check only. $changed to update, $missing to add. Re-run without --check to apply."
else
  printf '%s\n' "$PES_VERSION" > "$TARGET/.pes-version"
  echo "Updated to PES $PES_VERSION. Wrote .pes-version. Review the diff and commit."
fi
