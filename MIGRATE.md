# Migration Guide

How I move an existing app onto this system. Read the gotcha table at the
bottom before debugging anything — the answer is probably already there.

Needed on the Mac: Homebrew Ruby on PATH, `gh` CLI logged in, `firebase` CLI
logged in, Xcode signed into the team.

## 0. Already on PES? Use update.sh instead

An app that already has a `.pes-version` just needs:

```sh
handbook/scripts/update.sh --check ../MyApp   # what drifted
handbook/scripts/update.sh ../MyApp           # apply
```

Rewrites only the files PES owns, re-renders placeholders from the app
itself, leaves customizations alone. Run `--check` first and commit before
applying — the diff is the review.

Files it reports but never touches: `.gitignore`, `.swiftlint.yml`, and any
workflow PES no longer ships.

**One step it cannot do for you.** `update.sh` copies SYSKit into
`App/Packages/`, but linking it to the target is a `project.pbxproj` edit
done by hand in Xcode:

> File > Add Package Dependencies… > Add Local… > `App/Packages/SYSKit`
> then add `SYSKit` (and `SYSFirebase`) to the app target's Frameworks.

Until that's done the files are present but unused, which looks like a
finished migration. `scripts/lint-project.sh` and `update.sh` both flag it.

## 1. Repo (30 min)

1. `git init -b main`, copy the standard `.gitignore` first, then one
   snapshot commit of everything as-is.
2. Restructure to the playbook layout: project + sources + `ci_scripts/`
   under `App/`, content under `Hosting/`.
   Each extension target gets its own `App/<Role>/` folder named for what it
   is (`Watch/`, `Widget/`, not `<ProductName>Watch/`) with its own
   entitlements there; the main target's stay in `Resources/` (update
   `CODE_SIGN_ENTITLEMENTS` paths in the pbxproj). Inside `App/Source/`:
   exactly `App/`, `Features/<Name>/`, `Shared/` (PLAYBOOK §1). With
   synchronized folder groups this is plain `git mv`, but a pbxproj with
   `membershipExceptions` (files shared into watch/widget targets) needs
   those relative paths updated in the same commit or the extension targets
   silently lose the files.
3. Run `scripts/setup.sh` from this repo. Fill every `{{PLACEHOLDER}}`
   (`git grep '{{'`), delete the parts this app doesn't need.
4. Clean legacy naming: entry struct, `productName` in pbxproj, file
   headers. Bundle IDs stay.
5. `gh repo create <org>/<Name> --private --source=. --push`.

## 2. Make all dependencies local (1 hr)

List remote deps from `Package.resolved`, then one by one:

- Swift library → download the exact pinned release tag, copy `Sources/` +
  `LICENSE` + a small `Package.swift` into `App/Vendor/<Name>/`. Delete any
  `Documentation.docc` folder — old manifests try to compile its sample code
  and the build fails.
- Firebase → download the matching `Firebase.zip` release. Copy the
  xcframeworks of the needed products into `App/Vendor/FirebaseKit/`
  (binaryTarget package, products named `FirebaseAnalytics` /
  `FirebaseCrashlytics`). Add `-ObjC` to `OTHER_LDFLAGS`. Copy
  `upload-symbols` into `FirebaseKit/Tools/`.
- In the pbxproj, replace every `XCRemoteSwiftPackageReference` with an
  `XCLocalSwiftPackageReference` and remove the `package =` line from the
  matching product dependency.
- Delete every `Package.resolved`. Then check:
  `xcodebuild -resolvePackageDependencies` must list only local packages,
  and a full simulator build must pass.

## 3. Firebase (30 min, if used)

`firebase projects:create <name>-prod` → `firebase apps:create ios` →
`apps:sdkconfig` → plist into `App/Resources/`. **Check
`IS_ANALYTICS_ENABLED` is `true`** — it can sit at `false` silently with no
error, just missing events. `firebase.json` and `.firebaserc` at repo root.
Deploy once by hand to confirm. Create a service account with Hosting rights
only → `gh secret set FIREBASE_SERVICE_ACCOUNT`. Enable Google Analytics in
the console — CLI-created projects don't have it. Turn on Crashlytics email
alerts.

## 4. Xcode Cloud (30 min)

1. Grant access FIRST: github.com → org settings → GitHub Apps → Xcode Cloud
   → add this repo. Without this the wizard fails with no useful error.
2. If the project has an old `xcshareddata/xcodecloud/manifest.json`, delete
   it before onboarding.
3. One workflow, `Release`: **Branch Changes**, pattern `release/` with "is
   prefix" checked, Files and Folders filter set to `App`, Archive →
   TestFlight Internal. Not a tag condition (PLAYBOOK §5). No CI workflow —
   its results never surface in `gh pr checks`.
