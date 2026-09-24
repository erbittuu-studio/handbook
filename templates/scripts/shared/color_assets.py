"""Every Color("…") in the app names a real colorset.

A missing colour asset is not a build error. `Color("Theme/Acccent")` compiles,
ships, and renders as nothing — so a typo here is invisible until someone looks
at the screen it broke. The compiler cannot help, which is why this exists.
"""
import json
import re
from pathlib import Path


def available(catalog: Path) -> set[str]:
    """Colorset names as Swift must spell them, honouring provides-namespace."""
    names = set()
    for colorset in catalog.rglob("*.colorset"):
        namespaces = []
        for parent in colorset.relative_to(catalog).parents:
            if parent == Path("."):
                continue
            contents = catalog / parent / "Contents.json"
            if not contents.exists():
                continue
            try:
                properties = json.loads(contents.read_text()).get("properties", {})
            except json.JSONDecodeError:
                continue
            if properties.get("provides-namespace"):
                namespaces.append(parent.name)
        prefix = "/".join(reversed(namespaces))
        names.add(f"{prefix}/{colorset.stem}" if prefix else colorset.stem)
    return names


def used(root: Path, source: Path) -> dict[str, str]:
    """Every Color("…") in the app, with the file it appears in."""
    found = {}
    for swift in source.rglob("*.swift"):
        for name in re.findall(r'Color\("([^"]+)"\)', swift.read_text()):
            found.setdefault(name, str(swift.relative_to(root)))
    return found


def check(ctx):
    catalog_dir = ctx.root / "App/Resources/Assets.xcassets"
    defined = available(catalog_dir)
    if not defined:
        return [f"no colorsets found under {catalog_dir} — is the catalog where this expects it?"]

    referenced = used(ctx.root, ctx.root / "App/Source")
    problems = [
        f'Color("{name}") in {where} has no colorset — this compiles, ships, and renders as nothing'
        for name, where in sorted(referenced.items())
        if name not in defined
    ]
    if not problems:
        print(f"  {len(referenced)} referenced, {len(defined)} defined")
    return problems
