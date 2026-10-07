# Hosting — the content the app downloads

Everything a child colours lives here, not in the app bundle. The app fetches
it over plain HTTPS.

```
Hosting/
  RawPacks/<world>/*.svg        the drawings — never committed, see below
  RawPacks/<world>/index.json   that world's title + optional test flag
  config.json                  gates, flags, URLs, "manifests": ["content"]
  crypto.py                    encrypt/decrypt — shared, same in every app
  build.py                     run: python3 build.py publish --clean
  steps/publish.py                builds content/manifest.json + content/packs/*.zip
  steps/decrypt_to_rawpacks.py    rebuilds RawPacks/ for editing
  SVGFormat/                      SVG rules + the tool that enforces them

        │  python3 build.py publish --clean
        ▼
  content/manifest.json + content/packs/<hash>.zip     generated, encrypted — commit these
  (RawPacks/ is deleted after a successful build)

        │  git push
        ▼
  raw.githubusercontent.com            what the app downloads
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

**Why `content/`:** every manifest an app has lives under its own named
folder — `<name>/manifest.json` + `<name>/packs/` — named in `config.json`'s
`manifests` list. This app only has one ("content"), but the shape is the
same whether an app has one manifest or several (Prarthana has two: `content/`
and `festivals/`).

## Adding drawings

```sh
cd Hosting
python3 build.py decrypt_to_rawpacks  # if RawPacks/ isn't there — see above
python3 SVGFormat/canonicalize.py     # only if the SVGs came from outside — see SVGFormat/SVG-FORMAT.md
python3 build.py publish --clean --verbose
```

Drop files into `RawPacks/<world>/`, run the build — that's the whole loop.
Pack filenames are a content hash; a world whose art didn't change keeps its
hash and nothing re-downloads.

| Change | Deploy is enough? |
|---|---|
| Redraw, add or remove a page | yes |
| Bump `config.json`'s `version` | yes |
| Add a world, rename or re-tint one, change its symbol or position | yes — but deploy this before the app version that reads it |

## Renaming a world, or fixing a translation

Edit that world's own file:

```sh
$EDITOR Hosting/RawPacks/baby/index.json
```

```json
{ "title": { "en": "Baby", "es": "Bebés", "…": "…" } }
```

Then rebuild and push. `publish.py` warns if a world's `index.json` is
missing or has no title (it still builds — ships titled with the raw id).
`scripts/validate.py localization`, in the app repo, catches the rest:
every world needs every language.

## A world's look and position

The app builds its worlds from this manifest, so nothing about a world ships in
the app. Each world's own file carries it:

```json
{
  "title": { "en": "Weather", "…": "…" },
  "symbol": "cloud.sun.fill",
  "tint": "#3FA9F5",
  "accent": "#8ED8FF",
  "order": 0
}
```

`symbol` is an SF Symbol name (use one the oldest supported iOS has), `tint` and
`accent` are hex colours, and `order` is the world's place in the carousel.
`publish.py` copies the first three into the manifest item and sorts by `order`,
and warns when a real world lacks one — the app then draws it with a plain symbol
and grey. A new world therefore appears in the app with no release. The app
version that reads these fields must not go out before this is deployed: until
the live manifest has them, every world is drawn plain.


## Marking a world as test-only

Add `"test": true` to that world's `index.json`. Still goes through the real
pipeline; a Release build just never fetches or shows it.

## Changing config

Edit `config.json` and raise `version` — the app ignores anything not newer.

## Why nothing ships in the app

No bundled config, no bundled artwork. First launch needs the network and
says so if it can't reach it. After that, everything's cached and the app
works offline.