4. No environment variables. The pre-build script only reads the branch
   name. The ASC API key lives in GitHub Secrets only.
5. In ci_scripts: scripts start inside `ci_scripts/`, so `cd
   "$CI_PRIMARY_REPOSITORY_PATH/App"` first.

## 5. PR checks (30 min)

Copy `pr.yml`, `main.yml`, `release.yml` from `templates/workflows/`
(setup.sh already did this — confirm they're there, delete jobs the app
doesn't need). Open a throwaway PR touching each relevant path once to confirm
each check actually *runs* — a check that never fires looks like coverage
that isn't there.

Private + GitHub Free means no branch protection (classic or Rulesets) —
checks still run red/green, they just don't block the merge button.

## 6. Store content (10 min)

Set `ASC_KEY_ID` / `ASC_ISSUER_ID` / `ASC_KEY_CONTENT` repo secrets (API key
from ASC → Integrations, App Manager role; the .p8 goes to the password
manager, never the repo — same key as step 4, separate copy). The helper
scripts in `scripts/ci/` read them.

The store listing itself is not part of the app repo: it lives in Firebase and
is managed from the website repo (PLAYBOOK §6). Register the app there and its
App Store Sync brings in whatever Apple already has.

## 7. First release

1. `git checkout -b release/X.Y.Z` off `main`.
2. Add the CHANGELOG section for that version. Push. (What users read as
   "What's New" is part of the store listing, managed outside this repo —
   PLAYBOOK §6.)
3. Xcode Cloud builds from the branch directly — watch it in App Store
   Connect, not `gh run list`. Fix and push again to the same branch on
   failure.
4. Build appears in TestFlight → install → test on a real device.
5. Submit in App Store Connect. Rejected? Fix on the same branch and push
   again — nothing is merged or tagged yet.
6. **Once Apple approves**, open a PR from the release branch to `main`, let
   `pr.yml`'s `validate-release` job confirm CHANGELOG + version, merge.
   That merge creates tag `vX.Y.Z` and publishes the GitHub Release
   automatically (`release.yml`).

---

## Gotcha table

| Symptom | Cause / fix |
|---|---|
| `swift test` fails only inside a git hook, passes in the shell | A hook doesn't inherit the shell's toolchain selection, so `swift` picks the Command Line Tools SDK while compiling with Xcode's. Pin `DEVELOPER_DIR="$(xcode-select -p)"`, as the template pre-push hook does |
| Xcode Cloud "Failed to create workflow" | GitHub App has no access to the repo (org owner must add it), or a stale `xcodecloud/manifest.json` in the project — delete it and restart Xcode |
| `xcode-cloud` job fails: `no workflow named 'github_auto_release' in the report above` | `main.yml`/`xcode_cloud_workflow.rb` hardcode that exact name. A workflow made by hand under any other name is invisible to both. Rename the Xcode Cloud workflow to `github_auto_release` |
| Onboarding wizard stuck on a dependency repo | Still have remote packages — make them local (step 2). Also add a GitHub account in Xcode Settings → Accounts |
| `agvtool: There are no Xcode project files` in CI | Xcode Cloud starts scripts inside `ci_scripts/` — cd to the project folder first |
| Archive ships the dev placeholder version even though the pre-build script "ran fine" | agvtool only edits literal Info.plist values — with `GENERATE_INFOPLIST_FILE=YES` it's a silent no-op. Stamp `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in the pbxproj with sed — see the template `ci_pre_xcodebuild.sh` |
| Crashlytics reports arrive unsymbolicated; post-build log says `upload-symbols not found` | dSYM script paths must be `App/Vendor/FirebaseKit/Tools/upload-symbols` and `App/Resources/GoogleService-Info.plist` — a missing `App/` prefix warns and `exit 0`s forever |
| Analytics dashboard empty for weeks, no errors anywhere | `IS_ANALYTICS_ENABLED` sitting at `false` in `GoogleService-Info.plist` — `firebase apps:sdkconfig` can still return `false` even when Analytics is correctly linked, so treat the CLI's value as unreliable. `pr.yml`'s `firebase-config-guard` checks it on every PR |
| Release workflow never triggers | Branch condition pattern is wrong, or "is prefix" isn't checked — `release/1.8.0` needs to match a `release/` prefix |
| Build number climbs forever instead of resetting per version | Xcode Cloud's own global sequential counter (App Store Connect → Xcode Cloud → Settings → Build Number) overwrites `CFBundleVersion` at archive time regardless of what a script sets. Not fixable |
| `gh api .../branches/main/protection` returns 403 "Upgrade to GitHub Pro" | Branch protection needs a paid plan for a private repo |
| `dorny/paths-filter` fails with "Resource not accessible by integration" | The workflow's `permissions:` block needs `pull-requests: read` — `contents: read` alone isn't enough |
| `pr.yml`'s secret-scan flags its own source code | gitleaks' `private-key` rule matches the literal `-----BEGIN PRIVATE KEY-----` string anywhere, including marker text that isn't a real key. Confirm with a local scan, suppress with `# gitleaks:allow` |
| Secret-scan false positive persists after adding `gitleaks:allow` | gitleaks scans each commit individually — a later-commit comment doesn't clear an earlier one. Scan the working tree at HEAD (`--no-git`, no `--log-opts` range) instead of git history |
| Tag never triggers the Release workflow | Still using a tag-based trigger — this system is branch-driven (PLAYBOOK §5) |
| Screenshots run red: "failures of processing" | Apple processed slowly after a successful upload — check the listing before re-running |
| Tag pushed by a workflow triggers nothing | GitHub blocks workflow-created tags from firing other workflows — expected, since releases are branch-driven and the tag is meant to trigger nothing |
| gcloud dies complaining about Python | `export CLOUDSDK_PYTHON=/opt/homebrew/bin/python3.12` |
| Bundler asks for sudo | Never use system Ruby — Homebrew Ruby + `bundle config set --local path vendor/bundle` |
| Need to trigger an Xcode Cloud build without waiting for a real push | `POST /v1/ciBuildRuns` with `relationships.workflow` and `relationships.sourceBranchOrTag` pointing at a `scmGitReferences` id (from `/v1/scmRepositories/{id}/gitReferences`) |

## Moving an existing app to project.yml, the shared xcconfig and the fixed project name

Do these in order, one app at a time, and commit after each. Each is safe to stop after.

1. **One project file.** `scripts/migrate-config.sh ../MyApp`, then `scripts/update.sh ../MyApp`, then
   `python3 scripts/validate.py`. Nothing about the app's behaviour changes.
2. **Shared build settings.** `scripts/adopt-xcconfig.sh ../MyApp` sets `xcconfig: true`, syncs
   `App/Config/Base.xcconfig` and `App.xcconfig`, points the project's Debug and Release configurations at
   `App.xcconfig`, removes the project-level settings `Base.xcconfig` now provides, and moves
   `MARKETING_VERSION` into `App.xcconfig`. Anything that differs is kept and listed. Compare `xcodebuild -showBuildSettings` before and after: the
   values for the app target must be identical, apart from what you meant to change.
3. **Fixed project name** (last, and the only step that touches Xcode Cloud). `scripts/rename-project.sh ../MyApp`
   renames the project and the main scheme to `App` (the product name, bundle ID and targets are kept),
   updates `project.yml` and re-renders the paths. Then do a Debug and a Release build, and re-point the Xcode
   Cloud workflow at `App/App.xcodeproj` and scheme `App` (App Store Connect keeps the old names) before the
   next release branch is pushed.

## Re-pointing Xcode Cloud after the rename

Xcode Cloud workflows live in App Store Connect, not in the repo, and they still name the old project path
and scheme. Nothing in the repo can change that, and the first push of a `release/X.Y.Z` branch after the rename
fails to build until it is done. For each app, once:

1. Open the app's project in Xcode (`App/App.xcodeproj`), then **Product > Xcode Cloud > Manage Workflows**.
2. Open each workflow and choose **Edit Workflow**.
3. Under **Environment** or **General**, confirm the project or workspace is `App/App.xcodeproj`.
4. Under **Actions**, on every Build, Test or Archive action, change the **Scheme** to the one below.
5. Save, then **Start Build** on a branch (any branch, or manually) and confirm it archives.
6. Push the release branch only after that build is green.

| App | Old project and scheme | New project and scheme | Other schemes |
|---|---|---|---|
| ABCLearning | `App/ABCLearning.xcodeproj`, `ABCLearning` | `App/App.xcodeproj`, `App` | none |
| Colorful | `App/Colorful.xcodeproj`, `Colorful` | `App/App.xcodeproj`, `App` | none |
| Drawing | `App/DrawingBook.xcodeproj`, `DrawingBook` | `App/App.xcodeproj`, `App` | none |
| Prarthana | `App/Prarthana.xcodeproj`, `Prarthana` | `App/App.xcodeproj`, `App` | `WatchApp` and `WidgetExtension` are built as part of `App`; only change them if a workflow builds them by name (they were `PrarthanaWatch` and `PrarthanaWidgetExtension`) |

The product name, bundle ID and targets did not change, so the App Store Connect app, TestFlight and the
signing setup are untouched. Only the pointers above are stale.

