#!/bin/sh
# Every user brings their own key. Without one the plugin is inert, and quiet.
. "$(dirname "$0")/lib.sh"
new_world; api secret

it "does nothing without TYPESAFE_API_KEY"
printf 'KEY=sk-live-abc\n' > conf.ini
out=$(TYPESAFE_API_KEY= edit conf.ini)
assert_eq "" "$out" "hook output"
[ ! -d .git/jev-guard ] || fail "state written without a key"

it "does nothing in mode off"
git config jev-guard.mode off
assert_eq "" "$(edit conf.ini)" "hook output"

cleanup_world; exit $FAILURES
