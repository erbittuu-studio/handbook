#!/bin/sh
# Exercises every guard and hook: the passing path AND the rejection path.
# Run from the repo root. Makes no lasting changes and does nothing over the network.
# PES owns this file and `update.sh` keeps it current; it is the same in every app.
cd "$(git rev-parse --show-toplevel)" || exit 1

PASS=0
FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# expect <want-exit> <label> <command...>
expect() {
  want=$1; label=$2; shift 2
  "$@" >"$TMP/out" 2>&1
  got=$?
  if [ "$got" = "$want" ]; then
    printf "  \033[32mPASS\033[0m  %s\n" "$label"
    PASS=$((PASS + 1))
  else
    printf "  \033[31mFAIL\033[0m  %s (wanted exit %s, got %s)\n" "$label" "$want" "$got"
    sed 's/^/          /' "$TMP/out" | head -6
    FAIL=$((FAIL + 1))
  fi
}

echo ""
echo "REPO CHECKS (offline ones)"
expect 0 "nothing restates project.yml"     python3 App/Packages/PES/validate.py project
expect 0 "analytics event limits"           python3 App/Packages/PES/validate.py analytics_events
expect 0 "app uses SYSKit, not its own"     python3 App/Packages/PES/validate.py sys_adoption
expect 0 "no large files"                   python3 App/Packages/PES/validate.py big_files

# The branch is named by PES_BRANCH, which CI supplies from the pull request or the push.
rel() { PES_BRANCH="$1" python3 App/Packages/PES/validate.py release_branch; }
LATEST=$(git tag --list 'v*' | sed 's/^v//' | sort -V | tail -1)

echo ""
echo "RELEASE BRANCH CHECK"
expect 0 "a topic branch is not a release"  rel feat/x
expect 0 "main is not a release"            rel main
expect 1 "release/1.2 is not X.Y.Z"         rel release/1.2
expect 1 "release/v1.2.3 has a leading v"   rel release/v1.2.3
[ -n "$LATEST" ] && expect 1 "0.0.1 is older than any tag" rel release/0.0.1
if [ -n "$LATEST" ]; then
  expect 1 "$LATEST is not newer than its own tag" rel "release/$LATEST"
fi
expect 1 "999.0.0 has no changelog section" rel release/999.0.0

echo ""
echo "COMMIT-MSG HOOK"
msg() { printf '%s\n' "$1" > "$TMP/m"; App/Packages/PES/hooks/commit-msg "$TMP/m"; }
expect 0 "feat: subject"                    msg "feat: add search"
expect 0 "scoped fix(ci):"                  msg "fix(ci): normalize PEM key"
expect 0 "release: passthrough"             msg "release: 1.0.0"
expect 0 "merge commits ignored"            msg "Merge branch 'main'"
expect 1 "no type prefix"                   msg "updated some stuff"
expect 1 "unknown type"                     msg "wip: poking at things"

echo ""
echo "PRE-PUSH HOOK (branch names and tags; project checks skipped here)"
Z=0000000000000000000000000000000000000000
S=1111111111111111111111111111111111111111
push() { printf '%s\n' "$1" | PES_SKIP_CHECKS=1 App/Packages/PES/hooks/pre-push origin git@github.com:x/y.git; }
expect 1 "direct push to main blocked"      push "refs/heads/main $S refs/heads/main $Z"
expect 1 "deleting main blocked"            push "refs/heads/main $Z refs/heads/main $S"
expect 0 "release/X.Y.Z allowed"            push "refs/heads/release/1.2.3 $S refs/heads/release/1.2.3 $Z"
expect 1 "release/1.2 blocked"              push "refs/heads/release/1.2 $S refs/heads/release/1.2 $Z"
expect 0 "feature branch allowed"           push "refs/heads/feat/x $S refs/heads/feat/x $Z"
expect 1 "unknown branch name blocked"      push "refs/heads/random $S refs/heads/random $Z"
expect 1 "any local branch pushed as an unknown name" push "refs/heads/feat/a $S refs/heads/weird $Z"
expect 1 "tags are not pushed by hand"      push "refs/tags/v1.2.3 $S refs/tags/v1.2.3 $Z"

echo ""
echo "WORKFLOWS"
for f in .github/workflows/*.yml; do
  expect 0 "$(basename "$f") parses" ruby -ryaml -e "YAML.safe_load(File.read('$f'), aliases: true)"
done
unpinned=$(grep -rh "uses:" .github/workflows/ | grep -vcE "@[0-9a-f]{40} # v")
expect 0 "every action pinned to a SHA"     test "$unpinned" = "0"
outside=$(grep -rhE "uses: *erbittuu-studio/|secrets\.[A-Za-z_]+" .github/workflows/ | grep -vc "secrets.GITHUB_TOKEN")
expect 0 "self-contained: no other repo, no secret" test "$outside" = "0"
expect 0 "./build parses"                   python3 -m py_compile App/Packages/PES/ci/build.py

echo ""
echo "──────────────────────────────────"
printf "  %d passed, %d failed\n\n" "$PASS" "$FAIL"
[ "$FAIL" = "0" ]
