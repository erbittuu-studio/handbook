#!/usr/bin/env python3
"""Stages the whole hosted site directly into Hosting/ (this content folder).

Run by CI as `cd Hosting && python3 build.py site --clean` before the deploy.

The app's public pages (privacy, terms, support) are no longer staged here;
they're owned by the website repo. This script builds config.json validation
and the content bundles (texts, categories, festivals) directly into Hosting/.

Options:
    --clean     Remove the staged site before building
    --verify    Verify existing build integrity
    --verbose   Show detailed output

Version Management:
    Single version number in index.json. When it changes, the app clears its
    cache and re-downloads everything. Between version changes the app fetches
    only the bundles whose checksum moved, which is why the archives are built
    deterministically — see ZIP_EPOCH.

Directory Structure:
    index.json          - Source of truth: app info, items metadata, versioning
    config.json         - Remote config, served as-is from here
    Source/             - Content files (edit these)
        {item_id}/
            {item_id}_{lang}.json    - Content in each language
            {item_id}_meanings.json  - Meanings/explanations (optional)
            {item_id}.mp3            - Audio file (optional)
            {item_id}.png            - Image file (optional)

    Generated directly into this folder (gitignored nowhere now — commit it):
        manifest.json   - Final manifest with checksums and file info
        texts/{item_id}.zip
        categories/, festivals/, festivals_<year>.json

Workflow:
    1. Edit content files in Source/{item_id}/
    2. Run this script, commit the result.
"""

import os
import sys
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
SOURCE_DIR = HOSTING_DIR / "Source"
BUILD_DIR = HOSTING_DIR
INDEX_FILE = HOSTING_DIR / "index.json"
CONFIG_FILE = HOSTING_DIR / "config.json"
TEXTS_DIR = BUILD_DIR / "texts"
CATEGORIES_SRC_DIR = SOURCE_DIR / "categories"
CATEGORIES_BUILD_DIR = BUILD_DIR / "categories"
FESTIVALS_SRC_DIR = SOURCE_DIR / "festivals"
FESTIVAL_IMAGES_SRC_DIR = FESTIVALS_SRC_DIR / "images"
FESTIVAL_IMAGES_BUILD_DIR = BUILD_DIR / "festivals" / "images"

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
    """Load index.json - the source of truth."""
    if not INDEX_FILE.exists():
        log_error(f"index.json not found at {INDEX_FILE}")
        log_error("Create index.json with app info and items metadata")
        return None

    index = load_json(INDEX_FILE)
    if not index:
        return None

    # Validate required fields
    required = ["app", "data", "config", "items"]
    for field in required:
        if field not in index:
            log_error(f"Missing required field '{field}' in index.json")
            return None

    # Ensure version exists
    if "version" not in index["data"]:
        index["data"]["version"] = 1

    return index


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


def create_zip_bundle(item_id: str, files: Dict, verbose: bool = False) -> Optional[Path]:
    """Create ZIP bundle for an item."""
    item_dir = SOURCE_DIR / item_id
    zip_path = TEXTS_DIR / f"{item_id}.zip"

    # Ensure output directory exists
    TEXTS_DIR.mkdir(parents=True, exist_ok=True)

    # Create index.json for the bundle
    index_content = create_index_json(item_id, files)

    try:
        with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED) as zf:
            # Add index.json
            index_json = json.dumps(index_content, ensure_ascii=False, indent=2)
            _add(zf, f"{item_id}/index.json", index_json.encode("utf-8"))
            log(f"  Added: {item_id}/index.json", verbose)

            # Add content files
            for lang, filename in sorted(files["content"].items()):
                src_path = item_dir / filename
                if src_path.exists():
                    _add(zf, f"{item_id}/{filename}", src_path.read_bytes())
                    log(f"  Added: {item_id}/{filename}", verbose)

            # Add meanings file
            if files["meanings"]:
                src_path = item_dir / files["meanings"]
                if src_path.exists():
                    _add(zf, f"{item_id}/{files['meanings']}", src_path.read_bytes())
                    log(f"  Added: {item_id}/{files['meanings']}", verbose)

            # Add audio file
            if files["audio"]:
                src_path = item_dir / files["audio"]
                if src_path.exists():
                    _add(zf, f"{item_id}/{files['audio']}", src_path.read_bytes())
                    log(f"  Added: {item_id}/{files['audio']}", verbose)

            # Add image file
            if files["image"]:
                src_path = item_dir / files["image"]
                if src_path.exists():
                    _add(zf, f"{item_id}/{files['image']}", src_path.read_bytes())
                    log(f"  Added: {item_id}/{files['image']}", verbose)

        return zip_path

    except Exception as e:
        log_error(f"Failed to create ZIP for {item_id}: {e}")
        return None


