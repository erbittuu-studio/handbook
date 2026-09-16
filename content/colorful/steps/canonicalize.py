#!/usr/bin/env python3
"""Rewrites every page into one consistent vocabulary, without changing the art.

Corel exports each drawing with its own private stylesheet. Nothing is wrong
with any single file, but across 88 of them the same idea is spelled a dozen
ways, and the app then has to cope with all of them:

  - `.fil1` means `fill:white` in 54 pages and `fill:none` in 27. Same name,
    opposite meaning.
  - stroke widths are float noise around integers — `5.99882`, `15.9992`,
    `3.99922` — 20 distinct values for what is really 10 weights.
  - four shapes are filled `#FEFEFE` instead of `white`. Invisible, but a second
    way of saying the same thing.
  - one page declares `fill-rule:nonzero`, which the app does not read at all.

After this every page uses:

    .fil0 {fill:white}     a region a child can colour
    .fil1 {fill:none}      line art
    .strN {stroke:black;stroke-width:N}   N is the integer weight

so a class name means the same thing in every file, and `.str6` says what it is.

WHAT THIS DELIBERATELY DOES NOT DO
----------------------------------
It does not make every stroke the same weight. 87% of strokes already render at
6.0, but the other 13% are the artist's choice — a heavy outer contour, a fine
whisker — and flattening them to one number would redraw 170 shapes. Weights are
rounded to integers (a change of at most 0.0012 units, which is nothing) and
otherwise left alone.

It does not touch geometry, transforms, ids or draw order.

SAFETY
------
A file is rewritten only if every one of its shapes resolves to the expected
vocabulary: fill of white/none, stroke black. Anything else and the file is
reported and left exactly as it was — a page that does not fit the rules is a
page to look at, not to rewrite blindly.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Artwork"

PAGE = 1024
GEOMETRY = ("path", "circle", "ellipse", "rect", "line", "polyline", "polygon")
# Attributes that carry shape, not style. Everything else is re-derived.
KEEP = ("d", "cx", "cy", "r", "rx", "ry", "x", "y", "width", "height",
        "x1", "y1", "x2", "y2", "points", "transform", "id")

WHITE = {"white", "#fefefe", "#ffffff", "#fff"}

# Corel writes `y2= "526"` — 600 attributes across the corpus have whitespace
# around the '='. A regex demanding `key="` silently drops those, which turned
# every net line on the football page into a ray from the origin.
ATTR = r'(?:^|\s)%s\s*=\s*"([^"]*)"' 


class Unexpected(Exception):
    """The file uses something outside the vocabulary, so leave it alone."""


def stylesheet(text: str) -> dict[str, dict[str, str]]:
    block = re.search(r"<style.*?</style>", text, re.S)
    if not block:
        return {}
    rules: dict[str, dict[str, str]] = {}
    for name, body in re.findall(r"\.([\w-]+)\s*\{([^}]*)\}", block.group(0)):
        declarations = {}
        for part in body.split(";"):
            if ":" in part:
                key, value = part.split(":", 1)
                declarations[key.strip().lower()] = value.strip()
        rules[name] = declarations
    return rules


def resolve(attrs: str, rules: dict[str, dict[str, str]]) -> dict[str, str]:
    """Final fill / stroke / stroke-width for one element: classes, then inline."""
    style: dict[str, str] = {}
    classes = re.search(ATTR % "class", attrs)
    for name in (classes.group(1).split() if classes else []):
        style.update(rules.get(name, {}))
    for key in ("fill", "stroke", "stroke-width"):
        inline = re.search(ATTR % key, attrs)
        if inline:
            style[key] = inline.group(1).strip()
    return style


def weight(value: str) -> int:
    """Corel's float noise, as the integer it is really trying to be."""
    number = float(value)
    rounded = round(number)
    if abs(number - rounded) > 0.01 or rounded < 1:
        raise Unexpected(f"stroke-width {value} is not a clean weight")
    return rounded


def rebuild(text: str) -> tuple[str, set[int]]:
    rules = stylesheet(text)
    widths: set[int] = set()

    def one(match: re.Match[str]) -> str:
        element, attrs = match.group(1), match.group(2)
        style = resolve(attrs, rules)

        fill = style.get("fill", "").strip().lower()
        if fill in WHITE:
            classes = ["fil0"]
        elif fill in ("none", ""):
            classes = ["fil1"]
        else:
            raise Unexpected(f"<{element}> fill:{fill}")

        stroke = style.get("stroke", "").strip().lower()
        if stroke and stroke != "none":
            if stroke != "black" and stroke != "#000000":
                raise Unexpected(f"<{element}> stroke:{stroke}")
            width = weight(style.get("stroke-width", "0"))
            widths.add(width)
            classes.append(f"str{width}")

        kept = []
        for key in KEEP:
            found = re.search(ATTR % key, attrs)
            if found:
                kept.append(f'{key}="{found.group(1).strip()}"')
        return f'<{element} class="{" ".join(classes)}" {" ".join(kept)}/>'

    body = re.sub(r"<(%s)((?:\s[^>]*)?)/>" % "|".join(GEOMETRY), one, text)

    declarations = ['.fil0 {fill:white}', '.fil1 {fill:none}']
    declarations += [f'.str{w} {{stroke:black;stroke-width:{w}}}' for w in sorted(widths)]
    css = "\n".join(f"    {d}" for d in declarations)
    body = re.sub(r"(<!\[CDATA\[)(.*?)(\]\]>)", lambda m: f"{m.group(1)}\n{css}\n   {m.group(3)}",
                  body, flags=re.S)
    return body, widths


def backdrop(text: str) -> str:
    """Exactly one full-page backdrop, first, so it sits under everything."""
    rect = f'<rect class="fil0" width="{PAGE}" height="{PAGE}"/>'

    def drop(match: re.Match[str]) -> str:
        attrs = match.group(1)

        def number(key: str) -> float:
            found = re.search(ATTR % key, attrs)
            try:
                return float(found.group(1)) if found else 0.0
            except ValueError:
                return 0.0

        classes = re.search(ATTR % "class", attrs)
        names = classes.group(1).split() if classes else []
        covers_page = number("width") >= 1000 and number("height") >= 1000
        # `fil1` is fill:none — a decorative full-page frame the artist drew, and
        # line art rather than a backdrop. Only a painted one is replaced.
        paints = "fil0" in names
        return "" if covers_page and paints else match.group(0)

    stripped = re.sub(r"<rect([^>]*)/>", drop, text)
    stripped = re.sub(r"\n[ \t]*\n", "\n", stripped)

    anchor = re.search(r"<metadata[^>]*/>", stripped) or re.search(r"</defs>", stripped)
    if not anchor:
        raise Unexpected("no <metadata> or </defs> to anchor the backdrop to")
    return stripped[:anchor.end()] + "\n  " + rect + stripped[anchor.end():]


def main() -> int:
    pages = sorted(SOURCE.rglob("*.svg"))
    rewritten, skipped = 0, []

    for page in pages:
        text = page.read_text()
        try:
            body, _ = rebuild(text)
            body = backdrop(body)
        except Unexpected as problem:
            skipped.append(f"{page.parent.name}/{page.name}: {problem}")
            continue
        if body != text:
            page.write_text(body)
            rewritten += 1

    for note in skipped:
        print(f"  SKIPPED {note}")
    print(f"\n{rewritten} of {len(pages)} page(s) canonicalised, {len(skipped)} skipped.")
    return 1 if skipped else 0


if __name__ == "__main__":
    sys.exit(main())
