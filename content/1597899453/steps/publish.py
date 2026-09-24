#!/usr/bin/env python3
"""Turns RawPacks/ into the publishable site — two manifests, named in
config.json's "manifests" list, each entirely under its own folder:
content/ (prayer items, categories) and festivals/ (the calendar). Committing
the result to `main` is the deploy.

Run by CI (`cd Hosting && python3 build.py publish --clean`).

- Two manifests, not one, because prayers and festival years change on
  different schedules and aren't the same kind of thing — a calendar update
  shouldn't bump the checksum of every prayer's entry along with it.
  `festivals/manifest.json`'s items are years, same shape as `content/`'s
  items are prayers: id, bundle, bytes, sha256, required.
- Each item's own `RawPacks/<id>/index.json` holds its name, description,
  tags — not a separate list kept in sync with the folders by hand.
- `checksum`/`size` (not `sha256`/`bytes`) are the field names here,
  deliberately — a live app already reads them to verify and cache
  downloads, so the names don't change even though every other app in the
  portfolio calls them something else.
- Bundles are named by content hash (`packs/<hash>.zip`, `packs/<hash>.mp3`)
  — a changed item gets a new hash, so old installs keep the old URL until
  they refresh and nothing stale is ever served.
- Zips are built deterministically (sorted entries, fixed timestamps), so
  unchanged content keeps its hash and isn't re-uploaded.
- Every item's zip and audio, and every festival year, are encrypted
  (crypto.py, key = this app's own App Store id) before they're hashed and
  written — the checksum/size in each manifest are of the encrypted bytes,
  so `verify_build()` needs no changes. RawPacks/<item>/ and
  RawPacks/festivals/<year>.json are deleted after a successful build (see
  --keep-source); RawPacks/categories/ and RawPacks/festivals/images/ are
  NOT deleted, because those images aren't encrypted (they're copied as-is,
  no checksum) and there'd be nothing to reconstruct them from. RawPacks/ as
  a whole is git-ignored regardless. Run `decrypt_to_rawpacks.py` to rebuild
  the deleted parts for editing.

Options:
    --clean     Remove the staged site before building
    --verify    Verify existing build integrity
    --verbose   Show detailed output
"""

import os
import sys
import io
import json
import hashlib
import zipfile
import shutil
import argparse
import subprocess
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Optional, Any

# Constants
#
# Generates directly into HOSTING_DIR — that's this content folder, committed
# straight to GitHub, so there's no separate staging/deploy step anymore.
HOSTING_DIR = Path(__file__).resolve().parent.parent
SOURCE_DIR = HOSTING_DIR / "RawPacks"
INDEX_FILE = HOSTING_DIR / "index.json"
CONFIG_FILE = HOSTING_DIR / "config.json"

sys.path.insert(0, str(HOSTING_DIR))
import crypto  # noqa: E402

APP_STORE_ID = HOSTING_DIR.name

# The "content" manifest — prayer items and categories.
CONTENT_DIR = HOSTING_DIR / "content"
PACKS_DIR = CONTENT_DIR / "packs"
CATEGORIES_SRC_DIR = SOURCE_DIR / "categories"
CATEGORIES_BUILD_DIR = PACKS_DIR / "categories"

# The "festivals" manifest — its own folder, its own packs (one per year).
FESTIVALS_SRC_DIR = SOURCE_DIR / "festivals"
FESTIVALS_DIR = HOSTING_DIR / "festivals"
FESTIVALS_PACKS_DIR = FESTIVALS_DIR / "packs"
FESTIVAL_IMAGES_SRC_DIR = FESTIVALS_SRC_DIR / "images"
FESTIVAL_IMAGES_BUILD_DIR = FESTIVALS_PACKS_DIR / "images"

MANIFEST_VERSION = 1

# categories/ and festivals/ are RawPacks folders too, but they're source data
# for those two features, not downloadable items — never treated as one.
NON_ITEM_FOLDERS = {"categories", "festivals"}

