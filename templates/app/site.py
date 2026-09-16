#!/usr/bin/env python3
"""Stages the whole hosted site into Hosting/Content/.

Run by CI as `cd Hosting && python3 build.py site --clean`.

A Hosting deploy replaces the WHOLE site atomically: files absent from the
staged directory are deleted from the live one. So this stages everything the
site serves — config.json included — and there is exactly one deploy. Adding a
second job that stages its own half deletes the first's.

{{ EDIT — add this app's content below stage_config(). An app that hosts only
config.json can ship this file as-is. Content-address any bundle filenames
(name-<sha8>.zip) and build deterministically, so unchanged content keeps its
hash and installs do not re-download it on every publish.

Also stage Hosting/Web/ — see stage_web() below. Those are the URLs the App
Store listing points at, and Apple rejects a listing whose privacy or
support page 404s. A Hosting deploy replaces the whole site atomically, so
staging them in a separate job would delete them on the next deploy that
doesn't. }}
"""
import argparse
import json
import shutil
import sys
from pathlib import Path

HOSTING_DIR = Path(__file__).resolve().parent.parent
CONTENT_DIR = HOSTING_DIR / "Content"
CONFIG_FILE = HOSTING_DIR / "config.json"
WEB_DIR = HOSTING_DIR / "Web"


def stage_web() -> bool:
    """Copy Hosting/Web/* into the staged site, flat — the listing addresses
    /privacy.html, not /Web/privacy.html."""
    if not WEB_DIR.is_dir():
        print(f"error: {WEB_DIR} does not exist — the site must ship its public pages")
        return False
    pages = sorted(p for p in WEB_DIR.iterdir() if p.is_file() and not p.name.startswith("."))
    if not pages:
        print(f"error: {WEB_DIR} is empty — the listing's privacy and support URLs would 404")
        return False
    CONTENT_DIR.mkdir(parents=True, exist_ok=True)
    for page in pages:
        shutil.copyfile(page, CONTENT_DIR / page.name)
    print(f"Staged {len(pages)} public page(s): {', '.join(p.name for p in pages)}")
    return True


def stage_config() -> bool:
    if not CONFIG_FILE.is_file():
        print(f"error: {CONFIG_FILE} does not exist — the site must ship a config")
        return False
    try:
        json.loads(CONFIG_FILE.read_text())
    except json.JSONDecodeError as exc:
        print(f"error: config.json is not valid JSON ({exc})")
        return False
    CONTENT_DIR.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(CONFIG_FILE, CONTENT_DIR / "config.json")
    print("Staged config.json")
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description="Stage the hosted site")
    parser.add_argument("--clean", action="store_true", help="remove Content/ first")
    # pr.yml's data-ci job passes --verbose. argparse exits 2 on an unknown
    # argument, so a step without it fails the check with "unrecognized
    # arguments" rather than anything about the data.
    parser.add_argument("--verbose", "-v", action="store_true", help="list every staged file")
    args = parser.parse_args()

    if args.clean and CONTENT_DIR.exists():
        shutil.rmtree(CONTENT_DIR)

    if not stage_config():
        return 1

    if not stage_web():
        return 1

    if args.verbose:
        for path in sorted(CONTENT_DIR.rglob("*")):
            if path.is_file():
                print(f"  {path.relative_to(CONTENT_DIR)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
