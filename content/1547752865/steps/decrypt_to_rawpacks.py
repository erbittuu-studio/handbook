#!/usr/bin/env python3
"""Rebuilds RawPacks/ from the published (encrypted) content/ — run this
before editing content that publish.py already deleted RawPacks/ for.

    python3 build.py decrypt_to_rawpacks

Reverses what publish.py did: decrypts each pack, unzips its images, and
reconstructs RawPacks/<type>/<category>/index.json from the manifest's
type + free fields.
"""
import io
import json
import sys
import zipfile
from pathlib import Path

HOSTING = Path(__file__).resolve().parents[1]
RAW_PACKS = HOSTING / "RawPacks"
CONTENT = HOSTING / "content"

sys.path.insert(0, str(HOSTING))
import crypto  # noqa: E402

APP_STORE_ID = HOSTING.name


def main() -> int:
    manifest_path = CONTENT / "manifest.json"
    if not manifest_path.is_file():
        print(f"error: {manifest_path} does not exist — nothing to decrypt")
        return 1

    manifest = json.loads(manifest_path.read_text())
    RAW_PACKS.mkdir(parents=True, exist_ok=True)

    for item in manifest["items"]:
        bundle_path = CONTENT / item["bundle"].lstrip("/")
        payload = crypto.decrypt(bundle_path.read_bytes(), APP_STORE_ID)

        category_dir = RAW_PACKS / item["type"] / item["category"]
        category_dir.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(io.BytesIO(payload)) as zf:
            zf.extractall(category_dir)

        index = {"type": item["type"], "free": item.get("free", 0)}
        (category_dir / "index.json").write_text(
            json.dumps(index, ensure_ascii=False, indent=2) + "\n"
        )
        print(f"  restored {item['id']}")

    print(f"\nRawPacks/ restored from {len(manifest['items'])} pack(s).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
