# Playbook

How every app of mine works. Reference app: RealAIApp.

---

## 1. Repo layout

One private repo per app. Everything the app needs lives in it:

```
my-app/
├── README.md  CHANGELOG.md
├── .gitignore .gitattributes .editorconfig
├── .swiftlint.yml
├── .pes-version                 # which PES version this app is on (scripts/update.sh)
├── .env.example                 # documents every secret; real values never committed
├── firebase.json  .firebaserc   # must stay at root — Firebase CLI expects it here
├── .github/workflows/           # all automation
├── scripts/ci/                  # PR-check scripts the workflows call into
├── App/                         # only what Xcode compiles
│   ├── <Name>.xcodeproj
│   ├── Source/                  # exactly three top-level folders:
│   │   ├── App/                 #   @main, delegates, root navigation wiring, app-level setup
│   │   ├── Features/<Name>/     #   one folder per user-facing feature (views + their viewmodels)
│   │   └── Shared/              #   anything used by 2+ features; subfolders free-form
│   │                            #   (Components, Content, Engagement, Layout, Settings, Theme, …)
│   │                            #   If the app uses the analytics-enum pattern (§7), it lives at
│   │                            #   Shared/AnalyticsManager.swift — the PR check greps that exact path.
│   ├── Resources/               # assets, xcstrings, PrivacyInfo, GoogleService-Info,
│   │                            #   the main target's own entitlements
│   │                            #   config.json — remote config, shipped AND served
│   ├── <Role>/                  # one folder per extension target (Watch/, Widget/, …),
│   │                            #   named for its role, not the product — its own
│   │                            #   entitlements live right here, not in a shared folder
│   ├── Packages/                # PES's own (SYSKit, SYSFirebase) — ours, edited in
│   │                            #   place, promoted upstream (§8)
│   ├── Vendor/                  # true third-party — never edited, never linted,
│   │                            #   excluded by folder in .swiftlint.yml (§8)
│   └── ci_scripts/              # must stay next to the .xcodeproj — Apple rule
│       └── lib/                 # helpers ci_scripts call into (kept out of the three magic filenames)
└── Hosting/                        # content pipeline, only if the app ships remote content
    ├── build.py  index.json  source/
    └── build/                   # generated, gitignored, CI rebuilds it
```

`firebase.json` at root and `ci_scripts/` next to the xcodeproj are fixed by
the tools. Everything else: App = compile, Data = content,
.github = automation. Store content is not in the app repo (§6).

No empty folders, no unused files. Bundle IDs never change. No per-app
decision docs — the reasoning belongs in [decisions/](decisions/), where it
helps the next app too.

## 2. Who does what

| Actor | Job |
|---|---|
| GitHub | Everything starts here — push a branch, open a PR, merge it |
| GitHub Actions (Ubuntu) | PR checks, data deploy, store metadata, store screenshots, tagging a shipped release |
| Xcode Cloud (Apple Macs) | One job: archive release branches to TestFlight. Nothing else runs there |
| Me | Write code, review my own PRs, merge, test on device, press Submit |

Nothing runs on my Mac for a release.

| Automation | Where | Trigger | Does |
|---|---|---|---|
| `pr.yml` | GH Actions | every PR | Nine jobs: `swiftlint`, `secret-scan`, `dependency-guard`, `firebase-config-guard`, `analytics-event-guard`, `validate-metadata`, `validate-screenshots`, `data-ci` *(optional)*, `validate-release` |
| `main.yml` | GH Actions | merge to main | Three path-gated jobs: `store-metadata` (text only), `store-screenshots` (images only), `deploy-data` *(optional)*. Manual button takes a `job` input to run one on its own |
| `release.yml` | GH Actions | release branch merges to main | creates the `vX.Y.Z` tag + GitHub Release from CHANGELOG |
| `Release` workflow | Xcode Cloud | push to `release/*` | archive → TestFlight; scripts in `App/ci_scripts/` stamp the marketing version and upload dSYMs |
| dependabot | GitHub | weekly | bundler + actions version PRs |

Three workflow files, not one per check: GitHub reports a status per *job*, so
checks stay individually visible while triggers/permissions/concurrency live
in one place. Xcode Cloud runs a single Release workflow only — a CI workflow
there wouldn't surface in `gh pr checks`.

## 3. Branches

One permanent branch: `main`. Everything else is short-lived and deleted on
merge, including release branches.

**Work branches** — `code/*`, `data/*`, `metadata/*` (or `feat/`/`fix/`, pick
one). Branch from `main`, PR into `main`, squash merge, auto-delete. The
prefix is for readability — automation reacts to which files changed, not the
branch name.

**Release branches** — `release/X.Y.Z`, one per version, created only when
about to ship (§5).

No hotfix branch type — a bug in a shipped version is a normal work branch off
`main`, followed by a new `release/X.Y.Z+1`.

## 4. PR checks

Every PR gets automated checks. None hard-block the merge button — GitHub
only offers real branch protection on a private repo with a paid plan — so
treat a red check as "don't merge this," not as something that'll stop you.

All of these are jobs inside `pr.yml`.

