# Hosting — the content the app downloads

Everything a child colours, and everything that decides what the app does on
launch, lives here. **None of it ships inside the app.** The bundle carries the
interface; this carries the content, and the app fetches it.

```
Hosting/                     this content folder — all of it in git
  Artwork/<world>/*.svg        the drawings, one folder per world
  config.json                  gates, flags, URLs — fetched on every launch
  build.py                     the pipeline — one command, `--list` shows its steps
  steps/site.py                  builds manifest.json + packs/, right here
  steps/catalog.py               writes App/Resources/catalog.json (run from the app repo)
  steps/canonicalize.py          normalises new SVGs into the supported subset
  SVG-FORMAT.md                what an SVG may contain, and why so little

        │   cd Hosting && python3 build.py site --clean
        ▼

  manifest.json                names every pack and its hash — generated, commit it
  packs/<world>-<sha8>.json    the drawings, one pack per world — generated, commit it

        │   git push                (this is the deploy now — no separate staging step)
        ▼

  raw.githubusercontent.com  what the app downloads

        │   first launch
        ▼

  Application Support/Content/   the same names, on the phone
```

The app's public pages (privacy, terms, support) are owned by the website repo,
not built here.

**Three names, three stages.** `Artwork` is what you draw, the generated
`manifest.json`/`packs/` is what gets served, and a device keeps its copy under
the same names in the same shape — so "what's committed" and "what this phone
has" can be compared by looking.

## What the generated files are

**Build output, not content.** `manifest.json` and `packs/` are produced by
`build.py site` from `Artwork/` — delete them and the next run rebuilds them
exactly. They live in this same folder now (not a separate staging directory),
because there's no deploy step anymore: committing to `main` *is* the deploy —
GitHub serves whatever's here directly.

**So: if you add a new kind of hosted file, add it to `build.py`.**

## Adding drawings

Drop SVGs into `Hosting/Artwork/<world>/`, then:

```sh
cd Data
python3 build.py canonicalize     # if they came from outside — see SVG-FORMAT.md
python3 build.py site --clean --verbose
```

Pack filenames carry a content hash, so a world whose drawings did not change
keeps its filename and installed apps do not re-download it.

**Pages are content; categories are not.** The library asks the downloaded pack
what pages a world has, so adding or removing artwork reaches every install on
the next deploy. `App/Resources/catalog.json` ships in the app and still decides
which worlds exist, and their names, symbols and tints.

| Change | Deploy is enough? |
|---|---|
| Redraw an existing page | **yes** |
| **Add or remove a page** | **yes** — the library reads its list from the pack |
| Change `config.json` (bump `version`) | **yes** |
| Add a category, rename or re-tint one | **no — app release** |

## Changing the public pages

Privacy, terms and support pages live in the website repo now, not here —
`config.json`'s `urls.*` point at the website's rendered pages.

## Renaming a world, or fixing a translation of one

`worlds.json` holds every world's display name in all 19 app languages.
`build.py` copies it into `manifest.json` as each pack's `title`, and the app
resolves the reader's language from there — so **a rename or a retranslation is
a deploy, not an app release.**

```sh
$EDITOR Hosting/worlds.json          # keys are the category ids in catalog.json
python3 scripts/validate.py localization
cd Hosting && python3 build.py site --clean
```

Two rules the check enforces, both of which fail open otherwise:

- **Every world needs every language.** A missing one is not an error at
  runtime — the app quietly shows the bundled English name — so nothing but the
  check would tell you.
- **The `en` entry must match `catalog.json`'s `name` exactly.** That name is
  the fallback shown before the manifest arrives, so if the two disagree the
  word changes under the reader partway through launch.

Adding a *new* world is still an app release: it needs a tint, a symbol and an
entry in `catalog.json`, none of which are served.

Titles live in the manifest, not in the packs, so changing one does not change
any pack hash and nothing is re-downloaded.

## Changing config

Edit `Hosting/config.json` and **raise `version`**. The app refuses anything
not newer than what it holds, so a change without a version bump is a change
nobody receives.

`Hosting/build.py` copies it into the staged site; CI validates it
(`scripts/validate.py config`) and checks the deployed copy afterwards.

## Why the app ships none of this

There is no bundled config and no bundled artwork, so a first launch needs the
network — and says so, with a retry, rather than opening onto an app with
nothing in it. Once fetched, both are kept on the device and the app works
offline from then on. See `SYSBootstrap.start(requiresConfig:requiresAssets:)`.
