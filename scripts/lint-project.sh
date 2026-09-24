#!/usr/bin/env bash
# lint-project.sh — build settings that are wrong but still compile.
#
# CI builds the app, so anything that compiles passes. This covers the settings
# that compile fine and are still broken: a literal version in Info.plist beats
# MARKETING_VERSION, so CI stamps the version, reports success, and ships the
# wrong number every release. Missing -ObjC does not fail the build either — it
# fails Firebase at runtime.
#
# Usage: lint-project.sh <app-dir> [more-app-dirs...]
set -uo pipefail

fail=0

for target in "$@"; do
  app="$(basename "$target")"
  pbx="$(ls "$target/App/"*.xcodeproj/project.pbxproj 2>/dev/null | head -1)"
  [[ -f "$pbx" ]] || continue

  echo "── $app"

  # 1. Literal version keys in Info.plist. This is the one that silently ships
  #    the wrong version: ci_pre_xcodebuild.sh stamps MARKETING_VERSION, and a
  #    literal CFBundleShortVersionString overrides it without any error.
  for plist in "$target/App/Resources/"*-Info.plist "$target/App/Info.plist"; do
    [[ -f "$plist" ]] || continue
    for key in CFBundleShortVersionString CFBundleVersion; do
      value="$(plutil -extract "$key" raw -o - "$plist" 2>/dev/null || true)"
      if [[ -n "$value" && "$value" != \$* ]]; then
        echo "   ✗ $key is literal '$value' in $(basename "$plist")"
        echo "     CI stamps the build setting; this value silently wins over it"
        fail=1
      fi
    done
  done

  # 2. Firebase's manual integration needs -ObjC. Without it nothing fails to
  #    build; categories just do not load and it breaks at runtime.
  # App/Vendor/ is the current convention; App/Packages/ is the pre-split
  # layout some apps still carry.
  if { [[ -d "$target/App/Vendor/FirebaseKit" ]] || [[ -d "$target/App/Packages/FirebaseKit" ]]; } \
    && ! grep -q '"-ObjC"' "$pbx"; then
    echo "   ✗ FirebaseKit is vendored but -ObjC is missing from OTHER_LDFLAGS"
    fail=1
  fi

  # 3. Everything vendors locally (PLAYBOOK §8).
  if grep -q "isa = XCRemoteSwiftPackageReference" "$pbx"; then
    echo "   ✗ references a remote Swift package"
    fail=1
  fi

  # 4. SYSKit on disk but not linked — the migration gap. update.sh copies the
  #    package; adding it to the target is a manual Xcode step, and without it
  #    the app compiles happily while using none of it.
  if [[ -d "$target/App/Packages/SYSKit" ]] && ! grep -q "SYSKit" "$pbx"; then
    echo "   ✗ SYSKit is vendored but not linked in Xcode"
    echo "     File > Add Package Dependencies > Add Local… > App/Packages/SYSKit"
    fail=1
  fi

  # 5. Report-only: settings that differ across the portfolio are often
  #    deliberate, so these are printed rather than failed.
  ios="$(grep -oE 'IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+' "$pbx" | head -1 | awk '{print $3}')"
  swift="$(grep -oE 'SWIFT_VERSION = [0-9.]+' "$pbx" | head -1 | awk '{print $3}')"
  genplist="$(grep -c 'GENERATE_INFOPLIST_FILE = YES' "$pbx")"
  echo "   · iOS ${ios:-?}   Swift ${swift:-?}   GenerateInfoPlist $([[ $genplist -gt 0 ]] && echo yes || echo no)"
done

echo
if [[ $fail -eq 0 ]]; then
  echo "No blocking issues."
else
  echo "Blocking issues found — these compile, and are still wrong."
fi
exit $fail
