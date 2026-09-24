#!/usr/bin/env python3
"""Turns RawPacks/ into the publishable site: content/manifest.json +
content/packs/*.zip. Committing the result to `main` is the deploy — no
separate staging step.

Run by CI (`cd Hosting && python3 build.py publish --clean`) and by the
pre-push hook, so a RawPacks/ change can't reach `main` unrebuilt.

- This is the "content" manifest — config.json's `manifests` list names it.
  Everything it owns lives under `content/`, the same rule as any other
  manifest an app has (see Prarthana's `content/` + `festivals/`).
- Every pack is `required: true` — the whole library is small (~130 KB), so
  startup fetches it all up front instead of per category.
- Each pack's title lives in its own `RawPacks/<id>/index.json`, not a
  separate list — nothing to fall out of sync with the folders.
- Packs are zip, named by content hash alone (`1b8bc9fc.zip`). The app reads
  `bundle` from the manifest, never the filename, so the id doesn't need to
  be in it too. A changed pack gets a new hash, so old installs keep the old
  URL until they refresh and new installs never see a stale one.
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
import os
import shutil
import sys
import zipfile
from datetime import datetime, timezone
from pathlib import Path

HOSTING = Path(__file__).resolve().parents[1]
RAW_PACKS = HOSTING / "RawPacks"
CONFIG = HOSTING / "config.json"

sys.path.insert(0, str(HOSTING))
import crypto  # noqa: E402

APP_STORE_ID = HOSTING.name

# Fixed timestamp so identical content produces an identical zip — otherwise
# every checkout's mtime would change the hash even when nothing did.
# 1980-01-01 is the earliest a ZIP can express.
ZIP_EPOCH = (1980, 1, 1, 0, 0, 0)

# The library's grid is fixed at 4x2, so every world needs exactly this many pages.
PAGES_PER_CATEGORY = 8

# Everything this manifest owns lives under its own named folder — the same
# rule for every manifest an app has, whether it has one (this one) or several
# (Prarthana's content/ and festivals/). config.json's "manifests" list names
# them; each is exactly "<name>/manifest.json" + "<name>/packs/".
CONTENT = HOSTING / "content"
PACKS = CONTENT / "packs"

MANIFEST_VERSION = 1


def pack_meta(category_id: str, category_dir: Path) -> dict:
    """This pack's own index.json — title and test flag. Missing or invalid
    isn't an error (the build still has to go out), just a loud warning."""
    meta_path = category_dir / "index.json"
    if not meta_path.is_file():
        print(f"  warning: {category_id} has no index.json — it will ship titled \"{category_id}\"")
        return {}
    try:
        meta = json.loads(meta_path.read_text())
    except json.JSONDecodeError as error:
        print(f"  warning: {category_id}/index.json is not valid JSON ({error}) — "
              f"it will ship titled \"{category_id}\"")
        return {}
    if not meta.get("title"):
        print(f"  warning: {category_id}/index.json has no \"title\" — it will ship titled \"{category_id}\"")
    return meta


def _add(zf: zipfile.ZipFile, arcname: str, data: bytes) -> None:
    """Write one entry with a fixed timestamp and fixed permissions."""
    info = zipfile.ZipInfo(arcname, date_time=ZIP_EPOCH)
    info.compress_type = zipfile.ZIP_DEFLATED
    info.external_attr = 0o644 << 16
    zf.writestr(info, data)


def build_pack(category_dir: Path) -> tuple[bytes, list[str]]:
    """Zips one world's SVGs, nothing else — page order is just the sorted
    filenames. Returns (zip bytes, sorted page ids)."""
    svgs = sorted(p for p in category_dir.glob("*.svg") if p.is_file())
    if not svgs:
        return b"", []

    names = [p.stem for p in svgs]
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as zf:
        for svg_path in svgs:
            _add(zf, svg_path.name, svg_path.read_bytes())
    return buffer.getvalue(), names


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--clean", action="store_true", help="remove generated packs/manifest first")
    parser.add_argument("--verbose", action="store_true", help="list every page in every pack")
    parser.add_argument("--keep-source", action="store_true",
                         help="don't delete RawPacks/ after a successful build")
    args = parser.parse_args()

    if not RAW_PACKS.is_dir():
        print(f"error: {RAW_PACKS} does not exist")
        return 1
    if not CONFIG.is_file():
        print(f"error: {CONFIG} does not exist — the site must ship a config")
        return 1

    # --clean removes only content/ (everything this manifest generates),
    # never RawPacks/ or config.json.
    if args.clean:
        if PACKS.exists():
            shutil.rmtree(PACKS)
        (CONTENT / "manifest.json").unlink(missing_ok=True)
    PACKS.mkdir(parents=True, exist_ok=True)

    items = []
    wrong_size = []

    for category_dir in sorted(p for p in RAW_PACKS.iterdir() if p.is_dir()):
        payload, names = build_pack(category_dir)
        if not payload:
            print(f"  skipping {category_dir.name} — no .svg files")
            continue

        meta = pack_meta(category_dir.name, category_dir)
        is_test = meta.get("test") is True

        # A test world's page count is its own business, not the check every
        # real world answers to — it never reaches a real install either way.
        if not is_test and len(names) != PAGES_PER_CATEGORY:
            wrong_size.append((category_dir.name, len(names)))

        encrypted = crypto.encrypt(payload, APP_STORE_ID)
        digest = hashlib.sha256(encrypted).hexdigest()
        filename = f"{digest[:12]}.zip"
        (PACKS / filename).write_bytes(encrypted)

        item = {
            "id": category_dir.name,
            "required": True,
            "title": meta.get("title") or category_dir.name,
            "pageCount": len(names),
            "bundle": f"/packs/{filename}",
            "bytes": len(encrypted),
            "sha256": digest,
        }
        if is_test:
            item["test"] = True
        items.append(item)
        tag = "test" if is_test else "required"
        print(f"  {category_dir.name:18} {len(names):2} pages  {len(payload):>7,} B  {filename}  ({tag})")
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
        # One group, all worlds in it — no real category tier here, but every
        # app's manifest carries `groups` the same way. A reader can treat
        # "just one group" as "skip the category screen" without special-casing
        # this app.
        "groups": [
            {
                "id": "1",
                "name": {"en": "Worlds"},
                "order": [item["id"] for item in items],
            }
        ],
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
