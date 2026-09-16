#!/usr/bin/env bash
#
# promote.sh — copy an app's vendored SYS packages back into PES.
#
# SYSKit is easier to develop inside a real app: Xcode builds it, the simulator
# runs it, and Firebase and SwiftUI are actually present. Editing it in PES means
# a release and a pull for every experiment, which is slow enough that it doesn't
# happen.
#
# So changes flow UP from the app that proved them, then out to every other app
# through update.sh. This script is the "up" half.
#
#   scripts/promote.sh ../RealAIApp            # review the diff
#   scripts/promote.sh ../RealAIApp --apply    # copy it in and run the tests
#
# update.sh refuses to overwrite a package the app has modified, so the two
# directions cannot silently fight: you are told to promote first.
set -euo pipefail

PES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGES=("SYSKit" "SYSFirebase")

APPLY=0
TARGET=""
for arg in "$@"; do
  case "$arg" in
    --apply) APPLY=1 ;;
    -*) echo "unknown option: $arg" >&2; exit 2 ;;
    *) TARGET="$arg" ;;
  esac
done

if [[ -z "$TARGET" ]]; then
  echo "usage: promote.sh <path-to-app> [--apply]" >&2
  exit 2
fi

TARGET="$(cd "$TARGET" 2>/dev/null && pwd)" || { echo "no such directory: $TARGET" >&2; exit 1; }
APP_NAME="$(basename "$TARGET")"

echo "Promoting from $APP_NAME -> PES"
echo

changed=0
for pkg in "${PACKAGES[@]}"; do
  src="$TARGET/App/Packages/$pkg"
  dst="$PES_ROOT/SPM/$pkg"

  if [[ ! -d "$src" ]]; then
    echo "  SKIP    $pkg (not vendored in $APP_NAME)"
    continue
  fi
  if [[ ! -d "$dst" ]]; then
    echo "  NEW     $pkg"
    changed=$((changed + 1))
    [[ $APPLY -eq 1 ]] && cp -R "$src" "$dst"
    continue
  fi

  # .build and .swiftpm are local artefacts in either tree, and .pes-sync is
  # update.sh's own bookkeeping written into the app copy. A difference in any of
  # them is not a change to promote, and reporting it trains people to ignore
  # output — which is how a real change gets promoted without being read.
  if diff -rq --exclude '.build' --exclude '.swiftpm' --exclude '.pes-sync' "$dst" "$src" >/dev/null 2>&1; then
    echo "  SAME    $pkg"
  else
    echo "  CHANGED $pkg"
    diff -ru --exclude '.build' --exclude '.swiftpm' --exclude '.pes-sync' "$dst" "$src" \
      | sed -n '1,80p' | sed 's/^/          /' || true
    changed=$((changed + 1))
    if [[ $APPLY -eq 1 ]]; then
      rsync -a --delete --exclude '.build' --exclude '.swiftpm' --exclude '.pes-sync' "$src/" "$dst/"
    fi
  fi
done

echo
if [[ $changed -eq 0 ]]; then
  echo "Nothing to promote."
  exit 0
fi

if [[ $APPLY -eq 0 ]]; then
  echo "$changed package(s) differ. Re-run with --apply to copy them in."
  exit 0
fi

# A package that only builds inside an app is not a shared package. PES's copy
# has to stand alone — no Xcode, no simulator, no Firebase — or the next app to
# vendor it inherits a broken build.
echo "Running SYSKit tests against the promoted copy..."
if (cd "$PES_ROOT/SPM/SYSKit" && swift test 2>&1 | tail -5); then
  echo
  echo "Promoted $changed package(s). Bump VERSION, then tag."
else
  echo
  echo "✗ Tests failed against the promoted copy — PES must build standalone." >&2
  exit 1
fi
