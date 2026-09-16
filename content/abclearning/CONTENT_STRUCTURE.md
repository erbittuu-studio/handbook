# Content Sync Guide

This repository stores remote learning content for the iOS app.

## Structure

- `manifest.json`
  Main file the app reads first.
- `packs/<pack-id>/index.json`
  Pack content file.
- `packs/<pack-id>/images/...`
  Images used by that pack.
- `packs/<pack-id>.zip`
  Download bundle for the app.
- `scripts/validate_content.py`
  Validation script for manifest, packs, images, and zip bundles.
- `scripts/sync_content.py`
  Rebuilds all pack zip files and then runs validation.

## Manifest

`manifest.json` contains:

- `app`
- `data`
- `config`
- `languages`
- `groups`

Each group contains its own `packs` list.

Example:

```json
{
  "id": 1,
  "name": { "en": "Let's Learn" },
  "packs": [
    {
      "id": 11,
      "name": { "en": "ABC" },
      "path": "packs/11/index.json",
      "bundle": "packs/11.zip"
    }
  ]
}
```

## ID Rules

- Group ids:
  `1`, `2`, `3`, `4`, `5`, `6`
- Pack ids:
  `11`, `12`, `13` ... `63`
- Item ids:
  pack-based, for example:
  - pack `11` -> `1101`, `1102`
  - pack `41` -> `4101`, `4102`

## Pack Layout

Example:

```text
packs/
  11/
    index.json
    images/
      alphabet-apple.png
      alphabet-ball.png
  11.zip
```

`index.json` example:

```json
{
  "id": 11,
  "items": [
    {
      "id": 1101,
      "title": { "en": "Apple" },
      "asset": "images/alphabet-apple.png"
    }
  ]
}
```

## Current Group Mapping

- `1 Let's Learn`
  `11 ABC`, `12 Numbers`, `13 Colors`, `14 Shapes`, `15 First Words`
- `2 My Body`
  `21 Body Parts`, `22 Clothes`, `23 Dress Up`
- `3 Animal Friends`
  `31 Farm Animals`, `32 Wild Animals`, `33 Birds`, `34 Bugs`
- `4 Yummy Food`
  `41 Fruits`, `42 Veggies`, `43 Food`, `44 My Food`
- `5 My World`
  `51 Helpers`, `52 School Things`, `53 Music Time`
- `6 Play Time`
  `61 Toys`, `62 Fun Time`, `63 Sea Animals`

## Validation

Run validation only:

```bash
python3 scripts/validate_content.py
```

Run full sync:

```bash
python3 scripts/sync_content.py
```

The validator checks:

- required manifest sections
- group ids and pack ids
- pack file existence
- bundle zip existence
- pack id matches `index.json`
- item id uniqueness inside each pack
- missing `title.en`
- missing image files
- asset paths with spaces
- zip contains the expected `<pack-id>/index.json`

## Sync Flow

Use this flow for every content update:

1. Update `manifest.json`
2. Update the correct `packs/<pack-id>/index.json`
3. Add or update images in `packs/<pack-id>/images/`
4. Run:

```bash
python3 scripts/sync_content.py
```

This script:

- rebuilds every `packs/<pack-id>.zip`
- validates manifest, packs, images, and zip bundles

5. Ship only if sync passes

## Notes

- Keep pack names child-friendly
- Keep image paths stable when possible
- Do not add spaces to asset file paths
- Manifest is the source of truth for app sync and pack download
