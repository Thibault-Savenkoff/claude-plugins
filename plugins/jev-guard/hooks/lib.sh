# Shared helpers for the jev-guard hooks. Sourced, never executed directly.
#
# No jq, no python: the same constraint as git-sync, so the plugin runs on any
# machine that has git, sh, awk and curl. The API's answer has a fixed shape,
# which is what makes the awk extraction below tolerable.
#
# Process count matters: under Git Bash on Windows every fork costs tens of
# milliseconds, and the checkpoint scan has a few seconds for all files. So the
# config, the paths and the questions are read once (jg_load), and each file
# costs about a dozen processes, not forty.

JG_URL=${JEV_GUARD_API_URL:-https://api.typesafe.ai/v1/systemone}
JG_TAB=$(printf '\t')

# jg_config <name> [default] -- read jev-guard.<name> (repo, then global).
jg_config() {
  _v=$(git config --get "jev-guard.$1" 2>/dev/null || true)
  if [ -n "$_v" ]; then printf '%s' "$_v"; else printf '%s' "${2-}"; fi
}

# jg_valid_prob <value> <default> -- sets JG_V to <value> if it is a plain
# number in [0, 1], else to <default>. "0,9" must not read as 0 (block
# everything) or 9 (block nothing).
jg_valid_prob() {
  JG_V=$1
  case "$JG_V" in 0 | 1 | 0.[0-9]* | 1.0*) ;; *) JG_V=$2 ;; esac
  case "$JG_V" in *[!0-9.]* | *.*.*) JG_V=$2 ;; esac
  case "$JG_V" in 1.*[1-9]*) JG_V=$2 ;; esac
}

# jg_load -- read everything that does not change during a scan, once. Sets
# JG_MODE, JG_WARN, JG_BLOCK, JG_ART, JG_MAXKB, JG_EXCLUDES, JG_DIR, JG_Q, JG_NOW.
jg_load() {
  JG_LOADED=1
  _mode=warn; _w=; _b=; _a=; _kb=; JG_EXCLUDES=
  # --get-regexp prints keys lowercased; a later value overrides an earlier
  # one, as it does for `git config --get`.
  _cfg=$(git config --get-regexp '^jev-guard\.' 2>/dev/null)
  _ifs=$IFS; IFS='
'
  for _line in $_cfg; do
    _k=${_line%% *}; _v=${_line#* }
    case "$_k" in
      jev-guard.mode) _mode=$_v ;;
      jev-guard.warnthreshold) _w=$_v ;;
      jev-guard.blockthreshold) _b=$_v ;;
      jev-guard.artifactconfidence) _a=$_v ;;
      jev-guard.maxkb) _kb=$_v ;;
      jev-guard.exclude) JG_EXCLUDES="$JG_EXCLUDES$_v
" ;;
    esac
  done
  IFS=$_ifs
  # A typo must never turn blocking on: anything unrecognised reads as warn.
  case "$_mode" in off | strict) JG_MODE=$_mode ;; *) JG_MODE=warn ;; esac
  jg_valid_prob "$_w" 0.60; JG_WARN=$JG_V
  jg_valid_prob "$_b" 0.70; JG_BLOCK=$JG_V
  jg_valid_prob "$_a" 0.80; JG_ART=$JG_V
  case "$_kb" in "" | *[!0-9]*) JG_MAXKB=64 ;; *) JG_MAXKB=$_kb ;; esac
  JG_DIR="$(git rev-parse --absolute-git-dir 2>/dev/null)/jev-guard"
  JG_Q=$(cat "${CLAUDE_PLUGIN_ROOT}/hooks/questions.json")
  JG_NOW=$(date +%s)
}

# jg_mode -- off | warn (default) | strict.
jg_mode() { [ -n "${JG_LOADED:-}" ] || jg_load; printf '%s\n' "$JG_MODE"; }

# jg_active -- inside a repo, the user brought a key, and not switched off.
# Each user pays for their own calls; without a key the plugin does nothing,
# not even create its directory.
jg_active() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
  [ -n "${TYPESAFE_API_KEY:-}" ] || return 1
  jg_load
  [ "$JG_MODE" != off ]
}

