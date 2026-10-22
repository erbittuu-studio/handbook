#!/bin/sh
# Sets the marketing version from the release branch name. Called by App/ci_scripts/ci_pre_xcodebuild.sh, the one
# file Xcode Cloud finds by name; the logic lives here, in the package PES syncs, so it is the same in every app.
#
# Versioning (PLAYBOOK §5): the marketing version is the branch name (release/X.Y[.Z]); the build number is
# Xcode Cloud's own counter, which overwrites CFBundleVersion at export. No credentials are needed.

set -e

if [ "$CI_XCODEBUILD_ACTION" = "archive" ]; then
  # The sed below uses paths relative to the project folder, so move there first.
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
  #
  # An app on the shared build settings keeps the version in Config/App.xcconfig, one line in a
  # file of its own; the others still carry it in the project file.
  XCCONFIG="Config/App.xcconfig"
  if [ -f "$XCCONFIG" ] && grep -q '^MARKETING_VERSION' "$XCCONFIG"; then
    sed -i '' "s/^MARKETING_VERSION *=.*/MARKETING_VERSION = $VERSION/" "$XCCONFIG"
    echo "Set MARKETING_VERSION=$VERSION in $XCCONFIG."
  else
    PBXPROJ="$(ls -d ./*.xcodeproj | head -1)/project.pbxproj"
    sed -i '' "s/MARKETING_VERSION = [^;]*;/MARKETING_VERSION = $VERSION;/g" "$PBXPROJ"
    echo "Set MARKETING_VERSION=$VERSION in the project."
  fi
fi
