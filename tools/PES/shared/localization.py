"""Every string the app ships is translated into every language that can load it.

A string catalog fails open: a key with no entry for a language, or one still
marked `state: "new"`, falls back to the source language — so a
half-translated app builds clean and ships English to a device that asked for
something else, with no warning anywhere.

THREE SETS, NOT ONE LIST
------------------------
`languages` used to be a single list, which can only describe an app where the
interface is localized and iOS picks the language for every string. RealAIApp
doesn't work that way: the user picks a language *inside* the app, so
`AppLanguage.localized()` resolves through
`Bundle.main.path(forResource:ofType:"lproj")` — Hindi and Gujarati have to
exist as real bundle localizations even though the interface itself is
English-only and only the notification strings are translated. One list can't
express that: declaring all three interface languages demands translations
nobody intends to write, and declaring English-only reports the real
translations as dead.

    "languages": {
      "source": "en",
      "interface": ["en"],
      "selectable": {
        "mode": "in-app",
        "list": ["en", "hi", "gu"],
        "keys": ["notification*", "festivalWhen*", "festivalAdvanceBody"]
      }
    }

  - `source` — what the strings are written in. The catalog must agree.
  - `interface` — localizations iOS may pick on its own. Held to the old bar:
    every key, every language, no exceptions.
  - `selectable` — languages the app can load deliberately. Must exist in
    `knownRegions`, or there's no `.lproj` and `Bundle.main.path` returns nil
    at runtime with no error. (This is the bug the set was added for:
    RealAIApp shipped Hindi text for months while `knownRegions` said only
    `en, Base`, and it silently served English.)
  - `selectable.keys` — the keys that go through the app's own lookup. Must be
    complete in every selectable language. **Required** — without it
    "selectable" would demand nothing, which reads as coverage and isn't.

`mode` records how the choice is made (`in-app` or `system`) — documentation,
not a rule.

THE OLD SHAPE STILL WORKS
-------------------------
`"languages": ["en", "es"]` reads as source `en`, interface `["en", "es"]`, no
selectable set — apps migrate one at a time.

WHAT IS NOT COVERED
-------------------
Every `.xcstrings` under `App/` is checked, discovered rather than listed,
including `InfoPlist.xcstrings` (home-screen name, permission sentences).
Anything localized outside the string catalogs — content the app serves, a
name stored as data — needs its own check in `scripts/checks/`.
"""
import fnmatch
import json
import re


def catalogs(root):
    """Every string catalog the app ships, found rather than named.

    Vendored packages are skipped — their catalogs aren't this app's to fill in.
    """
    return sorted(
        p for p in (root / "App").rglob("*.xcstrings")
        if "Packages" not in p.parts
    )


class Languages:
    """The three sets, however Project.json spelled them."""

    def __init__(self, source, interface, selectable, selectable_keys, mode):
        self.source = source
        self.interface = interface
        self.selectable = selectable
        self.selectable_keys = selectable_keys
        self.mode = mode

    @property
    def loadable(self):
        """Everything that must exist as a real localization."""
        return set(self.interface) | set(self.selectable)


def parse(value):
    """Read either shape. Returns (Languages, problems)."""
    if isinstance(value, list):
        if not value:
            return None, ["Project.json languages is empty — nothing to hold anything to"]
        return Languages(value[0], list(value), [], [], "system"), []

    if not isinstance(value, dict):
        return None, [f"Project.json languages must be a list or an object, not {type(value).__name__}"]

    problems = []
    source = value.get("source")
    if not source:
        problems.append("languages.source is missing — say what the strings are written in")

    interface = value.get("interface")
    if not isinstance(interface, list) or not interface:
        problems.append("languages.interface must be a non-empty list")
        interface = []

    selectable, keys, mode = [], [], "system"
    block = value.get("selectable")
    if block is not None:
        if not isinstance(block, dict):
            problems.append("languages.selectable must be an object")
        else:
            mode = block.get("mode", "system")
            selectable = block.get("list") or []
            if not isinstance(selectable, list) or not selectable:
                problems.append("languages.selectable.list must be a non-empty list")
                selectable = []
            keys = block.get("keys")
            if not isinstance(keys, list) or not keys:
                problems.append(
                    "languages.selectable.keys is required — without it this rule "
                    "demands nothing, which reads as coverage and is not"
                )
                keys = []

    if source and source not in interface:
        problems.append(
            f"languages.source {source!r} is not in languages.interface — the source "
            f"language is always shipped"
        )

    return Languages(source, interface, selectable, keys, mode), problems