| Job | Runs on | Catches |
|---|---|---|
| `swiftlint` | any PR, skips if no `.swift` changed | SwiftLint, non-strict (a fresh migration inherits style debt) |
| `secret-scan` | every PR, always | Committed secrets (gitleaks, working tree at HEAD) — private repos don't get GitHub's free scanning |
| `dependency-guard` | every PR, always | Any `XCRemoteSwiftPackageReference`, and any committed `Package.resolved` |
| `firebase-config-guard` | every PR, always *(if the app has a `GoogleService-Info.plist`)* | `IS_ANALYTICS_ENABLED` set to false — silently drops every event |
| `analytics-event-guard` | every PR, always *(if the app has the §7 analytics enum)* | Event/param names Firebase would silently drop |
| `data-ci` *(optional)* | any PR, skips if `Hosting/` unchanged | Content that doesn't build — source data and manifest structurally sound |
| `validate-release` | any PR, skips unless it's from a `release/*` branch | CHANGELOG has a section for this version; the version is actually newer than the last tag |

Every job triggers on every PR and skips internally rather than being
path-filtered at the trigger level — a required check with no run at all
blocks a merge forever under branch protection.

### Where a check lives says who may edit it

`scripts/validate.py` discovers checks from the folders `Project.json` lists —
a check is a file with a `check(ctx)` in it, no registry to update.

| It checks… | Folder | Owner |
|---|---|---|
| something only this app has | `scripts/checks/` | the app |
| something every app has — the listing, a string catalog, an asset name | `scripts/shared/` | **PES — overwritten on every `update.sh`** |
| a contract of SYSKit itself | `App/Packages/SYSKit/Scripts/checks/` | PES, travels with the vendored package |

A shared check reads anything app-specific out of `Project.json` (screenshot
sizes, languages, locales) rather than hardcoding it — that's the test for
where a new check belongs: if it can't be written without naming something
only this app has, it goes in `scripts/checks/`.

### Declining a shared check, and packages the app owns

An app that genuinely cannot meet a shared check says so in `Project.json`, with
the reason: `"skip": {"analytics_events": "class-based manager, see PES-UPSTREAM.md"}`.
The check is left out of the run and printed as `skip  <name>: <reason>` every
time, so an exception stays visible. A skip without a reason, or for a check that
does not exist, fails the run. Likewise `"ownedPackages": ["SharedUI"]` tells the
pre-commit hook that a package under `App/Packages/` is the app's own code, not
vendored third-party source. `"sys": false` says the app is not built on SYS at all, so
`update.sh` neither vendors SYSKit/SYSFirebase into it nor seeds a template
`AnalyticsManager.swift` over its own.

### Shared build settings (xcconfig)

Every app used to restate the same ~60 project-level build settings (platform, Swift version, compiler and warning flags, linker flags, debug and release differences) inside its own `project.pbxproj`,
and `build_settings` caught the ones that drifted after the fact. They now live once, in the handbook:

| File | Owner | What it holds |
|---|---|---|
| `App/Config/Base.xcconfig` | PES — replaced on every sync | The shared settings: team, iOS 15, Swift version, warnings, Debug and Release. |
| `App/Config/App.xcconfig` | the app — written once | `#include "Base.xcconfig"` plus this app's own settings, and the `MARKETING_VERSION` line CI stamps. |

An app opts in with `"xcconfig": true` in `Project.json`; until then `update.sh` adds neither file, so a
sync never leaves an app failing. Once opted in, `build_settings` requires that the project points at
`App.xcconfig` and that `MARKETING_VERSION` is no longer also set in the project file (it would override
the stamped one). To switch an app over: set the flag, run `update.sh`, then in Xcode set
Project > Info > Configurations to `App` for Debug and Release, delete the project-level settings
`Base.xcconfig` now provides, and check nothing changed with `xcodebuild -showBuildSettings` before and after.

### One project file: `project.yml`

Each app's facts live in one file at the repo root, `project.yml`, and nowhere else:

| Section | What it holds |
|---|---|
| `pes.version` | The PES version the app was last synced to. `update.sh` keeps this line current. It used to be `.pes-version`. |
| `app` (`name`, `bundleId`, `project`, `scheme`, `schemes`) | The product name, bundle ID, the project path, the main scheme, and **every shared scheme in the project**. A scheme added in Xcode must be written to `app.schemes` (`scripts/sync-schemes.sh`); `build_settings` fails if the list and the project disagree. |
| `languages`, `checks`, `xcconfig`, `skip`, `ownedPackages`, `sys` | What `Project.json` held, now with real comments. |
| the `# >>> sync manifest` block at the end | The fingerprints `update.sh` uses to tell "PES moved on" from "the app changed this". It used to be `.pes-sync-manifest`. It is comments, so it never disturbs the YAML, and it is written by the script, not by hand. |

Shell and Ruby read it through `scripts/ci/project_value.sh app.bundleId`, and `validate.py` converts it with
Ruby, so nothing needs installing. An app still on `Project.json` keeps working until it moves:
`scripts/migrate-config.sh <app>` writes `project.yml`, proves it says the same as the old file, and removes the
three old files. It commits nothing.

### What an app declares in `project.yml`, and what holds it to it

Three sections say what is a decision and not an accident, and a check fails when they and the repo disagree:

| Section | It says | Held to it by |
|---|---|---|
| `adoption` | For each SYSKit feature (`bootstrap`, `analytics`, `share`, `notifications`, `spotlight`, `stored`, `streak`, `connectivity`, `backgroundTask`, `layout`, `blocker`, ...): `true`, or the reason this app does not use it. | `project.py`: a feature marked `true` must be used in the code, and a used one must be marked `true`. |
| `validation` | `expected`: the checks this app runs. `own`: scripts the app keeps that run with them, reported apart and not counted. `skip`: a shared check it declines, with the reason. | `validate.py`: a missing or unlisted check fails the run. |
| `overrides` | Each build setting the project sets differently from `Base.xcconfig`, with the reason. | `project.py`: any other difference, or a listed one that no longer differs, fails. |

