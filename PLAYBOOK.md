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
│   │                            #   (Components, DesignSystem, Models, Services, Managers, Data, …)
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
├── fastlane/ + Gemfile          # store content tooling, runs in CI
│   ├── metadata/<locale>.json   # store text — single source of truth
│   └── screenshots/<locale>/
└── Hosting/                        # content pipeline, only if the app ships remote content
    ├── build.py  index.json  source/
    └── build/                   # generated, gitignored, CI rebuilds it
```

`firebase.json` at root and `ci_scripts/` next to the xcodeproj are fixed by
the tools. Everything else: App = compile, Data = content, fastlane = store,
.github = automation.

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
| `validate-metadata` | any PR, skips if `fastlane/metadata/` unchanged | Every App Store rejection worth catching before merge: emoji, placeholder text, over-limit fields, unsupported locales |
| `validate-screenshots` | any PR, skips if `fastlane/screenshots/` unchanged | Wrong pixel dimensions, incomplete locale sets, corrupt files |
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
2. Add the CHANGELOG section for that version, and the user-facing
   `release_notes` in `fastlane/metadata/<locale>.json`. Push the branch.
3. Xcode Cloud archives directly from that branch — no tag needed. Push again
   as many times as TestFlight testing needs. Pushing also syncs store text
   and screenshots to App Store Connect (`main.yml`).
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

- `fastlane/metadata/<locale>.json` is the source of truth. `generate_metadata`
  converts it to the txt files deliver needs; `validate_metadata` parses the
  same files without pushing anything.
- The metadata lane is text-only. The screenshots lane uses
  `sync_screenshots` (checksum based, safe to re-run) — never mix them.
- Lane names are a CONTRACT with the workflows: `validate_metadata`,
  `metadata`, `screenshots` must exist under exactly those names. Three
  manual-only lanes: `promo` (promotional text), `pricing` (price tier),
  `review_notes` (app review contact info).
- Auth is an App Store Connect API key in repo secrets (`ASC_KEY_ID`,
  `ASC_ISSUER_ID`, `ASC_KEY_CONTENT`). Never Apple ID login. Xcode Cloud needs
  no credentials.
- Apple rejects: emoji in "What's New", placeholder URLs, store locales that
  don't exist (Hindi is a store locale, Gujarati is not — app languages and
  store languages are different lists).
- Local `bundle exec fastlane ...` works as a fallback with `fastlane/.env`,
  but CI is the normal path.

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
| `SYSKit` | config, network, logging, lifecycle, analytics plumbing | **none** |
| `SYSFirebase` | the one file that imports Firebase | SYSKit + FirebaseKit |

Separate on purpose: `SYSKit` has no dependencies, so it builds and tests
without Xcode, a simulator or Firebase. Its tests run in **this repo's** CI,
not in each app. They run on macOS, not Linux, because `SYSNetwork` uses
URLSession's async API, which swift-corelibs-foundation doesn't provide.

`SYSKit` contains **no screens** and imports no UI framework — it returns
state, the app renders it.

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

An app that ships content separately from its binary uses `SYSAssets`. The
site serves a `manifest.json` naming every pack; `Hosting/build.py` produces
it alongside `config.json` in one staging step, since a Hosting deploy
replaces the whole site.

Pack filenames are **content-addressed** (`seaworld-3446a234.json`) — new
content gets a new filename, so an installed app keeps resolving the URL it
already cached, and `/packs/**` can be marked immutable. Packs are JSON, not
zip: iOS has no public unzip API and PES forbids remote packages, and Hosting
gzips JSON on the wire for comparable bytes anyway.

For apps whose content is **not** optional, pass `requiresAssets: true` to
`SYSBootstrap.start`. Startup fails closed with
`.dataUnavailable(SYSAssetsError)` instead of reaching a home screen with
nothing to draw. This check runs *after* the maintenance/force-update gates.

Downloads verify the manifest's SHA-256; a hash mismatch is not retried (the
server is wrong, not the connection), nor is a 4xx. Only genuine network
failures retry, three times with a short backoff.

| Concern | Handler |
|---|---|
| Pack index, download, cache, prune | `SYSAssets` |
| Startup gating on required content | `SYSBootstrap` (`requiresAssets:`) |
| Integrity | `SYSHash` |

**Content that is remote-only makes first launch require a network** — a
product decision: either the offline claim changes, or a starter set ships
in the bundle.

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
      `fastlane/metadata/*.json` or `Hosting/config.json`'s `urls` block) —
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
