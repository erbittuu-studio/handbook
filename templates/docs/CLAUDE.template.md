# CLAUDE.md — {{PROJECT_NAME}}

Guidance for AI assistants working in this repo. The engineering system
here is defined by **Portfolio Engineering Standards (PES)** —
https://github.com/erbittuu-studio/handbook — read its
PLAYBOOK.md for the full picture and MIGRATE.md's gotcha table before
debugging CI/store issues. This file covers what's app-specific and the
rules you must not break.

## App facts

| | |
|---|---|
| Product | {{APP_STORE_NAME}} |
| Xcode project | `App/{{PROJECT_NAME}}.xcodeproj`, scheme `{{PROJECT_NAME}}` |
| Bundle ID | `{{BUNDLE_ID}}` (NEVER change — store identity) |
| Firebase | `{{FIREBASE_PROJECT_ID}}` ({{FIREBASE_SERVICES}}) |
| Store locales | {{STORE_LOCALES}} (must stay in sync across Deliverfile `languages()`, Fastfile `store_locales`, `scripts/ci/validate_screenshots.py` `STORE_LOCALES`) |

## Build & checks

```sh
xcodebuild -project App/{{PROJECT_NAME}}.xcodeproj -scheme {{PROJECT_NAME}} \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
swiftlint lint App/Source          # 0 errors required; warnings tolerated
bundle exec fastlane validate_metadata   # parse-only store text check
```

## Layout (PES PLAYBOOK §1)

- `App/Source/` has exactly three top-level folders: `App/` (entry,
  delegates, root navigation), `Features/<Name>/` (one per feature,
  views + their viewmodels), `Shared/` (used by 2+ features).
- `Shared/AnalyticsManager.swift` is a fixed path — the analytics PR
  check greps it (single enum, name + parameters per case).
- `App/Vendor/` is vendored third-party source — never edit, never
  lint, never add a remote SwiftPM package (a PR guard blocks
  `XCRemoteSwiftPackageReference`). `App/Packages/` is PES's own
  (SYSKit, SYSFirebase) — ours, edited in place, promoted upstream.
- `fastlane/metadata/<locale>.json` is the store-text source of truth;
  the per-locale txt dirs are generated in CI and gitignored.

## Hard rules

- Versions are NOT stored in the repo. `MARKETING_VERSION` in the
  project is a dev placeholder; releases stamp it from the
  `release/X.Y[.Z]` branch name via `App/ci_scripts/ci_pre_xcodebuild.sh`
  (sed on the pbxproj — agvtool does not work here).
- Fastlane lane names `validate_metadata` / `metadata` / `screenshots`
  are a contract with `.github/workflows/` — never rename.
- `IS_ANALYTICS_ENABLED` in `App/Resources/GoogleService-Info.plist`
  must stay `true` (a PR guard asserts it; `false` silently kills all
  analytics).
- No secrets in the repo — `.env.example` documents variables, real
  values live in `fastlane/.env` (gitignored) and GitHub/Xcode Cloud
  secrets.
- Commits: `type: what it does` (feat/fix/chore/docs/refactor/test/ci).
  Squash-merge PRs into `main`; branches auto-delete.

## Release (PES PLAYBOOK §5)

Branch `release/X.Y.Z` off main → push (Xcode
Cloud archives from the branch, TestFlight) → merge PR to main →
`release.yml` creates the `vX.Y.Z` tag + GitHub Release. Tags
never trigger anything.
