"""The things App Review rejects a build for, found before it is uploaded.

Four of them, each a rule Apple enforces at upload or review:

  - **A privacy manifest.** `App/Resources/PrivacyInfo.xcprivacy` must exist, parse, state whether the app tracks,
    and give a reason for every required-reason API it declares.
  - **Declared required-reason APIs.** Using `UserDefaults`, file timestamps, system uptime, disk space or the active
    keyboards without declaring the category is the most common upload rejection. The source is searched for each
    API, including SYSKit's, which links into the app.
  - **The encryption answer.** `ITSAppUsesNonExemptEncryption` in the Info.plist or the project's build settings.
    Without it every build waits in TestFlight as "Missing Compliance" until someone answers by hand.
  - **Usage descriptions.** An API that asks for a permission (camera, photos, microphone, location, contacts,
    speech, tracking, Bluetooth, Face ID, calendar) needs its `NS…UsageDescription`; without one the app crashes
    the first time it asks.

A match is a line of Swift that is not a comment. A check that guesses wrong on a line the app really needs can be
answered in `project.yml`, under `validation.skip`, with the reason, like any other shared check.
"""
import plistlib
import re
from pathlib import Path

PRIVACY_MANIFEST = "App/Resources/PrivacyInfo.xcprivacy"

REQUIRED_REASON_APIS = {
    "NSPrivacyAccessedAPICategoryUserDefaults": r"\bUserDefaults\b|@AppStorage",
    "NSPrivacyAccessedAPICategoryFileTimestamp": (
        r"\.creationDate\b|\.modificationDate\b|fileModificationDate|fileCreationDate|contentModificationDateKey|"
        r"creationDateKey|NSFileCreationDate|NSFileModificationDate|\bf?stat\("
    ),
    "NSPrivacyAccessedAPICategorySystemBootTime": r"systemUptime|mach_absolute_time|clock_gettime|kern\.boottime",
    "NSPrivacyAccessedAPICategoryDiskSpace": (
        r"volumeAvailableCapacity|volumeTotalCapacity|systemFreeSize|NSFileSystemFreeSize|NSFileSystemSize|"
        r"\bstatv?fs\("
    ),
    "NSPrivacyAccessedAPICategoryActiveKeyboards": r"activeInputModes",
}

USAGE_DESCRIPTIONS = {
    "NSCameraUsageDescription": r"\bAVCaptureDevice\b|\bAVCaptureSession\b",
    "NSPhotoLibraryUsageDescription": r"\bPHPhotoLibrary\b",
    "NSMicrophoneUsageDescription": r"\bAVAudioRecorder\b|requestRecordPermission|\.inputNode\b",
    "NSLocationWhenInUseUsageDescription": r"\bCLLocationManager\b",
    "NSContactsUsageDescription": r"\bCNContactStore\b",
    "NSSpeechRecognitionUsageDescription": r"\bSFSpeechRecognizer\b",
    "NSUserTrackingUsageDescription": r"\bATTrackingManager\b",
    "NSBluetoothAlwaysUsageDescription": r"\bCBCentralManager\b|\bCBPeripheralManager\b",
    "NSFaceIDUsageDescription": r"\bLAContext\b",
    "NSCalendarsUsageDescription": r"\bEKEventStore\b",
}


def source_folders(root: Path) -> list[Path]:
    """The Swift that ends up in the app binary: its own source and the SYS packages it links."""
    folders = [root / "App" / "Source"]
    folders += sorted((root / "App" / "Packages").glob("SYS*/Sources"))
    return [folder for folder in folders if folder.is_dir()]


def matches(root: Path, patterns: dict) -> dict:
    """Which of `patterns` appear in the source, and the first file each appears in."""
    compiled = {name: re.compile(pattern) for name, pattern in patterns.items()}
    found = {}
    for folder in source_folders(root):
        for path in sorted(folder.rglob("*.swift")):
            for line in path.read_text(errors="replace").splitlines():
                if line.lstrip().startswith("//"):
                    continue
                for name, pattern in compiled.items():
                    if name not in found and pattern.search(line):
                        found[name] = path.relative_to(root)
    return found


def build_settings_text(root: Path) -> str:
    """Info.plist files and the project's build settings: where an Info.plist key can live."""
    pieces = []
    for plist in sorted((root / "App").rglob("*Info.plist")):
        if "Packages" in plist.parts or "Vendor" in plist.parts or plist.name == "GoogleService-Info.plist":
            continue
        pieces.append(plist.read_text(errors="replace"))
    for project in (root / "App").glob("*.xcodeproj/project.pbxproj"):
        pieces.append(project.read_text(errors="replace"))
    for config in (root / "App" / "Config").glob("*.xcconfig") if (root / "App" / "Config").is_dir() else []:
        pieces.append(config.read_text(errors="replace"))
    return "\n".join(pieces)


def manifest_problems(root: Path) -> tuple[list[str], set]:
    path = root / PRIVACY_MANIFEST
    if not path.is_file():
        return [f"{PRIVACY_MANIFEST} is missing — App Review requires a privacy manifest"], set()
    try:
        with path.open("rb") as handle:
            manifest = plistlib.load(handle)
    except Exception as error:
        return [f"{PRIVACY_MANIFEST} is not a valid property list: {error}"], set()

    problems = []
    if not isinstance(manifest.get("NSPrivacyTracking"), bool):
        problems.append(f"{PRIVACY_MANIFEST}: NSPrivacyTracking must say true or false")
    elif manifest["NSPrivacyTracking"] and not manifest.get("NSPrivacyTrackingDomains"):
        problems.append(f"{PRIVACY_MANIFEST}: the app tracks but lists no NSPrivacyTrackingDomains")
    if not isinstance(manifest.get("NSPrivacyCollectedDataTypes"), list):
        problems.append(f"{PRIVACY_MANIFEST}: NSPrivacyCollectedDataTypes must be present, as an empty list if nothing is collected")

    declared = set()
    for entry in manifest.get("NSPrivacyAccessedAPITypes") or []:
        category = entry.get("NSPrivacyAccessedAPIType", "?")
        declared.add(category)
        if not entry.get("NSPrivacyAccessedAPITypeReasons"):
            problems.append(f"{PRIVACY_MANIFEST}: {category} declares no reason")
    return problems, declared


def check(ctx):
    root = ctx.root
    problems, declared = manifest_problems(root)

    for category, where in matches(root, REQUIRED_REASON_APIS).items():
        if category not in declared:
            problems.append(f"{where} uses an API that needs {category} declared in {PRIVACY_MANIFEST}")

    settings = build_settings_text(root)
    if "ITSAppUsesNonExemptEncryption" not in settings:
        problems.append(
            "ITSAppUsesNonExemptEncryption is not set in the Info.plist or build settings — every build would wait "
            "as 'Missing Compliance' in TestFlight until answered by hand"
        )

    for key, where in matches(root, USAGE_DESCRIPTIONS).items():
        if key not in settings and f"INFOPLIST_KEY_{key}" not in settings:
            problems.append(f"{where} asks for a permission, but there is no {key} — the app crashes when it asks")

    if not problems:
        print(f"  privacy manifest declares {len(declared)} required-reason categories; encryption answered")
    return problems
