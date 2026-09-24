#!/usr/bin/env python3
"""Rebuilds the parts of RawPacks/ that publish.py deletes after a
successful build — item folders, and festival year files. RawPacks/
categories/ and RawPacks/festivals/images/ are never touched by publish.py
(not encrypted, not checksummed), so this script leaves them alone too.

    python3 build.py decrypt_to_rawpacks

For each item: decrypts its zip, extracts its text/meanings/image files
(the zip's own index.json is a files-listing, not RawPacks'), decrypts its
audio if it has any, and reconstructs RawPacks/<id>/index.json from the
manifest's name/description/tags/readingTimeMinutes. For festivals: decrypts
each year's pack back to RawPacks/festivals/<year>.json.
"""
import io
import json
import sys
import zipfile
from pathlib import Path

HOSTING = Path(__file__).resolve().parents[1]
SOURCE_DIR = HOSTING / "RawPacks"
CONTENT_DIR = HOSTING / "content"
FESTIVALS_DIR = HOSTING / "festivals"

sys.path.insert(0, str(HOSTING))
import crypto  # noqa: E402

APP_STORE_ID = HOSTING.name


def restore_items() -> int:
    manifest = json.loads((CONTENT_DIR / "manifest.json").read_text())
    for item in manifest["items"]:
        item_id = item["id"]
        item_dir = SOURCE_DIR / item_id
        item_dir.mkdir(parents=True, exist_ok=True)

        zip_bytes = crypto.decrypt((CONTENT_DIR / item["bundle"]).read_bytes(), APP_STORE_ID)
        with zipfile.ZipFile(io.BytesIO(zip_bytes)) as zf:
            for name in zf.namelist():
                if name.endswith("/index.json"):
                    continue  # the zip's own files-listing, not RawPacks' index.json
                (item_dir / Path(name).name).write_bytes(zf.read(name))

        if item.get("audioBundle"):
            audio_bytes = crypto.decrypt((CONTENT_DIR / item["audioBundle"]).read_bytes(), APP_STORE_ID)
            ext = Path(item["audioBundle"]).suffix
            (item_dir / f"{item_id}{ext}").write_bytes(audio_bytes)

        index = {"name": item.get("name", item_id)}
        if item.get("description"):
            index["description"] = item["description"]
        if "readingTimeMinutes" in item:
            index["readingTimeMinutes"] = item["readingTimeMinutes"]
        if "tags" in item:
            index["tags"] = item["tags"]
        (item_dir / "index.json").write_text(
            json.dumps(index, ensure_ascii=False, indent=2) + "\n"
        )
        print(f"  restored {item_id}")

    return len(manifest["items"])


def restore_festivals() -> int:
    manifest_path = FESTIVALS_DIR / "manifest.json"
    if not manifest_path.is_file():
        return 0

    manifest = json.loads(manifest_path.read_text())
    festivals_src = SOURCE_DIR / "festivals"
    festivals_src.mkdir(parents=True, exist_ok=True)

    for item in manifest["items"]:
        payload = crypto.decrypt((FESTIVALS_DIR / item["bundle"]).read_bytes(), APP_STORE_ID)
        data = json.loads(payload)

        # publish.py rewrites bare "festival.png" -> "packs/images/festival.png"
        # before publishing. Undo that here, or re-editing and republishing
        # would double the prefix.
        for tm in data.get("types", []):
            if tm.get("image", "").startswith("packs/images/"):
                tm["image"] = tm["image"][len("packs/images/"):]
        for f in data.get("festivals", []):
            if f.get("image", "").startswith("packs/images/"):
                f["image"] = f["image"][len("packs/images/"):]

        (festivals_src / f"{item['id']}.json").write_text(
            json.dumps(data, ensure_ascii=False, indent=2) + "\n"
        )
        print(f"  restored festivals/{item['id']}.json")

    return len(manifest["items"])


def main() -> int:
    if not (CONTENT_DIR / "manifest.json").is_file():
        print("error: content/manifest.json does not exist — nothing to decrypt")
        return 1

    SOURCE_DIR.mkdir(parents=True, exist_ok=True)
    item_count = restore_items()
    festival_count = restore_festivals()

    print(f"\nRestored {item_count} item(s) and {festival_count} festival year(s). "
          "categories/ and festivals/images/ were never deleted, so they're untouched.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
