---
description: Show and change jev-guard settings (mode, thresholds, exclusions)
allowed-tools: Bash(git config:*), Bash(git rev-parse:*), AskUserQuestion
---

Current jev-guard settings:

- repo: !`git rev-parse --show-toplevel 2>/dev/null || echo "(not a git repo)"`
- API key: !`[ -n "$TYPESAFE_API_KEY" ] && echo "set" || echo "MISSING -- jev-guard does nothing"`
- mode: !`git config --get jev-guard.mode || echo "warn (default)"`
- warn threshold: !`git config --get jev-guard.warnThreshold || echo "0.60 (default)"`
- block threshold: !`git config --get jev-guard.blockThreshold || echo "0.70 (default)"`
- artifact confidence: !`git config --get jev-guard.artifactConfidence || echo "0.80 (default)"`
- max added text sent: !`git config --get jev-guard.maxKb || echo "64 KB (default)"`
- never sent: !`git config --get-all jev-guard.exclude || echo "(only gitignored files)"`
- gitleaks: !`command -v gitleaks >/dev/null 2>&1 && echo "installed" || echo "NOT INSTALLED -- strongly recommended"`
- git-sync hook: !`git config --get git-sync.preCheckpoint || echo "(not wired yet -- happens on the next file Claude writes)"`

The user asked: $ARGUMENTS

Show the settings above as a short table. If they asked for a change, apply it
and stop. If they asked nothing, use AskUserQuestion for the mode (off / warn /
strict), defaulting to the current one, with a way to leave everything as is.

Apply with `git config` (add `--global` if they want it for every repo):

- `git config jev-guard.mode off|warn|strict`
- `git config jev-guard.warnThreshold 0.6` (same for `blockThreshold`, `artifactConfidence`)
- `git config jev-guard.maxKb 64`
- `git config --add jev-guard.exclude 'secrets/*'` (a glob, one per call)

Tell them when relevant:

- **The key is theirs.** Each user sets `TYPESAFE_API_KEY` in their own
  environment (shell profile, or `env` in `~/.claude/settings.json`) and pays for
  their own calls. Never write it into a file in the repository.
- **The added lines of every file Claude writes are sent to TypeSafe**, a third
  party. Gitignored files and `jev-guard.exclude` globs never are.
- **strict** makes Claude remove a flagged secret before going on, and makes
  git-sync hold back a checkpoint that contains one. A false positive then
  costs a checkpoint, which is why `warn` is the default.
- **If gitleaks is not installed, say so first and recommend installing it**
  (<https://github.com/gitleaks/gitleaks#installing>). It runs locally, before
  any API call, and catches known key formats deterministically -- including
  ones hidden behind a comment that argues they are fake, which Jev alone can
  be talked out of.
- The secret thresholds were measured on ~100 generated cases (README,
  "Calibration"); the artifact threshold is still a guess.

Keep the answer short. Confirm what changed in one line.
