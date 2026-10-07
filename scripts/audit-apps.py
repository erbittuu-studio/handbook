#!/usr/bin/env python3
"""Are the apps set up the same way? Prints every difference, changes nothing.

    python3 scripts/audit-apps.py [apps-dir] [--no-remote] [--no-build]

Reads each app's git HEAD tree for files, the working tree for build settings, and (unless
--no-remote) GitHub and App Store Connect for repo settings and the Xcode Cloud workflow.
What an app may do differently is written in its project.yml, so the file lists below say what
must match, and everything else is the app's own.
"""
import base64, glob, hashlib, json, os, re, subprocess, sys, urllib.request

args = [a for a in sys.argv[1:] if not a.startswith("--")]
REMOTE = "--no-remote" not in sys.argv
BUILD = "--no-build" not in sys.argv
HERE = os.path.dirname(os.path.abspath(__file__))
APPS_DIR = os.path.abspath(args[0]) if args else os.path.dirname(os.path.dirname(HERE))
APPS = sorted(os.path.basename(d) for d in glob.glob(APPS_DIR + "/*") if os.path.isfile(d + "/project.yml"))
if len(APPS) < 2:
    sys.exit("needs at least two app folders with a project.yml in " + APPS_DIR)

findings = []
def section(title):
    print("\n" + title)
def ok(msg):
    print("  ✓ " + msg)
def info(msg, detail=None):
    print("  · " + msg)
    for line in detail or []:
        print("      " + line)
def bad(msg, detail=None):
    findings.append(msg)
    print("  ✗ " + msg)
    for line in detail or []:
        print("      " + line)

def sh(cmd, cwd=None):
    r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else ""
def git(app, *a):
    return sh(["git", "-C", os.path.join(APPS_DIR, app)] + list(a))
def tree(app):
    return [p for p in git(app, "ls-tree", "-r", "--name-only", "HEAD").split("\n") if p]
def blob(app, path):
    r = subprocess.run(["git", "-C", os.path.join(APPS_DIR, app), "show", "HEAD:" + path], capture_output=True)
    return r.stdout if r.returncode == 0 else None

def project(app):
    import yaml
    return yaml.safe_load(open(os.path.join(APPS_DIR, app, "project.yml"))) or {}
PROJ = {a: project(a) for a in APPS}

def norm(app, data):
    text = data.decode("utf-8", "replace")
    for token in sorted({app, PROJ[app].get("app", {}).get("name", app)}, key=len, reverse=True):
        text = text.replace(token, "<APP>")
    return text

def groups(mapping):
    out = {}
    for k, v in mapping.items():
        out.setdefault(v, []).append(k)
    return sorted(out.values(), key=lambda g: -len(g))

TREES = {a: tree(a) for a in APPS}

# ── 1. Files that must be the same in every app ───────────────────────────────────────────
section("1. Shared files (must be identical in every app, app name aside)")
MUST = [r"^\.github/workflows/", r"^\.github/(dependabot\.yml|pull_request_template\.md)$", r"^App/ci_scripts/",
        r"^scripts/[^/]+\.sh$", r"^\.(swiftlint\.yml|swiftformat|editorconfig|gitattributes|gitignore)$",
        r"^(CONTRIBUTING\.md|build)$", r"^App/Config/Base\.xcconfig$", r"^App/Packages/PES/"]
paths = sorted({p for a in APPS for p in TREES[a] if any(re.search(m, p) for m in MUST)})
differ = []
for p in paths:
    versions = {}
    for a in APPS:
        b = blob(a, p)
        versions[a] = "(missing)" if b is None else hashlib.sha1(norm(a, b).encode()).hexdigest()[:8]
    if len(set(versions.values())) > 1:
        differ.append((p, versions))
if differ:
    detail = []
    for p, versions in differ[:25]:
        detail.append(p + "   " + " | ".join(", ".join(g) + "=" + versions[g[0]] for g in groups(versions)))
    bad(str(len(differ)) + " of " + str(len(paths)) + " shared files differ", detail)
else:
    ok("all " + str(len(paths)) + " shared files are identical")

