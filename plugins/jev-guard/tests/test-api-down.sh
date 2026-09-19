#!/bin/sh
# An API that is down, slow or answering garbage must cost nothing: no noise,
# and above all no lost checkpoint.
. "$(dirname "$0")/lib.sh"
new_world

for mode in down garbage; do
  it "API $mode: the edit hook stays silent and logs"
  api $mode; git config jev-guard.mode strict
  printf 'KEY=sk-live-abc\n' > conf.ini
  assert_eq "" "$(edit conf.ini)" "hook output"
  [ -s .git/jev-guard/error.log ] || fail "nothing logged"

  it "API $mode: git-sync still pushes the checkpoint, even in strict"
  git_sync_stop >/dev/null
  [ -n "$(pushed)" ] || fail "checkpoint not pushed"
  git push -q origin :refs/heads/git-sync/main 2>/dev/null; rm -f .git/git-sync-*
done

cleanup_world; exit $FAILURES
