# Templates

Battle-tested files copied into app repos by `scripts/setup.sh`. Every one
of these shipped in the reference app; comments inside each file explain
the non-obvious choices.

| Folder | Contents | Copied to |
|---|---|---|
| `assets/` | gitignore, gitattributes, editorconfig, swiftlint, swiftformat | repo root (dot-prefixed) |
| `github/` | PR template, issue templates, dependabot | `.github/` |
| `workflows/` | `ci.yml` (checks on every PR and push) and `release.yml` (tag and release on merge): self-contained, identical in every app | `.github/workflows/` |
| `ci_scripts/` | post_clone, pre_xcodebuild (branch→version, ASC→build number), post_xcodebuild (dSYMs) | `App/ci_scripts/` |
| `App/Packages/PES/ci/` | PR-check scripts (`validate_analytics_events.py`) | `App/Packages/PES/ci/` |
| `docs/` | README / SECURITY / CLAUDE (AI-assistant guidance) skeletons | repo root |

After copying: replace every `{{PLACEHOLDER}}` (`git grep '{{'`), delete
what the app doesn't use (no Data pipeline → no data workflows, etc.).
Dotfiles are stored without the leading dot; setup.sh renames on copy.