# SYSKit package: same files and content, apart from the Firebase variant packages.
syskit = lambda p: p.startswith("App/Packages/SYSKit/")
sets = {a: {p for p in TREES[a] if syskit(p)} for a in APPS}
common = set.intersection(*sets.values())
missing = {a: sorted(set.union(*sets.values()) - sets[a]) for a in APPS}
mismatch = [p for p in sorted(common) if len({hashlib.sha1(blob(a, p) or b"").hexdigest() for a in APPS}) > 1]
if any(missing.values()) or mismatch:
    bad("SYSKit differs between apps", ["missing in " + a + ": " + ", ".join(m[:3]) + (" ..." if len(m) > 3 else "") for a, m in missing.items() if m] +
        ["content differs: " + ", ".join(mismatch[:4]) + (" ..." if len(mismatch) > 4 else "")] * bool(mismatch))
else:
    ok("SYSKit identical (" + str(len(common)) + " files)")

# ── 2. Source layout conventions ──────────────────────────────────────────────────────────
section("2. Source layout every app should have")
CONVENTIONS = ["App/Source/App/AppDelegate.swift", "App/Source/App/RootEvents.swift", "App/Source/App/RootScreens.swift",
               "App/Source/Shared/Settings/AppSettings.swift", "App/Source/Shared/Settings/DefaultsKey.swift",
               "App/Source/Shared/AnalyticsManager.swift", "App/Source/Features/Settings/SettingsScreen.swift",
               "App/Source/Features/Splash/SplashScreen.swift", "App/Resources/Info.plist", "App/Config/App.xcconfig",
               "CHANGELOG.md", "README.md", "CLAUDE.md", "build", ".github/workflows/ci.yml", ".github/workflows/release.yml"]
OLD = [".env.example", ".github/ISSUE_TEMPLATE/bug-report.yml", ".github/release-state.json", "scripts/checks/release_state.py", ".github/workflows/pr.yml", ".github/workflows/main.yml",
       ".github/workflows/release-guard.yml", ".github/workflows/diagnose.yml", ".github/workflows/xcode-cloud.yml"]
gaps = [(c, [a for a in APPS if c not in TREES[a]]) for c in CONVENTIONS]
gaps = [(c, m) for c, m in gaps if m]
left = [(o, [a for a in APPS if o in TREES[a]]) for o in OLD]
left = [(o, m) for o, m in left if m]
if left:
    bad("retired files still present", [o + "  in " + ", ".join(m) for o, m in left])
if gaps:
    bad(str(len(gaps)) + " expected files are missing somewhere", [c + "  missing in " + ", ".join(m) for c, m in gaps])
else:
    ok("all " + str(len(CONVENTIONS)) + " expected files exist in every app")
for folder in ("App/Source/App", "App/Source/Shared/Settings", "App/Source/Shared", "App/Source/Features"):
    have = {a: {p[len(folder) + 1:].split("/")[0] for p in TREES[a] if p.startswith(folder + "/")} for a in APPS}
    partial = sorted(set.union(*have.values()) - set.intersection(*have.values()))
    if partial:
        print("      only some apps have in " + folder.replace("App/Source/", "") + "/: " + ", ".join(n + "[" + "".join(a[0] if n in have[a] else "." for a in APPS) + "]" for n in partial))

# ── 3. project.yml ────────────────────────────────────────────────────────────────────────
section("3. project.yml")
def keys(d):
    return sorted(d.keys()) if isinstance(d, dict) else []
REQUIRED_SECTIONS = {"adoption", "app", "checks", "languages", "overrides", "pes", "sweep", "validation", "xcconfig"}
lacking = {a: sorted(REQUIRED_SECTIONS - set(PROJ[a])) for a in APPS if REQUIRED_SECTIONS - set(PROJ[a])}
if lacking:
    bad("project.yml is missing required sections", [a + ": " + ", ".join(m) for a, m in lacking.items()])
else:
    ok("every project.yml has the required sections")
own = {a: sorted(set(PROJ[a]) - REQUIRED_SECTIONS) for a in APPS if set(PROJ[a]) - REQUIRED_SECTIONS}
if own:
    info("app-specific sections: " + ", ".join(a + "=" + "/".join(v) for a, v in own.items()))
fv = {a: PROJ[a]["app"].get("firebaseVariant", "full") for a in APPS}
info("Firebase variant: " + ", ".join(a + "=" + v for a, v in fv.items()))
for sect in ("checks", "validation"):
    ks = {a: ",".join(keys(PROJ[a].get(sect))) for a in APPS}
    if len(set(ks.values())) > 1:
        bad("'" + sect + "' keys differ", [", ".join(g) + ": " + ks[g[0]] for g in groups(ks)])
old = [a for a in APPS if isinstance(PROJ[a].get("languages"), list)]
if old:
    bad("'languages' still uses the old list shape: " + ", ".join(old))
