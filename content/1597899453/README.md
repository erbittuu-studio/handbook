# Hosting — the content the app downloads

Prayer texts, meanings and audio live here, not in the app bundle. The app
fetches them over plain HTTPS.

```
Hosting/
  index.json                app/data/config + todaysPrayer/deities/categories
  RawPacks/<id>/index.json  that item's name, description, tags
  RawPacks/<id>/*.json      the text, one file per language
  RawPacks/<id>/*.mp3       audio, if it has any
  RawPacks/categories/      category images, filenames only (not an item — see below)
  RawPacks/festivals/       festival source data (not an item — see below)
  config.json               gates, flags, URLs, "manifests": ["content", "festivals"]
  build.py                  run: python3 build.py publish --clean
  steps/publish.py             builds both manifests below

        │  python3 build.py publish --clean
        ▼
  content/manifest.json               prayer items + categories — generated
  content/packs/<hash>.zip (+ .mp3)   one per item — generated
  content/packs/categories/*.jpg      generated

  festivals/manifest.json             one item per year — generated
  festivals/packs/<hash>.json         one per year, checksummed like any pack
  festivals/packs/images/*.png        generated

        │  git push
        ▼
  raw.githubusercontent.com                     what the app downloads
```

**Two manifests, not one** — `config.json`'s `manifests` list names them.
Prayers and festival years change on different schedules and aren't the same
kind of thing, so they don't share a checksum: editing next year's calendar
doesn't touch a single prayer's entry, and vice versa. Same rule every app in
the portfolio follows — one manifest per real content stream, each entirely
under its own folder (`<name>/manifest.json` + `<name>/packs/`). Apps with
only one stream just have a `manifests` list of length one.

Committing to `main` is the deploy. No staging step, no build server.

## RawPacks/ is never published, and packs are encrypted

`RawPacks/` is git-ignored, and `publish.py` deletes the parts of it that
were just published — each item's folder, and each festival year file —
after a successful build. `RawPacks/categories/` and
`RawPacks/festivals/images/` are left alone; those images aren't encrypted
or checksummed today, so there'd be nothing to rebuild them from.

Every item's zip and audio, and every festival year, are encrypted
(`crypto.py`) before they're hashed and written, with a key derived from
this app's own App Store id — the `checksum`/`sha256` in each manifest are
of the encrypted bytes, so nothing about how the app verifies downloads
changes. This is a deterrent against casual scraping of the hosting, not
strong protection — nothing can stop someone who reverse-engineers the
compiled app itself, since the app has to be able to decrypt its own
downloads.

To edit content, get the deleted parts of `RawPacks/` back first:

```sh
cd Hosting
python3 build.py decrypt_to_rawpacks
```

## The one field name that's deliberately different

Every other app in this portfolio calls a pack's hash `sha256` and its size
`bytes`. Here they're **`checksum`** and **`size`** — because the app already
reads those exact names to verify a download and decide whether to
re-fetch it. Renaming them would silently turn that off for real installs,
so they stay as they are.

## Adding or changing an item

```sh
cd Hosting
$EDITOR RawPacks/hanuman_chalisa/index.json    # name, description, tags
python3 build.py publish --clean --verbose
```

An item's own `index.json` holds its facts:

```json
{ "name": "Hanuman Chalisa", "description": "40 Chaupai by Tulsidas",
  "readingTimeMinutes": 8, "tags": ["morning", "evening", "popular"] }
```

Its languages, and whether it has audio/meanings/an image, are discovered
from whatever files sit beside that `index.json` — not authored separately.

**Audio is published on its own**, not inside the text zip — most prayers
are never played, so it's fetched only the first time someone taps play, not
bundled with the text every time.

## Adding a whole new item

1. `mkdir RawPacks/new_prayer`, add `new_prayer_en.json` (and other
   languages), `index.json`, and `new_prayer.mp3` if it has audio.
2. Add its id to the right category's `items` list in `index.json`.
3. Rebuild and push.

## Categories, festivals, deities

`categories`, `festivals`, `deities` and `todaysPrayer` are this app's own —
not shared with the rest of the portfolio the way `items` is. `categories`
in `index.json` is already the same shape used everywhere else
(`{id, name, items: [ids]}`), just under its existing name rather than
`groups`, for the same reason `checksum` kept its name.

`RawPacks/festivals/<year>.json` and `RawPacks/categories/*.jpg` are source
data for those two features — real folders under `RawPacks/`, but not items,
and `publish.py` never treats them as one.

Image references in the source files (`categories[].image`, a festival
type's or entry's `image`) are just filenames — `publish.py` rewrites them to
their served `packs/...` path (`content/packs/categories/...` or
`festivals/packs/images/...`) when it copies the images there. The source
never has to know where things end up served from.

**Festival years are packs too**, not flat copied files — each year is
checksummed and named by content hash the same as any prayer's zip, in
`festivals/manifest.json`'s own `items` list. The only thing that's
different about them is that a "pack" here is a year of JSON, not a zip.
