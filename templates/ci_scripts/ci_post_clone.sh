#!/bin/sh
# Xcode Cloud post-clone script — runs after Xcode Cloud clones the repo.
# Dependencies are vendored locally (PLAYBOOK §4), so nothing to install.
set -e

echo "Xcode Cloud: post-clone setup complete"
echo "Branch:      $CI_BRANCH"
echo "Tag:         $CI_TAG"
echo "Build #:     $CI_BUILD_NUMBER"