else:
    sel = [a for a in APPS if "selectable" in PROJ[a]["languages"]]
    ok("languages use source/interface (" + (", ".join(sel) + " also pick a language in the app)" if sel else "none pick a language in the app)"))
adoption = {a: {k: v for k, v in (PROJ[a].get("adoption") or {}).items()} for a in APPS}
names = sorted(set.union(*[set(v) for v in adoption.values()]))
undeclared, declared = [], []
for n in names:
    for a in APPS:
        v = adoption[a].get(n, "absent")
        if v is True:
            continue
        if isinstance(v, str) and v != "absent" and v.strip():
            declared.append(a + " does not use " + n + ": " + v[:80])
        else:
            undeclared.append(a + ": " + n + " is " + ("missing" if v == "absent" else "false") + " with no reason")
if undeclared:
    bad("SYSKit adoption flags with no reason", undeclared)
else:
    ok("every SYSKit feature is used, or declined with a reason in project.yml")
if declared:
    info(str(len(declared)) + " declined with a reason", declared)
overrides = {a: sorted((PROJ[a].get("overrides") or {}).keys()) for a in APPS}
if any(overrides.values()):
    info("build-setting overrides, each declared with a reason in project.yml", [a + ": " + ", ".join(k) for a, k in overrides.items() if k])
else:
    ok("no build-setting overrides")

# ── 4. Info.plist and the xcconfig ───────────────────────────────────────────────────────
section("4. Info.plist and App.xcconfig")
import plistlib
plist = {}
for a in APPS:
    b = blob(a, "App/Resources/Info.plist")
    plist[a] = sorted(plistlib.loads(b).keys()) if b else []
allk = sorted(set.union(*[set(v) for v in plist.values()]))
rows = [k + ": " + "".join(a[0] if k in plist[a] else "." for a in APPS) for k in allk if len({k in plist[a] for a in APPS}) > 1]
if rows:
    info("Info.plist keys only some apps have (" + "".join(a[0] for a in APPS) + " = " + ", ".join(APPS) + ")", rows)
else:
    ok("same Info.plist keys: " + ", ".join(allk))
xc = {}
for a in APPS:
    b = blob(a, "App/Config/App.xcconfig")
    xc[a] = sorted(set(re.findall(r"^([A-Z_]+)\s*=", b.decode(), re.M))) if b else []
if len({tuple(v) for v in xc.values()}) > 1:
    bad("App.xcconfig keys differ", [a + ": " + ", ".join(v) for a, v in xc.items()])
else:
    ok("App.xcconfig keys: " + ", ".join(xc[APPS[0]]))

# ── 5. Resolved build settings ────────────────────────────────────────────────────────────
section("5. Xcode build settings (Release, scheme App)")
IGNORE = re.compile(r"^(SRCROOT|PROJECT|PROJECT_DIR|PROJECT_FILE_PATH|PROJECT_NAME|TARGET_NAME|TARGETNAME|PRODUCT_NAME|PRODUCT_MODULE_NAME|PRODUCT_BUNDLE_IDENTIFIER|"
                    r"PRODUCT_SETTINGS_PATH|INFOPLIST_FILE|CODE_SIGN.*|PROVISIONING.*|DEVELOPMENT_TEAM|MARKETING_VERSION|CURRENT_PROJECT_VERSION|.*_DIR|.*_PATH|.*_ROOT|BUILD_.*|"
                    r"OBJROOT|SYMROOT|SDKROOT|SDK_.*|DERIVED.*|TARGET_BUILD.*|FULL_PRODUCT_NAME|EXECUTABLE.*|WRAPPER_NAME|CONTENTS_FOLDER_PATH|"
                    r"PACKAGE_.*|SHARED_.*|TEMP_.*|SCRIPT_.*|PROJECT_TEMP.*|CCHROOT|USER|UID|GID|HOME|PATH|LOCALIZED_.*|PBDEVELOPMENTPLIST_PATH|"
                    r"ASSETCATALOG_COMPILER_APPICON_NAME|INFOPLIST_KEY_CFBundleDisplayName|.*_NAME|.*FILE|.*_LIST|.*_DIRS|.*_SEARCH_PATHS|LOC.*|VERSION_INFO_STRING|.*FOLDER_PATH.*|TARGET_DEVICE_.*|ASSETCATALOG_FILTER_.*|COMPOSITE_SDK_DIRS)$")
