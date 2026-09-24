#!/usr/bin/env python3
"""Turns RawPacks/ into the publishable site: content/manifest.json +
content/packs/*.zip. Committing the result to `main` is the deploy — no
separate staging step.

Run by CI (`cd Hosting && python3 build.py publish --clean`) and by the
pre-push hook, so a RawPacks/ change can't reach `main` unrebuilt.

- This is the "content" manifest — config.json's `manifests` list names it.
  Everything it owns lives under `content/`, the same rule as any other
  manifest an app has (see Prarthana's `content/` + `festivals/`).
- `index.json` is the authored source: `app`/`data`/`config`/`languages`
  (this app's own remote-config block, separate from PES's config.json) and
  `groups` — which packs exist, and their display order. No pack titles or
  bundle paths live here; those come from the pack's own folder.
- Each pack's own title and items live in `RawPacks/<id>/index.json`, beside
  its images — not a separate list kept in sync with the folders by hand.
- Packs are zip, named by content hash alone. The app reads `bundle` from the
  manifest, never the filename.
- Zips are built deterministically (sorted entries, fixed timestamps), so
  unchanged art keeps its hash and isn't re-uploaded.
- Every pack is encrypted (crypto.py, key = this app's own App Store id)
  before it's hashed and written — the hash/size in the manifest are of the
  encrypted bytes, so the existing download-then-verify step needs no
  changes. RawPacks/ is deleted after a successful build (see --keep-source)
  and is git-ignored, so the plaintext source is never what gets published
  and never what gets committed. Run `decrypt_to_rawpacks.py` to get it back
  for editing.
"""
import argparse
import hashlib
import json
import shutil
import sys
import zipfile
from datetime import datetime, timezone
from pathlib import Path

HOSTING = Path(__file__).resolve().parents[1]
RAW_PACKS = HOSTING / "RawPacks"
CONFIG = HOSTING / "config.json"
INDEX = HOSTING / "index.json"
CONTENT = HOSTING / "content"
PACKS = CONTENT / "packs"

sys.path.insert(0, str(HOSTING))
import crypto  # noqa: E402

APP_STORE_ID = HOSTING.name

# Fixed timestamp so identical content produces an identical zip.
ZIP_EPOCH = (1980, 1, 1, 0, 0, 0)

MANIFEST_VERSION = 1


def pack_meta(pack_id: str, pack_dir: Path) -> dict:
    """This pack's own index.json — title and items. Missing or invalid isn't
    an error (the build still has to go out), just a loud warning."""
    meta_path = pack_dir / "index.json"
    if not meta_path.is_file():
        print(f"  warning: pack {pack_id} has no index.json — it will ship titled \"{pack_id}\"")
        return {}
    try:
        meta = json.loads(meta_path.read_text())
    except json.JSONDecodeError as error:
        print(f"  warning: pack {pack_id}/index.json is not valid JSON ({error})")
        return {}
    if not meta.get("title"):
        print(f"  warning: pack {pack_id}/index.json has no \"title\" — it will ship titled \"{pack_id}\"")
    return meta


def _add(zf: zipfile.ZipFile, arcname: str, data: bytes) -> None:
    info = zipfile.ZipInfo(arcname, date_time=ZIP_EPOCH)
    info.compress_type = zipfile.ZIP_DEFLATED
    info.external_attr = 0o644 << 16
    zf.writestr(info, data)


def build_pack(pack_id: str, pack_dir: Path) -> bytes:
    """Zips everything in a pack's folder — its own index.json plus every
    image — sorted, with a pinned timestamp, so unchanged content always
    produces the same bytes."""
    buffer = __import__("io").BytesIO()
    with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as zf:
        for path in sorted(pack_dir.rglob("*")):
            if not path.is_file():
                continue
            arcname = f"{pack_id}/{path.relative_to(pack_dir)}"
            _add(zf, arcname, path.read_bytes())
    return buffer.getvalue()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--clean", action="store_true", help="remove generated packs/manifest first")
    parser.add_argument("--verbose", action="store_true", help="list every file in every pack")
    parser.add_argument("--keep-source", action="store_true",
                         help="don't delete RawPacks/ after a successful build")
    args = parser.parse_args()

    if not RAW_PACKS.is_dir():
        print(f"error: {RAW_PACKS} does not exist")
        return 1
    if not CONFIG.is_file():
        print(f"error: {CONFIG} does not exist — the site must ship a config")
        return 1
    if not INDEX.is_file():
        print(f"error: {INDEX} does not exist")
        return 1

    if args.clean:
        if PACKS.exists():
            shutil.rmtree(PACKS)
        (CONTENT / "manifest.json").unlink(missing_ok=True)
    PACKS.mkdir(parents=True, exist_ok=True)

    index = json.loads(INDEX.read_text())
    known_ids = {pack_id for group in index.get("groups", []) for pack_id in group.get("order", [])}

    items = []
    for pack_dir in sorted(p for p in RAW_PACKS.iterdir() if p.is_dir()):
        pack_id = pack_dir.name
        if pack_id not in known_ids:
            print(f"  warning: RawPacks/{pack_id} isn't in any group's \"order\" — it won't be reachable")

        meta = pack_meta(pack_id, pack_dir)
        payload = build_pack(pack_id, pack_dir)
        item_count = len(meta.get("items", []))

        encrypted = crypto.encrypt(payload, APP_STORE_ID)
        digest = hashlib.sha256(encrypted).hexdigest()
        filename = f"{digest[:12]}.zip"
        (PACKS / filename).write_bytes(encrypted)

        items.append({
            "id": pack_id,
            "title": meta.get("title") or pack_id,
            "bundle": f"/packs/{filename}",
            "bytes": len(encrypted),
            "sha256": digest,
            "required": True,
        })
        print(f"  {pack_id:4} {item_count:2} item(s)  {len(payload):>7,} B  {filename}")
        if args.verbose:
            for item in meta.get("items", []):
                print(f"      {item.get('title', {}).get('en', item.get('id'))}")

    referenced_missing = known_ids - {i["id"] for i in items}
    if referenced_missing:
        print(f"\nerror: groups reference packs that don't exist in RawPacks/: {sorted(referenced_missing)}")
        return 1

    if not items:
        print("error: no packs produced a bundle")
        return 1

    manifest = {
        "app": index["app"],
        "data": index["data"],
        "config": index["config"],
        "languages": index["languages"],
        "manifestVersion": MANIFEST_VERSION,
        "generatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "items": items,
        "groups": index["groups"],
    }
    (CONTENT / "manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")

    total = sum(i["bytes"] for i in items)
    print(f"\nStaged {len(items)} pack(s), {total:,} B total, plus manifest.json and config.json")
    print(f"Site root: {CONTENT}")

    if not args.keep_source:
        shutil.rmtree(RAW_PACKS)
        print("Removed RawPacks/ (published packs are encrypted with it; "
              "run steps/decrypt_to_rawpacks.py to get it back for editing).")

    return 0


if __name__ == "__main__":
    sys.exit(main())
