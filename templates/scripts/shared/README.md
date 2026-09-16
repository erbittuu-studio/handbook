# scripts/shared — checks PES owns

**Do not edit these in an app repo.** `handbook`
overwrites this whole folder on every `update.sh`, so a local fix here is a fix
that disappears at the next sync. Change it upstream and pull it back down.

Every app gets the same file under the same name, so a check written once runs
everywhere: the store listing, the screenshots, the string catalogs, the URLs,
the analytics enum, the colour assets, and the single-source-of-truth rule.

## Where a check belongs

| It checks… | It lives in | Owned by |
|---|---|---|
| something every app has — the store listing, a string catalog, an asset name | `scripts/shared/` | PES |
| a contract of SYSKit itself | `App/Packages/SYSKit/Scripts/checks/` | PES, travels with the vendored package |
| something only this app has — its artwork format, its own constants | `scripts/checks/` | the app |

The split matters because the answer to "can I edit this?" has to be obvious
from where the file sits. It was not: these six started in `scripts/checks/`
beside RealAIApp's own, where nothing distinguished a rule every app needs from
one only this app could ever want.

## Adding one

Drop a file with a `check(ctx)` in the right folder. There is no registry to
update and no CI line to add — `Project.json`'s `checks` array lists the
folders, and `scripts/validate.py` discovers the rest. `ctx.root` is the repo
and `ctx.get("app.bundleId")` reads `Project.json`, so a check imports nothing
and never computes its own path.

Anything that differs per app — the screenshot sizes, the languages, the
locales — is read from `Project.json` rather than hardcoded. That is what lets
one file serve every app.
