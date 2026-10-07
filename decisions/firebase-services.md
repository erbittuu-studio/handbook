# Decision Guide: Firebase Services vs Static JSON

Work through this ladder **top-down** and stop at the first rung that
satisfies the requirement. Every rung below adds cost, security surface,
and maintenance.

```
1. Static files in the app bundle        (no network at all)
2. Static JSON on Hosting/Pages          (read-only remote data)
3. Remote Config                          (flags & tuning, no redeploy)
4. Firestore                              (per-user / queryable data)
5. Realtime Database                      (niche: high-freq tiny writes)
6. Cloud Functions                        (server-side logic, last resort)
```

---

## Static JSON (bundled or hosted)

**Use when:** data is read-only for clients, changes at most every few
days, is the same for all users, fits in a few MB. Catalogs, level data,
localized content, "what's new" feeds.
**Avoid when:** users write data; per-user views; needs querying beyond
"fetch and filter locally"; secrecy required (it's public).
**Pros:** zero backend, zero rules, zero cost, trivially cacheable/CDN'd,
versionable in Git, works offline by shipping a bundled fallback.
**Cons:** full-file fetch (mitigate with HTTP caching/ETag); schema changes
need coordination with shipped clients (version the path — see
[versioning.md](../standards/versioning.md)); no personalization.
**Alternatives:** Remote Config (if it's really just parameters), Firestore
(if it's really per-user).

## Firebase Hosting

**Use when:** the product's website or hosted JSON, especially alongside
other Firebase services; needs custom domain + SSL + CDN + instant rollback.
**Avoid when:** the repo is a pure open-source project page — GitHub Pages
is zero extra accounts; or when the "site" is one README.
**Pros:** global CDN, free SSL, `hosting:rollback`, preview channels for
testing, deploys in seconds via Actions.
**Cons:** another project/console to own; ties the site to Google account
lifecycle.
**Alternatives:** GitHub Pages (OSS/docs), Cloudflare Pages (only if already
on Cloudflare).

## Remote Config

**Use when:** feature flags, staged rollouts, kill switches, tuning values
(paywall copy, thresholds) that must change without an App Store release.
**Avoid when:** the value never changes between releases (hardcode it);
as a content CMS (that's hosted JSON or Firestore); for per-user state.
**Pros:** change behavior in production instantly; percentage rollouts and
conditions; built-in caching in the SDK; free.
**Cons:** invisible-config debugging ("works differently on my device");
every flag is permanent complexity until removed — prune quarterly.
**Alternatives:** hosted JSON config file (simpler, no SDK, but no
targeting/rollout), new app release (fine for non-urgent changes).

## Firestore

**Use when:** per-user data, user-generated content, sync across devices,
structured queries, offline persistence. **The default database** whenever a
real database is needed.
**Avoid when:** the ladder stops earlier (static/read-only data); relational
reporting/aggregation workloads (it's not SQL); >1 write/sec sustained to a
single document.
**Pros:** serverless, scales to zero cost at portfolio size, offline-first
Apple SDK, security rules keep you server-code-free, strong queries + indexes.
**Cons:** query model requires denormalization habits; costs are
per-operation (a runaway loop is a bill — set budget alerts); rules require
real testing discipline.
**Alternatives:** RTDB (below), CloudKit (Apple-only portfolio darling but
weak tooling/rules; consider for private-data-only apps with zero web needs),
SQLite/GRDB local-only (no sync requirement? no backend at all).

## Realtime Database

**Use when:** genuinely high-frequency, low-latency, small-payload sync —
presence/typing indicators, live cursors, ephemeral game state. Usually as a
*supplement* to Firestore, not instead.
**Avoid when:** anything Firestore already covers — for new general-purpose
work Firestore is Firebase's own recommended default; complex querying;
large/structured documents.
**Pros:** lower write latency & connection-based pricing (cheap for chatty
tiny writes), built-in presence (`onDisconnect`).
**Cons:** primitive querying, one big JSON tree invites tangled data, rules
language weaker than Firestore's, easy to outgrow.
**Alternatives:** Firestore (default), direct WebSocket to your own server
(never at this portfolio's scale).

## Cloud Functions

**Use when:** logic must not run on the client: payments/receipt validation,
privileged mutations, fan-out on write, scheduled jobs, third-party API
calls that need a secret key.
**Avoid when:** security rules alone can enforce the invariant (they cover
more than people expect); the job could be a scheduled GitHub Action
(batch, non-user-facing); "we might need an API later."
**Pros:** serverless, scales to zero, first-class Firebase triggers, secrets
stay server-side.
**Cons:** cold starts; a Node/TS toolchain to maintain in an Apple
portfolio; hardest Firebase piece to test; requires Blaze (billing) plan —
pair with budget alerts.
**Alternatives:** security rules (authorization), scheduled GitHub Actions
(cron/batch), no backend (most apps here need none).
