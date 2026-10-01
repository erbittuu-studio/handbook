"""Analytics events stay inside Firebase's limits.

Firebase silently DROPS events and params that violate its own limits instead
of erroring — this catches that class of bug at PR time instead of losing data
in production. Checks:
  - custom event names: <=40 chars, no reserved prefix (firebase_/google_/ga_)
  - custom param keys:  <=40 chars, no reserved prefix
  - <=25 params per event (Firebase's hard limit)

Regex-based on purpose-written source, not a general Swift parser — this only
needs to stay correct for AnalyticsManager.swift's own structure (one `name`
switch, one `parameters` switch, both on AnalyticsEvent).
"""
import re

RESERVED_PREFIXES = ("firebase_", "google_", "ga_")
MAX_NAME_LENGTH = 40
MAX_PARAMS_PER_EVENT = 25


def check_identifier(kind: str, name: str, errors: list[str]) -> None:
    if len(name) > MAX_NAME_LENGTH:
        errors.append(f"{kind} '{name}' is {len(name)} chars, over Firebase's {MAX_NAME_LENGTH}-char limit")
    if name.lower().startswith(RESERVED_PREFIXES):
        errors.append(f"{kind} '{name}' uses a reserved prefix ({'/'.join(RESERVED_PREFIXES)}) — Firebase drops these")


def brace_section(text: str, start_marker: str) -> str:
    start = text.index(start_marker) + len(start_marker)
    depth = 1
    i = start
    while depth > 0:
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
        i += 1
    return text[start:i - 1]



def check(ctx):
    source = ctx.root / "App/Source/Shared/AnalyticsManager.swift"
    if not source.is_file():
        return [f"{source} does not exist"]

    text = source.read_text()
    errors: list[str] = []

    name_section = brace_section(text, "var name: String {")
    for match in re.finditer(r'return "([a-zA-Z0-9_]+)"', name_section):
        check_identifier("event name", match.group(1), errors)

    params_section = brace_section(text, "var parameters: [String: Any] {")

    # `case let .x(y)` is the trap this check used to fall into. Cases are
    # found by splitting on "case .", so the `case let` spelling parsed as no
    # case at all — the validator reported success having checked nothing.
    # It is now an error rather than a comment in CLAUDE.md, because a rule
    # that only exists in prose is one the next person breaks.
    for stray in re.findall(r"\n\s*case\s+let\s+\.(\w+)", params_section):
        errors.append(
            f".{stray} is written `case let .{stray}(…)`, which this check cannot see — "
            f"write it `case .{stray}(let …)` so its params are actually validated"
        )

    cases = re.split(r"\n\s*case \.", params_section)[1:]  # drop preamble before first case

    for case_block in cases:
        case_name = re.split(r"[(:]", case_block, maxsplit=1)[0].strip()

        # Dict-literal keys: ["item_id": value, ...]
        literal_keys = re.findall(r'"([a-zA-Z0-9_]+)":', case_block)
        # Bracket-assignment keys: params["category_id"] = value
        assigned_keys = re.findall(r'\[\s*"([a-zA-Z0-9_]+)"\s*\]\s*=', case_block)
        # Firebase's own predefined constants used as keys — already compliant, just counted
        constant_keys = re.findall(r"\b(AnalyticsParameter\w+)\s*:", case_block)

        for key in set(literal_keys) - set(assigned_keys):
            check_identifier(f"param in .{case_name}", key, errors)
        for key in assigned_keys:
            check_identifier(f"param in .{case_name}", key, errors)

        total_params = len(set(literal_keys) | set(assigned_keys)) + len(constant_keys)
        if total_params > MAX_PARAMS_PER_EVENT:
            errors.append(f".{case_name} has {total_params} params, over Firebase's {MAX_PARAMS_PER_EVENT}-param limit")

    if not errors:
        print(f"  {len(cases)} event case(s) within Firebase's limits")
    return errors