FESTIVAL_TYPES = {"festival", "ekadashi", "purnima", "amavasya",
                  "pradosh", "sankashti", "shivaratri",
                  "vinayaka", "durgashtami", "sashti", "kalashtami"}
FESTIVAL_REQUIRED_FIELDS = ["id", "name", "description", "date",
                            "prayerIds", "notifyDaysBefore"]

AUDIO_EXTENSIONS = [".mp3", ".m4a", ".wav", ".aac"]
IMAGE_EXTENSIONS = [".png", ".jpg", ".jpeg", ".webp"]


def log(message: str, verbose: bool = True):
    """Print log message if verbose mode is on."""
    if verbose:
        print(f"  {message}")


def log_section(title: str):
    """Print section header."""
    print(f"\n{'='*60}")
    print(f"  {title}")
    print(f"{'='*60}")


def log_success(message: str):
    """Print success message."""
    print(f"  [OK] {message}")


def log_error(message: str):
    """Print error message."""
    print(f"  [ERROR] {message}")


def log_warning(message: str):
    """Print warning message."""
    print(f"  [WARN] {message}")


def compute_sha256(file_path: Path) -> str:
    """Compute SHA-256 hash of a file."""
    sha256_hash = hashlib.sha256()
    with open(file_path, "rb") as f:
        for byte_block in iter(lambda: f.read(4096), b""):
            sha256_hash.update(byte_block)
    return sha256_hash.hexdigest()


def compute_file_size(file_path: Path) -> int:
    """Get file size in bytes."""
    return file_path.stat().st_size


def format_size(size_bytes: int) -> str:
    """Format size in human readable format."""
    if size_bytes < 1024:
        return f"{size_bytes} B"
    elif size_bytes < 1024 * 1024:
        return f"{size_bytes / 1024:.1f} KB"
    else:
        return f"{size_bytes / (1024 * 1024):.1f} MB"


def load_json(file_path: Path) -> Optional[Dict]:
    """Load JSON file, return None if failed."""
    try:
        with open(file_path, "r", encoding="utf-8") as f:
            return json.load(f)
    except (json.JSONDecodeError, FileNotFoundError) as e:
        log_error(f"Failed to load {file_path}: {e}")
        return None


def save_json(file_path: Path, data: Dict, indent: int = 2):
    """Save data to JSON file."""
    file_path.parent.mkdir(parents=True, exist_ok=True)
    with open(file_path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=indent)


def load_index() -> Optional[Dict]:
    """Load index.json — app info, versioning, categories/deities/todaysPrayer.
    Item metadata lives per item now, in RawPacks/<id>/index.json instead."""
    if not INDEX_FILE.exists():
        log_error(f"index.json not found at {INDEX_FILE}")
        return None

    index = load_json(INDEX_FILE)
    if not index:
        return None

    required = ["app", "data", "config"]
    for field in required:
        if field not in index:
            log_error(f"Missing required field '{field}' in index.json")
            return None

    if "version" not in index["data"]:
        index["data"]["version"] = 1

    return index


def discover_items() -> List[str]:
    """Every RawPacks/ folder that isn't categories/ or festivals/ — the
    folder's existence is the only thing that says an item exists."""
    return sorted(
        p.name for p in SOURCE_DIR.iterdir()
        if p.is_dir() and p.name not in NON_ITEM_FOLDERS
    )


def item_meta(item_id: str) -> Dict:
    """This item's own index.json — name, description, tags, readingTimeMinutes.
    Missing isn't fatal (the build still has to go out), just a loud warning."""
    meta_path = SOURCE_DIR / item_id / "index.json"
    if not meta_path.is_file():
        log_warning(f"{item_id} has no index.json — it will ship named \"{item_id}\"")
        return {"id": item_id}
    meta = load_json(meta_path) or {}
    if not meta.get("name"):
        log_warning(f"{item_id}/index.json has no \"name\" — it will ship named \"{item_id}\"")
    return {"id": item_id, **meta}


