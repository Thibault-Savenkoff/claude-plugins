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
rm -f .git/jev-guard/error.log; api down; printf 'a\n' > one.txt; printf 'b\n' > two.txt; printf 'c\n' > three.txt
scan >/dev/null
assert_eq 1 "$(grep -c . .git/jev-guard/error.log)" "API attempts logged"

it "a malformed answer does not switch the guard off for other files"
rm -f .git/jev-guard/error.log; api garbage
scan >/dev/null
[ ! -f .git/jev-guard/api-down ] || fail "api-down marker set by a bad answer"
assert_eq 3 "$(grep -c . .git/jev-guard/error.log)" "each file still tried"

it "past git-sync's deadline, files are listed as not scanned"
api secret
out=$(GS_DEADLINE=$(( $(date +%s) - 1 )) scan)
assert_contains "$out" "not scanned" "scan output"
rm one.txt two.txt three.txt

it "a threshold that is not a number in [0, 1] falls back to the default"
# decide <p> -- jg_decide / Jg-Decide, whichever implementation is under test.
decide() {
  if [ "${GS_SHELL:-sh}" = pwsh ]; then
    pwsh -NoProfile -Command ". '$PLUGIN_ROOT/hooks/lib.ps1'; Jg-Decide '$1' source 0.9"
  else (. "$PLUGIN_ROOT/hooks/lib.sh"; jg_decide "$1" source 0.9); fi
}
git config jev-guard.mode strict
git config jev-guard.blockThreshold 0,9; git config jev-guard.warnThreshold 0,3
assert_eq pass "$(decide 0.5)" "0.5, warn threshold back to 0.60"
assert_eq block "$(decide 0.95)" "0.95, block threshold back to 0.70"
git config jev-guard.blockThreshold 1.5
assert_eq block "$(decide 0.95)" "1.5 is out of range"
git config jev-guard.blockThreshold 0.5
assert_eq block "$(decide 0.55)" "a valid threshold still applies"

it "an addition over maxKb is still checked by gitleaks, and reported"
git config --unset jev-guard.blockThreshold; git config --unset jev-guard.warnThreshold
git config jev-guard.maxKb 1
awk 'BEGIN { for (i = 0; i < 200; i++) print "line " i }' > big.txt
assert_contains "$(PATH="$WORLD/bin:$PATH" scan)" "gitleaks" "with gitleaks"
assert_contains "$(PATH="/nonexistent:$PATH" scan | grep big.txt)" "not sent" "without gitleaks"
rm "$WORLD/bin/gitleaks" big.txt

it "a malformed maxKb falls back to the default, and does not stop the scan"
api secret; git config jev-guard.maxKb 64k
printf 'KEY=sk-live-abc\n' > conf.ini
assert_contains "$(scan)" "conf.ini" "scan output"
git config --unset jev-guard.maxKb

it "the wiring survives a plugin path with quotes, \$ and an apostrophe"
ODD="$WORLD/it's \$odd \"dir\"/jev-guard"
mkdir -p "$(dirname "$ODD")"; cp -R "$PLUGIN_ROOT" "$ODD"
git config --unset git-sync.preCheckpoint
CLAUDE_PLUGIN_ROOT="$ODD" edit conf.ini >/dev/null
reset; out=$(git_sync_stop)
assert_contains "$out" "not pushed" "stop message"
assert_eq "" "$(pushed)" "remote checkpoint"
rm conf.ini

cleanup_world; exit $FAILURES
