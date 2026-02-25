#!/bin/bash
# ═══════════════════════════════════════════════════════════
# Claude Context Visualizer — Installer
# ═══════════════════════════════════════════════════════════
# One-line install:
#   curl -fsSL https://raw.githubusercontent.com/shreyasgupta/claude-context-visualizer/main/install.sh | bash
#
# What it does:
#   1. Downloads statusline.sh and context-tracker.sh
#   2. Patches ~/.claude/settings.json to wire them up
#   3. Creates the tracker temp directory
#
# Prerequisites: jq, curl, Claude Code

set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/GLaDO8/claude-context-visualizer/main"
CLAUDE_DIR="$HOME/.claude"
HOOKS_DIR="$CLAUDE_DIR/hooks"
SETTINGS="$CLAUDE_DIR/settings.json"
TRACKER_DIR="/tmp/claude-context-tracker"

# ─── Colors ───────────────────────────────────────────────
red="\033[31m"; green="\033[32m"; yellow="\033[33m"; bold="\033[1m"; reset="\033[0m"

info()  { printf "%b[+]%b %s\n" "${bold}${green}" "$reset" "$1"; }
warn()  { printf "%b[!]%b %s\n" "${bold}${yellow}" "$reset" "$1"; }
error() { printf "%b[x]%b %s\n" "${bold}${red}" "$reset" "$1"; exit 1; }

# ─── Prerequisites ────────────────────────────────────────
command -v jq   >/dev/null 2>&1 || error "jq is required. Install with: brew install jq (macOS) or apt install jq (Linux)"
command -v curl >/dev/null 2>&1 || error "curl is required."

# ─── Create directories ──────────────────────────────────
mkdir -p "$HOOKS_DIR"
mkdir -p "$TRACKER_DIR" && chmod 700 "$TRACKER_DIR"

# ─── Download scripts ────────────────────────────────────
info "Downloading statusline.sh..."
curl -fsSL "$REPO_RAW/statusline.sh" -o "$CLAUDE_DIR/statusline.sh"
chmod +x "$CLAUDE_DIR/statusline.sh"

info "Downloading context-tracker.sh..."
curl -fsSL "$REPO_RAW/context-tracker.sh" -o "$HOOKS_DIR/context-tracker.sh"
chmod +x "$HOOKS_DIR/context-tracker.sh"

# ─── Patch settings.json ─────────────────────────────────
# Create settings.json if it doesn't exist
if [ ! -f "$SETTINGS" ]; then
  echo '{}' > "$SETTINGS"
  info "Created new settings.json"
fi

# Backup before patching
backup="${SETTINGS}.backup.$(date +%s)"
cp "$SETTINGS" "$backup"
info "Backed up settings.json → $(basename "$backup")"

# Add statusLine (skip if already present)
if jq -e 'has("statusLine")' "$SETTINGS" >/dev/null 2>&1; then
  warn "statusLine already configured — skipping"
else
  jq '. + {"statusLine": {"type": "command", "command": "~/.claude/statusline.sh"}}' \
    "$SETTINGS" > "${SETTINGS}.tmp" && mv "${SETTINGS}.tmp" "$SETTINGS"
  info "Added statusLine config"
fi

# Add PostToolUse hook for context-tracker (skip if already present)
has_tracker=$(jq '
  (.hooks // {}).PostToolUse // [] |
  map(.hooks // []) | flatten |
  any(.command | tostring | test("context-tracker"))
' "$SETTINGS" 2>/dev/null)

if [ "$has_tracker" = "true" ]; then
  warn "context-tracker hook already configured — skipping"
else
  jq '
    .hooks = (.hooks // {}) |
    .hooks.PostToolUse = ((.hooks.PostToolUse // []) + [{
      "hooks": [{
        "type": "command",
        "command": "~/.claude/hooks/context-tracker.sh",
        "timeout": 5
      }]
    }])
  ' "$SETTINGS" > "${SETTINGS}.tmp" && mv "${SETTINGS}.tmp" "$SETTINGS"
  info "Added context-tracker PostToolUse hook"
fi

# ─── Done ─────────────────────────────────────────────────
printf "\n%b✓ Claude Context Visualizer installed!%b\n" "${bold}${green}" "$reset"
printf "\n  Restart Claude Code to see the statusline bar.\n"
printf "  The bar shows context window usage with a colored breakdown:\n"
printf "    %bpink%b = tool results  %bteal%b = MCP  %bgreen%b = chat  %bgrey%b = system overhead\n\n" \
  "$bold" "$reset" "$bold" "$reset" "$bold" "$reset" "$bold" "$reset"