def analyze_item_files(item_id: str, verbose: bool = False) -> Optional[Dict]:
    """Scan source folder to find content files for an item."""
    item_dir = SOURCE_DIR / item_id

    if not item_dir.exists():
        log_error(f"Source folder not found: {item_dir}")
        return None

    # Discover content files by language
    content_files: Dict[str, str] = {}
    for file in item_dir.iterdir():
        if file.suffix == ".json" and not file.name.endswith("_meanings.json"):
            # Parse language from filename: {item_id}_{lang}.json
            name = file.stem
            if name.startswith(f"{item_id}_"):
                lang = name[len(f"{item_id}_"):]
                if lang in ["en", "hi", "gu"]:
                    content_files[lang] = file.name
                    log(f"  Found content: {file.name} ({lang})", verbose)

    if not content_files:
        log_error(f"No content files found for {item_id}")
        return None

    # Check for meanings file
    meanings_file = item_dir / f"{item_id}_meanings.json"
    has_meanings = meanings_file.exists()
    if has_meanings:
        log(f"  Found meanings: {meanings_file.name}", verbose)

    # Check for audio file
    audio_file = None
    for ext in AUDIO_EXTENSIONS:
        potential_audio = item_dir / f"{item_id}{ext}"
        if potential_audio.exists():
            audio_file = potential_audio.name
            log(f"  Found audio: {audio_file}", verbose)
            break

    # Check for image file
    image_file = None
    for ext in IMAGE_EXTENSIONS:
        potential_image = item_dir / f"{item_id}{ext}"
        if potential_image.exists():
            image_file = potential_image.name
            log(f"  Found image: {image_file}", verbose)
            break

    return {
        "content": content_files,
        "meanings": meanings_file.name if has_meanings else None,
        "audio": audio_file,
        "image": image_file,
        "languages": list(content_files.keys()),
        "hasAudio": audio_file is not None,
        "hasMeanings": has_meanings,
        "hasImage": image_file is not None
    }


def create_index_json(item_id: str, files: Dict) -> Dict:
    """Create index.json content for a ZIP bundle."""
    index = {
        "id": item_id,
        "files": {
            "content": files["content"]
        }
    }

    if files["meanings"]:
        index["files"]["meanings"] = files["meanings"]

    if files["audio"]:
        index["files"]["audio"] = files["audio"]

    if files["image"]:
        index["files"]["image"] = files["image"]

    return index


# ZIP entries carry a timestamp, and the checksum below is taken over the
# archive bytes, so an unchanged prayer produced a different checksum on every
# build: writestr() stamps the current time, and write() copies the source
# file's mtime, which is fresh on every CI clone. The manifest exists so the app
# "only downloads ZIPs with changed checksums" — with churning checksums every
# install re-downloaded all 37 bundles after every deploy.
#
# Pinning the timestamp makes identical content produce an identical archive.
# 1980-01-01 is the earliest a ZIP can express.
ZIP_EPOCH = (1980, 1, 1, 0, 0, 0)


def _add(zf: zipfile.ZipFile, arcname: str, data: bytes) -> None:
    """Write one entry with a fixed timestamp and fixed permissions."""
    info = zipfile.ZipInfo(arcname, date_time=ZIP_EPOCH)
    info.compress_type = zipfile.ZIP_DEFLATED
    info.external_attr = 0o644 << 16
    zf.writestr(info, data)


