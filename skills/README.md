# AI agent skills

Vendored skills for AI assistants (Claude Code, Cursor, any Agent
Skills-compatible tool) that are useful across every app in the
portfolio.

## aso/ — App Store Optimization & app marketing

11 hand-picked, pure-ASO skills vendored from
https://github.com/Eronred/aso-skills (MIT — see `aso/LICENSE`):
aso-audit, keyword-research, metadata-optimization, localization,
screenshot-optimization, app-icon-optimization, category-positioning,
competitor-analysis, rating-prompt-strategy, review-management,
seasonal-aso. Everything else upstream (Android, paid UA, attribution,
monetization, analytics) was deliberately not vendored. These are local
copies — the frameworks work fully offline, no network or API key
needed, and nothing has to be fetched from GitHub to use them.

## How this relates to the studio's own ASO notes

The skills here are general frameworks. The studio's ASO process, rules and per-app research live in the faststore repo (`aso/`, with its own skill in `.claude/skills/aso`). Where they differ, faststore wins: for example, it never invents search volumes (the keyword-research skill here asks for a volume score; without a real data source, write "unknown"), and it counts keyword fields in characters, which our live listings confirm.

## Install on a new Mac

```sh
mkdir -p ~/.claude/skills
cp -R skills/aso/* ~/.claude/skills/
```

Skills then trigger automatically in any repo when a matching topic
comes up (e.g. "optimize my subtitle" → metadata-optimization).

To refresh from upstream: clone the source repo and re-copy `skills/`
over `skills/aso/`, keeping the LICENSE.
