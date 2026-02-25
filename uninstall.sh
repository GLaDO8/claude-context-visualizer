#!/bin/bash
# ═══════════════════════════════════════════════════════════
# Claude Context Visualizer — Uninstaller
# ═══════════════════════════════════════════════════════════
# Removes the statusline and context-tracker, cleans settings.json.

set -euo pipefail

CLAUDE_DIR="$HOME/.claude"
HOOKS_DIR="$CLAUDE_DIR/hooks"
SETTINGS="$CLAUDE_DIR/settings.json"
TRACKER_DIR="/tmp/claude-context-tracker"

green="\033[32m"; yellow="\033[33m"; bold="\033[1m"; reset="\033[0m"

info()  { printf "%b[-]%b %s\n" "${bold}${green}" "$reset" "$1"; }
warn()  { printf "%b[!]%b %s\n" "${bold}${yellow}" "$reset" "$1"; }

# ─── Remove scripts ──────────────────────────────────────
if [ -f "$CLAUDE_DIR/statusline.sh" ]; then
  rm "$CLAUDE_DIR/statusline.sh"
  info "Removed statusline.sh"
else
  warn "statusline.sh not found — skipping"
fi

if [ -f "$HOOKS_DIR/context-tracker.sh" ]; then
  rm "$HOOKS_DIR/context-tracker.sh"
  info "Removed context-tracker.sh"
else
  warn "context-tracker.sh not found — skipping"
fi

# ─── Patch settings.json ─────────────────────────────────
if [ -f "$SETTINGS" ]; then
  # Backup before patching
  backup="${SETTINGS}.backup.$(date +%s)"
  cp "$SETTINGS" "$backup"
  info "Backed up settings.json → $(basename "$backup")"

  # Remove statusLine key
  if jq -e 'has("statusLine")' "$SETTINGS" >/dev/null 2>&1; then
    jq 'del(.statusLine)' "$SETTINGS" > "${SETTINGS}.tmp" && mv "${SETTINGS}.tmp" "$SETTINGS"
    info "Removed statusLine from settings.json"
  fi

  # Remove context-tracker hook entries from PostToolUse
  has_tracker=$(jq '
    (.hooks // {}).PostToolUse // [] |
    map(.hooks // []) | flatten |
    any(.command | tostring | test("context-tracker"))
  ' "$SETTINGS" 2>/dev/null)

  if [ "$has_tracker" = "true" ]; then
    jq '
      .hooks.PostToolUse = [
        .hooks.PostToolUse[] |
        select(
          (.hooks // []) | map(.command | tostring | test("context-tracker")) | any | not
        )
      ] |
      if (.hooks.PostToolUse | length) == 0 then del(.hooks.PostToolUse) else . end |
      if (.hooks | length) == 0 then del(.hooks) else . end
    ' "$SETTINGS" > "${SETTINGS}.tmp" && mv "${SETTINGS}.tmp" "$SETTINGS"
    info "Removed context-tracker hook from settings.json"
  fi
else
  warn "settings.json not found — skipping"
fi

# ─── Clean up tracker data ───────────────────────────────
if [ -d "$TRACKER_DIR" ]; then
  rm -rf "$TRACKER_DIR"
  info "Cleaned up tracker data"
fi

printf "\n%b✓ Claude Context Visualizer uninstalled.%b\n" "${bold}${green}" "$reset"
printf "  Restart Claude Code to apply changes.\n\n"
