---
description: Scan the uncommitted work in this repo for plaintext secrets now
allowed-tools: Bash(sh:*)
---

!`sh "${CLAUDE_PLUGIN_ROOT}/hooks/pre-checkpoint.sh"; echo "(exit $?)"`

Above is jev-guard's scan of every file that differs from HEAD, untracked ones
included. Empty output with exit 0 means nothing was flagged, or that jev-guard
is inactive here (no `TYPESAFE_API_KEY`, or mode off -- check with
/jev-guard:config).

For each flagged file, look at the added lines yourself and tell the user
whether it is a real credential or a placeholder. For a real one, propose
moving it to an environment variable. Do not print the secret's value.
