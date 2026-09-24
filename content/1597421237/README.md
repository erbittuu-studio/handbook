# Hosting — the content the app downloads

Learning packs live here, not in the app bundle. The app fetches them over
plain HTTPS.

```
Hosting/
  index.json                app/data/config/languages + groups (which packs, what order)
  RawPacks/<id>/index.json  that pack's title + items (each item's own title, image, meta)
  RawPacks/<id>/images/...  the images
  config.json               gates, flags, URLs, "manifests": ["content"]
  build.py                  run: python3 build.py publish --clean
  steps/publish.py             builds content/manifest.json + content/packs/*.zip

        │  python3 build.py publish --clean
        ▼
  content/manifest.json + content/packs/<hash>.zip     generated — commit these

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
`manifests` list. This app only has one ("content"); Prarthana has two
(`content/` and `festivals/`), same shape either way.

## Adding or changing a pack

```sh
cd Hosting
$EDITOR RawPacks/11/index.json      # title, items — see below
python3 build.py publish --clean --verbose
```

A pack's own `index.json` holds everything about it:

```json
{
  "title": { "en": "ABC" },
  "items": [
    { "id": 1101, "title": { "en": "Apple" }, "asset": "images/alphabet-apple.png" }
  ]
}
```

`publish.py` zips the pack's own `index.json` together with its images, so
the app reads both after downloading — nothing about a pack lives anywhere
else. It warns if a pack has no title, and if `index.json`'s `groups` lists a
pack id that doesn't exist under `RawPacks/`, or vice versa.

**Item ids are stable — don't renumber them.** `1101`, `4102`, etc. track
progress per item; changing one resets what it tracked.

## Adding a whole new pack

1. `mkdir RawPacks/64`, add images and `index.json`.
2. Add `"64"` to the right group's `order` in the top-level `index.json`.
3. Rebuild and push.

New group ids follow the same two-digit convention: first digit is the
group, second digit is the pack's place in it — but that's a naming habit,
not something the build enforces.

## Changing config

Edit `config.json` and raise its version — see `config.json` for the exact
key. `index.json`'s own `config` block (`forceUpdate`/`maintenanceMode`/
`showAds`) is this app's separate, older remote-config mechanism.

## Groups

`groups` in `index.json` is the only place pack membership and order are
stated — a pack doesn't carry its own group id, so there's nothing to fall
out of sync. Same shape as every other app's `manifest.json`:

```json
{ "id": "1", "name": { "en": "Let's Learn" }, "order": ["11", "12", "13"] }
```
