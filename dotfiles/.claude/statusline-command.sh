#!/bin/bash
# Claude Code status line: repo name, git branch, context usage bar, model.

input=$(cat)

cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd')
model=$(echo "$input" | jq -r '.model.display_name')
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

# Repo name: prefer the resolved repo identity, fall back to the git toplevel
# directory name, then the current directory name.
repo=$(echo "$input" | jq -r '.workspace.repo.name // empty')
if [ -z "$repo" ]; then
  toplevel=$(git -C "$cwd" --no-optional-locks rev-parse --show-toplevel 2>/dev/null)
  if [ -n "$toplevel" ]; then
    repo=$(basename "$toplevel")
  else
    repo=$(basename "$cwd")
  fi
fi

# Current git branch (empty if not in a repo or detached with no name).
branch=$(git -C "$cwd" --no-optional-locks rev-parse --abbrev-ref HEAD 2>/dev/null)

# Context usage bar (10 cells wide).
bar=""
if [ -n "$used_pct" ]; then
  width=10
  filled=$(awk -v p="$used_pct" -v w="$width" 'BEGIN { printf "%.0f", (p / 100) * w }')
  [ "$filled" -gt "$width" ] && filled=$width
  [ "$filled" -lt 0 ] && filled=0
  empty=$((width - filled))
  for ((i = 0; i < filled; i++)); do bar+="#"; done
  for ((i = 0; i < empty; i++)); do bar+="-"; done
fi

RESET='\033[0m'
CYAN='\033[1;96m'
YELLOW='\033[1;93m'
GREEN='\033[1;92m'
RED='\033[1;91m'
MAGENTA='\033[1;95m'
SEP=" | "

# Pick the bar color based on how full context usage is.
BAR_COLOR="$GREEN"
if [ -n "$used_pct" ]; then
  is_high=$(awk -v p="$used_pct" 'BEGIN { print (p >= 80) ? 1 : 0 }')
  is_mid=$(awk -v p="$used_pct" 'BEGIN { print (p >= 50) ? 1 : 0 }')
  if [ "$is_high" -eq 1 ]; then
    BAR_COLOR="$RED"
  elif [ "$is_mid" -eq 1 ]; then
    BAR_COLOR="$YELLOW"
  fi
fi

out="${CYAN}${repo}${RESET}"
[ -n "$branch" ] && out="${out}${SEP}${YELLOW}${branch}${RESET}"
if [ -n "$bar" ]; then
  used_display=$(printf '%.0f' "$used_pct")
  out="${out}${SEP}${BAR_COLOR}[${bar}] ${used_display}%${RESET}"
fi
out="${out}${SEP}${MAGENTA}${model}${RESET}"

printf "%b\n" "$out"
