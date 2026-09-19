# Test harness for jev-guard. No test talks to the real API: the endpoint is
# pointed at a fixture file (curl reads file:// URLs), or at a closed port.

PLUGIN_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
GS_ROOT="$PLUGIN_ROOT/../git-sync"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
export TYPESAFE_API_KEY=test-key
FAILURES=0
CURRENT=""

fail() { printf '  FAIL %s\n       %s\n' "$CURRENT" "$1"; FAILURES=$((FAILURES + 1)); }
assert_eq() { [ "$1" = "$2" ] || fail "${3:-value}: expected [$1], got [$2]"; }
assert_contains() { case "$1" in *"$2"*) ;; *) fail "${3:-output}: [$2] missing from [$1]" ;; esac; }
it() { CURRENT="$1"; printf '  - %s\n' "$1"; }

# api <fixture|down> -- what the next calls will get back.
api() {
  if [ "$1" = down ]; then export JEV_GUARD_API_URL=http://127.0.0.1:9
  else export JEV_GUARD_API_URL="file://$PLUGIN_ROOT/tests/fixtures/$1.json"; fi
  rm -rf "$A/.git/jev-guard/cache" "$A/.git/jev-guard/api-down"
}

# new_world -- bare remote + clone A with one commit, cd into A.
new_world() {
  skip_unless_shell_available
  WORLD=$(mktemp -d); REMOTE="$WORLD/remote.git"; A="$WORLD/A"
  git init -q --bare "$REMOTE"; git -C "$REMOTE" symbolic-ref HEAD refs/heads/main
  git init -q -b main "$A"; cd "$A" || exit 1
  git config user.email a@test; git config user.name A
  git remote add origin "$REMOTE"
  printf 'x = 1\n' > app.py; git add -A && git commit -qm init
  git push -q origin main 2>/dev/null
  git branch -q --set-upstream-to=origin/main main 2>/dev/null
}
cleanup_world() { [ -n "${WORLD:-}" ] && rm -rf "$WORLD"; cd "$PLUGIN_ROOT" || exit 1; }

# edit <file> -- run the PostToolUse hook as Claude Code would after a Write.
edit() {
  _p="{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$PWD/$1\",\"content\":\"...\"}}"
  if [ "${GS_SHELL:-sh}" = pwsh ]; then
    printf '%s' "$_p" | pwsh -NoProfile -File "$PLUGIN_ROOT/hooks/post-edit.ps1" 2>&1
  else
    printf '%s' "$_p" | sh "$PLUGIN_ROOT/hooks/post-edit.sh" 2>&1
  fi
}

# git_sync_stop -- git-sync's real Stop hook, with jev-guard wired in.
git_sync_stop() {
  if [ "${GS_SHELL:-sh}" = pwsh ]; then
    CLAUDE_PLUGIN_ROOT="$GS_ROOT" pwsh -NoProfile -File "$GS_ROOT/hooks/stop-sync.ps1" 2>&1
  else
    CLAUDE_PLUGIN_ROOT="$GS_ROOT" sh "$GS_ROOT/hooks/stop-sync.sh" 2>&1
  fi
}
pushed() { git ls-remote "$REMOTE" refs/heads/git-sync/main | cut -f1; }

skip_unless_shell_available() {
  if [ "${GS_SHELL:-sh}" = pwsh ] && ! command -v pwsh >/dev/null 2>&1; then
    printf '  (pwsh not installed -- cases skipped)\n'; exit 0
  fi
}
