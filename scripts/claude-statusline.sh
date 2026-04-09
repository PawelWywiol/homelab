#!/usr/bin/env bash
# Claude Code statusline with metrics reporting to InfluxDB
#
# Setup:
#   1. Install deps:
#      macOS:  brew install jq curl
#      Debian: sudo apt install -y jq curl
#   2. Copy to ~/.claude/statusline-command.sh
#   3. Configure Claude Code statusline:
#      echo '{"statusline_command": "~/.claude/statusline-command.sh"}' > ~/.claude/settings.json
#      Or add to existing settings.json: "statusline_command": "~/.claude/statusline-command.sh"
#   4. Set INFLUXDB_URL in ~/.claude/statusline.env (optional, enables metrics):
#      INFLUXDB_URL=http://192.168.0.202:8086
#
# InfluxDB metrics (optional):
#   When INFLUXDB_URL is set in ~/.claude/statusline.env, metrics are sent
#   to InfluxDB on every statusline refresh (fire-and-forget, non-blocking).
#   Database "claude" must exist: curl -X POST "$INFLUXDB_URL/query" --data-urlencode "q=CREATE DATABASE claude"
#
# Statusline output:
#   ~/project · Opus 4.6 · 45%/20%/15% · $1.23 · +142 −8 · 234/45/12k · 🌳 feature
#   path      · model    · ctx/5h/7d   · cost  · lines    · tokens     · worktree

input=$(cat)

# Parse fields
model=$(echo "$input" | jq -r '.model.display_name // empty')
ctx_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
cost=$(echo "$input" | jq -r '.cost.total_cost_usd // empty')
lines_add=$(echo "$input" | jq -r '.cost.total_lines_added // empty')
lines_rm=$(echo "$input" | jq -r '.cost.total_lines_removed // empty')
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
worktree=$(echo "$input" | jq -r '.worktree.name // empty')
five_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
week_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
in_tok=$(echo "$input" | jq -r '.context_window.current_usage.input_tokens // empty')
cache_rd=$(echo "$input" | jq -r '.context_window.current_usage.cache_read_input_tokens // empty')
cache_cr=$(echo "$input" | jq -r '.context_window.current_usage.cache_creation_input_tokens // empty')

# Session ID: walk process tree to find Claude's session file
session_id=""
_pid=$$
while [ "$_pid" -gt 1 ]; do
  _sf="$HOME/.claude/sessions/${_pid}.json"
  if [ -f "$_sf" ]; then
    session_id=$(jq -r '.sessionId // empty' "$_sf")
    break
  fi
  _pid=$(ps -o ppid= -p "$_pid" 2>/dev/null | tr -d ' ')
  [ -z "$_pid" ] && break
done
session_id="${session_id:-unknown_$(hostname -s)}"

# --- Send metrics to InfluxDB (fire-and-forget) ---
_env_file="$HOME/.claude/statusline.env"
if [ -n "$ctx_pct" ] && [ -f "$_env_file" ]; then
  # shellcheck source=/dev/null
  source "$_env_file"
  if [ -n "$INFLUXDB_URL" ]; then
    _host=$(hostname -s)
    _project=$(basename "${cwd:-unknown}")
    _model_tag=$(echo "${model:-unknown}" | sed 's/ *(.*//' | tr ' ' '_')
    _worktree_tag=$(echo "${worktree:-none}" | tr ' ' '_')

    _line="claude_session,host=${_host},model=${_model_tag},project=${_project},worktree=${_worktree_tag},session=${session_id}"
    _fields=""
    [ -n "$ctx_pct" ]   && _fields="${_fields}ctx_pct=${ctx_pct},"
    [ -n "$cost" ]      && _fields="${_fields}cost=${cost},"
    [ -n "$lines_add" ] && _fields="${_fields}lines_add=${lines_add}i,"
    [ -n "$lines_rm" ]  && _fields="${_fields}lines_rm=${lines_rm}i,"
    [ -n "$five_pct" ]  && _fields="${_fields}five_pct=${five_pct},"
    [ -n "$week_pct" ]  && _fields="${_fields}week_pct=${week_pct},"
    [ -n "$in_tok" ]    && _fields="${_fields}in_tok=${in_tok}i,"
    [ -n "$cache_rd" ]  && _fields="${_fields}cache_rd=${cache_rd}i,"
    [ -n "$cache_cr" ]  && _fields="${_fields}cache_cr=${cache_cr}i,"
    _fields="${_fields%,}"

    curl -s -o /dev/null --max-time 2 \
      -X POST "${INFLUXDB_URL}/write?db=claude&precision=s" \
      -H "Content-Type: text/plain" \
      --data-raw "${_line} ${_fields}" &
  fi
fi

SEP=" · "
YELLOW="\033[33m"
RED="\033[31m"
RESET="\033[0m"

# Color a percentage value: >80% red, >60% yellow, else default
color_pct() {
  local val="$1"
  if [ -z "$val" ]; then
    printf "?%%"
    return
  fi
  local int_val=$(printf '%.0f' "$val")
  if [ "$int_val" -gt 80 ]; then
    printf "${RED}%d%%${RESET}" "$int_val"
  elif [ "$int_val" -gt 60 ]; then
    printf "${YELLOW}%d%%${RESET}" "$int_val"
  else
    printf "%d%%" "$int_val"
  fi
}

# Format tokens to k
to_k() {
  local val="$1"
  if [ -z "$val" ] || [ "$val" = "0" ]; then
    printf "0"
    return
  fi
  local k=$((val / 1000))
  printf "%d" "$k"
}

parts=()

# 1. Path (~ for home)
if [ -n "$cwd" ]; then
  parts+=("${cwd/#$HOME/\~}")
fi

# 2. Model (strip "Claude " prefix)
if [ -n "$model" ]; then
  parts+=("${model#Claude }")
fi

# 3. ctx%/5h%/7d%
pct_part="$(color_pct "$ctx_pct")/$(color_pct "$five_pct")/$(color_pct "$week_pct")"
parts+=("$pct_part")

# 4. Cost
if [ -n "$cost" ]; then
  parts+=("\$$(printf '%.2f' "$cost")")
fi

# 5. Lines +N −N
if [ -n "$lines_add" ] || [ -n "$lines_rm" ]; then
  parts+=("+${lines_add:-0} −${lines_rm:-0}")
fi

# 6. Tokens in k format
if [ -n "$in_tok" ] || [ -n "$cache_rd" ] || [ -n "$cache_cr" ]; then
  parts+=("$(to_k "$in_tok")/$(to_k "$cache_rd")/$(to_k "$cache_cr")k")
fi

# 7. Worktree (only when present)
if [ -n "$worktree" ]; then
  parts+=("🌳 $worktree")
fi

# Join with separator
result=""
for i in "${!parts[@]}"; do
  if [ "$i" -gt 0 ]; then
    result+="$SEP"
  fi
  result+="${parts[$i]}"
done

printf '%b' "$result"