def build_zip_bundle(item_id: str, files: Dict, verbose: bool = False) -> Optional[bytes]:
    """Builds an item's ZIP bundle in memory — its own index.json (page/file
    listing, distinct from RawPacks/<id>/index.json's authored metadata) plus
    its text/meanings/image files. Named by content hash once built, by the
    caller, so this only returns bytes."""
    item_dir = SOURCE_DIR / item_id
    index_content = create_index_json(item_id, files)

    try:
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, 'w', zipfile.ZIP_DEFLATED) as zf:
            index_json = json.dumps(index_content, ensure_ascii=False, indent=2)
            _add(zf, f"{item_id}/index.json", index_json.encode("utf-8"))
            log(f"  Added: {item_id}/index.json", verbose)

            for lang, filename in sorted(files["content"].items()):
                src_path = item_dir / filename
                if src_path.exists():
                    _add(zf, f"{item_id}/{filename}", src_path.read_bytes())
                    log(f"  Added: {item_id}/{filename}", verbose)

            if files["meanings"]:
                src_path = item_dir / files["meanings"]
                if src_path.exists():
                    _add(zf, f"{item_id}/{files['meanings']}", src_path.read_bytes())
                    log(f"  Added: {item_id}/{files['meanings']}", verbose)

            # Audio is NOT in the zip — see build()'s separate audio-file step. It is
            # often the largest thing an item has and, unlike text/meanings/image,
            # most installs never open it: bundling it here meant downloading it on
            # every first view of a prayer whether or not it was ever played.

            if files["image"]:
                src_path = item_dir / files["image"]
                if src_path.exists():
                    _add(zf, f"{item_id}/{files['image']}", src_path.read_bytes())
                    log(f"  Added: {item_id}/{files['image']}", verbose)

        return buffer.getvalue()

    except Exception as e:
        log_error(f"Failed to create ZIP for {item_id}: {e}")
        return None


def create_manifest_item(meta: Dict, files: Dict, zip_bytes: bytes, audio_bytes: Optional[bytes]) -> Dict:
    """Creates the manifest entry for an item, writing its zip (and audio, if
    any) to PACKS_DIR under a content-hash filename as it goes."""
    item_id = meta["id"]
    PACKS_DIR.mkdir(parents=True, exist_ok=True)

    zip_encrypted = crypto.encrypt(zip_bytes, APP_STORE_ID)
    checksum = hashlib.sha256(zip_encrypted).hexdigest()
    zip_name = f"{checksum[:12]}.zip"
    (PACKS_DIR / zip_name).write_bytes(zip_encrypted)

    result = {
        "id": item_id,
        "name": meta.get("name", item_id),
        "description": meta.get("description", ""),
        "path": f"packs/{item_id}/index.json",
        "bundle": f"packs/{zip_name}",
        "languages": files["languages"],
        "hasAudio": files["hasAudio"],
        "hasMeanings": files["hasMeanings"],
        "hasImage": files["hasImage"],
        "checksum": checksum,
        "size": len(zip_encrypted)
    }

    # A separate pack, fetched only when the item is played. Same shape as
    # `bundle`/`checksum`/`size` above so the app reads it the same way.
    if audio_bytes is not None:
        audio_encrypted = crypto.encrypt(audio_bytes, APP_STORE_ID)
        audio_checksum = hashlib.sha256(audio_encrypted).hexdigest()
        ext = Path(files["audio"]).suffix
        audio_name = f"{audio_checksum[:12]}{ext}"
        (PACKS_DIR / audio_name).write_bytes(audio_encrypted)
        result["audioBundle"] = f"packs/{audio_name}"
        result["audioChecksum"] = audio_checksum
        result["audioSize"] = len(audio_encrypted)

    # Include optional fields if present
    if "readingTimeMinutes" in meta:
        result["readingTimeMinutes"] = meta["readingTimeMinutes"]
    if "tags" in meta:
        result["tags"] = meta["tags"]

    return result


def copy_category_images(categories: List[Dict], verbose: bool = False) -> List[Dict]:
    """Copy category images to build directory and return updated categories with paths."""
    if not CATEGORIES_SRC_DIR.exists():
        log_warning("No categories source folder found")
        return categories

    CATEGORIES_BUILD_DIR.mkdir(parents=True, exist_ok=True)

    updated_categories = []
    for category in categories:
        cat_copy = category.copy()
        if "image" in category:
            src_image = CATEGORIES_SRC_DIR / category["image"]
            if src_image.exists():
                dst_image = CATEGORIES_BUILD_DIR / category["image"]
                shutil.copy2(src_image, dst_image)
                cat_copy["image"] = f"packs/categories/{category['image']}"
                log(f"  Copied: {category['image']}", verbose)
            else:
                log_warning(f"Category image not found: {src_image}")
                cat_copy.pop("image", None)
        updated_categories.append(cat_copy)

    return updated_categories


