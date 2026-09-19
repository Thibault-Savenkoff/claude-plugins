# Shared helpers for the jev-guard hooks. Sourced, never executed directly.
#
# No jq, no python: the same constraint as git-sync, so the plugin runs on any
# machine that has git, sh, awk and curl. The API's answer has a fixed shape,
# which is what makes the sed extraction below tolerable.

JG_URL=${JEV_GUARD_API_URL:-https://api.typesafe.ai/v1/systemone}

# jg_config <name> [default] -- read jev-guard.<name> (repo, then global).
jg_config() {
  _v=$(git config --get "jev-guard.$1" 2>/dev/null || true)
  if [ -n "$_v" ]; then printf '%s' "$_v"; else printf '%s' "${2-}"; fi
}

# jg_mode -- off | warn (default) | strict. Anything unrecognised reads as warn:
# a typo must never turn blocking on.
jg_mode() {
  case "$(jg_config mode warn)" in
    off) echo off ;; strict) echo strict ;; *) echo warn ;;
  esac
}

# jg_active -- inside a repo, not switched off, and the user brought a key.
# Each user pays for their own calls; without a key the plugin does nothing.
jg_active() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
  [ "$(jg_mode)" != off ] || return 1
  [ -n "${TYPESAFE_API_KEY:-}" ]
}

jg_dir() { _d="$(git rev-parse --git-dir)/jev-guard"; mkdir -p "$_d/cache"; printf '%s' "$_d"; }

jg_log() { printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$(printf '%s' "$1" | tr '\n' ' ')" >> "$(jg_dir)/error.log"; }

# jg_excluded <path> -- files that are never sent to the API: untracked
# gitignored ones (they never travel) and the user's jev-guard.exclude globs.
# No --no-index: a tracked file that matches .gitignore still travels with a
# checkpoint, so it has to be scanned.
jg_excluded() {
  git check-ignore -q -- "$1" 2>/dev/null && return 0
  # A pipe, not `for _g in $(...)`: that would glob-expand the patterns
  # against the current directory before they ever reach `case`.
  git config --get-all jev-guard.exclude 2>/dev/null | {
    while read -r _g; do
      # shellcheck disable=SC2254
      case "$1" in $_g) exit 0 ;; esac
    done
    exit 1
  }
}

# jg_added <base> <tree|""> <path> -- the lines the change adds to <path>.
# An empty <tree> means the work tree. Binary diffs have no "+" lines, so they
# come out empty and are skipped by the caller.
jg_added() {
  if [ -n "$2" ]; then
    git diff --no-color "$1" "$2" -- "$3" 2>/dev/null
  elif git ls-files --error-unmatch -- "$3" >/dev/null 2>&1; then
    git diff --no-color "$1" -- "$3" 2>/dev/null
  else
    git diff --no-color --no-index /dev/null "$3" 2>/dev/null
  fi | sed -n '/^+++ /d; s/^+//p'
}

# jg_esc -- stdin to a JSON string body. tr and sed rather than awk's gsub:
# how gsub treats backslashes in the replacement differs between awks (busybox
# left quotes unescaped), and a broken request fails silently.
jg_esc() {
  _t=$(printf '\t')
  tr -d '\000-\010\013-\037' |
    sed "s/\\\\/\\\\\\\\/g; s/\"/\\\\\"/g; s/$_t/\\\\t/g" |
    awk 'BEGIN { ORS = "" } { if (NR > 1) print "\\n"; print }'
}

# jg_ask <path> <text> -- ask Jev about the lines <text> added to <path>. The
# path goes in the state too: "is this a build artifact" is half a question
# without it. Prints "noul choice confidence", or
# returns 1 on any failure (logged, never shown: a guard must not get in the
# way of the work it guards). Answers are cached by content, so a file scanned
# at edit time costs nothing again at checkpoint time.
jg_ask() {
  _key=$( { printf '%s\n%s' "$1" "$2"; cat "${CLAUDE_PLUGIN_ROOT}/hooks/questions.json"; } | git hash-object --stdin)
  _c="$(jg_dir)/cache/$_key"
  if [ -f "$_c" ]; then cat "$_c"; return 0; fi
  # After a failure, stay quiet for a minute instead of paying the 2 s timeout
  # on every file: git-sync's whole Stop hook has only 15 s.
  _down="$(jg_dir)/api-down"
  if [ -n "$(find "$_down" -mmin -1 2>/dev/null)" ]; then return 1; fi
  _body=$(printf '{"model":"jev-latest","state":{"path":"%s","added_lines":"%s"},"questions":%s}' \
            "$(printf '%s' "$1" | jg_esc)" "$(printf '%s' "$2" | jg_esc)" "$(cat "${CLAUDE_PLUGIN_ROOT}/hooks/questions.json")")
  # One try, two seconds: a hook is no place for retries. Only a network error
  # or a 5xx means the service is down; a 4xx is about this one request (odd
  # encoding, too big), and must not switch the guard off for other files.
  if ! _r=$(printf '%s' "$_body" | curl -sS --max-time 2 -w '\n%{http_code}' \
              -H "Authorization: Bearer $TYPESAFE_API_KEY" \
              -H "Content-Type: application/json" \
              --data-binary @- "$JG_URL" 2>&1); then
    jg_log "api: $_r"; : > "$_down"; return 1
  fi
  _code=$(printf '%s' "$_r" | tail -n 1)
  _r=$(printf '%s' "$_r" | sed '$d' | tr -d '\n\r\t ')
  case "$_code" in
    5*) jg_log "api: HTTP $_code $_r"; : > "$_down"; return 1 ;;
    4*) jg_log "api: HTTP $_code $_r"; return 1 ;;
  esac
  _n=$(printf '%s' "$_r" | sed -n 's/.*"secret":{[^}]*"noul":\([0-9.eE+-]*\).*/\1/p')
  _k=$(printf '%s' "$_r" | sed -n 's/.*"choice":"\([a-z]*\)".*/\1/p')
  _f=$(printf '%s' "$_r" | sed -n 's/.*"confidence":\([0-9.eE+-]*\).*/\1/p')
  if [ -z "$_n" ]; then jg_log "unexpected response: $_r"; return 1; fi
  printf '%s %s %s\n' "$_n" "${_k:-unknown}" "${_f:-0}" | tee "$_c"
}