def settings(app):
    proj = PROJ[app]["app"].get("project", "App/App.xcodeproj")
    out = sh(["xcodebuild", "-project", os.path.join(APPS_DIR, app, proj), "-scheme", PROJ[app]["app"].get("scheme", "App"),
              "-configuration", "Release", "-destination", "generic/platform=iOS", "-showBuildSettings"])
    d = {}
    for m in re.finditer(r"^    ([A-Z0-9_]+) = (.*)$", out, re.M):
        if not IGNORE.match(m.group(1)):
            d[m.group(1)] = m.group(2).strip()
    return d
declared_keys = {}
for a in APPS:
    for k in list((PROJ[a].get("capabilities") or {})) + list((PROJ[a].get("overrides") or {})):
        declared_keys.setdefault(k, []).append(a)
if BUILD:
    S = {a: settings(a) for a in APPS}
    if not all(S.values()):
        bad("could not read build settings for: " + ", ".join(a for a in APPS if not S[a]))
    else:
        rows, declared_rows = [], []
        for k in sorted(set.union(*[set(v) for v in S.values()])):
            vals = {a: S[a].get(k, "(unset)") for a in APPS}
            if len(set(vals.values())) > 1:
                line = k + ":  " + " | ".join(", ".join(g) + "=" + vals[g[0]][:60] for g in groups(vals))
                (declared_rows if k in declared_keys else rows).append(line)
        if declared_rows:
            info(str(len(declared_rows)) + " differ, declared in project.yml (capabilities or overrides) with a reason", declared_rows)
        if rows:
            bad(str(len(rows)) + " build settings differ", rows[:60] + (["... " + str(len(rows) - 60) + " more"] if len(rows) > 60 else []))
        else:
            ok("resolved build settings identical")
else:
    print("  (skipped: --no-build)")

section("5b. Xcode project format and version stamps")
stamps = {}
for a in APPS:
    text = (blob(a, "App/App.xcodeproj/project.pbxproj") or b"").decode("utf-8", "replace")
    stamps[a] = ", ".join(k + "=" + (re.search(k + r" = (\d+);", text).group(1) if re.search(k + r" = (\d+);", text) else "-")
                          for k in ("objectVersion", "preferredProjectObjectVersion", "LastUpgradeCheck", "LastSwiftUpdateCheck"))
if len(set(stamps.values())) > 1:
    bad("Xcode project stamps differ", [", ".join(g) + ": " + stamps[g[0]] for g in groups(stamps)])
else:
    ok("same project format and stamps: " + stamps[APPS[0]])

# ── 6. Docs ───────────────────────────────────────────────────────────────────────────────
section("6. Docs")
REQUIRED = {"README.md": ["Requirements", "Build & run", "Test", "Release", "Content", "Project structure"],
            "CLAUDE.md": ["App facts", "Build & checks", "Layout (PES PLAYBOOK §1)", "Hard rules", "Release (PES PLAYBOOK §5)"]}
for doc, need in REQUIRED.items():
    heads = {a: set(re.findall(r"^## (.+)$", (blob(a, doc) or b"").decode(), re.M)) for a in APPS}
    miss = [a + " has no '" + h + "' in " + doc for a in APPS for h in need if h not in heads[a]]
    if miss:
        bad(doc + " is missing required headings", miss)
    else:
        ok(doc + " has the required headings")
fmt = {}
for a in APPS:
    first = re.search(r"^## \[(\d[^\]]*)\](.*)$", (blob(a, "CHANGELOG.md") or b"").decode(), re.M)
    fmt[a] = "dated" if first and re.search(r"\d{4}-\d{2}-\d{2}", first.group(2)) else "undated"
unreleased = [a for a in APPS if re.search(r"^## \[(\d[^\]]*)\]", (blob(a, "CHANGELOG.md") or b"").decode(), re.M).group(1) != json.loads((blob(a, ".github/release-state.json") or b"{}").decode()).get("app_store_live")]
undated = [a for a in APPS if fmt[a] == "undated" and a not in unreleased]
if undated:
    bad("CHANGELOG: released versions without a date: " + ", ".join(undated))
else:
    ok("CHANGELOG headings are " + fmt[APPS[0]])

