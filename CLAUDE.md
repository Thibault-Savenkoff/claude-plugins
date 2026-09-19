## Current state

_Updated 2026-09-19._

### Decisions
- jev-guard (branch `feat/jev-guard`, spec in `/root/jev-guard-spec.md` on srv-tsa) hooks two places:
  PostToolUse on Edit|Write (warns Claude at write time) and git-sync's new `git-sync.preCheckpoint`
  (last check before push, also catches files written via Bash).
- Why not a jev-guard Stop hook: Claude Code runs plugin Stop hooks in parallel, so it cannot gate
  git-sync's push; the secret would already be on the remote. Touching git-sync was accepted by the user.
- preCheckpoint contract: exit 2 vetoes the push, anything else (crash, missing command) lets it through.
- Default mode stays `warn`: thresholds (0.60 / 0.90) are uncalibrated guesses; revisit `strict` default after calibration.
- Each user brings their own `TYPESAFE_API_KEY`; without it the plugin is inert.
- All text in the repo is English, no exceptions (user rule) — except quoted legacy identifiers like `## État courant` in git-sync's upgrade notes.
- No test framework (no bats/Pester): plain sh test scripts, run against both sh and pwsh hooks, no network.

### In flight
- `feat/jev-guard` pushed (signed commits). No PR opened, not merged: the user reviews the diff from a local machine first.
- Not done: spec §8 adversarial test and §9 calibration (need a real key); `skills/review/SKILL.md` skipped;
  PowerShell hooks tested with pwsh 7 on Linux only, never on real Windows / PowerShell 5.1.

### Traps
- awk `gsub` backslash handling differs between awks (busybox left `"` unescaped) — JSON escaping uses tr/sed.
- In git-sync's PowerShell, running preCheckpoint as an in-process scriptblock let an `exit` kill the whole hook;
  it now runs in a child PowerShell with `; exit $LASTEXITCODE` to keep the native exit code.
- pre-checkpoint scripts must locate themselves from `$0`/`$PSScriptRoot`: git-sync calls them with its own `CLAUDE_PLUGIN_ROOT` set.
- `lib.sh` reads `JEV_GUARD_API_URL` once at source time; tests that change it afterwards must set `JG_URL`.
