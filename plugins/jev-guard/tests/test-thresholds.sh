#!/bin/sh
# Decisions at the edges of each threshold. Pure arithmetic, so it runs
# against lib.sh directly -- both hook implementations must agree with it.
. "$(dirname "$0")/lib.sh"
new_world
. "$PLUGIN_ROOT/hooks/lib.sh"

it "warn mode never blocks"
assert_eq warn "$(jg_decide 0.99 config 0.9)"
assert_eq warn "$(jg_decide 0.60 source 0.9)"
assert_eq pass "$(jg_decide 0.59 source 0.9)"

it "strict blocks at the block threshold, not below"
git config jev-guard.mode strict
assert_eq block "$(jg_decide 0.90 config 0.9)"
assert_eq warn "$(jg_decide 0.89 config 0.9)"

it "a typo in the mode never turns blocking on"
git config jev-guard.mode stirct
assert_eq warn "$(jg_decide 0.99 config 0.9)"

it "artifact hint needs its own confidence, and loses to a secret"
assert_eq artifact "$(jg_decide 0.1 artifact 0.80)"
assert_eq pass "$(jg_decide 0.1 artifact 0.79)"
assert_eq warn "$(jg_decide 0.7 artifact 0.99)"

it "thresholds are configurable"
git config jev-guard.warnThreshold 0.3
assert_eq warn "$(jg_decide 0.35 source 0.9)"

cleanup_world; exit $FAILURES
