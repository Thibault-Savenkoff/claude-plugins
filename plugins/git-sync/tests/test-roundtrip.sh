#!/bin/sh
# The whole point of the plugin: work left on machine A shows up on machine B,
# as uncommitted work, with nothing lost and nothing committed along the way.
. "$(dirname "$0")/lib.sh"

new_world
clone_b

it "A pushes a checkpoint (change, addition, deletion)"
printf 'line 2 from A\n' >> file.txt
printf 'new from A\n' > added.txt
printf 'to delete\n' > doomed.txt
git add doomed.txt && git commit -qm "add doomed" && git push -q origin main
rm doomed.txt
run_stop >/dev/null
[ -n "$(sync_branch_sha git-sync/main)" ] || fail "no checkpoint"

it "B receives A's work in its work tree"
cd "$B"
git pull -q --ff-only 2>/dev/null
out=$(run_start)
assert_contains "$(cat file.txt)" "line 2 from A" "file.txt modified"
[ -f added.txt ] || fail "added.txt did not arrive"
[ ! -f doomed.txt ] || fail "doomed.txt should have been removed"

it "B announces the arrival and describes what changed"
assert_contains "$out" "applied from git-sync/main" "systemMessage"
assert_contains "$out" "machineA" "origin machine"
assert_contains "$out" "added.txt" "the injected diff --stat"

it "on B the work is uncommitted and HEAD has not moved"
assert_eq "$(git rev-parse origin/main)" "$(git rev-parse HEAD)" "HEAD"
[ -n "$(git status --porcelain)" ] || fail "the work should be uncommitted"

it "B does not replay its own checkpoint"
printf 'ligne 3 depuis B\n' >> file.txt
run_stop >/dev/null
before=$(cat file.txt)
run_start >/dev/null
assert_eq "$before" "$(cat file.txt)" "file.txt after re-reading"

it "A refuses to overwrite B's checkpoint (stale lease)"
cd "$A"
printf 'ligne 4 depuis A\n' >> file.txt
out=$(run_stop)
assert_contains "$out" "another machine pushed" "message de refus"

it "and B's checkpoint is intact on the remote"
body=$(git fetch -q origin "refs/heads/git-sync/main:refs/probe/x" 2>/dev/null; git log -1 --format=%B refs/probe/x)
assert_contains "$body" "Git-Sync-Machine: machineB" "checkpoint owner"

cleanup_world

# Both refusals are tested on a fresh world: the previous cases deliberately
# leave A and B diverged, which would hide what we want to see.
new_world
clone_b

it "B refuses to apply over changes that are not its own"
# The distinction that matters: work you already pushed yourself can be
# overwritten without loss; work never pushed cannot.
printf 'work from A\n' >> file.txt
run_stop >/dev/null
cd "$B"; git pull -q --ff-only 2>/dev/null
printf 'local work never pushed\n' >> file.txt
out=$(run_start)
assert_contains "$out" "local changes" "refusal"
assert_contains "$(cat file.txt)" "local work never pushed" "B's work is intact"
assert_not_contains "$(cat file.txt)" "work from A" "nothing was applied"

it "B refuses when the bases diverge"
git checkout -q -- .; git clean -qfd 2>/dev/null
git commit -q --allow-empty -m "B's local commit"
out=$(run_start)
assert_contains "$out" "based on a different commit" "refusal"

cleanup_world
exit $FAILURES
