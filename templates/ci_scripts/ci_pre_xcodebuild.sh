#!/bin/sh
# Xcode Cloud runs this file by name before every build. The work is done by the package PES syncs into the app.
exec sh "$CI_PRIMARY_REPOSITORY_PATH/App/Packages/PES/ci/stamp_version.sh"