def process_festivals(index: Dict, item_ids: List[str], verbose: bool = False) -> tuple[bool, List[Dict]]:
    """Validate RawPacks/festivals/<year>.json files and build them into the
    festivals manifest's own packs — one checksummed pack per year, image
    paths rewritten to their served location. Returns (ok, festival items)."""
    if not FESTIVALS_SRC_DIR.exists():
        log_warning("No festivals source folder found — skipping")
        return True, []

    log_section("Processing Festivals")

    valid_prayer_ids = set(item_ids)
    valid_deity_ids = {d["id"] for d in index.get("deities", [])}

    ok = True
    festival_items: List[Dict] = []

    # Type artwork: RawPacks/festivals/images/*.png → festivals/packs/images/
    if FESTIVAL_IMAGES_SRC_DIR.exists():
        FESTIVAL_IMAGES_BUILD_DIR.mkdir(parents=True, exist_ok=True)
        image_count = 0
        for img in sorted(FESTIVAL_IMAGES_SRC_DIR.glob("*.png")):
            shutil.copy2(img, FESTIVAL_IMAGES_BUILD_DIR / img.name)
            image_count += 1
        log_success(f"festivals/packs/images: {image_count} type images")

    latest_date = None
    for src in sorted(FESTIVALS_SRC_DIR.glob("*.json")):
        year_str = src.stem
        if not (year_str.isdigit() and len(year_str) == 4):
            log_error(f"festivals/{src.name}: filename must be <year>.json")
            ok = False
            continue
        year = int(year_str)

        data = load_json(src)
        if not data:
            ok = False
            continue

        errors = []
        if data.get("year") != year:
            errors.append(f"'year' is {data.get('year')}, expected {year}")
        festivals = data.get("festivals", [])
        if data.get("count") != len(festivals):
            errors.append(f"'count' is {data.get('count')}, "
                          f"but file has {len(festivals)} festivals")

        # Type metadata block: the app builds its filter UI from this, so
        # every type used by an entry must be described here.
        type_metas = data.get("types", [])
        meta_ids = set()
        for tm in type_metas:
            tid = tm.get("id", "<missing id>")
            for field in ["id", "label", "image", "order", "showLabel",
                          "notifyDefault"]:
                if field not in tm:
                    errors.append(f"types/{tid}: missing field '{field}'")
            if tid in meta_ids:
                errors.append(f"types/{tid}: duplicate id")
            meta_ids.add(tid)
            tm_img = tm.get("image")
            if tm_img and not (FESTIVAL_IMAGES_SRC_DIR / tm_img).exists():
                errors.append(f"types/{tid}: image '{tm_img}' not found")
        used_types = {f.get("type") for f in festivals if f.get("type")}
        undescribed = used_types - meta_ids
        if undescribed:
            errors.append(f"types used by entries but missing from "
                          f"'types' block: {sorted(undescribed)}")

        seen_ids = set()
        prev_date = ""
        for f in festivals:
            fid = f.get("id", "<missing id>")
            for field in FESTIVAL_REQUIRED_FIELDS:
                if field not in f:
                    errors.append(f"{fid}: missing field '{field}'")
            if fid in seen_ids:
                errors.append(f"{fid}: duplicate id")
            seen_ids.add(fid)

            date = f.get("date", "")
            try:
                parsed = datetime.strptime(date, "%Y-%m-%d")
                if parsed.year != year:
                    errors.append(f"{fid}: date {date} outside year {year}")
                if latest_date is None or date > latest_date:
                    latest_date = date
            except ValueError:
                errors.append(f"{fid}: bad date '{date}' (need YYYY-MM-DD)")
            if date < prev_date:
                errors.append(f"{fid}: festivals not in chronological order")
            prev_date = date

            end = f.get("endDate")
            if end:
                try:
                    datetime.strptime(end, "%Y-%m-%d")
                    if end < date:
                        errors.append(f"{fid}: endDate {end} before date {date}")
                except ValueError:
                    errors.append(f"{fid}: bad endDate '{end}'")

            ftype = f.get("type")
            if ftype and ftype not in FESTIVAL_TYPES:
                errors.append(f"{fid}: unknown type '{ftype}'")

            deity = f.get("deity")
            if deity and deity not in valid_deity_ids:
                errors.append(f"{fid}: unknown deity '{deity}'")

            for pid in f.get("prayerIds", []):
                if pid not in valid_prayer_ids:
                    errors.append(f"{fid}: unknown prayerId '{pid}'")

            image = f.get("image")
            if image and not (FESTIVAL_IMAGES_SRC_DIR / image).exists():
                errors.append(f"{fid}: image '{image}' not found")

        if errors:
            for e in errors:
                log_error(f"festivals/{src.name}: {e}")
            ok = False
            continue

        # Source image fields are just filenames ("festival.png") — rewritten
        # here to the served path, same as copy_category_images() does for
        # categories, rather than the source having to know where things end
        # up served from.
        for tm in type_metas:
            if tm.get("image"):
                tm["image"] = f"packs/images/{tm['image']}"
        for f in festivals:
            if f.get("image"):
                f["image"] = f"packs/images/{f['image']}"

        # A year is its own checksummed pack, same as any other pack — named
        # by content hash, so an unchanged year isn't re-uploaded and old
        # installs keep the old URL until they refresh.
        FESTIVALS_PACKS_DIR.mkdir(parents=True, exist_ok=True)
        payload = json.dumps(data, ensure_ascii=False, indent=2).encode("utf-8")
        encrypted = crypto.encrypt(payload, APP_STORE_ID)
        digest = hashlib.sha256(encrypted).hexdigest()
        pack_name = f"{digest[:12]}.json"
        (FESTIVALS_PACKS_DIR / pack_name).write_bytes(encrypted)
        festival_items.append({
            "id": year_str,
            "bundle": f"packs/{pack_name}",
            "bytes": len(encrypted),
            "sha256": digest,
            "required": True,
        })
        log_success(f"festivals/packs/{pack_name}: {len(festivals)} entries")

    # Freshness: warn when the data horizon is running out
    if latest_date:
        days_left = (datetime.strptime(latest_date, "%Y-%m-%d")
                     - datetime.now()).days
        if days_left < 90:
            log_warning(f"Festival data ends {latest_date} "
                        f"({days_left} days away) — add next year's file")
        else:
            log(f"Festival data horizon: {latest_date} ({days_left} days)", verbose)

    return ok, festival_items


