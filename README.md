# Portfolio Engineering Standards

This is my personal playbook for building and shipping iOS apps. I maintain
multiple apps alone, so I need every project to work the same way — same
folder structure, same automation, same release process. This repo is the
single source of truth for all of that.

Everything here comes from real shipping apps, not from
theory. If a rule is written here, it is because I actually use it in
production.

## How I use this repo

| File | When I open it |
|---|---|
| [PLAYBOOK.md](PLAYBOOK.md) | To remember how the system works — repo layout, CI/CD, releases, store automation. One read covers everything |
| [decisions/](decisions/) | When choosing between tools or Firebase services |
| [templates/](templates/) | Ready files that `scripts/setup.sh` copies into a new repo |

## My core rules

1. Keep it simple. If the current solution works, don't touch it.
2. Automate everything except what Apple forces a human to do.
3. **No remote packages. All dependencies live inside the repo** — source
   copies for Swift libraries. Builds
   should never depend on someone else's server.
4. The app version lives nowhere but a `release/X.Y.Z` branch and, once
   shipped, a git tag created automatically on merge. Never a stored
   version number, never a tag pushed by hand.
5. One private repo per app. App code, data, store content, automation —
   all in one place.

## Starting a new app

```sh
cd my-app && git init -b main
/path/to/handbook/scripts/setup.sh
```

## Versioning this repo

Simple SemVer, see [VERSION](VERSION). The version moves on a schedule, not on every change.

- **Day to day:** commit to `main`. No version bump, no tag, and the apps do not update.
- **Once a month**, when the monthly release branches of the apps start: bump the minor once (1.6.0 to 1.7.0), tag it, and let every app adopt it with `scripts/update.sh`.
- **Only if something breaks** in an app that already adopted it (a check fails, or the build stamps the wrong version): ship a patch (1.7.1).
- An app adopts a new version only when it starts a release branch, never in the middle of a release.

Current version: **1.6.0**