def create_manifest_item(item_meta: Dict, files: Dict, zip_path: Path) -> Dict:
    """Create manifest entry for an item with checksum."""
    checksum = compute_sha256(zip_path)
    size = compute_file_size(zip_path)
    item_id = item_meta["id"]

    result = {
        "id": item_id,
        "name": item_meta.get("name", item_id),
        "description": item_meta.get("description", ""),
        "path": f"texts/{item_id}/index.json",
        "bundle": f"texts/{item_id}.zip",
        "languages": files["languages"],
        "hasAudio": files["hasAudio"],
        "hasMeanings": files["hasMeanings"],
        "hasImage": files["hasImage"],
        "checksum": checksum,
        "size": size
    }

    # Include optional fields if present
    if "readingTimeMinutes" in item_meta:
        result["readingTimeMinutes"] = item_meta["readingTimeMinutes"]
    if "tags" in item_meta:
        result["tags"] = item_meta["tags"]

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
                cat_copy["image"] = f"categories/{category['image']}"
                log(f"  Copied: {category['image']}", verbose)
            else:
                log_warning(f"Category image not found: {src_image}")
                cat_copy.pop("image", None)
        updated_categories.append(cat_copy)

    return updated_categories


def process_festivals(index: Dict, verbose: bool = False) -> bool:
    """Validate source/festivals/<year>.json files and copy them to
    build/festivals_<year>.json (the app fetches that exact path).
    Returns False on any validation error."""
    if not FESTIVALS_SRC_DIR.exists():
        log_warning("No festivals source folder found — skipping")
        return True

    log_section("Processing Festivals")

    valid_prayer_ids = {item["id"] for item in index["items"]}
    valid_deity_ids = {d["id"] for d in index.get("deities", [])}

    ok = True

    # Type artwork: source/festivals/images/*.png → build/festivals/images/
    if FESTIVAL_IMAGES_SRC_DIR.exists():
        FESTIVAL_IMAGES_BUILD_DIR.mkdir(parents=True, exist_ok=True)
        image_count = 0
        for img in sorted(FESTIVAL_IMAGES_SRC_DIR.glob("*.png")):
            shutil.copy2(img, FESTIVAL_IMAGES_BUILD_DIR / img.name)
            image_count += 1
        log_success(f"festivals/images: {image_count} type images")

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
            if tm_img and not (BUILD_DIR / tm_img).exists():
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
            if image and not (BUILD_DIR / image).exists():
                errors.append(f"{fid}: image '{image}' not found in build")

        if errors:
            for e in errors:
                log_error(f"festivals/{src.name}: {e}")
            ok = False
            continue

        BUILD_DIR.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, BUILD_DIR / f"festivals_{year}.json")
        log_success(f"festivals_{year}.json: {len(festivals)} entries")

    # Freshness: warn when the data horizon is running out
    if latest_date:
        days_left = (datetime.strptime(latest_date, "%Y-%m-%d")
                     - datetime.now()).days
        if days_left < 90:
            log_warning(f"Festival data ends {latest_date} "
                        f"({days_left} days away) — add next year's file")
        else:
            log(f"Festival data horizon: {latest_date} ({days_left} days)", verbose)

    return ok