So the differences between apps are a diff of these sections, and a new difference has to be written down.

### One name for the project

New apps use the same project and scheme name, `App/App.xcodeproj` and scheme `App`, so no workflow, script
or hook has to know an app's name. What still differs per app is the **product**: `app.name` in `project.yml`
is what the store, the release title and Xcode Cloud call it (`{{APP_NAME}}` in templates), and the bundle ID,
`PRODUCT_NAME` and display name stay per app in `App.xcconfig` and the target. `{{PROJECT_NAME}}` is only the
`.xcodeproj` file name and only appears in paths. Renaming an existing app is a per-app step: see MIGRATE.md.

**Scheme names are common too**, named by role and never after the app: `App` (the main scheme), `WatchApp`
(a watchOS app) and `WidgetExtension` (a widget). An app that has one of these adds the name to
`app.schemes` in `project.yml` and nothing else changes: the checks, the sync and the CI read the list, and
`build_settings` fails if it and the project disagree. A role that does not exist yet (say `IntentsExtension`)
is added the same way, and to this list, so every app names it alike.

### Languages: three sets, not one list

`languages` describes three different things, and collapsing them into one
list can only describe one kind of app.

```json
"languages": {
  "source": "en",
  "interface": ["en"],
  "selectable": {
    "mode": "in-app",
    "list": ["en", "hi", "gu"],
    "keys": ["notification*", "festivalWhen*"]
  }
}
```

- **`source`** — what the strings are written in. The catalog must agree.
- **`interface`** — localizations iOS may pick on its own. Every key, every
  language, no exceptions.
- **`selectable`** — languages the app loads *deliberately*, because the user
  picked one inside it. Must appear in `knownRegions`; only the keys matching
  `selectable.keys` must be complete.

RealAIApp is `selectable`: the interface is English, the user picks a language
in Settings, and `AppLanguage.localized()` resolves it through
`Bundle.main.path(forResource:ofType:"lproj")`. It declared `["en", "hi",
"gu"]` while `knownRegions` said `(en, Base)`, so no `hi.lproj` was ever
built and every Hindi notification silently arrived in English for months.
**`selectable.keys` is required** — without it the set demands nothing while
reading as coverage, which is worse than not checking at all.

`"languages": ["en", "es"]` still reads as source `en`, interface `["en",
"es"]`, no selectable set — apps move to the new shape one at a time.

Two properties are deliberate:

- **A check that raises is a failed check, not a crashed run.** One bad file
  can't take down the rest.
- **A check that finds nothing to look at fails.** "Checked nothing" and
  "passed" are otherwise the same green tick.

## 5. Releases: a release branch, not a tag push

Version numbers are not stored in the repo. `MARKETING_VERSION` in the
project is a dev placeholder only.

To release:

1. `main` already has everything you want to ship. Branch: `release/X.Y.Z`.
2. Add the CHANGELOG section for that version. Push the branch. (The
   user-facing "What's New" belongs to the store listing — §6.)
3. Xcode Cloud archives directly from that branch — no tag needed. Push again
   as many times as TestFlight testing needs.
4. Test on a real device. Submit in App Store Connect (phased release on,
   manual release). If Apple rejects, fix on the same branch and push again —
   nothing is merged or tagged yet.
5. **Once Apple approves**, merge the branch into `main`. That merge is the
   **only** moment a tag gets created (`vX.Y.Z`), permanent and immovable.

Merging last means the newest tag always answers "what is live?", and a
rejected build never leaves a tag behind. It also keeps content deploys
(`deploy-data`, main-only) from going live while the build that understands
them is still in review.

Rollback: pause phased release, ship the next patch.

`App/ci_scripts/ci_pre_xcodebuild.sh` reads the marketing version straight
from the branch name (`release/1.8.0` → `1.8.0`). The build number is Xcode
Cloud's own — a global sequential counter per app that overwrites
`CFBundleVersion` at export time regardless of what a script sets, so nothing
here tries to compute one.

The script stamps `MARKETING_VERSION` directly in the pbxproj with `sed` —
NOT agvtool. With `GENERATE_INFOPLIST_FILE=YES`, agvtool only edits literal
Info.plist values and silently no-ops. The `/g` in the sed also keeps
watch/widget extension targets on the same version.

**The build number climbs forever instead of resetting per version** — Xcode
Cloud's own counter (App Store Connect → Xcode Cloud → Settings → Build
Number), not exposed through the API, not a bug.

Why a branch instead of a tag: a tag is immovable — great for "this is what
shipped," useless for "I need three more builds while QA finds things." A
branch can be pushed to any number of times; the tag is created once, at the
very end.

## 6. Store content

Store text and screenshots are **not** kept in an app repo. There is no
`fastlane/` folder, no Gemfile, and no store job in `main.yml` or `pr.yml`.

- The listing — per-locale text, screenshots, categories, review notes — lives
  in Firebase and is shown in the studio portal.
- The website repo (`ERbittuu/website`) owns everything that talks to App Store
  Connect. Its *App Store Sync* workflow pulls what Apple has into Firebase
  every week, and its `store-runner/` (fastlane) is the only place fastlane
  runs. To add an app: create its Firebase data and register it there.
- Auth is an App Store Connect API key. An app repo keeps `ASC_KEY_ID`,
  `ASC_ISSUER_ID` and `ASC_KEY_CONTENT` in its secrets only for the Xcode Cloud
  helper scripts in `scripts/ci/`; Xcode Cloud itself needs no credentials.
