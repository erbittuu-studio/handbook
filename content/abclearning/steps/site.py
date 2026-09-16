#!/usr/bin/env python3
"""Stages the hosted data directly into Hosting/ (this content folder).

Run by CI as `cd Hosting && python3 build.py site --clean`.

Stages config.json and manifest.json — the app's public pages (privacy,
terms, support) are no longer built here; they're owned by the website repo.

Builds every numeric folder under Hosting/Source/packs/ into
Hosting/packs/<id>.zip, whether or not the manifest currently
references it — this app pre-stages pack content ahead of the manifest
update that references it, and the original Data/scripts/sync_content.py did
the same. manifest.json is copied through unchanged: its `config` block
(forceUpdate/maintenanceMode/showAds) is this app's own remote-config
mechanism, separate from and untouched by PES's seeded config.json.
"""
import argparse
import json
import shutil
import sys
import zipfile
from pathlib import Path

HOSTING_DIR = Path(__file__).resolve().parent.parent
SOURCE_DIR = HOSTING_DIR / "Source"
PACKS_SOURCE_DIR = SOURCE_DIR / "packs"
BUILD_DIR = HOSTING_DIR
CONFIG_FILE = HOSTING_DIR / "config.json"
MANIFEST_FILE = HOSTING_DIR / "index.json"

# ZIP entries carry a timestamp; zipfile.write() embeds the SOURCE file's
# mtime, which is fresh on every CI checkout — proven by touching a source
# file and rebuilding: the archive changed even though the content did not.
# A fixed timestamp makes identical content produce an identical archive, so
# an unpublished pack does not re-download for every install on every
# deploy. 1980-01-01 is the earliest a ZIP can express.
ZIP_EPOCH = (1980, 1, 1, 0, 0, 0)


def build_pack(pack_dir: Path, packs_out: Path, verbose: bool) -> int:
    """Zips one pack folder. Returns its item count for the summary line."""
    zip_path = packs_out / f"{pack_dir.name}.zip"
    index_path = pack_dir / "index.json"
    item_count = 0
    if index_path.exists():
        item_count = len(json.loads(index_path.read_text()).get("items", []))

    with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        for path in sorted(pack_dir.rglob("*")):
            if not path.is_file():
                continue
            arcname = str(path.relative_to(PACKS_SOURCE_DIR))
            info = zipfile.ZipInfo(arcname, date_time=ZIP_EPOCH)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            zf.writestr(info, path.read_bytes())
            if verbose:
                print(f"  {arcname}")
    return item_count


def stage_packs(verbose: bool) -> bool:
    if not PACKS_SOURCE_DIR.is_dir():
        print(f"error: {PACKS_SOURCE_DIR} does not exist")
        return False
    pack_dirs = sorted(p for p in PACKS_SOURCE_DIR.iterdir() if p.is_dir() and p.name.isdigit())
    if not pack_dirs:
        print(f"error: no numeric pack folders under {PACKS_SOURCE_DIR}")
        return False

    packs_out = BUILD_DIR / "packs"
    packs_out.mkdir(parents=True, exist_ok=True)
    for pack_dir in pack_dirs:
        count = build_pack(pack_dir, packs_out, verbose)
        print(f"  packs/{pack_dir.name}.zip — {count} item(s)")
    return True


def stage_manifest() -> bool:
    if not MANIFEST_FILE.is_file():
        print(f"error: {MANIFEST_FILE} does not exist")
        return False
    try:
        json.loads(MANIFEST_FILE.read_text())
    except json.JSONDecodeError as exc:
        print(f"error: manifest.json is not valid JSON ({exc})")
        return False
    BUILD_DIR.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(MANIFEST_FILE, BUILD_DIR / "manifest.json")
    print("  Staged manifest.json")
    return True


def stage_config() -> bool:
    """config.json already lives at BUILD_DIR — nothing to copy, just validate."""
    if not CONFIG_FILE.is_file():
        print(f"error: {CONFIG_FILE} does not exist — the site must ship a config")
        return False
    try:
        json.loads(CONFIG_FILE.read_text())
    except json.JSONDecodeError as exc:
        print(f"error: config.json is not valid JSON ({exc})")
        return False
    print("  config.json OK")
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description="Stage the hosted site")
    parser.add_argument("--clean", action="store_true", help="remove generated packs/manifest first")
    # pr.yml's data-ci job passes --verbose. argparse exits 2 on an unknown
    # argument, so a step without it fails the check with "unrecognized
    # arguments" rather than anything about the data.
    parser.add_argument("--verbose", "-v", action="store_true", help="list every staged file")
    args = parser.parse_args()

    # BUILD_DIR is the content folder itself now (no separate staging dir), so
    # --clean removes only what this script generates, never Source/ or config.
    if args.clean:
        if (BUILD_DIR / "packs").exists():
            shutil.rmtree(BUILD_DIR / "packs")
        (BUILD_DIR / "manifest.json").unlink(missing_ok=True)

    print("Staging packs...")
    ok = stage_packs(args.verbose)
    print("Staging manifest and config...")
    ok = stage_manifest() and ok
    ok = stage_config() and ok
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