def create_manifest(index: Dict, items: List[Dict], verbose: bool = False) -> Dict:
    """Create the complete manifest.json."""
    manifest = {
        "app": index["app"],
        "data": index["data"],
        "config": index["config"],
        "manifestVersion": MANIFEST_VERSION,
        "generatedAt": datetime.utcnow().isoformat() + "Z",
        "items": items,
    }

    # Include categories if defined, with updated image paths
    if "categories" in index:
        manifest["categories"] = copy_category_images(index["categories"], verbose)

    # Include deities if defined
    if "deities" in index:
        manifest["deities"] = index["deities"]

    # Include todaysPrayer if defined
    if "todaysPrayer" in index:
        manifest["todaysPrayer"] = index["todaysPrayer"]

    return manifest


def create_festivals_manifest(festival_items: List[Dict]) -> Dict:
    """The festivals manifest — its own file, its own folder, same shape as
    content/manifest.json but nothing else in it: a festival year isn't an
    app fact the way `app`/`data`/`config` are, so there's nothing to repeat
    here that content/manifest.json already states."""
    return {
        "manifestVersion": MANIFEST_VERSION,
        "generatedAt": datetime.utcnow().isoformat() + "Z",
        "items": festival_items,
    }


def _verify_manifest(base: Path, checksum_key: str, verbose: bool) -> bool:
    """Checks every item's bundle against `checksum_key` ("checksum" for
    content/, "sha256" for festivals/ — see the field-name note up top)."""
    manifest_path = base / "manifest.json"
    if not manifest_path.exists():
        log_error(f"{manifest_path} not found")
        return False

    manifest = load_json(manifest_path)
    if not manifest:
        return False

    all_valid = True
    for item in manifest.get("items", []):
        item_id = item["id"]
        expected = item.get(checksum_key)
        bundle_path = base / item["bundle"]

        if not bundle_path.exists():
            log_error(f"{item_id}: bundle missing")
            all_valid = False
            continue

        if expected:
            actual = compute_sha256(bundle_path)
            if actual == expected:
                log_success(f"{item_id}: Checksum valid")
            else:
                log_error(f"{item_id}: Checksum mismatch!")
                log(f"  Expected: {expected}", verbose)
                log(f"  Actual:   {actual}", verbose)
                all_valid = False
        else:
            log_warning(f"{item_id}: No checksum in manifest")

        if item.get("audioBundle"):
            audio_path = base / item["audioBundle"]
            expected_audio = item.get("audioChecksum")
            if not audio_path.exists():
                log_error(f"{item_id}: audio file missing")
                all_valid = False
            elif expected_audio and compute_sha256(audio_path) != expected_audio:
                log_error(f"{item_id}: audio checksum mismatch!")
                all_valid = False

    return all_valid