def create_manifest(index: Dict, items: List[Dict], verbose: bool = False) -> Dict:
    """Create the complete manifest.json."""
    manifest = {
        "app": index["app"],
        "data": index["data"],
        "config": index["config"],
        "items": items,
        "_meta": {
            "generatedAt": datetime.utcnow().isoformat() + "Z",
            "generator": "build.py",
            "itemCount": len(items)
        }
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


def verify_build(verbose: bool = False) -> bool:
    """Verify integrity of existing build."""
    log_section("Verifying Build Integrity")

    manifest_path = BUILD_DIR / "manifest.json"
    if not manifest_path.exists():
        log_error("manifest.json not found in build directory")
        return False

    manifest = load_json(manifest_path)
    if not manifest:
        return False

    all_valid = True
    for item in manifest.get("items", []):
        item_id = item["id"]
        expected_checksum = item.get("checksum")
        zip_path = BUILD_DIR / item["bundle"]

        if not zip_path.exists():
            log_error(f"{item_id}: ZIP file missing")
            all_valid = False
            continue

        if expected_checksum:
            actual_checksum = compute_sha256(zip_path)
            if actual_checksum == expected_checksum:
                log_success(f"{item_id}: Checksum valid")
            else:
                log_error(f"{item_id}: Checksum mismatch!")
                log(f"  Expected: {expected_checksum}", verbose)
                log(f"  Actual:   {actual_checksum}", verbose)
                all_valid = False
        else:
            log_warning(f"{item_id}: No checksum in manifest")

    return all_valid


def clean_build():
    """Remove generated output only — BUILD_DIR is the content folder itself
    now (no separate staging dir), so this must never touch Source/ or config."""
    for path in (TEXTS_DIR, CATEGORIES_BUILD_DIR, BUILD_DIR / "festivals"):
        if path.exists():
            shutil.rmtree(path)
    (BUILD_DIR / "manifest.json").unlink(missing_ok=True)
    for path in BUILD_DIR.glob("festivals_*.json"):
        path.unlink()
    log_success("Removed generated output")


def build(verbose: bool = False) -> tuple[bool, Optional[Dict], List[Dict]]:
    """Main build process. Returns (success, index, manifest_items)."""
    log_section("Loading Index")
    index = load_index()
    if not index:
        return False, None, []

    log_success(f"Version: {index['data']['version']}")
    log_success(f"Items defined: {len(index['items'])}")

    log_section("Processing Items")
    manifest_items = []
    errors = []

    for item_meta in index["items"]:
        item_id = item_meta["id"]
        log(f"\nProcessing: {item_id}", True)

        # Scan source folder for files
        files = analyze_item_files(item_id, verbose)
        if not files:
            errors.append(item_id)
            continue

        log_success(f"{item_id}: {len(files['languages'])} langs, audio={files['hasAudio']}, meanings={files['hasMeanings']}, image={files['hasImage']}")

        # Create ZIP bundle
        zip_path = create_zip_bundle(item_id, files, verbose)
        if not zip_path:
            errors.append(item_id)
            continue

        # Create manifest entry
        manifest_item = create_manifest_item(item_meta, files, zip_path)
        manifest_items.append(manifest_item)

    if errors:
        log_section("Errors")
        for item_id in errors:
            log_error(f"Failed to build: {item_id}")

    if not process_festivals(index, verbose):
        errors.append("festivals")

    log_section("Creating Manifest")
    manifest = create_manifest(index, manifest_items, verbose)
    manifest_path = BUILD_DIR / "manifest.json"
    save_json(manifest_path, manifest)
    log_success(f"Created manifest.json with {len(manifest_items)} items")
    if "categories" in manifest:
        log_success(f"Included {len(manifest['categories'])} categories with images")

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
      - texts/*.zip ({len(manifest_items)} files)

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
    """config.json already lives at BUILD_DIR — nothing to copy, just validate."""
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

    return 0 if success else 1


if __name__ == "__main__":
    sys.exit(main())
