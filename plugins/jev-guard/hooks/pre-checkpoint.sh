#!/bin/sh
# Called by git-sync (git-sync.preCheckpoint) just before it pushes a
# checkpoint, with GS_BASE and GS_TREE set. This is the safety net for what the
# edit hook cannot see: files written through Bash, or by the user.
#
# Contract: stdout is shown to the user; exit 75 stops the push; any other exit
# lets it through. So a crash here can never cost anyone their checkpoint.
# Located from $0, never from the environment: git-sync runs us with ITS
# CLAUDE_PLUGIN_ROOT still set.
CLAUDE_PLUGIN_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$CLAUDE_PLUGIN_ROOT/hooks/lib.sh"

jg_active || exit 0
git rev-parse -q --verify HEAD >/dev/null 2>&1 || exit 0
# Without GS_TREE (a manual /jev-guard:scan), scan the work tree against HEAD.
GS_BASE=${GS_BASE:-HEAD}

# ponytail: sequential calls, 2 s each at worst, cut off by the deadline below.
# time come from the cache; if cold scans outgrow git-sync's 15 s Stop timeout,
# batch them into one request (spec 4, option B).
cd "$(git rev-parse --show-toplevel)" || exit 0
# quotePath off: otherwise a path with non-ASCII characters comes out as
# "na\303\257ve.sh", matches no file, and is silently skipped.
# Time budget: git-sync's Stop hook is killed at 15 s, checkpoint and all, so
# stop starting scans once one more (gitleaks + a 2 s call) could overrun the
# deadline git-sync hands us. Run by hand, allow 8 s.
DEADLINE=${GS_DEADLINE:-$(( $(date +%s) + 8 ))}
OUT=$( { if [ -n "${GS_TREE:-}" ]; then git -c core.quotePath=false diff --name-only --no-renames "$GS_BASE" "$GS_TREE"
         else git -c core.quotePath=false diff --name-only --no-renames HEAD
              git -c core.quotePath=false ls-files -o --exclude-standard; fi; } |
       while IFS= read -r f; do
         if [ $(( $(date +%s) + 3 )) -gt "$DEADLINE" ]; then printf 'skipped\t%s\tnot scanned, time budget\n' "$f"; continue; fi
         jg_scan "$GS_BASE" "${GS_TREE:-}" "$f"
       done)
[ -n "$OUT" ] || exit 0

# Anchored at line start: a path ending in "block" must not match.
if printf '%s\n' "$OUT" | grep -q "^block$(printf '\t')"; then
  printf 'jev-guard: checkpoint NOT pushed, plaintext secret found:\n%s\n' "$(jg_report "$OUT")"
  exit 75
fi
printf 'jev-guard:\n%s\n' "$(jg_report "$OUT")"
exit 0
