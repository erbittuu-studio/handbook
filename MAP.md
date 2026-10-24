# Map: where is everything

One page. Find the thing, then open its own file. Rules for changing anything are in [RULES.md](RULES.md).

## The folders in `PES_Apps/`

| Folder | What it is | Who changes it |
|---|---|---|
| `handbook/` | The standards, the shared code (SYSKit) and the content and config the apps download | by hand, straight on `main` |
| `faststore/` | Everything sent to the App Store and the website: listings, screenshots, events, ASO research, the plan | pull request, then you run `./push-store` and `./publish` |
| `website/` | The public site (`erbittuu-studio.web.app`). A push to `main` goes live | made by `faststore/./publish site`, you push |
| `Prarthana/`, `ABCLearning/`, `Colorful/`, `Drawing/` | One app each | `release/X.Y.Z` branch, pull request, tag on merge |
| `1tattooz/` | A client app, separate from ours | its own `release/X.Y.Z` branch |
| `nomination-assets/` | Pictures for featuring nominations, sent by hand | you |
| `secrets/` | The Apple key and notes. Never in git, never copied | you |
| `branch-backups-*/` | A one-time safety copy of every repo. Delete it 30 days after it was made | you |

## I want to…

| I want to | Open or run |
|---|---|
| See one app's ids, versions, URL scheme, widgets and folders | `faststore/APPS.md` (generated: `node tools/apps-index.mjs`) |
| Understand the whole system | `handbook/PLAYBOOK.md` |
| See what is next, the live versions and the numbers | `faststore/aso/tracker/REPORT.md` |
| Add, tick or pause a plan item | `faststore/aso/tracker/plan.json`; `node tools/aso-track.mjs done <id>` |
| Change store text, keywords or What's New | `faststore/data/apps/<id>/listing/<locale>.json`, then `./push-store --dry-run` |
| Change screenshots | `faststore/aso/screenshots-2026-11-01.md` for the plan; the pictures are in `faststore/data/media/screenshots/<id>/` |
| Read the competitor and keyword research | `faststore/aso/apps/<id>/` and the dated reports in `faststore/aso/reviews/` |
| Build an app in Xcode Cloud | `faststore/./build <app> --dry-run`, then without the flag |
| Follow one release start to finish | `faststore/USAGE.md` and `faststore/RELEASE-PLAN.md` |
| Know an app's own rules | `<App>/CLAUDE.md` |
| Change shared app code | edit in ABC's `App/Packages/SYSKit`, then `handbook/scripts/promote.sh ../ABCLearning --apply`, then `scripts/update.sh ../<app>` |
| Change what the apps download (config, links, catalog) | `handbook/content/<id>/config.json` and `handbook/content/app.json` (see the frozen list in RULES.md) |
| Change the website pages | `faststore/data/` then `./publish site --preview` |
| Check the analytics | `node tools/aso-analytics.mjs pull`; read `REPORT.md` |
| Send featuring nominations | `faststore/aso/nominations-2026-11.md` and `nomination-assets/` |

## Words used everywhere

- **Plan** is only `faststore/aso/tracker/plan.json`. No other file holds dates or open items.
- **Live** means approved and on the App Store. The live versions are in `REPORT.md`, never typed into another document.
- **History** is a file or section labelled as history. It is kept for the record and may be out of date.
