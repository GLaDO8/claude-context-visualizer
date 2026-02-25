#!/bin/bash
# ═══════════════════════════════════════════════════════════
# Claude Code Context Window Visualizer — v4.2
# ═══════════════════════════════════════════════════════════
#
# Bar: 36 chars, █ body + ▊ cap per segment (visible gaps) — results(pink) mcp(teal) chat(green) fixed(grey) free(dark) buffer(black)
# Line 1: ███████▊████▊█▊███▊████████████████████▊█████▊  20k/200k $8.44

IFS= read -r -d '' input

# ─── Extract status data (single jq call, shell-safe quoting) ─
eval "$(jq -r '
  @sh "model_name=\(.model.display_name // "Unknown")",
  @sh "cwd=\(.workspace.current_dir // .cwd // "")",
  @sh "session_id=\(.session_id // "default")",
  @sh "context_size=\(.context_window.context_window_size // 200000)",
  @sh "used_pct=\(.context_window.used_percentage // 0)",
  @sh "total_cost=\(.cost.total_cost_usd // 0)"
' <<< "$input" 2>/dev/null)"

# Fallback defaults if jq eval failed
: "${model_name:=Unknown}" "${session_id:=default}"
: "${context_size:=200000}" "${used_pct:=0}" "${total_cost:=0}"

# Guard against zero/negative context_size (prevents division-by-zero)
[ "$context_size" -le 0 ] 2>/dev/null && context_size=200000

# Truncate float used_pct (e.g. 85.5 → 85) to prevent bash arithmetic crash
used_pct=${used_pct%.*}

# Derived values
context_k=$((context_size / 1000))
tokens_used=$((used_pct * context_size / 100))

# ─── Git branch detection ─────────────────────────────
git_branch=""
if [ -n "$cwd" ] && [ -e "$cwd/.git" ]; then
  git_branch=$(git -C "$cwd" --no-optional-locks rev-parse --abbrev-ref HEAD 2>/dev/null)
fi

# ─── Fixed overhead (single unified segment) ────────────
# These are always present — system prompt, tool/agent/skill
# definitions, MCP schemas, memory files. They never go away,
# not even after /clear.
#
# Calibrated from /context:
#   System prompt:    4,200
#   Custom agents:    1,700
#   System tools:    10,100  (built-in + MCP + deferred tools loaded via ToolSearch)
#   Skills:           3,200
#   Memory (CLAUDE.md): measured
overhead_base=$((4200 + 1700 + 10100 + 3200))  # 19,200
overhead_memory=0

