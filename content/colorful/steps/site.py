#!/usr/bin/env python3
"""Builds the hosted content directly into Hosting/ (this content folder).

Run by CI (`cd Hosting && python3 build.py --clean`) before the Hosting deploy.

WHY THIS BUILDS EVERYTHING, INCLUDING config.json VALIDATION
--------------------------------------------------------
This script produces the whole set of generated files in one run — packs and
manifest.json — directly into this content folder, committed straight to
GitHub. If you add a new kind of hosted file, add it here rather than a
second script that only covers part of it.

The app's public pages (privacy, terms, support) are no longer staged here;
they're owned by the website repo.

WHY EVERY PACK IS REQUIRED
--------------------------
Startup fetches the whole library before the first screen appears. All eleven
category packs together are ~300 KB, gzipped well under that on the wire, which
is one small download once rather than a wait every time a child opens a world
they have not opened before. After it, the app works offline — and a child
handed an iPad in a car is the normal case, not the edge case.

There used to be a separate `highlights` pack carrying the four preview pages of
every category, so home could draw its cards after one small download while full
categories were fetched on demand. Once startup fetches everything, that pack is
44 pages that already arrive in the category packs — 150 KB of the 453 KB total
spent downloading the same artwork twice. It is gone. Home still previews four
pages per category; which four is `catalog.json`'s business, and the pages
resolve out of the category packs by id.

Which packs are required is decided HERE, not in the app. When the library grows
past what is sensible to fetch up front, change the flags and old installs follow
without an app update.

WHY PACKS ARE JSON, NOT ZIP
---------------------------
iOS ships no public unzip API, and PES forbids remote SwiftPM packages, so a
zip pack would mean hand-writing a zip reader inside SYSKit. A JSON pack needs
none of that: Hosting gzips text responses on the wire, so the bytes over the
network match what a zip would cost, and SYSNetwork.get decodes it directly.

WHY BUNDLE NAMES CONTAIN A HASH
-------------------------------
Pack filenames are content-addressed (`seaworld-a1b2c3d4.json`). New artwork
means a new filename, so:
  - a client holding the old manifest keeps fetching the old URL, which still
    exists, and keeps working until it refreshes;
  - a client with the new manifest fetches a URL it has never cached, so no
    stale copy can be served to it;
  - the files can be cached ~forever instead of revalidated constantly.
That is what lets artwork be added without shipping an app update, and without
old installs breaking.

The zips are built deterministically (sorted entries, fixed timestamps), so an
unchanged category always hashes to the same name and is not re-uploaded.
"""
import argparse
import hashlib
import json
import os
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path

HOSTING = Path(__file__).resolve().parents[1]
REPO = HOSTING.parent
ARTWORK = HOSTING / "Artwork"
CATALOG = REPO / "App" / "Resources" / "catalog.json"
CONFIG = HOSTING / "config.json"

# Every world has exactly this many pages, and the app is built around it: the
# library lays out one screen of 4x2 tiles with nothing to scroll, and a child
# sees a whole world at once. Nine would wrap to a third row of one and the
# tiles would shrink to fit; seven would leave a hole.
#
# **Checked here because pages are now content.** The library takes its page
# list from the pack rather than from anything shipped, so a category staged
# with the wrong number does not fail a build — it reaches every install that
# is already out there. This is the last place it can be stopped.
#
# Used to read this from the app repo's Project.json (single source of truth
# with `Category.pagesPerWorld` on the Swift side). This script now lives in
# the content repo, not next to Project.json, so that's no longer reachable —
# still tried first for anyone running this from inside the app repo; falls
# back to the known value otherwise, loudly, so drift is visible rather than
# silent.
_PROJECT_JSON = REPO / "Project.json"
if _PROJECT_JSON.is_file():
    PAGES_PER_CATEGORY = json.loads(_PROJECT_JSON.read_text())["content"]["pagesPerCategory"]
else:
    PAGES_PER_CATEGORY = 8
    print(f"  warning: {_PROJECT_JSON} not found — using PAGES_PER_CATEGORY = {PAGES_PER_CATEGORY} "
          f"(confirm this still matches the app's Project.json)")
CONTENT = HOSTING
PACKS = CONTENT / "packs"

WORLDS = HOSTING / "worlds.json"

MANIFEST_VERSION = 1