# jg_dir -- create the state directory the first time something is written.
jg_dir() { [ -d "$JG_DIR/cache" ] || mkdir -p "$JG_DIR/cache"; }

jg_log() {
  jg_dir
  printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$(printf '%s' "$1" | tr '\n' ' ')" >> "$JG_DIR/error.log"
}

# jg_excluded <path> -- files that are never sent to the API: untracked
# gitignored ones (they never travel) and the user's jev-guard.exclude globs.
# No --no-index: a tracked file that matches .gitignore still travels with a
# checkpoint, so it has to be scanned.
jg_excluded() {
  git check-ignore -q -- "$1" 2>/dev/null && return 0
  # set -f: the patterns must reach `case` as patterns, not be glob-expanded
  # against the current directory first.
  _ifs=$IFS; IFS='
'; set -f
  for _g in $JG_EXCLUDES; do
    # shellcheck disable=SC2254
    case "$1" in $_g) IFS=$_ifs; set +f; return 0 ;; esac
  done
  IFS=$_ifs; set +f
  return 1
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
  tr -d '\000-\010\013-\037' |
    sed "s/\\\\/\\\\\\\\/g; s/\"/\\\\\"/g; s/$JG_TAB/\\\\t/g" |
    awk 'BEGIN { ORS = "" } { if (NR > 1) print "\\n"; print }'
}

# jg_ask <path> <text> -- ask Jev about the lines <text> added to <path>. The
# path goes in the state too: "is this a build artifact" is half a question
# without it. Sets JG_ANS to "noul choice confidence" and prints it, or
# returns 1 on any failure (logged, never shown: a guard must not get in the
# way of the work it guards). Answers are cached by content, so a file scanned
# at edit time costs nothing again at checkpoint time.
jg_ask() {
  [ -n "${JG_LOADED:-}" ] || jg_load
  _key=$(printf '%s\n%s%s' "$1" "$2" "$JG_Q" | git hash-object --stdin)
  _c="$JG_DIR/cache/$_key"
  if [ -f "$_c" ]; then read -r JG_ANS < "$_c"; printf '%s\n' "$JG_ANS"; return 0; fi
  # After a failure, stay quiet for a minute instead of paying the 2 s timeout
  # on every file: git-sync's whole Stop hook has only 15 s.
  _down="$JG_DIR/api-down"
  if [ -f "$_down" ]; then
    _t=; read -r _t < "$_down" || true
    case "$_t" in "" | *[!0-9]*) _t=0 ;; esac
    [ $(( JG_NOW - _t )) -ge 60 ] || return 1
  fi
  # Paths rarely need escaping; skip the three processes when they do not.
  case "$1" in *[\\\"]* | *"$JG_TAB"*) _p=$(printf '%s' "$1" | jg_esc) ;; *) _p=$1 ;; esac
  _body=$(printf '{"model":"jev-latest","state":{"path":"%s","added_lines":"%s"},"questions":%s}' \
            "$_p" "$(printf '%s' "$2" | jg_esc)" "$JG_Q")
  # One try, two seconds: a hook is no place for retries. Only a network error
  # or a 5xx means the service is down; a 4xx is about this one request (odd
  # encoding, too big), and must not switch the guard off for other files.
  if ! _r=$(printf '%s' "$_body" | curl -sS --max-time 2 -w '\n%{http_code}' \
              -H "Authorization: Bearer $TYPESAFE_API_KEY" \
              -H "Content-Type: application/json" \
              --data-binary @- "$JG_URL" 2>&1); then
    jg_log "api: $_r"; jg_dir; printf '%s\n' "$JG_NOW" > "$_down"; return 1
  fi
  # One awk for the whole answer: the HTTP code (last line), then the three
  # values. match/substr only -- no gsub replacement strings, whose backslash
  # handling differs between awks.
  # shellcheck disable=SC2046
  set -- $(printf '%s' "$_r" | awk '
    { l[NR] = $0 }
    END {
      b = ""; for (i = 1; i < NR; i++) b = b l[i]
      gsub(/[ \t\r]/, "", b)
      n = "-"; k = "unknown"; f = "0"
      if (match(b, /"secret":[{][^}]*"noul":[0-9.eE+-]+/)) {
        s = substr(b, RSTART, RLENGTH); sub(/.*"noul":/, "", s); n = s }
      if (match(b, /"choice":"[a-z]*"/)) k = substr(b, RSTART + 10, RLENGTH - 11)
      if (match(b, /"confidence":[0-9.eE+-]+/)) f = substr(b, RSTART + 13, RLENGTH - 13)
      print l[NR], n, k, f, (b == "" ? "-" : b)
    }')
  case "$1" in
    5*) jg_log "api: HTTP $1 $5"; jg_dir; printf '%s\n' "$JG_NOW" > "$_down"; return 1 ;;
    4*) jg_log "api: HTTP $1 $5"; return 1 ;;
  esac
  if [ "$2" = - ]; then jg_log "unexpected response: $5"; return 1; fi
  JG_ANS="$2 $3 $4"
  jg_dir; printf '%s\n' "$JG_ANS" > "$_c"
  printf '%s\n' "$JG_ANS"
}

