# Studio data

The files the studio's apps download: `content/<store id>/...` (packs, manifests and config for each app).
This repository holds data only, no code. `main` is what every app reads, and a push to `main` is live at once.

## Branches
- `main` is the live state: one squash commit per release, with a tag (`YYYY-MM`). Never work on `main`.
- Work on `release/YYYY-MM`. When the change should go live, squash-merge it to `main` and tag it.

The packs are encrypted by each app's own `build.py` before they are committed. Plain source (`RawPacks/`) is never committed.
