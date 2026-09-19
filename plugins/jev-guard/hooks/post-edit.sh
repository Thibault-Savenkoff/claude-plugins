#!/bin/sh
# PostToolUse on Edit|Write|MultiEdit: scan the file Claude just wrote, while
# there is still time to fix it -- minutes before git-sync pushes anything.
. "${CLAUDE_PLUGIN_ROOT}/hooks/lib.sh"

# The one field we need from the hook payload. File paths with an escaped
# quote in them are not worth a JSON parser.
FILE=$(tr -d '\n' | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | sed 's/\\\\/\\/g')
[ -n "$FILE" ] && [ -f "$FILE" ] || exit 0
cd "$(dirname "$FILE")" 2>/dev/null || exit 0
jg_active || exit 0
git rev-parse -q --verify HEAD >/dev/null 2>&1 || exit 0

jg_wire
ROOT=$(git rev-parse --show-toplevel)
REL=${FILE#"$ROOT"/}
cd "$ROOT" || exit 0

OUT=$(jg_scan HEAD "" "$REL")
[ -n "$OUT" ] || exit 0
REPORT=$(jg_report "$OUT" | jg_esc)

case "$OUT" in
  block*)
    printf '{"decision":"block","reason":"jev-guard (strict): %s\\nRemove the secret from this file (read it from an environment variable instead) before continuing. git-sync will refuse to push a checkpoint while it is there."}\n' "$REPORT" ;;
  *)
    printf '{"systemMessage":"jev-guard: %s","hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"jev-guard flagged the file just written: %s\\nIf this is a real credential, move it to an environment variable. If it is a placeholder or test value, say so to the user and carry on."}}\n' "$REPORT" "$REPORT" ;;
esac
exit 0
