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
        r"\"-debug(Route|State|Orientation)\"",
        "SYSDebugRoute.launch, SYSAppState.debugForced and SYSDebugRoute.applyLaunchOrientation",
        "a launch argument parsed in the app is a second grammar for the same "
        "thing, and the one place a release build must not honour it is the "
        "one place SYSKit already guards",
    ),
    (
        r"\bAVSpeechSynthesizer\b",
        "SYSSpeech",
        "a synthesizer built per call pays its cold start on every call, nothing "
        "ends the audio ducking it causes, and a caller that cannot await the end "
        "of speech ends up guessing with timers",
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

# Rules about layout, the only ones that also apply outside App/Source: an extension
# target or an owned package measures the window too, and gets it wrong the same way.
LAYOUT_RULES: list[tuple[str, str, str]] = [
    (
        r"\bUIScreen\b",
        "SYSMetrics for the window's size, @Environment(\\.displayScale) for pixel scale",
        "a device with two displays has no single screen, and UIScreen reads the "
        "display rather than the window, so Split View and the folded pose report "
        "a size the app is not actually given",
    ),
    (
        r"\buserInterfaceIdiom\b|\bisPad\w*\b",
        "the size classes or SYSMetrics",
        "an idiom says what the device is, not how much room the window has — an "
        "iPad in Split View, a phone in landscape and iPhone Duo open all break "
        "the assumption in different directions",
    ),
    (
        r"\bUIDevice\s*\.\s*current\s*\.\s*(orientation|model)\b",
        "SYSMetrics.aspect or the size classes",
        "device orientation says nothing about the window's shape, and the inner "
        "display rotates regardless of the orientations the app declares",
    ),
    (
        r"\.windows\.first\b|\.keyWindow\b|\bUIApplication\s*\.\s*shared\s*\.\s*windows\b",
        "the scene the view is in (window?.windowScene or the SwiftUI environment)",
        "with more than one scene open this picks an arbitrary window, so the "
        "result is right until the app is in Split View or on a second display",
    ),
    (
        r"\bisLandscape\b|\bisPortrait\b",
        "the size classes, ViewThatFits or SYSTwoPane",
        "orientation is not a question about room — a foldable held open is "
        "neither, and the layout that answers it is wrong on the next shape",
    ),
    (
        r"(?i)\bwidth\w*\s*[<>]=?\s*[\w.]*height",
        "the size classes, ViewThatFits or SYSTwoPane",
        "comparing width to height is orientation by another name; ask how "
        "much room there is, not which way the window is turned",
    ),
    (
        r"(?i)^(?!.*\b(translation|velocity|predictedEndTranslation)\b).*\b\w*(width|height)\w*\s*[<>]=?\s*\d{3,4}\b",
        "SYSMetrics or a size class",
        "a breakpoint tuned to one phone is wrong on the next device — every "
        "such number is a size the app will meet in a shape it was not drawn for",
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


def scan(root: Path, source: Path, rules: list[tuple[str, str, str]], entry_point: bool) -> list[str]:
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
            for pattern, replacement, why in rules:
                if re.search(pattern, line):
                    problems.append(
                        f"{rel}:{line_number}: use {replacement} — {why}\n"
                        f"    {stripped[:100]}"
                    )

        if entry_point:
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


def app_code_dirs(ctx) -> list[Path]:
    """Everywhere the app's own Swift lives: the source, its extension targets, and
    any package under App/Packages it declares as its own in `ownedPackages`."""
    folders = [ctx.root / "App" / "Source", ctx.root / "App" / "Watch", ctx.root / "App" / "Widget"]
    for name in ctx.project.get("ownedPackages") or []:
        folders.append(ctx.root / "App" / "Packages" / name)
    return [folder for folder in folders if folder.is_dir()]


def check(ctx):
    source = ctx.root / "App" / "Source"
    if not source.is_dir():
        return [f"{source} does not exist"]

    folders = app_code_dirs(ctx)
    problems = scan(ctx.root, source, RULES + LAYOUT_RULES, entry_point=True)
    for folder in folders:
        if folder != source:
            problems += scan(ctx.root, folder, LAYOUT_RULES, entry_point=False)
    if problems:
        problems.append(
            "SYSKit exists so every app behaves the same way and one fix reaches all "
            "of them. Use the shared path, or mark the line `sys-ok: <reason>` in a "
            "comment on it or directly above it, if this app genuinely has to differ."
        )
    else:
        print(f"  {sum(len(list(folder.rglob('*.swift'))) for folder in folders)} Swift file(s) clean")
    return problems
