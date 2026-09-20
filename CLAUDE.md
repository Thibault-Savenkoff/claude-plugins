## Current state

_Updated 2026-09-20.

### Decisions
- jev-guard (spec in `/root/jev-guard-spec.md` on srv-tsa) hooks two places:
  PostToolUse on Edit|Write (warns Claude at write time) and git-sync's new `git-sync.preCheckpoint`
  (last check before push, also catches files written via Bash).
- Why not a jev-guard Stop hook: Claude Code runs plugin Stop hooks in parallel, so it cannot gate
  git-sync's push; the secret would already be on the remote. Touching git-sync was accepted by the user.
- preCheckpoint contract: exit 75 vetoes the push, anything else lets it through. Not 2: dash/busybox `sh` exit 2 on a missing script, which bricked git-sync after a jev-guard update/uninstall. git-sync passes `GS_DEADLINE` so the scan leaves time to push.
- Secret thresholds measured with `plugins/jev-guard/tests/calibrate.sh` (real API, 49 generated cases x2): warn 0.60, block 0.70, 24/24 caught, 0 false alarms. Default mode `strict` since 0.3.0 (user decision): in `warn` a secret still reaches the remote, which forces a key rotation; a false alarm costs far less. If false alarms show up, raise blockThreshold rather than going back to warn.
- The `secret` question wording matters more than thresholds: v1 let "this is a fake secret" comments pull real keys to ~0.53; v2 says such comments do not change the answer (-> >= 0.76). Rerun calibrate.sh after any questions.json change.
- Each user brings their own `TYPESAFE_API_KEY`; without it the plugin is inert.
- All text in the repo is English, no exceptions (user rule) — except quoted legacy identifiers like `## État courant` in git-sync's upgrade notes.
- No test framework (no bats/Pester): plain sh test scripts, run against both sh and pwsh hooks, no network.

### In flight
- On main: jev-guard 0.3.0 (strict default), installed on srv-tsa; Windows still on 0.2.2 until updated. git-sync 2.2.0.
- Verified live on Windows 11 / PS 5.1 (2026-09-19): edit-time block, checkpoint veto, and clean checkpoint push all work.
- Windows timing (0.2.2, 5 files): 8.1 s -> 2.9 s, all scanned; jev-guard suite green under Git Bash.
- macOS verified (2026-09-20, git 2.54 Apple): both suites green after two test-harness fixes; BSD awk parses answers fine. The .ps1 hooks verified in Windows Sandbox (2026-09-20, PS 5.1, no Git Bash, MinGit): warn message, strict block, checkpoint veto exit 75. Nothing left untested.
- Verified live (2026-09-19): hooks fire in a real headless Claude Code session (PostToolUse block reaches
  Claude; git-sync Stop pushes a clean checkpoint and vetoes one with a secret); a 401 is logged without
  disabling the guard; real gitleaks 8.30.1 (installed on srv-tsa) exits 42 on leaks; artifact hint measured.

### Traps
- awk `gsub` backslash handling differs between awks (busybox left `"` unescaped) — JSON escaping uses tr/sed.
- In git-sync's PowerShell, running preCheckpoint as an in-process scriptblock let an `exit` kill the whole hook;
  it now runs in a child PowerShell with `; exit $LASTEXITCODE` to keep the native exit code.
- pre-checkpoint scripts must locate themselves from `$0`/`$PSScriptRoot`: git-sync calls them with its own `CLAUDE_PLUGIN_ROOT` set.
- Windows: Claude Code passes `C:\...` paths, git returns `C:/...`; never derive repo-relative paths by string stripping, use `git rev-parse --show-prefix`. On Windows with Git Bash, Claude Code runs the sh hooks, not the .ps1 ones (confirmed by the wired preCheckpoint command): the .ps1 path only matters without Git Bash.
- Git Bash on Windows: ~2.5 s per scanned file before 0.2.2 (process start-up); every fork counts. curl there cannot read file:///c/... URLs, only file:///C:/... (tests use furl()). The user's terminal injects an invisible U+0083 before the first pasted line: give them a sacrificial `true` first line.
- `lib.sh` reads `JEV_GUARD_API_URL` once at source time; tests that change it afterwards must set `JG_URL`.
- A var prefixed onto a shell *function* call (`X=1 my_func`) survives the call in bash (macOS /bin/sh) but not in dash: tests must export and unset it instead. Same class: a guard called only from `new_world` never runs in tests that build their world inline.
