#!/bin/sh
# What must never leave the machine. The API is pointed at a missing fixture:
# any call at all would leave a line in error.log.
. "$(dirname "$0")/lib.sh"
new_world
export JEV_GUARD_API_URL="file://$WORLD/no-such-fixture"
calls() { [ -s .git/jev-guard/error.log ] && echo yes || echo no; }

it "skips gitignored files"
printf '.env\n' > .gitignore; git add .gitignore; git commit -qm ignore
printf 'KEY=sk-live-abc\n' > .env
edit .env >/dev/null; assert_eq no "$(calls)" "API called"

it "skips jev-guard.exclude globs"
git config --add jev-guard.exclude 'private/*'
mkdir private; printf 'KEY=sk-live-abc\n' > private/notes.txt
edit private/notes.txt >/dev/null; assert_eq no "$(calls)" "API called"

it "skips files whose added text is over maxKb"
git config jev-guard.maxKb 1
awk 'BEGIN { for (i = 0; i < 200; i++) print "line " i }' > big.txt
edit big.txt >/dev/null; assert_eq no "$(calls)" "API called"

it "skips binaries"
printf '\000\001\002KEY=sk\n' > blob.bin
edit blob.bin >/dev/null; assert_eq no "$(calls)" "API called"

it "sends only the added lines, not the file"
api secret
printf 'OLD_SECRET_LINE\n' > app.py; git commit -qam base
printf 'NEW_LINE\n' >> app.py
. "$PLUGIN_ROOT/hooks/lib.sh"
assert_eq NEW_LINE "$(jg_added HEAD "" app.py)" "added lines"

cleanup_world; exit $FAILURES
