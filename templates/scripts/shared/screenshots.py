"""Store screenshots are present, valid, and exactly the size Apple requires.

The PRIMARY locale — `store.locales[0]` in Project.json — must carry the full
set: exactly the required screenshots per device size, at exact pixel
dimensions, no corrupt or zero-byte files, and no unexpected extras.

**Only the primary one must.** The listing is localized into two dozen locales
for search coverage, and App Store Connect shows the primary locale's
screenshots on any localization that has none of its own. Requiring a folder
per locale would mean the same six PNGs committed twenty-four times, and would
make adding a locale — the cheapest ASO move there is — cost 30 MB of git.

A locale that DOES ship its own folder is still held to the full set, because a
half-filled folder is the one case Apple will not paper over: deliver uploads
what it finds, and a localization with two screenshots shows two.

Folders outside the store-locale list are skipped, so the app can carry more
languages than the store listing does.
"""
import struct
from pathlib import Path

# The required set comes from Project.json, not from here. It is the one part of
# the store rules that genuinely differs per app.
#
# A landscape-only app transposes Apple's portrait dimensions — a 6.9" iPhone
# shot is 2868x1320, not 1320x2868 — and uploading a portrait-shaped image for a
# landscape app is accepted by deliver and then looks wrong on the product page,
# which is exactly the kind of thing this check exists for. A portrait app
# states the numbers the other way round and this file does not change.


def required_files(ctx) -> dict:
    """`{filename: (width, height)}` for every screenshot the store needs."""
    required = {}
    for prefix, spec in ctx.get("screenshots.required").items():
        for index in range(1, int(spec["count"]) + 1):
            required[f"{prefix}-{index:02d}.png"] = (int(spec["width"]), int(spec["height"]))
    if not required:
        raise ValueError("Project.json screenshots.required is empty")
    return required


def png_dimensions(path: Path) -> tuple[int, int]:
    with path.open("rb") as f:
        header = f.read(33)
    if header[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG file")
    width, height = struct.unpack(">II", header[16:24])
    return width, height


def check(ctx):
    REQUIRED = required_files(ctx)
    all_locales = ctx.get("store.locales")
    locales = set(all_locales)
    primary = all_locales[0]
    folder = ctx.root / "fastlane" / "screenshots"
    if not folder.is_dir():
        return [f"{folder} does not exist"]

    errors: list[str] = []
    checked = 0

    # The one folder that is not optional. Checked by name rather than by
    # walking what happens to be on disk: a missing primary folder is exactly
    # the failure a walk cannot see.
    if not (folder / primary).is_dir():
        errors.append(
            f"{primary}/ does not exist — it is the primary store locale, so its "
            f"screenshots are the ones every other localization falls back to"
        )

    for locale_dir in sorted(p for p in folder.iterdir() if p.is_dir()):
        locale = locale_dir.name
        if locale not in locales:
            print(f"  skipping {locale}/ — not a store locale")
            continue
        checked += 1

        for filename, expected_size in REQUIRED.items():
            path = locale_dir / filename
            if not path.is_file():
                errors.append(f"{locale}: missing {filename}")
                continue
            if path.stat().st_size == 0:
                errors.append(f"{locale}: {filename} is zero bytes")
                continue
            try:
                actual_size = png_dimensions(path)
            except (ValueError, struct.error) as e:
                errors.append(f"{locale}: {filename} is not a valid PNG ({e})")
                continue
            if actual_size != expected_size:
                errors.append(
                    f"{locale}: {filename} is {actual_size[0]}x{actual_size[1]}, "
                    f"App Store requires exactly {expected_size[0]}x{expected_size[1]}"
                )

        extra = {p.name for p in locale_dir.glob("*.png")} - set(REQUIRED)
        if extra:
            errors.append(f"{locale}: unexpected file(s) not part of the required set: {', '.join(sorted(extra))}")

    # A run that checked nothing is not a pass. Without this, deleting the
    # primary folder — or renaming a locale in Project.json — turns this check
    # green while the store listing has no screenshots at all.
    if not checked:
        errors.append(
            f"no screenshot folder matched a store locale ({', '.join(sorted(locales))}) — "
            f"checked nothing, which is not the same as passing"
        )
    elif not errors:
        others = checked - 1
        note = f" (+{others} with their own)" if others > 0 else ""
        print(
            f"  {primary} carries the full set of {len(REQUIRED)}{note}; "
            f"{len(locales) - checked} locale(s) fall back to it"
        )
    return errors
