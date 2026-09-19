#!/bin/sh
# The two halves together: the edit hook talks to Claude, and git-sync's
# pre-checkpoint veto is the last line before anything leaves the machine.
. "$(dirname "$0")/lib.sh"
new_world

it "warn: Claude and the user are told, the checkpoint still goes"
api secret
printf 'KEY=sk-live-abc\n' > conf.ini
out=$(edit conf.ini)
assert_contains "$out" "possible plaintext secret" "edit hook"
assert_contains "$out" "additionalContext" "edit hook"
out=$(git_sync_stop)
assert_contains "$out" "jev-guard" "stop message"
[ -n "$(pushed)" ] || fail "checkpoint not pushed in warn mode"

it "strict: the edit hook blocks, and the checkpoint is held back"
git push -q origin :refs/heads/git-sync/main 2>/dev/null; rm -f .git/git-sync-*
git config jev-guard.mode strict
out=$(edit conf.ini)
assert_contains "$out" '"decision":"block"' "edit hook"
out=$(git_sync_stop)
assert_contains "$out" "not pushed" "stop message"
assert_eq "" "$(pushed)" "remote checkpoint"

it "strict: catches a file the edit hook never saw (written by Bash)"
rm conf.ini; printf 'TOKEN=ghp_live\n' > deploy.sh
out=$(git_sync_stop)
assert_contains "$out" "deploy.sh" "stop message"
assert_eq "" "$(pushed)" "remote checkpoint"

it "strict: a clean tree goes through"
rm deploy.sh; api clean; printf 'y = 2\n' >> app.py
git_sync_stop >/dev/null
[ -n "$(pushed)" ] || fail "clean checkpoint not pushed"

it "the wiring follows the plugin's current path"
assert_contains "$(git config git-sync.preCheckpoint)" "$PLUGIN_ROOT/hooks/pre-checkpoint" "preCheckpoint"

it "does not take over another tool's preCheckpoint"
git config git-sync.preCheckpoint "my-own-check"
edit app.py >/dev/null
assert_eq "my-own-check" "$(git config git-sync.preCheckpoint)"

it "manual scan (no GS_TREE) sees untracked and modified files"
git config --unset git-sync.preCheckpoint; api secret
printf 'TOKEN=ghp_live\n' > new.sh
if [ "${GS_SHELL:-sh}" = pwsh ]; then out=$(pwsh -NoProfile -File "$PLUGIN_ROOT/hooks/pre-checkpoint.ps1")
else out=$(sh "$PLUGIN_ROOT/hooks/pre-checkpoint.sh"); fi
assert_contains "$out" "new.sh" "scan output"

cleanup_world; exit $FAILURES
