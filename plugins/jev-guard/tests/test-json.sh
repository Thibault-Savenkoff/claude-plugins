#!/bin/sh
# The two places where sh handles JSON by hand, without a parser: escaping the
# diff into the request, and reading the answer back out.
. "$(dirname "$0")/lib.sh"
new_world
. "$PLUGIN_ROOT/hooks/lib.sh"

it "escapes quotes, backslashes and tabs in the diff"
tab=$(printf '\t')
got=$(printf 'a "q" b\\c%sd\ne' "$tab" | jg_esc)
assert_eq 'a \"q\" b\\c\td\ne' "$got" "escaped"

it "drops carriage returns and other control characters"
got=$(printf 'x\r\001y\n' | jg_esc)
assert_eq 'xy' "$got" "escaped"

it "keeps non-ASCII text as is (valid JSON as UTF-8)"
assert_eq 'naïve' "$(printf 'naïve' | jg_esc)" "escaped"

# answer <json> -- feed one API response to jg_ask, print its parse.
answer() {
  printf '%s' "$1" > "$WORLD/r.json"
  JG_URL=$(furl "$WORLD/r.json")
  rm -rf .git/jev-guard/cache
  jg_ask f.txt "$(date +%N)"
}

it "reads the answer whatever the key order and spacing"
assert_eq "0.87 config 0.79" "$(answer '{"answers":{"secret":{"type":"noul","noul":0.87},"kind":{"type":"choice","choice":"config","probabilities":{"source":0.1,"config":0.85},"confidence":0.79}}}')" "canonical"
assert_eq "0.87 config 0.79" "$(answer '{
  "usage": {"input_tokens": 3},
  "answers": {
    "kind": { "confidence": 0.79, "probabilities": { "config": 0.85 }, "choice": "config", "type": "choice" },
    "secret": { "noul": 0.87, "type": "noul" }
  },
  "model": "jev-latest"
}')" "reordered, pretty-printed"

it "reads a probability in exponent notation"
assert_eq "1e-05 source 0.9" "$(answer '{"answers":{"secret":{"type":"noul","noul":1e-05},"kind":{"type":"choice","choice":"source","confidence":0.9}}}')"

it "refuses an answer without the secret probability"
answer '{"answers":{"kind":{"type":"choice","choice":"config","confidence":0.9}}}' >/dev/null && fail "accepted"

cleanup_world; exit $FAILURES
