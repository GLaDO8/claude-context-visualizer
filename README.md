# Claude Context Visualizer

A truecolor statusline for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that shows your context window usage as a segmented bar — so you always know how much room you have left.

<img width="full" height="full" alt="Frame 21" src="https://github.com/user-attachments/assets/298c0ae0-afeb-4d99-8257-18bc920f5837" />


## Install

```bash
curl -fsSL https://raw.githubusercontent.com/GLaDO8/claude-context-visualizer/main/install.sh | bash
```

Then restart Claude Code.

## What You Get

A two-line status bar at the bottom of every Claude Code session:

**Segments** (left to right):

| Color | Segment | What it tracks |
|-------|---------|----------------|
| Pink | Tools + Agents | Results from Read, Grep, Bash, Task, etc. |
| Teal | MCP | Results from Figma, Supabase, Slack, etc. |
| Green | Chat | Your messages + Claude's responses |
| Grey | System | Prompt, tool schemas, skills, CLAUDE.md |
| Dark | Free | Available usable space |
| Black | Buffer | Autocompact reserve (16.5%) — not usable |

**Extras**: model name, git branch, session cost, and warnings at 70% (`!`) and 85% (`[/clear]`).

## How It Works

Two scripts work together:

1. **`statusline.sh`** — Renders the bar. Claude Code calls it via `settings.json` → `statusLine.command`, piping session metrics as JSON on stdin. It reads the context window size, usage percentage, cost, and model info, then composites the bar from tracked data.

2. **`context-tracker.sh`** — A PostToolUse hook. Every time Claude uses a tool, this hook estimates the token cost of the result (`payload_chars / 4`) and categorizes it (tools, agents, or MCP). It writes cumulative totals to `/tmp/claude-context-tracker/<session>.json`, which the statusline reads for the breakdown.

### Architecture

```
Claude Code
  ├─ PostToolUse hook ──→ context-tracker.sh ──→ /tmp/claude-context-tracker/<session>.json
  └─ statusLine command ──→ statusline.sh ──→ reads tracker file ──→ renders bar
```

The tracker uses `lockf` (macOS) or `flock` (Linux) for concurrency-safe writes, and all `jq` interpolation uses `--arg`/`@sh` to prevent shell injection.

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (any version with `statusLine` + `hooks` support)
- `jq` — JSON processor (`brew install jq` / `apt install jq`)
- macOS or Linux
- A truecolor terminal (Ghostty, iTerm2, WezTerm, Kitty, Alacritty, etc.)

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/GLaDO8/claude-context-visualizer/main/uninstall.sh | bash
```

Or run locally:

```bash
./uninstall.sh
```

This removes the scripts, cleans `settings.json`, and deletes tracker data.

## Configuration

The statusline is calibrated for a typical Claude Code setup. If you have many MCP servers or plugins, the overhead estimate may drift. To recalibrate:

1. Run `/context` in Claude Code to see actual token breakdown
2. Update `overhead_base` in `statusline.sh` (line ~52)

## License

MIT
