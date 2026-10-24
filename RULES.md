# Rules: structure, documents and safe change

Short on purpose. The map of where things are is in [MAP.md](MAP.md). The release routine is in [PLAYBOOK.md](PLAYBOOK.md).

## 1. One fact, one place

- A fact is written in one file. Every other file points to it.
- **Never type a number that changes** (live version, ratings, downloads, counts of files or languages) into a document. Point to `faststore/aso/tracker/REPORT.md`, which is generated.
- Generated files are never edited by hand: `REPORT.md`, `analytics.json`, `ratings.json`, `ranks.json`, `reviews.json`, `sales.json`, `state.json`, `SYSKIT-API.md`, `faststore/APPS.md` (run `node tools/apps-index.mjs` after a release).
- Downloaded working files are not committed. `aso/apps/*/data/analytics/` is ignored.

## 2. Documents

- The first line says what the file is for. A time-bound file also says its date or status ("Status: built", "As of 2026-10-24").
- **No pointer files.** A file that only says "moved, see X" is deleted once its links are fixed.
- **History is labelled.** Old text stays under a heading "History" or in a dated file. It is never mixed into the current instructions.
- Dated files are named `YYYY-MM-DD-topic.md` and live only in `aso/reviews/` (reports) or next to the plan they belong to.
- A folder with more than about 10 files has a `README.md` that lists them in one line each.
- Write plain text: no em dashes, no divider lines, no claim that was not checked.

## 3. The plan

- Only `faststore/aso/tracker/plan.json` holds dates and open items.
- An item has `id` (kebab-case), `date` (`YYYY-MM-DD` or `null`), `who` (`you`, `me` or `you and me`), `what` (one paragraph) and `status`: **`open`**, **`done`** or **`paused`**.
- Every open or paused item also has `app` (an app short name, several separated by ", ", or `all`) and `kind`: `store`, `release`, `content`, `fix`, `read`, `idea`, `admin` or `rule`. An idea is an item of kind `idea`, paused while the focus is downloads. `aso/tracker/REPORT.md` and `APPS.md` read these two fields.
- Finish with `node tools/aso-track.mjs done <id>`. Pause by setting `status: "paused"` and starting `what` with the reason and the date. A paused item is listed apart in the report, so it never looks due.
- A standing decision of the owner is also an item (for example `focus-downloads`), so it is read at the start of every session.

## 4. Names and branches

- Commit types, branch prefixes and pull requests: each app's `CONTRIBUTING.md`. A branch prefix matches its commit type.
- `release/X.Y.Z` is only for shipping; `X.month.patch` (`faststore/aso/versioning.md`). A tag means shipped and is made only by merging the release pull request.
- A repo's own docs name files and folders as they are. After a rename or a delete, search every repo for the old name and fix the references in the same pull request.

## 5. Safe change: never break anything live

Do this before moving, renaming, deleting or reshaping anything.

1. **Is it on the frozen list (section 6)?** If yes, do not rename or move it. Add the new thing beside it and keep the old one working until no live app version uses it.
2. **Search for references** in every repo: `grep -rnF "<name>" PES_Apps --exclude-dir=node_modules --exclude-dir=.git`. Zero references means unused; anything else means fix them in the same change.
3. **Run the checks** for what you touched: `faststore/node tools/validate-data.mjs --errors`, `handbook/scripts/validate.sh`, an app's `python3 App/Packages/PES/validate.py` and a simulator build, and a Markdown link check.
4. **Anything Apple or the apps read:** `./push-store --dry-run` must show no change at Apple, and a served file must change only by adding. Old app versions keep reading the old keys.
5. **One pull request per kind of change.** Moves and deletes in one, behaviour in another. A cleanup never rides with a feature.
6. **Rollback is `git revert`.** Do not rewrite shared history or force-push without the owner's yes, and then only with a guarded lease on the exact hash.

## 6. Frozen: never rename or move

Live apps, Apple or the public site depend on these exact names.

| What | Why |
|---|---|
| Every value in `faststore/data/studio.json` and `faststore/data/apps/<id>/identity.json`: Apple IDs and the folders named by them, bundle IDs and their widget and watch extensions, app groups, URL schemes, widget `kind` names | Store identity, signing, shared data, and what widgets and links open. `node tools/studio-check.mjs` compares every copy with them |
| The deep link paths (`pack/<id>`, `page/<id>`, `drawing/<uuid>`, `new`, `resume`, `ideas`, `festival/<id>`, `calendar`, `jaap`, `wisdom`) | Widgets, events, notes and shortcuts open them |
| `handbook/content/<id>/config.json`, `handbook/content/<id>/content/manifest.json`, the packs, and `handbook/content/app.json` | The apps download these from GitHub raw. Add keys, never rename |
| Config keys `urls.website`, `urls.support`, `urls.privacy`, `urls.terms` | Apps work out their links from them |
| Website routes `/apps`, `/apps/<id>`, `/apps/<id>/support`, `/apps/<id>/privacy`, `/apps/<id>/terms` | Apps, the store pages and Apple reviewers open these |
| `release/X.Y.Z` branches, `vX.Y.Z` tags, the workflow names `CI`, `Release` and `manual_release_xcode27` | The Release workflow and Xcode Cloud key on them |
| `faststore/data/apps/<id>/{app,config,release,events,screenshots,pages,purchases,site-media}.json`, `listing/<locale>.json`, `data/media/**`, `media-checksums.json` | `push-store`, `push-events`, `push-pages` and `publish` read these paths |
| `faststore/aso/tracker/{plan,config,notes}.json` | The tracker and the report read them |
| `secrets/AuthKey_*.p8` and `secrets/APPLE.md` | The Apple tools read them by name |
| The public SYSKit API in `SYSKIT-API.md` | Four apps compile against it. Change it by adding |

## 7. Housekeeping

- After a pull request merges, delete its branch and prune (`git fetch --prune`).
- Look for unused files each month: no reference found by the search in section 5, step 2.
- A one-time backup folder is deleted 30 days after it was made.