# ── 7. Release records ────────────────────────────────────────────────────────────────────
section("7. Release records (a tag means shipped)")
import plistlib as _pl
for a in APPS:
    tags = [t[1:] for t in git(a, "tag", "--list", "v*").split() if re.fullmatch(r"v\d+\.\d+\.\d+", t)]
    latest = max(tags, key=lambda v: tuple(map(int, v.split(".")))) if tags else None
    live = None
    try:
        store_id = _pl.loads(blob(a, "App/Resources/Info.plist")).get("SYSAppStoreID")
        live = json.load(urllib.request.urlopen("https://itunes.apple.com/lookup?id=" + str(store_id) + "&country=us", timeout=10))["results"][0]["version"]
    except Exception:
        pass
    if live is None:
        info(a + ": latest tag v" + str(latest) + " (could not read the live version)")
    elif latest != live:
        bad(a + ": latest tag is v" + str(latest) + ", the App Store has " + live)
    else:
        ok(a + ": latest tag v" + latest + " is the live version")

# ── 8. Git state ──────────────────────────────────────────────────────────────────────────
section("8. Git")
rows = {}
for a in APPS:
    rows[a] = {"branch": git(a, "branch", "--show-current").strip(),
               "main commits": git(a, "rev-list", "--count", "main").strip() if git(a, "rev-parse", "--verify", "main") else "-",
               "tags": ",".join(git(a, "tag").split()) or "-",
               "uncommitted": str(len([l for l in git(a, "status", "--short").split("\n") if l])),
               "origin/main": git(a, "rev-parse", "--short", "origin/main").strip(),
               "local main": git(a, "rev-parse", "--short", "main").strip()}
    rows[a]["main pushed"] = "yes" if rows[a]["origin/main"] == rows[a]["local main"] else "NO (local only)"
for field in ("main commits", "uncommitted", "main pushed"):
    v = {a: rows[a][field] for a in APPS}
    same = len(set(v.values())) == 1 and not (field == "main pushed" and "NO" in "".join(v.values())) and not (field == "uncommitted" and "0" not in v.values())
    (ok if same else bad)(field + ": " + ", ".join(a + "=" + x for a, x in v.items()))
for a in APPS:
    print("      " + a + ": branch " + rows[a]["branch"] + ", tags " + rows[a]["tags"])