def verify_build(verbose: bool = False) -> bool:
    """Verify integrity of both manifests."""
    log_section("Verifying Build Integrity")
    content_ok = _verify_manifest(CONTENT_DIR, "checksum", verbose)
    festivals_ok = True
    if (FESTIVALS_DIR / "manifest.json").exists():
        festivals_ok = _verify_manifest(FESTIVALS_DIR, "sha256", verbose)
    return content_ok and festivals_ok


def delete_published_source(manifest_items: List[Dict]):
    """Removes only the RawPacks/ content that's fully reconstructable from
    what was just published — item folders, and festival year files. Never
    touches RawPacks/categories/ or RawPacks/festivals/images/, since those
    aren't encrypted/checksummed and there'd be nothing to rebuild them
    from."""
    for item in manifest_items:
        item_dir = SOURCE_DIR / item["id"]
        if item_dir.exists():
            shutil.rmtree(item_dir)

    festivals_manifest_path = FESTIVALS_DIR / "manifest.json"
    if festivals_manifest_path.exists():
        festivals_manifest = load_json(festivals_manifest_path) or {}
        for fitem in festivals_manifest.get("items", []):
            (FESTIVALS_SRC_DIR / f"{fitem['id']}.json").unlink(missing_ok=True)

    log_success("Removed published RawPacks/ content (items + festival "
                "years) — categories/ and festivals/images/ are left as-is. "
                "Run decrypt_to_rawpacks.py to get the rest back for editing.")


def clean_build():
    """Remove generated output only — never RawPacks/ or config.json.
    Everything generated lives under content/ and festivals/ now, so removing
    those two folders is the whole job."""
    for path in (CONTENT_DIR, FESTIVALS_DIR):
        if path.exists():
            shutil.rmtree(path)
    log_success("Removed generated output")