- Apple rejects: emoji in "What's New", placeholder URLs, store locales that
  don't exist (app languages and store languages are different lists). The
  website repo's checks cover these before anything is published.

## 7. Firebase

Hosting serves the content `Hosting/build.py` produces (zips + manifest.json;
short cache for JSON, longer for zips). `main.yml`'s `deploy-data` job
smoke-tests the live manifest and one sample bundle right after every deploy.

Analytics and Crashlytics: one prod project, SDKs disabled in Debug builds,
dSYMs uploaded by `ci_post_xcodebuild.sh`. Custom Analytics events live in one
file as an enum (name + parameters per case) — that's what makes
`scripts/shared/analytics_events.py` possible. Deploy auth is a service
account JSON in the `FIREBASE_SERVICE_ACCOUNT` secret with Hosting rights
only.

Anything more (Firestore, RTDB, Functions) has to justify itself through
[decisions/firebase-services.md](decisions/firebase-services.md) first — then
the separate dev/prod project rule applies.

## 8. SYSKit — the shared layer

**`SYS` means our code.** Vendored third-party packages keep their own names
(`FirebaseKit`, `Kingfisher`) — that distinction is what `.swiftlint.yml`
excludes and what `update.sh` reports on but never overwrites.

Every app vendors two local packages from `SPM/`:

| Package | Contents | Dependencies |
|---|---|---|
| `SYSKit` | config, network, logging, lifecycle, analytics plumbing, layout and design tokens. Grouped by domain under `Sources/SYSKit`: `Startup`, `Layout`, `Design`, `Content`, `Networking`, `Storage`, `Engagement`, `Platform`, `Diagnostics` | **none** |
| `SYSFirebase` | the one file that imports Firebase | SYSKit + FirebaseKit |

Separate on purpose: `SYSKit` has no dependencies, so it builds and tests
without Xcode, a simulator or Firebase. Its tests run in **this repo's** CI,
not in each app. They run on macOS, not Linux, because `SYSNetwork` uses
URLSession's async API, which swift-corelibs-foundation doesn't provide.

