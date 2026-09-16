#!/usr/bin/env python3
"""Generates Resources/catalog.json from the SVG source tree.

Category names and highlight picks come from the legacy Category.plist so the
app keeps the ordering and cover art the original shipped with; everything else
is derived from the folders, so dropping a new page into Hosting/Artwork/<slug> is
all it takes to add content.

Reads Hosting/Artwork rather than the old rasterized tree: no PNGs ship any more.
The pages are served as SVG (see build.py), and catalog.json carries only the
presentation the app needs before any pack downloads — names, symbols, tints
and which four pages a category previews.
"""
import json, plistlib, pathlib, subprocess, sys

ROOT = pathlib.Path(__file__).resolve().parents[1].parent
SOURCE = ROOT / "Hosting/Artwork"
OUT = ROOT / "App/Resources/catalog.json"
LEGACY_PLIST = sys.argv[1] if len(sys.argv) > 1 else None

# Ordering and the four preview pages per category come from the legacy plist and
# cannot be derived from the folders. Without it this script still produces a
# valid catalog.json — alphabetical, previewing pages 0-3 — which silently
# replaces the curation the app actually ships. Refusing is better than a diff
# that looks like a reformat.
if LEGACY_PLIST is None and OUT.exists():
    sys.exit(
        f"error: {OUT.name} already exists and no Category.plist was given.\n"
        "       Regenerating without it would reorder the categories and reset\n"
        "       every highlight to the first four pages.\n"
        "       Pass the legacy plist, or delete catalog.json to accept defaults."
    )

# Per-category presentation, hand-picked for the new UI.
STYLE = {
    "climate_weather": ("Weather",        "cloud.sun.fill",     "#3FA9F5", "#8ED8FF"),
    "baby":            ("Baby",           "heart.fill",         "#FF6F91", "#FFB3C6"),
    "space":           ("Space",          "moon.stars.fill",    "#6C4BF6", "#B9A4FF"),
    "food":            ("Food",           "cup.and.saucer.fill","#FF8A3D", "#FFC48A"),
    "school":          ("School",         "book.fill",          "#3D6BE5", "#9DB6FF"),
    "seaworld":        ("Sea World",      "tortoise.fill",      "#00B2A9", "#7BE0D8"),
    "home":            ("Home",           "house.fill",         "#3FB950", "#9BE8A6"),
    "toys":            ("Toys",           "gamecontroller.fill","#F0459B", "#FFA3CE"),
    "vehicles":        ("Vehicles",       "car.fill",           "#F2542D", "#FFA48D"),
    "bugs":            ("Bugs",           "ant.fill",           "#7CB518", "#C6E86F"),
    "sports":          ("Sports",         "sportscourt.fill",   "#F5A623", "#FFD98A"),
}

legacy = {}
order = []
if LEGACY_PLIST:
    with open(LEGACY_PLIST, "rb") as f:
        for entry in plistlib.load(f):
            legacy[entry["cat_id"]] = entry
            order.append(entry["cat_id"])

slugs = sorted(p.name for p in SOURCE.iterdir() if p.is_dir())
ordered = [s for s in order if s in slugs] + [s for s in slugs if s not in order]

categories = []
for slug in ordered:
    pages = sorted(
        (p.stem for p in (SOURCE / slug).glob("*.svg")),
        key=lambda n: (len(n), n),           # page_2 before page_10
    )
    entry = legacy.get(slug, {})
    highlights = [
        entry["preview_images"][k] for k in sorted(entry.get("preview_images", {}))
    ] or pages[:4]
    highlights = [h for h in highlights if h in pages][:4]

    name, symbol, tint, accent = STYLE.get(
        slug, (slug.replace("_", " ").title(), "sparkles", "#3FA9F5", "#8ED8FF")
    )
    categories.append({
        "id": slug,
        "name": name,
        "symbol": symbol,
        "tint": tint,
        "accent": accent,
        "highlights": highlights,
        "pages": [{"id": p, "title": f"Page {i + 1}"} for i, p in enumerate(pages)],
    })

OUT.write_text(json.dumps({"version": 1, "categories": categories}, indent=2) + "\n")
print(f"catalog.json: {len(categories)} categories, {sum(len(c['pages']) for c in categories)} pages")
