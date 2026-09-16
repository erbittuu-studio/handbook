# Scripts

| Script | Run from | Purpose |
|---|---|---|
| `setup.sh [dir]` | anywhere | Copy the full parts box into a **new** app repo (never overwrites; delete what the app doesn't use) |
| `update.sh [--check] <dir>` | anywhere | Bring an **existing** app up to this PES version. `--check` reports drift and changes nothing. Always run it first |
| `status.sh [apps-dir]` | anywhere | One table: live version, TestFlight version, tag, PES version, drift and open PRs for every app. Read-only |
| `lint-project.sh <app>…` | anywhere | Portfolio-wide audit of the same build settings `build_settings.py` (below) checks per-app in CI — run this by hand across every app at once, e.g. after a PES change to what it looks for |
| `validate.sh` | PES repo | Sanity-check this repo |

`update.sh` also syncs `SPM/SYSKit` and `SPM/SYSFirebase` into an app's
`App/Packages/`, and compares third-party package versions in `App/Vendor/`
against `vendor.json` — reporting drift without ever touching their contents.

`templates/scripts/shared/build_settings.py` runs the same checks as
`lint-project.sh` automatically, on every PR, for the one app whose CI is
actually running — a literal Info.plist version, missing `-ObjC`, SYSKit
vendored but unlinked. `lint-project.sh` stays for auditing the whole
portfolio at once by hand; the two are meant to overlap.
