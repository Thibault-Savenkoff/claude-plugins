# Claude Code Plugins Marketplace

A curated collection of productivity and engineering workflow plugins for **Claude Code**, maintained by [Thibault Savenkoff](https://github.com/Thibault-Savenkoff).

[![Claude Code](https://img.shields.io/badge/Claude%20Code-Plugin%20Marketplace-purple.svg)](https://code.claude.com)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

---

## 📦 Quick Start: Add the Marketplace

Add this marketplace directly inside your Claude Code session:

```text
/plugin marketplace add Thibault-Savenkoff/claude-plugins
```

Or outside:

```text
claude plugin marketplace add Thibault-Savenkoff/claude-plugins
```

Once added, you can install any of the plugins below with a single command.

---

## 🧩 Available Plugins

| Plugin | Description | Category | Install Command |
| :--- | :--- | :--- | :--- |
| **[`claude-model-advisor`](./plugins/claude-model-advisor)** | Recommends the ideal Claude model and reasoning effort based on task complexity. | Productivity / AI | `/plugin install claude-model-advisor` |
| **[`git-sync`](./plugins/git-sync)** | Carries work in progress between machines as a checkpoint branch, without WIP commits in your history. | Productivity | `/plugin install git-sync` |
| **[`jev-guard`](./plugins/jev-guard)** | Flags plaintext secrets in the files Claude writes, and can hold back a git-sync checkpoint that carries one. | Security | `/plugin install jev-guard` |

---

### 1. Claude Model Advisor (`claude-model-advisor`)

Analyzes task scope, codebase blast radius, and ambiguity to recommend the most cost-effective and capable model configuration.

- **Models covered**: Claude Haiku 4.5, Claude Sonnet 5, and Claude Opus 5.
- **Effort tiers evaluated**: Low, Medium, High, Extra (`xhigh`), Max, and **Ultracode** (multi-agent dynamic orchestration).
- **Autonomous Detection**: Automatically triggers before multi-file refactors, architecture redesigns, framework migrations, or subtle concurrency bugs.
- **Manual Command**:
  ```text
  /model-advisor Refactor the entire state management layer to Zustand
  ```

👉 [Read full documentation & decision matrix](./plugins/claude-model-advisor/README.md)

---

### 2. Git Sync (`git-sync`)

Carries your work in progress between machines without leaving `WIP: auto-sync` commits in the project's history.

- **On Session Stop**: Pushes the work tree to a throwaway `git-sync/<branch>` checkpoint, without committing anything.
- **On Session Start**: Pulls, then applies the other machine's checkpoint as uncommitted work.
- **`/git-sync:land`**: The only way anything enters your branch: Claude proposes commits from the diff, you approve.

👉 [Read full documentation](./plugins/git-sync/README.md)

---

### 3. Jev Guard (`jev-guard`) — v0.1.0

Catches plaintext secrets while there is still time to fix them, using the [TypeSafe](https://docs.typesafe.ai) API (model Jev) with **your own API key** (`TYPESAFE_API_KEY`).

- **After every Edit/Write**: The lines Claude just added are checked; Claude is warned (`warn`, the default) or must remove the secret (`strict`).
- **Before every git-sync checkpoint**: A last scan of everything the checkpoint carries, including files written through Bash. In `strict`, a secret holds the push back.
- **Fail-open**: If the API is down or slow, nothing is blocked and no work is lost.
- **Privacy**: The added lines are sent to TypeSafe, a third party. Gitignored and excluded files never are.

👉 [Read full documentation](./plugins/jev-guard/README.md)

---

## 📂 Repository Structure

```text
claude-plugins/
├── .claude-plugin/
│   └── marketplace.json         # Central marketplace catalog registry
├── plugins/
│   ├── claude-model-advisor/    # Model & reasoning effort routing
│   ├── git-sync/                # Multi-machine work-in-progress sync
│   └── jev-guard/               # Plaintext secret detection
├── LICENSE                      # MIT License (covers all plugins)
└── README.md                    # Marketplace documentation
```

Each plugin has its own `README.md`; `git-sync` and `jev-guard` also ship a `tests/run.sh`.

---

## 🛠️ Local Development & Testing

To test this entire plugin suite locally without installing from GitHub:

```bash
claude --plugin-dir ./plugins/claude-model-advisor
```

---

## 📄 License

This repository and all included plugins are released under the [MIT License](./LICENSE).