# jg_decide <noul> <kind> <confidence> -- block | warn | artifact | pass.
# Thresholds are per question type on purpose: a Noul threshold means nothing
# for a Choice. All defaults are measured (README, "Calibration").
jg_decide() {
  [ -n "${JG_LOADED:-}" ] || jg_load
  awk -v p="$1" -v k="$2" -v c="$3" -v m="$JG_MODE" \
      -v b="$JG_BLOCK" -v w="$JG_WARN" -v a="$JG_ART" 'BEGIN {
    if (p + 0 >= b + 0) print (m == "strict" ? "block" : "warn")
    else if (p + 0 >= w + 0) print "warn"
    else if (k == "artifact" && c + 0 >= a + 0) print "artifact"
    else print "pass"
  }'
}

# jg_scan <base> <tree|""> <path> -- one report line, "<verdict>\t<path>\t<why>",
# or nothing when the file is skipped or the API could not answer.
jg_scan() {
  [ -n "${JG_LOADED:-}" ] || jg_load
  jg_excluded "$3" && return 0
  _add=$(jg_added "$1" "$2" "$3")
  [ -n "$_add" ] || return 0
  # The deterministic scanner goes first: a known pattern needs no model, and
  # Jev reads the diff as data it can be argued with (spec section 5).
  # Only exit 42 means a leak: gitleaks also exits 1 on its own errors (an old
  # version without `stdin`), and that must not flag every file as a secret.
  if command -v gitleaks >/dev/null 2>&1 &&
     { printf '%s\n' "$_add" | gitleaks stdin --no-banner -l error --exit-code 42 >/dev/null 2>&1; [ $? -eq 42 ]; }; then
    printf '%s\t%s\t%s\n' "$([ "$JG_MODE" = strict ] && echo block || echo warn)" "$3" "gitleaks"
    return 0
  fi
  # maxKb limits what leaves the machine, so it gates the API call only, after
  # the local gitleaks pass. ${#} counts characters, not bytes: close enough
  # for a size cap.
  _sz=${#_add}
  if [ "$_sz" -gt $(( JG_MAXKB * 1024 )) ]; then
    printf 'skipped\t%s\tnot sent, %s KB added (maxKb %s)\n' "$3" $(( _sz / 1024 )) "$JG_MAXKB"
    return 0
  fi
  jg_ask "$3" "$_add" >/dev/null || return 0
  # shellcheck disable=SC2086
  set -- "$1" "$2" "$3" $JG_ANS
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
  # Escaped for the double quotes below: a path with " $ ` or \ in it would
  # otherwise make the command a syntax error, and silently disarm the guard.
  _s=$(printf '%s' "${CLAUDE_PLUGIN_ROOT}/hooks/pre-checkpoint.sh" | sed 's/[\\"$`]/\\&/g')
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