# jg_prob <name> <default> -- a threshold, or the default unless it is a plain
# number in [0, 1]. "0,9" must not read as 0 (block everything) or 9 (never).
jg_prob() {
  _v=$(jg_config "$1" "$2")
  case "$_v" in 0 | 1 | 0.[0-9]* | 1.0*) ;; *) _v=$2 ;; esac
  case "$_v" in *[!0-9.]* | *.*.*) _v=$2 ;; esac
  case "$_v" in 1.*[1-9]*) _v=$2 ;; esac
  printf '%s' "$_v"
}

# jg_decide <noul> <kind> <confidence> -- block | warn | artifact | pass.
# Thresholds are per question type on purpose: a Noul threshold means nothing
# for a Choice. The defaults are guesses until calibrated (spec section 9).
jg_decide() {
  awk -v p="$1" -v k="$2" -v c="$3" -v m="$(jg_mode)" \
      -v b="$(jg_prob blockThreshold 0.90)" -v w="$(jg_prob warnThreshold 0.60)" \
      -v a="$(jg_prob artifactConfidence 0.80)" 'BEGIN {
    if (p + 0 >= b + 0) print (m == "strict" ? "block" : "warn")
    else if (p + 0 >= w + 0) print "warn"
    else if (k == "artifact" && c + 0 >= a + 0) print "artifact"
    else print "pass"
  }'
}

# jg_scan <base> <tree|""> <path> -- one report line, "<verdict>\t<path>\t<why>",
# or nothing when the file is skipped or the API could not answer.
jg_scan() {
  jg_excluded "$3" && return 0
  _add=$(jg_added "$1" "$2" "$3")
  [ -n "$_add" ] || return 0
  [ "$(printf '%s' "$_add" | wc -c)" -le $(( $(jg_config maxKb 64) * 1024 )) ] || return 0
  # The deterministic scanner goes first: a known pattern needs no model, and
  # Jev reads the diff as data it can be argued with (spec section 5).
  # Only exit 42 means a leak: gitleaks also exits 1 on its own errors (an old
  # version without `stdin`), and that must not flag every file as a secret.
  if command -v gitleaks >/dev/null 2>&1 &&
     { printf '%s\n' "$_add" | gitleaks stdin --no-banner -l error --exit-code 42 >/dev/null 2>&1; [ $? -eq 42 ]; }; then
    printf '%s\t%s\t%s\n' "$([ "$(jg_mode)" = strict ] && echo block || echo warn)" "$3" "gitleaks"
    return 0
  fi
  _ans=$(jg_ask "$3" "$_add") || return 0
  set -- "$1" "$2" "$3" $_ans
  _v=$(jg_decide "$4" "$5" "$6")
  case "$_v" in
    pass) ;;
    artifact) printf 'artifact\t%s\tlooks generated (%s)\n' "$3" "$6" ;;
    *) printf '%s\t%s\tsecret p=%s\n' "$_v" "$3" "$4" ;;
  esac
}

# jg_wire -- point git-sync's pre-checkpoint at this plugin, with the path of
# the version running now: an update moves CLAUDE_PLUGIN_ROOT, and a stale path
# would silently disarm the guard. Leaves any other tool's command alone.
jg_wire() {
  # The existence test turns a stale path (after an uninstall) into a no-op.
  _s="${CLAUDE_PLUGIN_ROOT}/hooks/pre-checkpoint.sh"
  _want="[ ! -f \"$_s\" ] || sh \"$_s\""
  _have=$(git config --get git-sync.preCheckpoint 2>/dev/null || true)
  case "$_have" in "" | *jev-guard*) ;; *) return 0 ;; esac
  [ "$_have" = "$_want" ] || git config git-sync.preCheckpoint "$_want"
}

# jg_report <lines> -- human-readable summary of jg_scan output.
jg_report() {
  printf '%s\n' "$1" | awk -F '\t' 'NF {
    if ($1 == "skipped") printf "- %s: %s\n", $2, $3
    else if ($1 == "artifact") printf "- %s: %s, consider git-sync ignore-patterns\n", $2, $3
    else printf "- %s: %s (%s)\n", $2, ($1 == "block" ? "BLOCKED, plaintext secret" : "possible plaintext secret"), $3
  }'
}