def untranslated(catalog, languages, keys=None):
    """(key, language) pairs that would fall back to the source language.

    `keys` narrows it to matching patterns, for a set that is deliberately not
    translated in full.
    """
    source = catalog.get("sourceLanguage", "en")
    gaps = []
    for key, entry in sorted(catalog.get("strings", {}).items()):
        if keys is not None and not any(fnmatch.fnmatch(key, p) for p in keys):
            continue
        localizations = entry.get("localizations", {})
        for language in languages:
            if language == source:
                continue
            unit = localizations.get(language, {}).get("stringUnit", {})
            state, value = unit.get("state"), unit.get("value")
            if not value:
                gaps.append(f"{key!r} has nothing for {language}")
            elif state == "new":
                gaps.append(f"{key!r} is still marked new in {language} — extracted, not translated")
    return gaps


def known_regions(text: str):
    """The languages the Xcode project admits to having, or None if it says nothing."""
    block = re.search(r"knownRegions = \(\s*(.*?)\s*\);", text, re.S)
    if not block:
        return None
    return [r.strip().strip('",') for r in block.group(1).split("\n") if r.strip()]


def check(ctx):
    raw = ctx.get("languages")
    if not raw:
        return ["Project.json states no languages — this check has nothing to hold anything to"]

    langs, problems = parse(raw)
    if langs is None or problems:
        return problems

    counted = 0
    found = catalogs(ctx.root)
    if not found:
        # A screen written entirely in Swift string literals has no catalog to
        # check — fine, as long as nothing beyond the source language is claimed.
        if len(langs.interface) <= 1 and not langs.selectable:
            print("  no .xcstrings under App/ — none declared, none to check")
            return []
        return [
            "no .xcstrings under App/, but languages declares more than the "
            "source language — nothing proves those translations exist"
        ]

    for path in found:
        relative = path.relative_to(ctx.root)
        catalog = json.loads(path.read_text())
        strings = catalog.get("strings", {})
        if not strings:
            problems.append(f"{relative} has no strings in it — nothing was checked")
            continue
        counted += len(strings)

        source = catalog.get("sourceLanguage", "en")
        if source != langs.source:
            problems.append(
                f"{relative} is written in {source!r} but Project.json says the source "
                f"language is {langs.source!r}"
            )

        # A language in the catalog that nothing can load is translated, paid
        # for, and never read.
        for key, entry in sorted(strings.items()):
            for extra in sorted(set(entry.get("localizations", {})) - langs.loadable):
                problems.append(
                    f"{relative}: {key!r} is translated into {extra}, which is in neither "
                    f"languages.interface nor languages.selectable — it will never be loaded"
                )

        problems += [f"{relative}: {gap}" for gap in untranslated(catalog, langs.interface)]

        extra_selectable = [lang for lang in langs.selectable if lang not in langs.interface]
        if extra_selectable and langs.selectable_keys:
            problems += [
                f"{relative}: {gap} (a languages.selectable.keys string)"
                for gap in untranslated(catalog, extra_selectable, langs.selectable_keys)
            ]

    # knownRegions is Xcode's own copy of the same fact — a missing region
    # builds no .lproj, and the app's lookup silently returns the source
    # language forever.
    pbxproj = ctx.root / ctx.get("app.project") / "project.pbxproj"
    if not pbxproj.is_file():
        problems.append(f"{pbxproj} does not exist")
    else:
        regions = known_regions(pbxproj.read_text())
        if regions is None:
            problems.append(f"{pbxproj} has no knownRegions block — this check proved nothing")
        else:
            declared = set(regions) - {"Base"}
            for missing in sorted(langs.loadable - declared):
                problems.append(
                    f"knownRegions is missing {missing!r} — no {missing}.lproj is built, so "
                    f"Bundle.main.path(forResource:ofType:) returns nil and every lookup "
                    f"falls back to {langs.source!r} with nothing in the log"
                )
            for stray in sorted(declared - langs.loadable):
                problems.append(
                    f"knownRegions has {stray!r}, which Project.json does not ship"
                )

    if not problems:
        summary = f"  {counted} strings x {len(langs.interface)} interface language(s)"
        if langs.selectable:
            summary += (
                f", {len(langs.selectable)} selectable ({langs.mode})"
                f" across {len(langs.selectable_keys)} key pattern(s)"
            )
        print(summary + ", and knownRegions agrees")
    return problems
