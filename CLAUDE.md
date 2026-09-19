## Current state

_Updated 2026-09-19._

### Decisions
- jev-guard (spec in `/root/jev-guard-spec.md` on srv-tsa) hooks two places:
  PostToolUse on Edit|Write (warns Claude at write time) and git-sync's new `git-sync.preCheckpoint`
  (last check before push, also catches files written via Bash).
- Why not a jev-guard Stop hook: Claude Code runs plugin Stop hooks in parallel, so it cannot gate
  git-sync's push; the secret would already be on the remote. Touching git-sync was accepted by the user.
- preCheckpoint contract: exit 75 vetoes the push, anything else lets it through. Not 2: dash/busybox `sh` exit 2 on a missing script, which bricked git-sync after a jev-guard update/uninstall. git-sync passes `GS_DEADLINE` so the scan leaves time to push.
- Secret thresholds measured with `plugins/jev-guard/tests/calibrate.sh` (real API, 49 generated cases x2): warn 0.60, block 0.70, 24/24 caught, 0 false alarms. Default mode still `warn` (user has not decided on `strict` default).
- The `secret` question wording matters more than thresholds: v1 let "this is a fake secret" comments pull real keys to ~0.53; v2 says such comments do not change the answer (-> >= 0.76). Rerun calibrate.sh after any questions.json change.
- Each user brings their own `TYPESAFE_API_KEY`; without it the plugin is inert.
- All text in the repo is English, no exceptions (user rule) — except quoted legacy identifiers like `## État courant` in git-sync's upgrade notes.
- No test framework (no bats/Pester): plain sh test scripts, run against both sh and pwsh hooks, no network.

### In flight
- On main: jev-guard 0.2.0, git-sync 2.2.0. Nothing pending on a branch.
- Not done: test on real Windows / PowerShell 5.1; `artifactConfidence` (0.80) still uncalibrated;
  decide whether `strict` becomes the default; gitleaks not installed on srv-tsa.

### Traps
- awk `gsub` backslash handling differs between awks (busybox left `"` unescaped) — JSON escaping uses tr/sed.
- In git-sync's PowerShell, running preCheckpoint as an in-process scriptblock let an `exit` kill the whole hook;
  it now runs in a child PowerShell with `; exit $LASTEXITCODE` to keep the native exit code.
- pre-checkpoint scripts must locate themselves from `$0`/`$PSScriptRoot`: git-sync calls them with its own `CLAUDE_PLUGIN_ROOT` set.
- `lib.sh` reads `JEV_GUARD_API_URL` once at source time; tests that change it afterwards must set `JG_URL`.
