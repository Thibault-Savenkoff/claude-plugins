# jev-guard

Flags plaintext secrets in the files Claude writes, while there is still time
to fix them, and can stop a [git-sync](../git-sync) checkpoint that would carry
one off the machine. The judgment comes from the
[TypeSafe](https://docs.typesafe.ai) API (model Jev), with **your own key**.

## What it does

- **After every Edit/Write**, the lines Claude just added (plus the file's path)
  are sent to Jev with two questions: does this add a real credential in clear,
  and what kind of file is this. Code, not the model, decides what to do.
  - `warn` (default): you and Claude get a message; nothing is blocked.
  - `strict`: Claude is told to remove the secret before going on.
  - A file that looks generated gets a hint to add it to git-sync's ignore patterns.
- **Before git-sync pushes a checkpoint**, the same scan runs on everything the
  checkpoint carries, including files written through Bash or by hand. In
  `strict`, a flagged secret holds the checkpoint back. Answers are cached, so
  files already scanned at edit time cost nothing twice.
- **`/jev-guard:scan`** runs that scan on demand; **`/jev-guard:config`** shows
  and changes the settings.

**Install [gitleaks](https://github.com/gitleaks/gitleaks#installing) too.**
jev-guard runs it first when it is present: it is local, free, and catches known
key formats with certainty. Jev reads the diff as data it can be argued with
(see Calibration), so it should not be your only barrier. `/jev-guard:config`
tells you when gitleaks is missing.

## Setup

1. Get a TypeSafe API key and put it in your environment as `TYPESAFE_API_KEY`
   (shell profile, or `env` in `~/.claude/settings.json`). Every user brings
   their own; without one the plugin does nothing at all.
2. `claude plugin install jev-guard@ts-plugins`
3. Optional: `/jev-guard:config` to switch to `strict`.

The git-sync hook wires itself (`git-sync.preCheckpoint` in `.git/config`) the
first time Claude writes a file in the repo, and follows the plugin's path
across updates. It needs git-sync 2.2 or later.

## Privacy

**The added lines of the files Claude writes leave your machine** for
TypeSafe's servers. Fine for personal code; check before using it on code you
are not allowed to share. Never sent: gitignored files, files matching a
`jev-guard.exclude` glob, and anything over `jev-guard.maxKb` (64 KB default).

## Failure behaviour

API down, slow (2 s timeout, no retry), key rejected, or an answer it cannot
read: nothing is shown, the reason goes to `.git/jev-guard/error.log`, and the
checkpoint is pushed as usual, even in `strict`. After a failure the API is
left alone for a minute, so a dead API costs one timeout, not one per file.

The checkpoint-time scan stops before the deadline git-sync hands it, to stay inside git-sync's 15 s
Stop timeout; files it did not reach are listed as not scanned.

## Settings

All in git config, per repo (or `--global`):

| Key | Default | |
|---|---|---|
| `jev-guard.mode` | `warn` | `off`, `warn`, `strict` |
| `jev-guard.warnThreshold` | `0.60` | probability of a secret that triggers a warning |
| `jev-guard.blockThreshold` | `0.70` | probability that blocks, in `strict` |
| `jev-guard.artifactConfidence` | `0.80` | confidence needed for the "generated file" hint |
| `jev-guard.maxKb` | `64` | larger additions are not sent |
| `jev-guard.exclude` | | glob, repeatable; matching files are never sent |

All thresholds are measured (below).

## Calibration

`tests/calibrate.sh` sends 49 generated cases to the real API (it needs a key
and is never run by the test suite): 24 secrets in realistic formats, 4 of them
next to a comment arguing they are fake, and 25 look-alikes that are not
secrets (placeholders, environment variables, public keys, hashes, UUIDs,
`.env.example`, code that only mentions passwords). Every value is random.

Two runs with `jev-1.13`, September 2026:

| | Lowest secret | Highest non-secret |
|---|---|---|
| Run 1 | 0.77 (adversarial comment) | 0.48 (`password: 'test'` in a test) |
| Run 2 | 0.76 (adversarial comment) | 0.50 (same) |

At `0.60` (warn) and `0.70` (block), both runs caught 24/24 secrets with 0
false alarms. 0.90, the first guess, would have blocked only 14 of 24.

The wording of the question mattered more than the thresholds. The first
version put every realistic secret between 0.60 and 0.78, and the adversarial
comments pulled theirs down to 0.53. Saying explicitly that comments claiming
a value is fake do not change the answer moved them to 0.76 or more.

Limits: 98 answers over cases one person wrote, in English, in common
formats. Rerun the script after changing `questions.json` or when the model
changes.

**Generated-file hint** (`artifactConfidence`), one run over 30 files: the 9
build outputs it recognised (bundles, source maps, `__pycache__`, generated
protobuf/GraphQL code, coverage reports) all scored 0.98 or more, and none of
15 hand-written files was taken for one, so any value from 0.5 to 0.95 behaves
the same. Lockfiles come out as `config`, which is right: they belong in the
repository. One miss: a Maven `MANIFEST.MF` (0.38).

## Limits

- Only files written with Edit/Write are checked at write time; the rest are
  caught at checkpoint time, which is later.
- Checkpoint-time scans are sequential, within the time git-sync leaves: with many new
  files at once, the last ones may go unscanned (and are reported as such).
- Files are scanned one request each; batching several files into one request
  costs accuracy, so it is not done.

## Tests

`sh tests/run.sh` runs every case against both the sh and the PowerShell hooks
(`sh tests/run.sh sh` for sh only). No test calls the real API: the endpoint is
pointed at fixture files or a closed port, so it runs without a key or network.