def build(verbose: bool = False) -> tuple[bool, Optional[Dict], List[Dict]]:
    """Main build process. Returns (success, index, manifest_items)."""
    log_section("Loading Index")
    index = load_index()
    if not index:
        return False, None, []

    item_ids = discover_items()
    log_success(f"Version: {index['data']['version']}")
    log_success(f"Items found: {len(item_ids)}")

    log_section("Processing Items")
    manifest_items = []
    errors = []

    for item_id in item_ids:
        log(f"\nProcessing: {item_id}", True)
        meta = item_meta(item_id)

        # Scan source folder for files
        files = analyze_item_files(item_id, verbose)
        if not files:
            errors.append(item_id)
            continue

        log_success(f"{item_id}: {len(files['languages'])} langs, audio={files['hasAudio']}, meanings={files['hasMeanings']}, image={files['hasImage']}")

        zip_bytes = build_zip_bundle(item_id, files, verbose)
        if not zip_bytes:
            errors.append(item_id)
            continue

        audio_bytes = None
        if files["audio"]:
            audio_bytes = (SOURCE_DIR / item_id / files["audio"]).read_bytes()

        manifest_item = create_manifest_item(meta, files, zip_bytes, audio_bytes)
        manifest_items.append(manifest_item)

    if errors:
        log_section("Errors")
        for item_id in errors:
            log_error(f"Failed to build: {item_id}")

    festivals_ok, festival_items = process_festivals(index, item_ids, verbose)
    if not festivals_ok:
        errors.append("festivals")

    log_section("Creating Manifests")
    CONTENT_DIR.mkdir(parents=True, exist_ok=True)
    manifest = create_manifest(index, manifest_items, verbose)
    save_json(CONTENT_DIR / "manifest.json", manifest)
    log_success(f"content/manifest.json: {len(manifest_items)} items")
    if "categories" in manifest:
        log_success(f"Included {len(manifest['categories'])} categories with images")

    if festival_items:
        FESTIVALS_DIR.mkdir(parents=True, exist_ok=True)
        festivals_manifest = create_festivals_manifest(festival_items)
        save_json(FESTIVALS_DIR / "manifest.json", festivals_manifest)
        log_success(f"festivals/manifest.json: {len(festival_items)} year(s)")

    return len(errors) == 0, index, manifest_items


def print_summary(index: Dict, manifest_items: List[Dict], pushed: bool = False):
    """Print build summary."""
    log_section("Build Summary")

    total_size = sum(item.get("size", 0) for item in manifest_items)

    print(f"""
    Version:          {index['data']['version']}
    Items Built:      {len(manifest_items)}
    Total Size:       {format_size(total_size)}

    Files Generated:
      - manifest.json
      - packs/*.zip ({len(manifest_items)} files)

    Items:""")

    for item in manifest_items:
        size_str = format_size(item.get("size", 0))
        checksum_short = item.get("checksum", "")[:12] + "..."
        print(f"      - {item['id']}: {size_str} [{checksum_short}]")

    if pushed:
        print(f"""
    Status: Pushed v{index['data']['version']} — deploying to https://prarthana-prod.web.app
    """)
    else:
        print("""
    Next Steps:
      Open a PR — merging to main is what deploys.
    """)


def stage_config() -> bool:
    """config.json stays at the content root, outside any manifest folder —
    nothing to copy, just validate."""
    if not CONFIG_FILE.is_file():
        log_error(f"{CONFIG_FILE} does not exist — the site must ship a config")
        return False
    try:
        json.loads(CONFIG_FILE.read_text())
    except json.JSONDecodeError as exc:
        log_error(f"config.json is not valid JSON ({exc})")
        return False
    log_success("config.json OK")
    return True


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Stage the whole hosted site directly into Hosting/",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__
    )
    parser.add_argument("--clean", action="store_true", help="Clean the staged site before building")
    parser.add_argument("--verify", action="store_true", help="Verify existing build integrity")
    parser.add_argument("--keep-source", action="store_true",
                         help="don't delete the published parts of RawPacks/ after a successful build")
    # pr.yml's data-ci job runs this with --clean --verbose. Accepting the flag
    # is part of the contract: argparse exits 2 on an unknown argument, so a
    # step without it fails the PR check with "unrecognized arguments" rather
    # than anything about the data.
    parser.add_argument("--verbose", "-v", action="store_true", help="Verbose output")

    args = parser.parse_args()

    print("\n" + "="*60)
    print("  Site Builder")
    print("="*60)

    if args.verify:
        return 0 if verify_build(args.verbose) else 1

    if args.clean:
        log_section("Cleaning Staged Site")
        clean_build()

    success, index, manifest_items = build(args.verbose)

    if success and index:
        log_section("Verifying Build")
        verify_build(args.verbose)
        success = stage_config() and success
        print_summary(index, manifest_items, False)
        if success and not args.keep_source:
            delete_published_source(manifest_items)

    return 0 if success else 1


if __name__ == "__main__":
    sys.exit(main())
