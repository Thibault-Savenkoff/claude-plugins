# claude-model-advisor

Claude Code plugin that routes tasks to the right model and reasoning effort tier — **without burning your token budget on routine edits or starving critical architecture of cognitive depth.**

Repo: <https://github.com/Thibault-Savenkoff/claude-plugins/tree/main/plugins/claude-model-advisor>

## The idea

Model selection and reasoning depth should match the problem's blast radius, not user habit.

Defaulting to maximum reasoning tokens on a 3-line CSS fix burns budget and adds useless latency. Conversely, running a lightweight model on distributed state machines or monorepo-wide AST refactors invites subtle regressions.

`claude-model-advisor` audits the problem before you touch code.

- **Inspection** — when a prompt arrives, the advisor gauges impact radius (file count, dependencies), conceptual ambiguity, and safety criticality.
- **Routing** — it selects the optimal combination between **Haiku 4.5**, **Sonnet 5**, and **Opus 5**, and calibrates reasoning effort from **Low** up to **Ultracode**.
- **Actionable output** — it outputs the exact CLI commands needed (`/model`, `/effort`) or execution flags before running changes.

## What it does

- **Autonomous detection**: triggers on its own before large features, framework migrations, system-level architecture redesigns, or subtle concurrency debugging. It steps in *before* code generation starts.
- **Manual override**: `/model-advisor [task]` lets you query the routing engine on demand.
- **Multi-agent escalation (`Ultracode`)**: reserves high-overhead multi-agent execution (parallel code sweeps, adversarial review panels) strictly for massive refactors and zero-tolerance migrations.

## Install

Run inside Claude Code:
```
/plugin marketplace add Thibault-Savenkoff/claude-plugins
/plugin install claude-model-advisor
```

Or outside:
```
claude plugin marketplace add Thibault-Savenkoff/claude-plugins
claude plugin install claude-model-advisor
```

## Decision Matrix

### 1. Claude Haiku 4.5
- **Sweet spot**: Pure execution, low ambiguity, minimal token cost.
- **Workloads**: Boilerplate, DTOs, mock factories, simple unit tests for pure functions, inline documentation, typing fixes.
- **Effort**: Standard baseline (no extended thinking overhead needed).

### 2. Claude Sonnet 5
- **Sweet spot**: Day-to-day software engineering, multi-file features, deterministic debugging.
- **Tiers**:
  - `Low`: Routine endpoint edits, lightweight automation, single-file PR reviews.
  - `Medium`: Standard feature delivery, 3rd-party API integrations, clear stack trace fixes.
  - `High`: Non-trivial algorithms, refactors spanning 3–5 interdependent files, domain validation with edge cases.
  - `Extra (xhigh)`: Deep performance profiling, security-sensitive module audits, race condition diagnosis.

### 3. Claude Opus 5
- **Sweet spot**: High conceptual abstraction, architectural topology, consensus logic, monorepo migrations.
- **Tiers**:
  - `Low / Medium`: System architecture blueprints, schema design, distributed message bus topologies.
  - `High / Extra (xhigh)`: Abstract algorithm proofs, custom parsers/compilers, complex asynchronous state machine debugging.
  - `Max`: Zero-tolerance mission-critical implementations (cryptographic primitives, financial transaction ledgers).
  - `Ultracode`: Full monorepo migrations, multi-agent parallel execution trees, and adversarial code reviews.

## Example Output

```text
### 🎯 Automatic Task Assessment
- Perceived Complexity: High
- Impact Radius: 6 services, auth middleware, database migration
- Ambiguity Level: Moderate

### 💡 Recommended Configuration
- Model: Claude Sonnet 5
- Effort Level: Extra

### 📋 Rationale
The auth overhaul touches multi-tenant session isolation and cookie flags across multiple boundaries. Requires rigorous reasoning across edge cases without necessitating full multi-agent orchestration.

### ⚙️ Action Required
/model claude-sonnet-5
/effort extra
```

## How It Works

Skills in Claude Code are autonomous by default. The plugin registers the advisor's semantic trigger in Claude's tool context. When Claude identifies that a prompt exceeds routine complexity thresholds, it halts blind execution, runs the advisor tool, outputs the diagnostic, and lets you set the optimal environment.
