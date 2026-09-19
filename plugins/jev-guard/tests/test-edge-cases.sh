#!/bin/sh
# Cases a code review caught: each one let a secret through, or blocked for
# no reason, or cost a checkpoint.
. "$(dirname "$0")/lib.sh"
new_world
reset() { git push -q origin :refs/heads/git-sync/main 2>/dev/null; rm -f .git/git-sync-*; }
scan() {
  if [ "${GS_SHELL:-sh}" = pwsh ]; then pwsh -NoProfile -File "$PLUGIN_ROOT/hooks/pre-checkpoint.ps1"
  else sh "$PLUGIN_ROOT/hooks/pre-checkpoint.sh"; fi
}
edit app.py >/dev/null   # wires git-sync.preCheckpoint

it "warn mode: a path ending in 'block' does not veto the checkpoint"
api maybe; mkdir -p src; printf 'k = 1\n' > src/codeblock
git_sync_stop >/dev/null
[ -n "$(pushed)" ] || fail "checkpoint held back in warn mode"
rm -r src; reset

it "a tracked file that matches .gitignore is still scanned"
git config jev-guard.mode strict; api secret
printf '.env\n' > .gitignore; printf 'A=1\n' > .env
git add .gitignore && git add -f .env && git commit -qm env
printf 'KEY=sk-live-abc\n' >> .env
assert_contains "$(scan)" ".env" "scan output"
git reset -q --hard HEAD~1; rm -f .env

it "a path with non-ASCII characters is scanned, not skipped"
printf 'TOKEN=ghp_live\n' > "naïve.sh"
out=$(scan)
assert_contains "$out" "naïve.sh" "scan output"
rm "naïve.sh"

it "a failing gitleaks (old version, bad flag) does not flag everything"
mkdir -p "$WORLD/bin"; printf '#!/bin/sh\nexit 1\n' > "$WORLD/bin/gitleaks"; chmod +x "$WORLD/bin/gitleaks"
api clean; printf 'x = 2\n' >> app.py
assert_eq "" "$(PATH="$WORLD/bin:$PATH" scan)" "scan output"

it "gitleaks' leak exit code does flag"
printf '#!/bin/sh\nexit 42\n' > "$WORLD/bin/gitleaks"
assert_contains "$(PATH="$WORLD/bin:$PATH" scan)" "gitleaks" "scan output"
git checkout -q app.py

it "API down: one timeout, not one per file"
api down; printf 'a\n' > one.txt; printf 'b\n' > two.txt; printf 'c\n' > three.txt
scan >/dev/null
assert_eq 1 "$(grep -c . .git/jev-guard/error.log)" "API attempts logged"

cleanup_world; exit $FAILURES
