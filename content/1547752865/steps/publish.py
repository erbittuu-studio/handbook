#!/usr/bin/env python3
"""Turns RawPacks/ into the publishable site: content/manifest.json +
content/packs/*.zip. Committing the result to `main` is the deploy — no
separate staging step.

Run by CI (`cd Hosting && python3 build.py publish --clean`) and by the
pre-push hook, so a RawPacks/ change can't reach `main` unrebuilt.

- This is the "content" manifest — config.json's `manifests` list names it.
  Everything it owns lives under `content/`, the same rule as any other
  manifest an app has (see Prarthana's `content/` + `festivals/`).
- One pack per (type, category) — `RawPacks/doodle/Animal/` and
  `RawPacks/stamp/Animal/` are two different packs, because a doodle and a
  stamp category can share a name. The manifest id is `doodle_Animal` /
  `stamp_Animal`; `type` is also its own field, not just baked into the id,
  so a reader can filter by it without parsing the id apart.
- Every pack's own `RawPacks/<type>/<category>/index.json` holds `type` and
  `free` (how many of its images are free vs. premium) — not a separate list
  kept in sync with the folders by hand.
- Nothing is `required` — nothing ships and nothing blocks launch; every
  pack is fetched only once a category is actually opened.
- Packs are zip, named by content hash alone. The app reads `bundle` from
  the manifest, never the filename.
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
import io
import json
import shutil
import sys
import zipfile
from datetime import datetime, timezone
from pathlib import Path

HOSTING = Path(__file__).resolve().parents[1]
RAW_PACKS = HOSTING / "RawPacks"
CONFIG = HOSTING / "config.json"
CONTENT = HOSTING / "content"
PACKS = CONTENT / "packs"

sys.path.insert(0, str(HOSTING))
import crypto  # noqa: E402

APP_STORE_ID = HOSTING.name

MEDIA_TYPES = ("doodle", "stamp")

# Fixed timestamp so identical content produces an identical zip.
ZIP_EPOCH = (1980, 1, 1, 0, 0, 0)

MANIFEST_VERSION = 1


def pack_meta(pack_id: str, pack_dir: Path) -> dict:
    """This pack's own index.json — type and free count. Missing or invalid
    isn't an error (the build still has to go out), just a loud warning."""
    meta_path = pack_dir / "index.json"
    if not meta_path.is_file():
        print(f"  warning: {pack_id} has no index.json — shipping with no free count")
        return {}
    try:
        return json.loads(meta_path.read_text())
    except json.JSONDecodeError as error:
        print(f"  warning: {pack_id}/index.json is not valid JSON ({error})")
        return {}


def _add(zf: zipfile.ZipFile, arcname: str, data: bytes) -> None:
    info = zipfile.ZipInfo(arcname, date_time=ZIP_EPOCH)
    info.compress_type = zipfile.ZIP_DEFLATED
    info.external_attr = 0o644 << 16
    zf.writestr(info, data)


def build_pack(category: str, pack_dir: Path) -> tuple[bytes, int]:
    """Zips every image in a category's folder. Returns (zip bytes, image
    count). Page order is just the sorted filenames — `Animal_1.png`,
    `Animal_2.png`, ... — same as every other simple pack in the portfolio."""
    images = sorted(p for p in pack_dir.glob("*.png") if p.is_file())
    if not images:
        return b"", 0

    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as zf:
        for image in images:
            _add(zf, image.name, image.read_bytes())
    return buffer.getvalue(), len(images)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--clean", action="store_true", help="remove generated content/ first")
    parser.add_argument("--verbose", action="store_true", help="list every image in every pack")
    parser.add_argument("--keep-source", action="store_true",
                         help="don't delete RawPacks/ after a successful build")
    args = parser.parse_args()

    if not RAW_PACKS.is_dir():
        print(f"error: {RAW_PACKS} does not exist")
        return 1
    if not CONFIG.is_file():
        print(f"error: {CONFIG} does not exist — the site must ship a config")
        return 1

    if args.clean and CONTENT.exists():
        shutil.rmtree(CONTENT)
    PACKS.mkdir(parents=True, exist_ok=True)

    items = []
    for media_type in MEDIA_TYPES:
        type_dir = RAW_PACKS / media_type
        if not type_dir.is_dir():
            print(f"  warning: {type_dir} does not exist — skipping")
            continue

        for pack_dir in sorted(p for p in type_dir.iterdir() if p.is_dir()):
            category = pack_dir.name
            pack_id = f"{media_type}_{category}"

            payload, image_count = build_pack(category, pack_dir)
            if not payload:
                print(f"  skipping {pack_id} — no .png files")
                continue

            meta = pack_meta(pack_id, pack_dir)
            encrypted = crypto.encrypt(payload, APP_STORE_ID)
            digest = hashlib.sha256(encrypted).hexdigest()
            filename = f"{digest[:12]}.zip"
            (PACKS / filename).write_bytes(encrypted)

            items.append({
                "id": pack_id,
                "type": media_type,
                "category": category,
                "free": meta.get("free", 0),
                "imageCount": image_count,
                "bundle": f"/packs/{filename}",
                "bytes": len(encrypted),
                "sha256": digest,
                "required": False,
            })
            print(f"  {pack_id:24} {image_count:3} images  {len(payload):>9,} B  {filename}")
            if args.verbose:
                for image in sorted(pack_dir.glob("*.png")):
                    print(f"      {image.name}")

    if not items:
        print("error: no categories produced a bundle")
        return 1

    manifest = {
        "manifestVersion": MANIFEST_VERSION,
        "generatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "items": items,
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