def category_titles() -> dict[str, dict[str, str]]:
    """Display names per world, per language, from Hosting/worlds.json.

    These used to be copied from `catalog.json`, which meant the manifest
    carried the same English word the app already had in its bundle — a second
    copy of a fact, and no way to rename a world or fix a translation without
    shipping a build. They live here now, the app resolves them with
    `SYSLocale`, and `catalog.json`'s `name` is only the fallback.

    A world with no entry falls back to its id rather than failing the build:
    the deploy still has to be able to go out, and `validate.py localization`
    is what refuses to let one ship missing a language.
    """
    if not WORLDS.is_file():
        print(f"  warning: {WORLDS.name} is missing — packs will carry no titles")
        return {}
    try:
        return json.loads(WORLDS.read_text()).get("worlds", {})
    except json.JSONDecodeError as error:
        print(f"  warning: {WORLDS.name} is not valid JSON ({error}) — packs will carry no titles")
        return {}



def build_pack(category_id: str, category_dir: Path) -> tuple[bytes, list[str]]:
    """Return (pack bytes, sorted page ids) for one category.

    separators= and sort_keys= keep the encoding byte-identical run to run, so
    unchanged artwork keeps its hash and its filename.
    """
    svgs = sorted(p for p in category_dir.glob("*.svg") if p.is_file())
    if not svgs:
        return b"", []

    pack = {
        "id": category_id,
        "pages": [{"id": p.stem, "svg": p.read_text()} for p in svgs],
    }
    payload = json.dumps(pack, separators=(",", ":"), sort_keys=True).encode("utf-8")
    return payload, [p.stem for p in svgs]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--clean", action="store_true", help="remove generated packs/manifest first")
    # pr.yml's data-ci job runs this with --clean --verbose. argparse exits 2 on
    # an unknown argument, so omitting it fails the PR check with
    # "unrecognized arguments" rather than anything about the artwork.
    parser.add_argument("--verbose", action="store_true", help="list every page in every pack")
    args = parser.parse_args()

    if not ARTWORK.is_dir():
        print(f"error: {ARTWORK} does not exist")
        return 1
    if not CONFIG.is_file():
        print(f"error: {CONFIG} does not exist — the site must ship a config")
        return 1

    # CONTENT is the content folder itself now (no separate staging dir), so
    # --clean removes only what this script generates, never Artwork/ or config.
    if args.clean:
        if PACKS.exists():
            shutil.rmtree(PACKS)
        (CONTENT / "manifest.json").unlink(missing_ok=True)
    PACKS.mkdir(parents=True, exist_ok=True)

    titles = category_titles()
    items = []

    wrong_size = []

    for category_dir in sorted(p for p in ARTWORK.iterdir() if p.is_dir()):
        payload, names = build_pack(category_dir.name, category_dir)
        if not payload:
            print(f"  skipping {category_dir.name} — no .svg files")
            continue

        if len(names) != PAGES_PER_CATEGORY:
            wrong_size.append((category_dir.name, len(names)))

        digest = hashlib.sha256(payload).hexdigest()
        filename = f"{category_dir.name}-{digest[:8]}.json"
        (PACKS / filename).write_bytes(payload)

        items.append({
            "id": category_dir.name,
            "required": True,
            "title": titles.get(category_dir.name) or category_dir.name,
            "pageCount": len(names),
            "pages": names,
            "bundle": f"/packs/{filename}",
            "bytes": len(payload),
            "sha256": digest,
        })
        print(f"  {category_dir.name:18} {len(names):2} pages  {len(payload):>7,} B  {filename}  (required)")
        if args.verbose:
            for name in names:
                print(f"      {name}")

    if wrong_size:
        # Loud in CI, where this decides whether a deploy happens at all.
        annotate = "::error::" if os.environ.get("GITHUB_ACTIONS") else ""
        detail = ", ".join(f"{name} has {count}" for name, count in wrong_size)
        print()
        print(f"{annotate}every category must have exactly {PAGES_PER_CATEGORY} pages — {detail}")
        for name, count in wrong_size:
            short = PAGES_PER_CATEGORY - count
            need = f"{short} more needed" if short > 0 else f"{-short} too many"
            print(f"  {name:18} {count:2} pages  ({need})")
        print()
        print("The library draws one screen of 4x2 tiles per world.")
        print("Nothing was staged, so the deploy will not run and the live site")
        print("is left exactly as it is — nobody using the app is affected.")
        return 1

    if not items:
        print("error: no categories produced a bundle")
        return 1

    manifest = {
        "manifestVersion": MANIFEST_VERSION,
        "generatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "items": items,
    }
    (CONTENT / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")

    total = sum(i["bytes"] for i in items)
    print(f"\nStaged {len(items)} pack(s), {total:,} B total, plus manifest.json and config.json")
    print(f"Site root: {CONTENT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
