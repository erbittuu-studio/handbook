# CLAUDE.md: handbook

Public, data only. The files every app downloads: `content/<store id>/` (encrypted packs, manifests, config). The repo name `handbook` and the `content/` path are written in every live app: never rename or move them. No code, standards or docs belong here (those live in `pes`).

## Never do
- Never commit `RawPacks/` (plain source) or a secret. Never put code here. Never rename `handbook` or `content/`.
- Never push unless the owner says so in that message. A push to `main` is live for every app at once, with GitHub's cache delay of about five minutes.
- Never rewrite or force-push `main` after a release is merged.

## Branches and commits
- `main` is the live state: one squash commit per release, with a tag `YYYY-MM`. Never work on `main`.
- Work on `release/YYYY-MM`. When the change should go live, squash-merge it to `main` and tag it. Commit in small honest commits on the branch and fold fix-ups into them before pushing.

## How to change content
Each app has its own folder with its own `README.md`, `build.py` (encrypts and writes the packs), `crypto.py` and `steps/`. Decrypt `RawPacks/` with `python3 build.py decrypt_to_rawpacks`, edit, then `python3 build.py publish --clean`. Commit the generated `content/<id>/content/` files. App facts in `content/<id>/config.json` and `content/app.json` are written from faststore (`./publish handbook`); change them there, not by hand.
