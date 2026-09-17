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

Once added, you can install any of the plugins below with a single command.

---

## 🧩 Available Plugins

| Plugin | Description | Category | Install Command |
| :--- | :--- | :--- | :--- |
| **[`claude-model-advisor`](./plugins/claude-model-advisor)** | Recommends the ideal Claude model and reasoning effort based on task complexity. | Productivity / AI | `/plugin install claude-model-advisor` |
| **[`git-sync`](./plugins/git-sync)** | Auto-syncs git repositories across machines on session start and stop. | Productivity | `/plugin install git-sync` |

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

Keeps your repository continuously in sync across multiple development workstations without manual Git commands.

- **On Session Start**: Automatically pulls the latest remote changes.
- **On Session End**: Automatically creates a commit with the session diff and pushes upstream.

👉 [Read full documentation](./plugins/git-sync/README.md)

---

## 📂 Repository Structure

```text
claude-plugins/
├── .claude-plugin/
│   └── marketplace.json         # Central marketplace catalog registry
├── plugins/
│   ├── claude-model-advisor/    # Model & Reasoning Effort routing plugin
│   │   ├── .claude-plugin/
│   │   │   └── plugin.json
│   │   ├── skills/
│   │   │   └── model-advisor/
│   │   │       └── SKILL.md
│   │   └── README.md
│   │
│   └── git-sync/                # Automated multi-machine Git sync plugin
│       ├── .claude-plugin/
│       │   └── plugin.json
│       ├── commands/
│       │   ├── config.md
│       │   ├── land.md
│       │   └── land-context.sh
│       ├── hooks/
│       │   ├── hooks.json
│       │   ├── ignore-patterns.txt
│       │   ├── legacy-commit.ps1
│       │   ├── legacy-commit.sh
│       │   ├── lib.ps1
│       │   ├── lib.sh
│       │   ├── session-end-archive.ps1
│       │   ├── session-end-archive.sh
│       │   ├── session-start.ps1
│       │   ├── session-start.sh
│       │   ├── stop-sync.ps1
│       │   └── stop-sync.sh
│       ├── skills/
│       │   └── notes/
│       │       ├── extract-transcript.py
│       │       └── SKILL.md
│       ├── tests/
│       │   ├── lib.sh
│       │   ├── run.sh
│       │   ├── test-branch-lifecycle.sh
│       │   ├── test-checkpoint.sh
│       │   ├── test-crossplatform.sh
│       │   ├── test-degenerate.sh
│       │   ├── test-excludes.sh
│       │   ├── test-file-kinds.sh
│       │   ├── test-land-aftermath.sh
│       │   ├── test-land-context.sh
│       │   ├── test-pingpong.sh
│       │   ├── test-remote-naming.sh
│       │   └── test-submodules.sh
│       └── README.md
│
├── LICENSE                      # MIT License (covers all plugins)
└── README.md                    # Marketplace documentation
```

---

## 🛠️ Local Development & Testing

To test this entire plugin suite locally without installing from GitHub:

```bash
claude --plugin-dir ./plugins/claude-model-advisor
```

---

## 📄 License

This repository and all included plugins are released under the [MIT License](./LICENSE).
