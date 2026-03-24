# Three Kingdoms (/tk)

**[中文文档](README.zh-CN.md)**

Multi-model review and collaborative implementation for Claude Code. Claude orchestrates Codex (GPT) and Gemini as CLI subprocesses to conduct plan reviews, code reviews, and collaborative implementation.

## How It Works

```
You: "/tk" or "开会" (start meeting)
  ↓
Claude (Opus) — Meeting host + executor
  ├── Codex (GPT) — Code reviewer + gatekeeper
  └── Gemini — Design + frontend + supplementary perspective
```

**Three phases:**
1. **Draft** — Claude helps you refine a vague idea into a structured plan
2. **Review** — Codex and Gemini independently review the plan, iterate until three-way APPROVE
3. **Implement** — Claude writes code, Codex reviews every step, Gemini assists on visual/UX

## Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code/overview) installed and configured
- [Codex CLI](https://github.com/openai/codex) installed (`npm install -g @openai/codex`)
- [Gemini CLI](https://github.com/google-gemini/gemini-cli) installed (`npm install -g @google/gemini-cli`)

## Installation

```bash
# Add the marketplace
/plugin marketplace add Tenkkk/three-kingdoms-cooperation

# Install the plugin
/plugin install tk@three-kingdoms-cooperation
```

## Usage

Trigger the skill by saying any of:
- `/tk`
- "开会" (start meeting)
- "会审" (review meeting)
- "让 codex 和 gemini 看看" (let codex and gemini take a look)
- "多模型审查" (multi-model review)
- "three kingdoms"

### Example

```
You: /tk I want to add a priority field to the Todo model

Claude: [Drafts a plan with you]
Claude: "Plan ready. Start review?"

You: "Start"

Claude → Codex: [Reviews plan, finds issues]
Claude → Gemini: [Reviews plan, adds perspective]
Claude: [Iterates until three-way APPROVE]
Claude: "All three models approved. Start implementation?"

You: "Go"

Claude: [Implements step by step, Codex reviews each step]
```

## Key Features

- **Three-way APPROVE gate** — Codex + Gemini + Claude must all independently approve before implementation begins
- **Step-by-step review** — Each implementation step is reviewed by Codex before proceeding to the next
- **Independent thinking** — Workers are instructed to verify claims independently, not blindly agree
- **Attribution** — Every message is prefixed with the speaker's identity (Opus/Codex/Gemini)
- **Session management** — Tracks session IDs for multi-turn conversations with each worker
- **Stream log** — Worker output is tee'd to a log file; open a second terminal with `tail -f` to watch in real-time

## Architecture

Pure Claude Code skill — no TypeScript, no Python, no build step, no dependencies. Just markdown instructions and one bash script.

```
plugins/tk/skills/
  tk/
    SKILL.md                 — Main skill file
    references/
      cli-reference.md       — Codex/Gemini CLI syntax reference
      communication-protocol.md — Message format, verdict JSON structure
      role-presets.md         — Role assignments & prompt templates
    scripts/
      call-worker.sh         — Unified worker calling script
  detect-workers/
    SKILL.md                 — Quick detection of installed CLI workers
```

## License

[MIT](LICENSE)
