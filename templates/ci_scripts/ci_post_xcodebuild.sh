#!/bin/sh
# Xcode Cloud post-build script.
# Uploads dSYMs to Firebase Crashlytics after archive builds so crash
# reports symbolicate. upload-symbols is vendored with FirebaseKit
# (PLAYBOOK §4) — delete this file if the app has no Crashlytics.
set -e

if [ "$CI_XCODEBUILD_ACTION" = "archive" ] && [ -d "$CI_ARCHIVE_PATH" ]; then
  echo "Uploading dSYMs to Crashlytics"
  UPLOAD_SYMBOLS="$CI_PRIMARY_REPOSITORY_PATH/App/Vendor/FirebaseKit/Tools/upload-symbols"
  PLIST="$CI_PRIMARY_REPOSITORY_PATH/App/Resources/GoogleService-Info.plist"

  if [ ! -f "$UPLOAD_SYMBOLS" ]; then
    echo "warning: upload-symbols not found at $UPLOAD_SYMBOLS" >&2
    exit 0
  fi

  "$UPLOAD_SYMBOLS" -gsp "$PLIST" -p ios "$CI_ARCHIVE_PATH/dSYMs"
  echo "dSYM upload complete"
fi
