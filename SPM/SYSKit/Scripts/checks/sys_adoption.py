"""The app uses SYSKit instead of quietly re-implementing it.

SYSKit exists so five apps behave the same way and one fix reaches all of them.
That only holds while apps actually use it. Nothing stops someone reaching for
`UserDefaults.standard` or `URLSession` directly — it works, it is one line, and
the app quietly stops sharing the behaviour everything else depends on. By the
time that matters, the divergence is old and expensive.

So each rule below names something SYSKit already does, and fails the build when
app code does it another way. This is not style: every rule maps to a defect that
has already happened, or to behaviour other apps rely on being identical.

`sys-ok: <reason>` opts out where an app genuinely has to be different. Put it
on the line itself or anywhere in the comment block directly above it — a
justification worth reading rarely fits on the end of a line, and one squeezed
until it does is not a justification. The reason is required: an opt-out nobody
has to explain is a rule that quietly stops applying.

Only `App/Source/` is scanned. Vendored packages, tests and generated code are
not app code.
"""
import re
from pathlib import Path

# (pattern, what to use instead, why it matters)
RULES: list[tuple[str, str, str]] = [
    (
        r"\bUserDefaults\s*\.\s*standard\b",
        "@SYSStored or SYSSettings",
        "reading defaults directly loses the typed key and the "
        "absent-vs-false distinction that keeps upgrades from resetting settings",
    ),
    (
        r"\bURLSession\s*\.\s*shared\b",
        "SYSNetwork",
        "SYSNetwork carries the ETag handling, retry policy and offline "
        "detection every app's config and content fetching depends on",
    ),
    (
        r"\bSKStoreReviewController\b",
        "SYSReview",
        "asking without recording spends all three of Apple's yearly review "
        "requests on one user",
    ),
    (
        r"https://[a-z0-9-]+\.web\.app",
        "SYSHosting",
        "the hosting URL is derived from PROJECT_ID; hardcoding it is how a "
        "release ends up pointing at another project's content",
    ),
    (
        r"\bAnalytics\s*\.\s*logEvent\b",
        "SYSAnalytics with an AnalyticsEvent case",
        "events sent outside the enum skip the CI limit checks, and Firebase "
        "drops what breaks its limits without erroring",
    ),
    (
        r"\bCrashlytics\s*\.\s*crashlytics\(\)",
        "SYSLogger",
        "reporting through SYSLogger keeps non-fatals consistent and keeps "
        "Firebase out of app code",
    ),
    (
        r"\bUI(Impact|Selection|Notification)FeedbackGenerator\b",
        "SYSHaptics",
        "a generator built per call is deallocated before it can be prepared, "
        "so the Taptic Engine is cold — the first tap lags and quick repeats "
        "are dropped; SYSHaptics keeps one per style and re-prepares it",
    ),
    (
        r"\bUIActivityViewController\b",
        "SYSShare",
        "presenting from connectedScenes.first reaches a scene the user is not "
        "looking at, and a popover with no sourceView raises on iPad rather "
        "than degrading — SYSShare handles both",
    ),
    (
        r"(?<!\.)(?<!func )\bprint\s*\(",
        "SYSLogger",
        "print output never reaches a device log or Crashlytics once shipped — "
        "SYSLogger.error keeps failures visible in production and "
        "debug/info/warning still print in DEBUG",
    ),
    (
        r"\bUIApplicationShortcutItem\s*\(",
        "SYSQuickActions",
        "building a shortcut item outside registration also skips the "
        "pending-intent queue, so a tap landing before the UI is ready is "
        "dropped instead of delivered once it is",
    ),
    (
        r"\bCSSearchableIndex\b|\bCSSearchableItem\s*\(",
        "SYSSpotlight",
        "indexing directly skips the shared stale-id sync and the one "
        "identifier scheme every app's Spotlight tap handler now parses — "
        "a hand-rolled identifier breaks that handler silently, not loudly",
    ),
    (
        r"\bUNUserNotificationCenter\s*\.\s*current\(\)",
        "SYSNotifications",
        "scheduling or asking permission directly skips the shared "
        "'have we asked' flag and the delegate that routes a tap through "
        "the pending-intent queue — a hand-rolled ask can burn the "
        "permission prompt for nothing",
    ),
]

# An app's entry point should hand its launch to SYSKit rather than re-deriving
# the sequence. Checked separately because it is an absence, not a pattern.
ENTRY_POINT = re.compile(r"@main\s+struct\s+(\w+)\s*:\s*([^{]+)\{", re.MULTILINE)


def opted_out_above(lines: list[str], line_number: int) -> bool:
    """True when the comment block immediately above the line carries sys-ok."""
    index = line_number - 2   # zero-based, the line before this one
    while index >= 0:
        stripped = lines[index].strip()
        if not stripped.startswith("//"):
            return False
        if "sys-ok:" in stripped:
            return True
        index -= 1
    return False


def scan(root: Path, source: Path) -> list[str]:
    problems: list[str] = []

    entry_points: list[tuple[Path, str, str]] = []

    for path in sorted(source.rglob("*.swift")):
        text = path.read_text(errors="replace")
        rel = path.relative_to(root)

        lines = text.splitlines()
        for line_number, line in enumerate(lines, start=1):
            if "sys-ok:" in line or opted_out_above(lines, line_number):
                continue
            stripped = line.strip()
            if stripped.startswith("//") or stripped.startswith("///"):
                continue
            for pattern, replacement, why in RULES:
                if re.search(pattern, line):
                    problems.append(
                        f"{rel}:{line_number}: use {replacement} — {why}\n"
                        f"    {stripped[:100]}"
                    )

        for match in ENTRY_POINT.finditer(text):
            entry_points.append((rel, match.group(1), match.group(2)))

    for rel, name, conformances in entry_points:
        if "SYSBootstrappedApp" not in conformances:
            problems.append(
                f"{rel}: {name} does not conform to SYSBootstrappedApp — the launch "
                "sequence, the retry path and the task that starts them are shared; "
                "an app that wires its own can forget the task and sit on its "
                "loading screen forever with nothing in the log"
            )

    return problems


def check(ctx):
    source = ctx.root / "App" / "Source"
    if not source.is_dir():
        return [f"{source} does not exist"]

    problems = scan(ctx.root, source)
    if problems:
        problems.append(
            "SYSKit exists so every app behaves the same way and one fix reaches all "
            "of them. Use the shared path, or mark the line `sys-ok: <reason>` in a "
            "comment on it or directly above it, if this app genuinely has to differ."
        )
    else:
        print(f"  {len(list(source.rglob('*.swift')))} Swift file(s) clean")
    return problems
