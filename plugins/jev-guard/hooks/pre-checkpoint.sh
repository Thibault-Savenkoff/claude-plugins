#!/bin/sh
# Called by git-sync (git-sync.preCheckpoint) just before it pushes a
# checkpoint, with GS_BASE and GS_TREE set. This is the safety net for what the
# edit hook cannot see: files written through Bash, or by the user.
#
# Contract: stdout is shown to the user; exit 2 stops the push; any other exit
# lets it through. So a crash here can never cost anyone their checkpoint.
# Located from $0, never from the environment: git-sync runs us with ITS
# CLAUDE_PLUGIN_ROOT still set.
CLAUDE_PLUGIN_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$CLAUDE_PLUGIN_ROOT/hooks/lib.sh"

jg_active || exit 0
git rev-parse -q --verify HEAD >/dev/null 2>&1 || exit 0
# Without GS_TREE (a manual /jev-guard:scan), scan the work tree against HEAD.
GS_BASE=${GS_BASE:-HEAD}

# ponytail: sequential calls, 2 s each at worst. Files already scanned at edit
# time come from the cache; if cold scans outgrow git-sync's 15 s Stop timeout,
# batch them into one request (spec 4, option B).
cd "$(git rev-parse --show-toplevel)" || exit 0
OUT=$( { if [ -n "${GS_TREE:-}" ]; then git diff --name-only --no-renames "$GS_BASE" "$GS_TREE"
         else git diff --name-only --no-renames HEAD; git ls-files -o --exclude-standard; fi; } |
       while read -r f; do jg_scan "$GS_BASE" "${GS_TREE:-}" "$f"; done)
[ -n "$OUT" ] || exit 0

case "$OUT" in
  *"block	"*|block*)
    printf 'jev-guard: checkpoint NOT pushed, plaintext secret found:\n%s\n' "$(jg_report "$OUT")"
    exit 2 ;;
esac
printf 'jev-guard:\n%s\n' "$(jg_report "$OUT")"
exit 0
