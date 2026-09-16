# Decision Guide: CI/CD Tooling

Three tools, three distinct jobs. The mistake to avoid is using two tools
for the same job.

**TL;DR defaults**

| Job | Tool |
|---|---|
| App Store app build/test/sign/deliver | **Xcode Cloud** |
| Everything else CI/CD (packages, web, data, functions, direct-distribution macOS) | **GitHub Actions** |
| Store metadata & screenshots | **Fastlane in GitHub Actions** (local runs = fallback; see PLAYBOOK §6) |

---

## GitHub Actions

**Use when:** CI for Swift packages; validating/deploying websites, static
data, Cloud Functions; building + notarizing direct-distribution macOS apps;
any Linux-friendly automation (lint, JSON schema checks, link checks).

**Avoid when:** building/signing App Store apps (you'd hand-manage
certificates and profiles that Xcode Cloud manages for free); anything
needing >10 macOS-minutes per run on a private repo (cost).

**Pros:** lives with the code; free for public repos and generous for
private; enormous action ecosystem; reusable workflows across all repos;
Linux runners are fast and cheap.

**Cons:** macOS runners are 10× billing and often trail latest Xcode;
signing on it means exporting and rotating certificates yourself; YAML
debugging loop is slow.

**Alternatives:** Xcode Cloud (Apple builds), local scripts + manual runs
(fine for rare tasks), GitLab CI/CircleCI (no benefit worth leaving the
GitHub ecosystem).

---

## Xcode Cloud

**Use when:** any iOS/macOS app distributed through TestFlight/App Store.
CI (build+test on PRs) and CD (archive to TestFlight on `release/*`
branches — see PLAYBOOK §5 for why this is branch-driven, not tag-driven).

**Avoid when:** the product isn't an ASC-distributed app; jobs are
non-Apple (web, data); you need custom environments/hardware; you've
consistently exceeded the included 25 h/month and Actions macOS minutes
would be cheaper.

**Pros:** zero signing management (the killer feature); TestFlight/ASC
native; macOS+Xcode always compatible; configured in Xcode, no YAML;
included with the developer program.

**Cons:** Apple-only; limited workflow expressiveness (post-clone/build
scripts only); build logs/debuggability weaker than Actions; capacity
occasionally queues around Apple event weeks.

**Alternatives:** GitHub Actions + Fastlane (`gym`+`pilot`) with manually
managed signing — the standard escape hatch, costing you certificate
lifecycle ownership.

---

## Fastlane

**Use when:** generating localized screenshots (`snapshot`/`frameit`);
bulk-managing App Store metadata (`deliver`); scripting ASC operations that
the web UI makes repetitive; notarization lane for direct-distribution macOS.

**Avoid when:** Xcode Cloud already does the job (build/sign/upload);
the repo would gain a Ruby toolchain for one trivial task a shell script
covers; "because every iOS tutorial uses it."

**Pros:** best-in-class for screenshots/metadata; mature; runs identically
locally and in CI.

**Cons:** Ruby/Bundler maintenance surface; breaks with ASC API changes and
needs updating; overlaps confusingly with Xcode Cloud if allowed to.

**Alternatives:** Xcode Cloud (delivery), raw `xcodebuild`/`notarytool`
scripts (single-purpose tasks), manual ASC UI (rare operations — manual is
the right amount of automation for once-a-year tasks).