# Measure CLAUDE.md files (global + project) → tokens ≈ chars/4
for f in "$HOME/.claude/CLAUDE.md" "$HOME/.claude/claude.md"; do
  if [ -f "$f" ]; then
    _content=$(<"$f")
    overhead_memory=$((overhead_memory + ${#_content} / 4))
  fi
done
if [ -n "$cwd" ]; then
  for f in "$cwd/CLAUDE.md" "$cwd/.claude/CLAUDE.md"; do
    if [ -f "$f" ]; then
      _content=$(<"$f")
      overhead_memory=$((overhead_memory + ${#_content} / 4))
    fi
  done
fi

overhead=$((overhead_base + overhead_memory))

# Named sub-components (for legend breakdown)
overhead_system=$((4200 + overhead_memory))  # system prompt + CLAUDE.md
overhead_schemas=$((1700 + 10100))           # agent defs + tool schemas (11800)
overhead_skills=3200

# Autocompact buffer: 16.5% of context_size (reserved, unusable)
buffer=$((context_size * 165 / 1000))

# ─── Read tracker data ──────────────────────────────────
tracker="/tmp/claude-context-tracker/${session_id}.json"
t_agents=0; t_tools=0; t_mcp=0
if [ -f "$tracker" ]; then
  eval "$(jq -r '
    @sh "t_agents=\(.agents // 0)",
    @sh "t_tools=\(.tools // 0)",
    @sh "t_mcp=\(.mcp // 0)"
  ' "$tracker" 2>/dev/null)"
fi

# Merge tool + agent → results
t_results=$((t_agents + t_tools))

# ─── Compute category breakdown ─────────────────────────
# Overhead is always present. If the API reports less than our
# overhead estimate, use overhead as the floor.
if [ $tokens_used -lt $overhead ]; then
  tokens_used=$overhead
  used_pct=$((tokens_used * 100 / context_size))
fi
tokens_k=$((tokens_used / 1000))

# Messages budget = everything beyond fixed overhead
msg_budget=$((tokens_used - overhead))
[ $msg_budget -lt 0 ] && msg_budget=0

# Scale tracked values to fit within message budget.
# Tracker is cumulative (total-ever-seen) but context is a snapshot.
# After compaction, old tool results are gone so tracker over-estimates.
tracked=$((t_results + t_mcp))
if [ $tracked -gt 0 ] && [ $tracked -gt $msg_budget ]; then
  # Reserve 15% floor for chat (user msgs + assistant responses)
  chat_floor=$((msg_budget * 15 / 100))
  tool_budget=$((msg_budget - chat_floor))
  scale=$((tool_budget * 100 / tracked))
  t_agents=$((t_agents * scale / 100))
  t_tools=$((t_tools * scale / 100))
  t_mcp=$((t_mcp * scale / 100))
  t_results=$((t_agents + t_tools))
  tracked=$((t_results + t_mcp))
fi

# Chat = residual (user messages + assistant reasoning + responses)
t_chat=$((msg_budget - tracked))
[ $t_chat -lt 0 ] && t_chat=0

# Free = remaining usable space
free=$((context_size - tokens_used - buffer))
[ $free -lt 0 ] && free=0

# ─── Colors (all truecolor) ─────────────────────────────
reset="\033[0m"
c_results="\033[38;2;252;102;177m"  # #FC66B1 — pink (tool+agent results)
c_mcp="\033[38;2;55;243;186m"       # #37F3BA — teal (MCP results)
c_chat="\033[38;2;202;255;68m"      # #CAFF44 — green (chat)
c_fixed="\033[38;2;153;153;153m"    # #999999 — grey (overhead + stats text)
c_free="\033[38;2;57;57;57m"        # #393939 — dark grey (free space)
c_buf="\033[38;2;34;34;34m"         # #222222 — near-black (buffer)
c_orange="\033[38;2;243;155;55m"    # #F39B37 — orange (git branch)
c_model="\033[3;38;2;255;96;68m"   # #FF6044 — red-orange italic (model name)
c_bold="\033[1m"                    # bold
c_warn_y="\033[33m"                 # yellow
c_warn_r="\033[31m"                 # red

# ─── Build 36-char stacked bar ──────────────────────────
bar_len=36

# 6 segments: results, mcp, chat, overhead, free, buffer
seg_vals=($t_results $t_mcp $t_chat $overhead $free $buffer)
seg_colors=("$c_results" "$c_mcp" "$c_chat" "$c_fixed" "$c_free" "$c_buf")

# Calculate bar chars: tokens * bar_len / context_size
# Min 1 char for: chat (2), overhead (3), free (4), buffer (5)
bar_chars=()
total_bar=0
for i in "${!seg_vals[@]}"; do
  v=${seg_vals[$i]}
  if [ $v -gt 0 ] && [ $context_size -gt 0 ]; then
    c=$((v * bar_len / context_size))
    # Enforce min 1 for structural + chat segments
    if [ $c -eq 0 ]; then
      case $i in
        2|3|4|5) c=1 ;;  # chat, overhead, free, buffer
      esac
    fi
  else
    c=0
  fi
  bar_chars+=($c)
  total_bar=$((total_bar + c))
done

# Adjust to exactly bar_len: free absorbs first, then buffer, then overhead
diff=$((total_bar - bar_len))
if [ $diff -ne 0 ]; then
  free_orig=${bar_chars[4]}
  adj=$((free_orig - diff))
  if [ $adj -ge 0 ]; then
    bar_chars[4]=$adj
  else
    bar_chars[4]=0
    overflow=$((diff - free_orig))
    buf_orig=${bar_chars[5]}
    bar_chars[5]=$((buf_orig - overflow))
    if [ ${bar_chars[5]} -lt 0 ]; then
      remaining=$(( -${bar_chars[5]} ))
      bar_chars[5]=0
      bar_chars[3]=$((bar_chars[3] - remaining))
      [ ${bar_chars[3]} -lt 1 ] && bar_chars[3]=1
    fi
  fi
fi

# Warning indicator
warn=""
if [ "$used_pct" -ge 85 ]; then
  warn=" ${c_warn_r}[/clear]${reset}"
elif [ "$used_pct" -ge 70 ]; then
  warn=" ${c_warn_y}!${reset}"
fi

# Format cost
cost_fmt=$(printf '$%.2f' "$total_cost" 2>/dev/null || echo "\$$total_cost")

# ─── RENDER LINE 1: Bar + stats + model + git ───────────
# Each segment: (n-1) × █ then 1 × ▊ — the 3/4 block cap creates visible gaps
BLOCKS="████████████████████████████████████"  # 36 █ chars
for i in "${!seg_vals[@]}"; do
  n=${bar_chars[$i]}
  [ $n -le 0 ] && continue
  if [ $n -eq 1 ]; then
    printf "${seg_colors[$i]}▊"
  else
    printf "${seg_colors[$i]}%s▊" "${BLOCKS:0:$((n-1))}"
  fi
done
printf "${reset}"

git_tag=""
[ -n "$git_branch" ] && git_tag="  ${c_bold}${c_orange}[${git_branch}]${reset}"
printf "${c_fixed}  %dk/%dk (%s)${reset}%b${c_model}  %s${reset}%b" \
  "$tokens_k" "$context_k" "$cost_fmt" "$warn" "$model_name" "$git_tag"

# ─── RENDER LINE 2: Legend (with blank line spacer) ──────
# Legend items gated on bar visibility — show only if segment has chars
legend=""
[ ${bar_chars[0]} -gt 0 ] && legend="${legend}${c_results}tools-$((t_results / 1000))k${reset} "
[ ${bar_chars[1]} -gt 0 ] && legend="${legend}${c_mcp}mcp-$((t_mcp / 1000))k${reset} "
[ ${bar_chars[2]} -gt 0 ] && legend="${legend}${c_chat}chat-$((t_chat / 1000))k${reset} "
legend="${legend}${c_fixed}(system-$((overhead_system / 1000))k, schemas-$((overhead_schemas / 1000))k, skills-$((overhead_skills / 1000))k)${reset}"
printf "\n\n%b" "$legend"
