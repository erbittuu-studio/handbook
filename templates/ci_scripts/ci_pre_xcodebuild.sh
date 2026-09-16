#!/bin/sh
# Xcode Cloud pre-build script
# Runs before every archive build on Apple's CI servers.
#
# Versioning model (PLAYBOOK §5):
#   - The Release workflow triggers on pushes to release/X.Y[.Z] branches
#     only — never on tags. A tag is created once, after that branch merges
#     to main, purely as a permanent record. It never triggers a build.
#   - Marketing version comes straight from the branch name.
#   - Build number is Xcode Cloud's own. It maintains a global sequential
#     counter per app (App Store Connect → Xcode Cloud → Settings → Build
#     Number) and OVERWRITES CFBundleVersion with it at archive/export
#     time, regardless of anything set here. That is not a toggle and is
#     not exposed via the API, so this script does not try to compute one.
#
# Consequence worth knowing: this script needs no credentials at all, so
# the Xcode Cloud Release workflow needs no environment variables. The
# App Store Connect API key lives only in GitHub Secrets, where the store
# metadata and screenshot workflows use it.

set -e

if [ "$CI_XCODEBUILD_ACTION" = "archive" ]; then
  # Xcode Cloud starts scripts in ci_scripts/; the sed below uses a path
  # relative to the project folder, so move there first.
  cd "$CI_PRIMARY_REPOSITORY_PATH/App"

  case "$CI_BRANCH" in
    release/[0-9]*.[0-9]*.[0-9]* | release/[0-9]*.[0-9]*)
      VERSION="${CI_BRANCH#release/}"
      ;;
    *)
      echo "error: archive triggered from branch '$CI_BRANCH', not release/X.Y[.Z] — refusing to build" >&2
      exit 1
      ;;
  esac

  echo "Marketing version: $VERSION (build number is assigned by Xcode Cloud)"

  # GENERATE_INFOPLIST_FILE=YES means CFBundleShortVersionString derives from
  # the MARKETING_VERSION build setting, not a literal Info.plist value —
  # agvtool only edits Info.plist and would silently no-op here. The /g also
  # keeps watch/widget extension targets on the same version.
  #
  # CURRENT_PROJECT_VERSION is left alone: Xcode Cloud overwrites
  # CFBundleVersion with its own counter at export time regardless.
  PBXPROJ="{{PROJECT_NAME}}.xcodeproj/project.pbxproj"
  sed -i '' "s/MARKETING_VERSION = [^;]*;/MARKETING_VERSION = $VERSION;/g" "$PBXPROJ"
  echo "Set MARKETING_VERSION=$VERSION in the project."
fi