SYSKit and every app build in Swift 6 language mode: `SWIFT_VERSION = 6.0` is one line in
`Base.xcconfig`, and the package manifest is `swift-tools-version: 6.0`. State shared across threads
inside SYSKit (the logger's settings, launch record, configuration, hosting flags) sits behind a lock
and the types that own it are `@unchecked Sendable`; delegate callbacks hand `Sendable` values to the
main actor. Do not add `nonisolated(unsafe)` to a SYSKit type to make a build pass.

`SYSKit` contains **no full screens** — it returns state, the app renders it. Small
UI utilities are allowed where a shared behaviour needs a view to carry it
(`SYSAssetGate`, `SYSShareSheet`, `SYSMetrics`'s environment). The one exception is the
launch blocker, `SYSLaunchBlocker`: the states it shows are the startup contract every app
obeys, so the screen is shared too. The app still supplies every colour, font and string.

### Startup

```swift
switch await SYSBootstrap.start() {
case .maintenance(let message):            // your screen
case .updateRequired(let message, let url): // your screen
case .onboarding:                          // your screens
case .whatsNew(let notes):                 // your sheet
case .ready:                               // home
}
```

`SYSBootstrap` loads config locally, records the launch, gives the network a
bounded moment, then decides. Apps write screens, not startup plumbing.

### Remote config

Every app ships `App/Resources/config.json` and serves that **same file**
from its Firebase Hosting, so bundled and served copies can't drift.

Config normally applies on the **next** launch. The gates — maintenance and
force-update — are the exception: `SYSBootstrap` waits briefly for a refresh
before evaluating them. Offline, malformed, non-2xx, or older-than-current all
fall back silently — the app never ends up worse than the copy that shipped.
Cache lives in Application Support, not Caches.

**Every key in config needs a handler in SYSKit, or it is dead config** —
config and handler ship together.

| Config key | Handler |
|---|---|
| `update` | `SYSUpdate` |
| `maintenance` | `SYSMaintenance` |
| `whatsNew` | `SYSWhatsNew` |
| `rating` | `SYSRating` + `SYSLifecycle` |
| `flags`, `urls`, `crossPromo` | `SYSConfig` |
| `app` | `SYSConfig.value(_:)` |

Version comparison is numeric, never string: `"1.10.0"` sorts *below* `"1.9.0"`
as text.

`pr.yml`'s `validate-config` job checks the schema on every PR touching the
file, and refuses a `minimumVersion` above the version live on the App
Store.

**Local notifications go through `SYSNotifications`.** `install()` in the app
delegate, `clearBadge()` in `decorate`, `isAuthorized`, `requestPermission()` and
`openSettings()` for a denied permission. An app decides what to say and when; the
plumbing is SYSKit's: `scheduleRepeating(id:matching:content:)` for daily and
weekly reminders, and `replaceScheduled(prefix:with:reserved:)` to rebuild a family
of one-time requests (festival dates, say) within iOS's 64-pending limit, earliest
first. No app builds a calendar trigger, counts slots or cancels stale ids itself.

### Changing SYSKit

SYSKit is developed **inside a real app**, not here — Xcode, simulator, and
Firebase are actually present there. Changes flow **up** from the app that
proved them, then **out** to every other app:

```sh
# in the app: edit App/Packages/SYSKit, build, run, get it right
scripts/promote.sh ../RealAIApp             # review what would move
scripts/promote.sh ../RealAIApp --apply     # copy it in, run the tests
# bump VERSION, tag, then update.sh the other apps
```

`--apply` runs `swift test` against the promoted copy — PES's copy has to
stand alone with no Xcode, no simulator, no Firebase.

`update.sh` **refuses** to overwrite a vendored package the app has modified.
It tells the difference using `.pes-sync`, a fingerprint of what was last
synced, written into the app's copy — commit it.

### Hosted content

An app that ships content separately from its binary uses `SYSContentSync`:
one instance per manifest, packs served encrypted (`SYSCrypto`, keyed by the
app's App Store id in `Info.plist` as `SYSContentID`), each verified against the
manifest's SHA-256 before it is decrypted and unzipped into a live/backup
layout, so a failed install restores what was there.

**Start up manifest-first.** A first launch that waits for every pack holds the
app on a splash for the whole download (ABCLearning's is ~70 MB). Pass both
flags and let `prepareContent` return once the manifest is known:

```swift
SYSStartup(requiresAssets: true, backgroundAssets: true,
           prepareContent: { progress in await content.prepareContent(progress: progress) })
```

```swift
func prepareContent(progress: SYSAssetProgressHandler?) async -> Result<Void, SYSContentError> {
    await sync.refresh(downloadAll: false)          // manifest only; cached copy when offline
    guard hasContent else { return .failure(sync.lastManifestError ?? .notConfigured) }
    startDownloadTask { await sync.downloadMissing(progress: progress) }   // behind Home
    return .success(())
}
```

- `minimumSplash: .standard` holds the splash for at least 2.0 s on an install's
  first launch and 0.5 s after, measured from when startup began, so a launch that
  is ready at once does not flash it. The default `.none` waits only for loading.
  An app writes no splash timer of its own.
- `requiresAssets` makes "no manifest and nothing cached" a `.dataUnavailable`,
  which the app renders with SYSKit's own blocker and `startup.retry()`. An app
  keeps no content-failure screen or download state of its own.
- `backgroundAssets` re-runs `prepareContent` on every foreground, which is what
  resumes an interrupted download. Keep the manifest step and the download task
  each single-flight, because launch and foreground can overlap.
- `downloadMissing(progress:)` fetches whatever is not on disk without another
  manifest request. Use it after `refresh(downloadAll: false)`; do not call
  `refresh(downloadAll: true)` for the same purpose, see below.
- A tile the user taps calls `ensure(_:)`, which shares any download already in
  flight for that item.

Behaviours to rely on, all covered by tests:

- **A 304 is not "everything is downloaded".** `refresh` stores the ETag, so a
  `downloadAll: false` call followed by `downloadAll: true` gets `notModified`.
  `SYSContentSync` now downloads what is missing in that case; an app must not
  assume the second call was a no-op.
- Downloads run three at a time, each through `ensure`, so they never race a tap
  on the same pack.
- Hashing, decrypting and unzipping run off the main actor.
- `SYSNetwork.download` retries 5xx and dropped connections (two retries with
  backoff) like `data` requests do. A hash mismatch or a 4xx is never retried.
- A pack's `index.json` decodes with only the keys it really has. A required key
  the published packs lack fails every pack, and every caller reads that as
  "pack not found". Decode into a type of exactly what is published.

**Content that is remote-only makes first launch require a network**; a product
decision: either the offline claim changes, or a starter set ships in the
bundle.

### Launch, onboarding and preferences

**One state drives launch.** Everything an app shows between process start and
its home screen is a function of `SYSAppState`; an app keeps no navigation enum
of its own (no `splash / onboarding / home`).

```swift
func screen(for state: SYSAppState?) -> some View {
    switch state {
    case .onboarding:                 OnboardingScreen(onFinish: finishOnboarding)
    case .ready, .whatsNew:           HomeScreen()
    case .maintenance, .updateRequired, .dataUnavailable: /* SYS blocker */
    case .none:                       SplashScreen()
    }
}
```

- **Onboarding is `SYSOnboarding`.** Pass `onboardingEnabled: true`; the first-run
  screen calls `SYSOnboarding.markSeen()` then `startup.advance()`. Bump
  `SYSOnboarding.currentVersion` to show it again. An app that had its own
  "onboarded" flag must call `markSeen()` at launch when that flag is set, or every
  existing install sees onboarding again on update.
- Work that must happen once per launch after startup succeeds (launch counters,
  notification prompts) goes in `afterReady()`, not in a screen's `onAppear`.
- **Preferences are `@SYSStored`** on an `ObservableObject`:
  `@SYSStored("kl.shuffleMode", default: true) var shuffleMode: Bool`. It reads
  and writes the native `UserDefaults` value, so keys inherited from an older
  build keep working, publishes on change, and needs no save call. Typed values
  (an enum, a struct) store their raw `String` and expose a computed property.
  `SYSSettings` covers one-off reads.
- Preferences written from a test with `simctl spawn defaults write` survive an
  app uninstall in the simulator, so a "fresh install" check needs
  `defaults delete <bundle id>` as well.

### Layout

An app never measures the screen. The root view calls `.sysMetrics()` once and every view
reads `@Environment(\.sysMetrics)`:

| It gives | Notes |
|---|---|
| `isCompactWidth`, `isCompactHeight` | The size classes: compact width on the outer display, regular on the inner. |
| `prefersSideBySide` | Two things next to each other, or stacked: true when the usable area is wider than it is tall, the same rule `ArrangementView`'s split style applies. It reads the area the view actually has, so an iPad held upright stacks and a phone on its side does not. App code asks this; it never compares width to height itself. |
| `hasFold`, `isFolded` | Whether the device has a fold at all (true even when flat: use it for stable choices), and whether it is folded right now (use it for live ones). |
| `usableFrames`, `occlusions` | The content area split around an active fold, and the active camera regions, for custom manually placed controls. System containers already avoid both. |
| `shortSide`, `contentSize`, `contentFrame`, `safeArea` | The window less its safe area, each edge on its own, and the shorter side of what is left: size artwork as a fraction of it. |
| `margin(readableWidth:)`, `screenMargin`, `sectionSpacing`, `cardColumnWidth` | Centring margin for a readable width, the standard screen margin and section gap, and the minimum width of a grid card. |

There is deliberately no window-proportional scale factor, no aspect ratio and no `isLandscape`. Apple's
guidance is to respond to size classes and available space, and to let text follow Dynamic Type. Use
`@ScaledMetric` for sizes that belong to text, a fraction of `shortSide` or of the container for artwork,
and plain constants for small controls. Widths that cap a reading column are `SYSReadableWidth`
(`action`, `form`, `content`, `grid`). Pixel scale is `@Environment(\.displayScale)`.

There is no `isLandscape` either. Orientation is not a question about room, and a foldable held open is
neither. Ask the size class, ask whether the content fits (`ViewThatFits`), or hand two views to
`SYSTwoPane`, which is `ArrangementView` on iOS 27.1 and a size-class stack or row before that.

| Component | Replaces |
|---|---|
| `SYSTwoPane` | An `HStack` or `VStack` chosen by comparing width to height. |
| `SYSColumnGrid` | A hand-measured `LazyVGrid` column count. It is `GridItem(.adaptive(minimum:))`, so the system picks the count. |
| `SYSNavigationContainer` | The `NavigationStack` with a `NavigationView` fallback every app wrote, and the one place a presented screen declares its bar: `SYSNavigationContainer(tint:title:background:accessory:trailing:)`. The title is `sysNavigationTitle`, `background` fills the screen, `accessory` is an extra trailing view (a progress ring) and `trailing` is a `SYSToolbarAction` such as `.close(...)` or `.settings(...)`. An app keeps no container, bar state or toolbar modifier of its own. |
| `sysNavigationBar(title:accessory:trailing:)` | The same title and buttons for a screen pushed inside a stack that already exists. |
| `SYSToolbarButton` | A toolbar button with an icon-only label, an accessibility title and the light haptic. Built from a `SYSToolbarAction` or from a title, symbol and action. |
| `SYSLaunchBlocker`, `blocker(for:style:text:)` | Each app's own maintenance, update and offline screens. Strings come from `SYSLaunchBlockerText` so the app localizes them. |
| `sysRegularWidthText()` | A per-app text boost for iPad: steps Dynamic Type up on regular width, never past the largest size. |
| `sysNavigationTitle(_:)` | A per-app navigation title. A large leading title in a normal-height bar (`ToolbarItem(placement: .title)` with `.toolbarRole(.browser)`), shrinking rather than wrapping, still the navigation title for the back button and VoiceOver. The system large title before iOS 16. |
| `sysSearchable(text:prompt:focusOnAppear:)` | A search field that sits below the navigation bar and stays visible, like the iPhone Settings app, before iOS 26; on iOS 26 it leaves placement to the system, so a `Tab(role: .search)` gets the floating search. `focusOnAppear: true` focuses the field and shows the keyboard when the screen opens (iOS 26 and later), Apple's button-appearance search tab: "tapping the search tab brings focus to the search field and displays the keyboard". |
| `TabRole.sysSearch` | The role for a search tab: `.prominent` on iOS 27, `.search` before. Apple documents `.prominent` as the explicit way to give one tab the detached treatment; a `.search` tab only may get it by default. Use `Tab("Search", systemImage: SYSSymbol.search, value: …, role: .sysSearch)` with `sysSearchable` inside. |

App code does not use `UIScreen`, `userInterfaceIdiom` or `isPad`, `UIDevice.current.orientation` or `.model`,
`isLandscape` or `isPortrait`, a width compared to a height, `.windows.first` or `.keyWindow`, or a numeric
width/height breakpoint, and `sys_adoption` fails on each. Every one of them asserts something fixed about the
device: iPhone Duo, Split View and a tablet window shrunk to a slice all break it, in different directions.
`sys-ok: <reason>` opts a line out.

### Design tokens

The values every screen repeats live in SYSKit, in `Sources/SYSKit/Design`, so apps look and move the same
and nothing is typed twice. An app calls them directly; it does not wrap them.

| Token | What it is |
|---|---|
| `SYSSpace`, `SYSRadius` | Spacing `xs` 4, `sm` 8, `md` 12, `lg` 16, `xl` 24, `xxl` 32, `xxxl` 48, and radii `sm` 8 to `xl` 24. |
| `SYSFont`, `SYSFont.rounded` | Apple's text styles by name (`largeTitle` to `caption2`), so every font follows Dynamic Type. Weight is applied at the call site: `SYSFont.title3.weight(.semibold)`. A fixed `.system(size:)` ignores the user's text size, so the app does not write one for text. |
| `SYSOpacity`, `SYSStroke`, `SYSSize` | Named opacities (`subtle` 0.1 to `intense` 0.8), stroke widths (`thin`, `medium`) and the 44 pt minimum touch target. |
| `SYSMotion` | Named animations: `press`, `standard`, `bounce`, `pageTurn`, `floatLoop`. iOS 17 curves where available, springs before. |
| `SYSTiming` | `quick`, `standard`, `relaxed`, `stagger(_:)`, awaitable `pause(_:)`, and cancellable `after(_:_:)` in place of `DispatchQueue.asyncAfter` and `Task.sleep(nanoseconds:)`. |
| `SYSShadow` | `xs`, `card`, `raised`, `text`, applied with `.sysShadow(_:)`. |
| `SYSGlass` | `.sysGlassCard`, `.sysGlassCapsule`, `.sysGlassCircle`: Liquid Glass on iOS 26, material before. Also `.sysNumericTransition()` and `.sysSymbolBounce(value:)`. |
| `SYSEffects` | Availability-safe effects an app would otherwise gate itself: `sysOnChange(of:perform:)` (no iOS 17 deprecation), `sysSymbolBreathe`, `sysSymbolRotate`, `sysSymbolReplace`, `sysInterpolateTransition`, `sysScrollTransition`, `sysHorizontalScrollTransition`, `sysSheetDetents`, `sysShimmer`, and `sysReadableWidth` to cap a reading column and centre it. |
| `SYSPressStyle` | The press-scale `ButtonStyle`, `.subtle` or `.strong`. |
| `SYSSymbol` | SF Symbol names by meaning (`forward`, `close`, `doneCircle`, `starFilled`), so a glyph is named once. |

Colour stays in the app: a theme's accent, gradients and on-accent colour are the app's identity, and
belong in one `Palette`. The rule is that a colour, a spacing, a duration or a symbol name is written once.

### Root screens

Every app states what its launch screens are the same way, in `App/Source/App/RootScreens.swift`, and the
routing around them is written once, in SYSKit. The app's `@main` struct is plain `App`; `RootScreens.swift`
declares `extension <Name>App: SYSRootedApp`:

| The app provides | Notes |
|---|---|
| `splash(progress:)` | Shown while startup runs. `progress` is the download progress, for apps that show it. |
| `home` | Shown for `.ready` and `.whatsNew`. |
| `blockerStyle`, `blockerText` | The look and wording of the maintenance, update and offline screens. SYSKit routes to them and decides whether a button belongs. |
| `onboarding(finish:)` | Optional. An app with `onboardingEnabled: false` leaves it out. |

SYSKit does the rest: the blocker routing, finishing onboarding, the transitions and animation, and, in a
Debug build, `-debugRoute splash`. Three hooks are optional and default to doing nothing: `homeReached()`
(the user first reaches home), `open(_:)` (a URL opened the app) and `openSpotlight(_:)`. They are attached to
the root so a link that arrives while the splash is up is not lost. The app keeps them in
`App/Source/App/RootEvents.swift`. `sys_adoption` fails an app whose entry point does not conform to
`SYSRootedApp`, or whose conformance is not in `RootScreens.swift`, and `adoption.rooted` records it.

### App identity

What the app is called, where it lives in the store and which URL scheme it answers to is written once, in
`Info.plist`, and read from there:

| Fact | Where it is written | Read with |
|---|---|---|
| Display name | `CFBundleDisplayName` | `SYSAbout.appName()` |
| App Store id | `SYSAppStoreID` | `SYSAppStore.url()`, `SYSAppStore.openReview()` |
| URL scheme | `CFBundleURLTypes` | `SYSDeepLink.matches(url)`, `SYSDeepLink.url(host:path:)` |
| Support email | `config.json` `supportEmail` | `SYSAbout.supportEmail` |

An app does not keep an identity type that restates them.

`sys_adoption` fails an app whose `Info.plist` has no numeric `SYSAppStoreID` (the digits after `id` in its store URL),
since the store page, review and share links depend on it.

### Debug launch

Verifying a screen that is three taps in should not take three blind taps. In a Debug build, launch with
`-debugRoute <name>[/<id>]` and the app opens that screen, or with `-debugState maintenance|update|offline` and
`SYSStartup` shows that launch blocker instead of starting. The app reads the route from `SYSDebugRoute.launch`
(`name` and `id`, nil in Release and when the flag is absent) and maps names to its own navigation. It never
reads `CommandLine.arguments` itself, and `sys_adoption` fails if it does. The app decides which names exist; a
route it does not know is ignored. `-debugOrientation landscape|portrait` turns the window once at launch, through `SYSDebugRoute.applyLaunchOrientation()`, because the simulator cannot be rotated from the command line. With `simctl`, `xcrun simctl launch <udid> <bundle id> -debugRoute quiz`.

### Speech

Text to speech is `SYSSpeech.shared`, configured once at launch with `configure(language:genderKey:)`. It keeps one
synthesizer, warms it up, and picks the voice with `SYSVoicePicker`, which never chooses a voice of the opposite
gender to the one asked for. `speak(_:)` is `async` and returns `true` when the speech finished and `false` when it
was replaced or cancelled, so a flow waits for the real end of speech and never for a timer or an estimate.
`start(_:)` is the same without waiting. Audio ducking of other apps ends a second after the last speech. What stays
in the app: what to say, the rate and pitch of each kind of phrase, and any pronunciation table. `sys_adoption`
fails on `AVSpeechSynthesizer` in app code.

### Analytics

The manager is shared; the vocabulary is not. Apps declare their own events
conforming to `SYSAnalyticsEvent`, at
`App/Source/Shared/AnalyticsManager.swift` where the PR check greps for them.

### Vendored third-party packages

`vendor.json` records the canonical **version** of each third-party package,
never the binaries. Each app records what it actually has in
`App/Vendor/<Name>/.vendor-version`, and `update.sh --check` reports drift.

Contents are never copied between apps — RealAIApp excludes Firebase
Analytics because the Kids Category forbids third-party measurement SDKs, and
overwriting that would be a store compliance problem.

## 9. Git hooks

On GitHub Free a private repo gets no branch protection, so hooks are the
only place something can actually be stopped.

Committed in `.githooks/` and activated with `core.hooksPath` (`.git/hooks`
isn't versioned). `setup.sh`/`update.sh` set it; `update.sh --check` reports
when it's missing.

**pre-commit**

| Check | Why here rather than CI |
|---|---|
| files over 5MB | history is forever, every future clone pays |
| secrets (gitleaks) | a secret pushed to GitHub is compromised even if the branch is deleted a minute later |
| remote SwiftPM packages | easy to reintroduce by accident via Xcode's UI |
| `config.json` | it reaches every user at once |
| `.env`, `.p8`, `.p12`, `.mobileprovision` by name | cheaper and more reliable than a scanner |
| edits inside `App/Vendor` | vendored third-party is only touched when re-vendoring |
| SwiftLint on changed files only | fast feedback without waiting for CI |

Skips the secret scan with a note when gitleaks isn't installed.

**commit-msg** enforces Conventional Commits and a 72-character subject — the
CHANGELOG is written from these.

**pre-push**

| Check | Why |
|---|---|
| branch name | `release.yml` takes the tag straight from the branch name, so `release/v2.9.0` or `release/2.9` produce a wrong tag or none |

SYSKit's tests don't run here — vendored unchanged and tested at source in
this repo's CI. They also can't run reliably from a hook: a hook doesn't
inherit the shell's toolchain selection, so `swift` picks the wrong SDK.

Both hooks are escapable with `--no-verify`.

## 10. This repo is the source of truth, not a subject of it

PES defines how *apps* work; it is not an app. Installing its own hooks/layout
rules here produced checks that silently no-opped — nothing in this repo has
`App/Packages`, `App/Resources/config.json`, or `App/Source`.

What this repo does have is CI over its own output: `validate.sh`, the SYSKit
tests, and a scaffold job that builds a throwaway app from `setup.sh` and
checks it passes its own PR checks.

## 11. Git

Trunk-based, one permanent branch (§3). Squash merge only, branches
auto-delete. Commit format: `type: what it does`
(feat/fix/chore/docs/refactor/test/ci). Secrets never in the repo. Private
repos by default.

## 12. Once per app

- [ ] Xcode Cloud workflow named exactly `github_auto_release` — archives
      `release/*` when something under `App/` changes, Archive action's
      Distribution Preparation set to **App Store Connect** (not "TestFlight
      Internal Testing Only" — see §5). `main.yml`'s `xcode-cloud` job and
      `scripts/ci/xcode_cloud_workflow.rb` both hardcode this name. Create it
      once by hand in Xcode's Cloud tab.
- [ ] 2FA everywhere; ASC API key in password manager + repo secrets + Xcode
      Cloud Environment Variables (three places, same key)
- [ ] PrivacyInfo.xcprivacy present; ASC privacy labels updated in the same
      release that adds any SDK
- [ ] `Hosting/Web/` privacy/terms/support pages filled in from
      `templates/hosting-web/` and self-hosted (never an external URL in
      `Hosting/config.json`'s `urls` block) —
      `scripts/shared/urls.py` fails the build if any of them 404
- [ ] Crashlytics email alerts on
- [ ] String catalogs from day one; automatic signing everywhere
- [ ] Old endpoints that shipped binaries still call: freeze, never delete
- [ ] Branch protection: enable it if the repo is public or on a paid plan;
      otherwise the PR checks are advisory only

## 13. Starting a NEW app (the complete recipe)

MIGRATE.md is for moving an *existing* app onto this system; this is the
from-scratch path.

1. **Xcode project.** New iOS App project at `App/<Name>.xcodeproj`. Keep
   `GENERATE_INFOPLIST_FILE=YES`. Create `Source/App`, `Source/Features`,
   `Source/Shared` (§1) and put the `@main` file in `Source/App/`.
2. **Repo.** `git init -b main`, run PES `scripts/setup.sh`, fill every
   `{{PLACEHOLDER}}` (`git grep '{{'`), delete what the app doesn't use. The
   store locales, app languages, and required screenshot sizes are stated
   **once**, in `Project.json`. `gh repo create <org>/<Name> --private
   --source=. --push`.
3. **Dependencies.** Vendored-local from day one (§4, MIGRATE §2). For
   Firebase: `FirebaseKit` binary package + `-ObjC` in `OTHER_LDFLAGS`,
   `upload-symbols` into `FirebaseKit/Tools/`.
4. **Firebase** (if used) — MIGRATE §3. Plist into `App/Resources/`, check
   `IS_ANALYTICS_ENABLED` is `true`.
5. **App Store Connect.** Create the app record. One ASC API key (App
   Manager) in password manager + GitHub repo secrets (`ASC_KEY_ID` /
   `ASC_ISSUER_ID` / `ASC_KEY_CONTENT`).
6. **Xcode Cloud** — MIGRATE §4: grant the GitHub App access first, then two
   workflows (`CI` on main+PRs, `Release` on Branch Changes with `release/`
   prefix), both filtered to Files and Folders = `App`.
7. **Secrets for data hosting** (if used): `FIREBASE_SERVICE_ACCOUNT` repo
   secret, Hosting rights only.
8. **Prove the automation before writing the app.** Open one throwaway PR
   touching a Swift file, a metadata JSON, and a screenshot — all checks must
   produce a run. Then a `release/0.1.0` dry run end to end (§5).
9. Finish the §12 checklist.

---

If reality and this playbook disagree, one of them gets fixed the same week.
