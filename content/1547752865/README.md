# Hosting — the content the app downloads

Doodle and stamp art lives here, not in the app bundle. The app fetches it
over plain HTTPS.

```
Hosting/
  RawPacks/doodle/<category>/*.png    the doodles
  RawPacks/stamp/<category>/*.png     the stamps
  RawPacks/<type>/<category>/index.json   that pack's type + free count
  config.json                        gates, flags, URLs, "manifests": ["content"]
  build.py                           run: python3 build.py publish --clean
  steps/publish.py                      builds content/manifest.json + content/packs/*.zip

        │  python3 build.py publish --clean
        ▼
  content/manifest.json + content/packs/<hash>.zip     generated — commit these

        │  git push
        ▼
  raw.githubusercontent.com                            what the app downloads
```

Committing to `main` is the deploy. No staging step, no build server.

## RawPacks/ is never published, and packs are encrypted

`RawPacks/` is git-ignored and `publish.py` deletes it after a successful
build — the plaintext source never sits in the repo next to the packs made
from it. Every pack is encrypted (`crypto.py`) before it's hashed and
written, with a key derived from this app's own App Store id, so what's on
GitHub is unreadable without it. This is a deterrent against casual
scraping of the hosting, not strong protection — nothing can stop someone
who reverse-engineers the compiled app itself, since the app has to be able
to decrypt its own downloads.

To edit content, get `RawPacks/` back first:

```sh
cd Hosting
python3 build.py decrypt_to_rawpacks
```

## Why `doodle` and `stamp` aren't separate manifests

They're the same *kind* of thing — a category of images — just two flavors,
and several category names exist in both (`Animal`, `Christmas`, `Dating`,
`Jungle`). One manifest, one flat `items` list; each pack's `id` is
`<type>_<category>` (`doodle_Animal`, `stamp_Animal`) so the two never
collide, and `type` is also its own field so a reader can filter by it
without parsing the id apart.

## Nothing is required

Every pack has `"required": false` — nothing ships in the app and nothing
blocks launch. A category's pack is fetched the first time someone actually
opens it, same as every category in every category-browsing screen in this
portfolio.

## Adding art to a category

```sh
cd Hosting
# add images to RawPacks/doodle/Animal/ (or stamp/...)
python3 build.py publish --clean --verbose
```

Drop numbered files into the category's folder, rebuild — that's the whole
loop. Pack filenames are a content hash; a category whose art didn't change
keeps its hash and nothing re-downloads.

## Adding a whole new category

1. `mkdir RawPacks/doodle/NewCategory`, add the images.
2. Add `RawPacks/doodle/NewCategory/index.json`: `{ "type": "doodle", "free": 3 }`.
3. Rebuild and push. No app release needed — the library reads categories
   from the manifest, not from anything shipped.

## Changing config

Edit `config.json` and raise `version` — the app ignores anything not newer.

## Legacy

App versions up to 2.9.0 read the `drawingpro-a7d1` Firebase Storage bucket
instead of this content; it must stay online until nobody runs those
versions. The old `catalog.json` this folder used to serve is gone —
`content/manifest.json` replaces it, with real checksums per category
instead of none at all.
