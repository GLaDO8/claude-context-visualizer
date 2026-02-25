#!/bin/bash
# ═══════════════════════════════════════════════════════════
# Context Tracker — PostToolUse hook (v4.2)
# ═══════════════════════════════════════════════════════════
# Estimates token consumption per tool category by measuring
# the size of tool inputs and results passing through hooks.
#
# Categories:
#   agents — Task (subagent) results
#   tools  — Read, Grep, Glob, Bash, Edit, Write, etc.
#   mcp    — Any mcp__* tool (Figma, Supabase, Slack, etc.)
#
# Writes running totals to /tmp/claude-context-tracker/<session>.json
# which the statusline reads for the breakdown display.
#
# Performance: 2 direct forks (1× jq metadata, 1× lockf → sh → jq)
# Security: all jq interpolation uses @sh/--arg (no shell injection)
# Concurrency: lockf (macOS) / flock (Linux) prevents read-modify-write races

# Detect platform lock command (lockf on macOS, flock on Linux)
if command -v lockf >/dev/null 2>&1; then
  _LOCK_CMD="lockf"
elif command -v flock >/dev/null 2>&1; then
  _LOCK_CMD="flock"
else
  _LOCK_CMD=""
fi

IFS= read -r -d '' input
total_chars=${#input}

# Extract metadata (single jq call, @sh-quoted for safety)
eval "$(jq -r '
  @sh "session_id=\(.session_id // "default")",
  @sh "tool_name=\(.tool_name // "unknown")"
' <<< "$input" 2>/dev/null)" || exit 0

# Estimate tokens: ~4 characters per token, subtract JSON envelope overhead
est=$(( (total_chars > 300) ? (total_chars - 300) / 4 : 0 ))

# Categorize tool into context buckets
case "$tool_name" in
  Task)   key="agents" ;;
  mcp__*) key="mcp" ;;
  *)      key="tools" ;;
esac

# Ensure tracker directory exists with secure permissions
dir="/tmp/claude-context-tracker"
[ -d "$dir" ] || { mkdir -p "$dir" && chmod 700 "$dir"; } 2>/dev/null
file="$dir/${session_id}.json"

# Locked read-modify-write (lockf on macOS, flock on Linux, 2s timeout)
# Lock command acquires an advisory lock on ${file}.lock, runs sh -c as
# child, releases lock when the child exits. Env vars pass data to inner shell.
_CT_INNER='
  [ -f "$_CT_FILE" ] || printf "{\"agents\":0,\"tools\":0,\"mcp\":0,\"calls\":0}\n" > "$_CT_FILE"
  jq --arg key "$_CT_KEY" --argjson est "$_CT_EST" --arg tool "$_CT_TOOL" '"'"'
    .[$key] = ((.[$key] // 0) + $est) |
    .calls = ((.calls // 0) + 1) |
    .last = $tool
  '"'"' "$_CT_FILE" > "${_CT_FILE}.tmp" && mv "${_CT_FILE}.tmp" "$_CT_FILE"
'
export _CT_FILE="$file" _CT_KEY="$key" _CT_EST="$est" _CT_TOOL="$tool_name"
case "$_LOCK_CMD" in
  lockf) lockf -s -t 2 "${file}.lock" /bin/sh -c "$_CT_INNER" ;;
  flock) flock -w 2 "${file}.lock" /bin/sh -c "$_CT_INNER" ;;
  *)     /bin/sh -c "$_CT_INNER" ;;  # No lock available — direct write fallback
esac 2>/dev/null

exit 0