# ── 9. GitHub and Xcode Cloud ─────────────────────────────────────────────────────────────
if REMOTE:
    section("9. GitHub settings")
    gh = {}
    for a in APPS:
        remote = git(a, "remote", "get-url", "origin").strip()
        slug = re.search(r"github\.com[:/](.+?)(?:\.git)?$", remote)
        settings_line = sh(["gh", "api", "repos/" + slug.group(1), "--jq",
                   "[.default_branch,(.allow_squash_merge|tostring),(.allow_merge_commit|tostring),(.allow_rebase_merge|tostring),(.delete_branch_on_merge|tostring)]|join(\" \")"]) if slug else ""
        sec = sh(["gh", "secret", "list", "-R", slug.group(1)]) if slug else ""
        gh[a] = {"default/squash/merge/rebase/delete-branch": settings_line.strip() or "unreadable", "repo secrets": str(len([l for l in sec.split("\n") if l]))}
    for field in ("default/squash/merge/rebase/delete-branch", "repo secrets"):
        v = {a: gh[a][field] for a in APPS}
        (ok if len(set(v.values())) == 1 else bad)(field + ": " + ", ".join(a + "=" + x for a, x in v.items()))

    XCODE_CLOUD = "27.1"
    section("10. Xcode Cloud workflow (manual_release, no start conditions)")
    def creds():
        d = os.environ.get("PES_SECRETS") or os.path.join(APPS_DIR, "secrets")
        key = next(iter(glob.glob(d + "/AuthKey_*.p8")), None)
        notes = os.path.join(d, "APPLE.md")
        issuer = re.search(r"ASC_ISSUER_ID`?\s*\|\s*`?([0-9a-f-]{36})", open(notes).read(), re.I) if os.path.exists(notes) else None
        return (re.search(r"AuthKey_(\w+)\.p8", key).group(1), issuer.group(1), key) if key and issuer else None
    def token(kid, iss, keyfile):
        import time
        b64 = lambda b: base64.urlsafe_b64encode(b).rstrip(b"=").decode()
        head = b64(json.dumps({"alg": "ES256", "kid": kid, "typ": "JWT"}).encode())
        now = int(time.time())
        body = b64(json.dumps({"iss": iss, "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"}).encode())
        der = subprocess.run(["openssl", "dgst", "-sha256", "-sign", keyfile], input=(head + "." + body).encode(), capture_output=True).stdout
        i = 3 if der[1] < 0x80 else 4
        rlen = der[i]; r = der[i + 1:i + 1 + rlen]; j = i + 1 + rlen + 1
        slen = der[j]; s = der[j + 1:j + 1 + slen]
        raw = r.lstrip(b"\0").rjust(32, b"\0") + s.lstrip(b"\0").rjust(32, b"\0")
        return head + "." + body + "." + b64(raw)
    c = creds()
    if not c:
        print("  (skipped: no Apple key in the secrets folder)")
    else:
        def asc(path):
            req = urllib.request.Request("https://api.appstoreconnect.apple.com" + path, headers={"Authorization": "Bearer " + token(*c)})
            return json.load(urllib.request.urlopen(req, timeout=30))
        try:
            res = asc("/v1/ciProducts?include=app&limit=50")
            appnames = {x["id"]: x["attributes"].get("bundleId") for x in res.get("included", []) if x.get("attributes")}
            wf = {}
            xcode = {}
            for a in APPS:
                bundle = PROJ[a]["app"].get("bundleId")
                prod = next((p for p in res["data"] if appnames.get(p["relationships"]["app"]["data"]["id"]) == bundle), None)
                if not prod:
                    wf[a] = "no Xcode Cloud product"
                    continue
                ws = asc("/v1/ciProducts/" + prod["id"] + "/workflows?limit=20")["data"]
                parts = []
                for w in ws:
                    t = w["attributes"]
                    if t["name"] == "manual_release":
                        full = asc("/v1/ciWorkflows/" + w["id"] + "?include=xcodeVersion")
                        xcode[a] = next((x["attributes"]["name"] for x in full.get("included", []) if x["type"] == "ciXcodeVersions"), "unknown")
                    triggers = [k for k in ("branchStartCondition", "tagStartCondition", "pullRequestStartCondition", "scheduledStartCondition") if t.get(k)]
                    act = "/".join(x["actionType"] + ":" + str(x.get("scheme")) for x in t.get("actions", []))
                    parts.append(t["name"] + " [" + (",".join(triggers) or "manual") + "] " + t.get("containerFilePath", "?") + " " + act)
                wf[a] = "; ".join(parts)
            want = {a: [w for w in wf[a].split("; ") if w.startswith("manual_release [manual] ")] for a in APPS}
            for a in APPS:
                others = [w.split(" [")[0] for w in wf[a].split("; ") if not w.startswith("manual_release ")]
                if not want[a]:
                    bad(a + ": no 'manual_release' workflow with no start conditions yet (PLAYBOOK §12)")
                else:
                    ok(a + ": " + want[a][0])
                if want[a] and not xcode.get(a, "").startswith("Xcode " + XCODE_CLOUD):
                    bad(a + ": manual_release builds with '" + xcode.get(a, "unknown") + "', not Xcode " + XCODE_CLOUD)
                elif want[a]:
                    ok(a + ": builds with " + xcode[a])
                if others:
                    info(a + ": delete the old workflow(s): " + ", ".join(others))
            for a in APPS:
                proj = PROJ[a]["app"].get("project")
                if want[a] and proj and proj not in want[a][0]:
                    bad(a + ": manual_release builds a project that is not " + proj)
        except Exception as e:
            print("  (could not read Xcode Cloud: " + str(e)[:80] + ")")

section("11. A clean clone passes the project checks (what GitHub sees)")
import shutil, tempfile
for a in APPS:
    branch = git(a, "rev-parse", "--abbrev-ref", "HEAD").strip()
    dirty = [l for l in git(a, "status", "--short").splitlines() if l.strip()]
    scratch = tempfile.mkdtemp(prefix="pes-clone-")
    try:
        cloned = subprocess.run(["git", "clone", "-q", "--branch", branch, os.path.join(APPS_DIR, a), scratch + "/app"], capture_output=True, text=True)
        if cloned.returncode:
            bad(a + ": could not clone " + branch + ": " + cloned.stderr.strip()[:90])
            continue
        run = subprocess.run([sys.executable, "App/Packages/PES/validate.py"], cwd=scratch + "/app", capture_output=True, text=True, env=dict(os.environ, PES_BRANCH=branch))
        last = (run.stdout.strip().splitlines() or [run.stderr.strip()])[-1]
        if run.returncode:
            bad(a + " (" + branch + "): the checks fail in a clean clone: " + last[:120])
        else:
            ok(a + " (" + branch + "): " + last)
        if dirty:
            info(a + ": " + str(len(dirty)) + " uncommitted change(s) are not in that clone")
    finally:
        shutil.rmtree(scratch, ignore_errors=True)

print("\n" + ("All " + str(len(APPS)) + " apps are set up the same way." if not findings else str(len(findings)) + " difference(s) found."))
sys.exit(1 if findings else 0)
