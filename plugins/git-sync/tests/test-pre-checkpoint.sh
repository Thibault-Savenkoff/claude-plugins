#!/bin/sh
# git-sync.preCheckpoint: an add-on may veto a push with exit 2, and only then.
# Anything else it does -- fail, crash, vanish -- must not cost the checkpoint.
. "$(dirname "$0")/lib.sh"

new_world
pushed() { sync_branch_sha git-sync/main; }
reset() { git push -q origin :refs/heads/git-sync/main 2>/dev/null; rm -f .git/git-sync-*; }
if [ "${GS_SHELL:-sh}" = pwsh ]; then veto='Write-Output "nope"; exit 2'; fail='exit 1'
else veto='echo nope; exit 2'; fail='exit 1'; fi

it "exit 2 holds the checkpoint back and says why"
git config git-sync.preCheckpoint "$veto"
printf 'work\n' >> file.txt
out=$(run_stop)
assert_contains "$out" "nope" "stop message"
assert_contains "$out" "not pushed" "stop message"
assert_eq "" "$(pushed)" "remote checkpoint"

for cmd in "$fail" "no-such-command-anywhere"; do
  it "a failing or missing command ($cmd) does not stop the push"
  reset; git config git-sync.preCheckpoint "$cmd"
  run_stop >/dev/null
  [ -n "$(pushed)" ] || fail "checkpoint not pushed"
done

cleanup_world
exit $FAILURES
