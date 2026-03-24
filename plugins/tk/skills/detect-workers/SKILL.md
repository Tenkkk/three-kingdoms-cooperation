---
name: detect-workers
description: This skill should be used when the user asks to "detect workers", "check available workers", "what workers are installed", "which AI tools are available", "检测worker", "有哪些AI工具可用", or wants to know if Codex or Gemini CLI is installed on this machine.
version: 0.2.0
---

# Detect Available Local Workers

Detect locally installed AI CLI workers that can serve as delegation targets for the `/delegate` skill.

## Detection

Run all checks in a single parallel Bash call:

```bash
for w in codex gemini; do
  if command -v "$w" &>/dev/null; then
    VER=$("$w" --version 2>&1 | head -1)
    echo "$w: installed ($VER)"
  else
    echo "$w: not found"
  fi
done
```

## Report Format

Present results as a compact table:

```
Worker Detection:
  Codex: installed (codex-cli 0.114.0)
  Gemini: installed (0.33.1)

Ready for delegation: Codex, Gemini
```

If no workers found, inform the user: "No external workers detected. Claude Code will handle all tasks directly. Install Codex (`npm i -g @openai/codex`) or Gemini CLI to enable delegation."

## Terminal Environment

Also report the terminal environment (affects how worker panes are displayed):

```bash
[ -n "$WT_SESSION" ] && echo "Terminal: Windows Terminal (split pane supported)" || \
[ -n "$TMUX" ] && echo "Terminal: tmux (split pane supported)" || \
echo "Terminal: basic (workers will run in background)"
```
