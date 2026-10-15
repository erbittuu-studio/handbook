#!/usr/bin/env bash
# validate.sh — sanity checks for the PES repo itself (run before release).
set -euo pipefail

PES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PES_ROOT"
fail=0
err() { echo "FAIL: $*" >&2; fail=1; }

# 1. Required files
for f in README.md PLAYBOOK.md VERSION LICENSE SECURITY.md; do
  [[ -f "$f" ]] || err "missing $f"
done

# 2. VERSION / README consistency
version="$(tr -d '[:space:]' < VERSION)"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || err "VERSION '$version' is not X.Y.Z"
grep -q "Current version: \*\*$version\*\*" README.md || err "README version line != $version"

# 3. Shell templates and scripts parse
for s in scripts/*.sh templates/ci_scripts/*.sh; do
  bash -n "$s" || err "$s has syntax errors"
done
for s in scripts/*.sh; do [[ -x "$s" ]] || err "$s not executable"; done

# 4. Workflow YAML parses (ruby is always present on macOS)
for y in templates/workflows/*.yml .github/workflows/*.yml templates/github/*.yml; do
  ruby -ryaml -e "YAML.safe_load(File.read('$y'), aliases: true)" >/dev/null 2>&1 || err "$y invalid YAML"
done

# 4a. App workflows are self-contained: no call into another repo, no secret
for y in templates/workflows/*.yml; do
  if grep -E "uses: *erbittuu-studio/|secrets\.[A-Za-z_]+" "$y" | grep -qv "secrets.GITHUB_TOKEN"; then
    err "$y reaches outside the app (another repo or a secret); app workflows must be self-contained"
  fi
done

# 4b. Ruby templates parse (ci_scripts/lib helpers, scripts/ci helpers)
for r in templates/ci_scripts/lib/*.rb tools/PES/ci/*.rb; do
  [[ -f "$r" ]] || continue
  ruby -c "$r" >/dev/null 2>&1 || err "$r has syntax errors"
done

# 4c. Python templates parse
for p in tools/PES/validate.py tools/PES/shared/*.py tools/PES/ci/*.py; do
  [[ -f "$p" ]] || continue
  python3 -m py_compile "$p" 2>/dev/null || err "$p has syntax errors"
done

# 4d. The shared tooling package: shell helpers and hooks parse, hooks are executable
for s in tools/PES/ci/*.sh tools/PES/hooks/*; do
  bash -n "$s" || err "$s has syntax errors"
done
for s in tools/PES/hooks/*; do [[ -x "$s" ]] || err "$s not executable"; done

# 4e. The SYSKit API reference is current, and no doc names something that no longer exists
python3 scripts/api-docs.py check || err "SYSKit API reference or the docs are out of step (python3 scripts/api-docs.py)"

# 5. Core docs contain no unresolved {{PLACEHOLDER}}
# (PLAYBOOK.md and templates/ legitimately document the token
# syntax itself, so they are checked for stray tokens elsewhere, not here)
if grep -rnE '\{\{[A-Z][A-Z_]*\}\}' README.md decisions/ 2>/dev/null \
    | grep -v 'adr-template.md'; then
  err "placeholder tokens found in core docs"
fi

if [[ $fail -eq 0 ]]; then echo "OK: PES v$version validates clean."; else exit 1; fi
