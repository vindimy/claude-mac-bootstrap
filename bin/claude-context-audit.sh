#!/bin/bash
# Claude Code context audit: measure the hidden per-turn payload (tool schemas,
# skills catalogue, system prompt) and track it over time.
#
# Runs Matt Pocock's zero-dependency logging proxy (agent-proxy, proxy.mjs)
# between Claude Code and the API, sends one headless probe through it, and
# records the proxy's ranked summary: tool count, tool bytes, real input
# tokens. Each run is appended to history.tsv so growth is visible, and a
# stamp file lets .zprofile / run.sh / update.sh nag when an audit is due.
#
# Managed by the claude-mac-bootstrap repo (bin/claude-context-audit.sh);
# install.sh symlinks it into ~/.local/bin. Bash 3.2 compatible.
#
# Usage: claude-context-audit.sh [--interactive] [--here] [--refresh]
#                                [--top N] [--dry-run] | --due | --help
set -u

# The proxy is fetched (not vendored — the gist carries no licence) from a
# pinned revision so a run today and a run next year measure the same way.
PROXY_GIST_ID="5b3d76ea21f5f698aefded47a9cea3b1"
PROXY_GIST_REV="e142f08fd2d1de0adc914355112d6f2b56386959"
PROXY_URL="https://gist.githubusercontent.com/mattpocock/$PROXY_GIST_ID/raw/$PROXY_GIST_REV/proxy.mjs"
PROXY_PORT_DEFAULT=8787
DUE_AFTER_DAYS=30
PROBE_PROMPT="Reply with exactly: ok"

STATE_DIR="${CLAUDE_CONTEXT_AUDIT_STATE:-$HOME/.local/state/claude-context-audit}"
PROXY_DIR="$STATE_DIR/agent-proxy"     # proxy.mjs lives here; it writes logs/ beside itself
PROXY_FILE="$PROXY_DIR/proxy.mjs"
PROBE_DIR="$STATE_DIR/probe"           # empty dir: no project CLAUDE.md, no project MCP servers
HISTORY_FILE="$STATE_DIR/history.tsv"
STAMP_FILE="$STATE_DIR/last-run.stamp"
CLAUDE_BIN="$HOME/.local/bin/claude"

# --- pure helpers (also sourced by tests with CLAUDE_CONTEXT_AUDIT_LIB=1) ----

# "[agent-proxy] 69 tools · 154,946 tool bytes · 65,538 real input tokens"
# -> "69<TAB>154946<TAB>65538" (tokens empty if the proxy saw no usage event).
cca_parse_summary() {
  case "$1" in
    "[agent-proxy] "*" tools "*" tool bytes"*) ;;
    *) return 1 ;;
  esac
  printf '%s\n' "$1" | awk '
    function num(re,  v) { if (!match($0, re)) return ""; v = substr($0, RSTART, RLENGTH); sub(/ .*/, "", v); gsub(/,/, "", v); return v }
    { printf "%s\t%s\t%s\n", $2, num("[0-9,]+ tool bytes"), num("[0-9,]+ real input tokens") }'
}

# The proxy logs every request, including small side requests (titles,
# classifiers) that carry few tools. The audit is the biggest one.
cca_pick_summary() {
  awk '
    /^\[agent-proxy\] .* tools / {
      if (match($0, /[0-9,]+ real input tokens/)) { v = substr($0, RSTART, RLENGTH); sub(/ .*/, "", v); gsub(/,/, "", v) }
      else { v = $2 }
      if (v + 0 >= best) { best = v + 0; line = $0 }
    }
    END { if (line == "") exit 1; print line }' "$1" 2>/dev/null
}

# The chosen summary line plus its ranked table, through the "logs/…" line.
cca_report_block() {
  local want
  want="$(cca_pick_summary "$1")" || return 1
  awk -v want="$want" '
    $0 == want { on = 1 }
    on { print }
    on && /^  logs\// { exit }' "$1"
}

# Same block, table trimmed to the first N rows; summary, "… more" and the
# log path always survive.
cca_report_top() { # file N
  cca_report_block "$1" | awk -v top="$2" '
    NR == 1 || !/ B  ~[0-9]+ tok$/ { print; next }
    ++rows <= top { print }'
}

# Integer percent growth from prev to new; empty when there is no baseline.
cca_growth_pct() {
  local prev="${1:-}" new="${2:-}"
  if [ -z "$prev" ] || [ -z "$new" ] || [ "$prev" = 0 ]; then return 0; fi
  awk -v p="$prev" -v n="$new" 'BEGIN { printf "%d\n", int((n - p) * 100 / p) }'
}

cca_history_append() { # file date tools bytes tokens mode
  local file="$1"
  if [ ! -f "$file" ]; then
    mkdir -p "$(dirname "$file")"
    printf 'date\ttools\ttool_bytes\tinput_tokens\tmode\n' >"$file"
  fi
  printf '%s\t%s\t%s\t%s\t%s\n' "$2" "$3" "$4" "$5" "$6" >>"$file"
}

cca_history_last() { [ -f "$1" ] && tail -n +2 "$1" | tail -1; return 0; }
cca_history_last_tokens() { cca_history_last "$1" | cut -f4; }

# Days since the stamp, or "never".
cca_stamp_age_days() {
  local stamp="$1" now mtime
  [ -f "$stamp" ] || { printf 'never\n'; return 0; }
  now="$(date +%s)"
  mtime="$(stat -f %m "$stamp")"
  printf '%d\n' $(( (now - mtime) / 86400 ))
}

# Exit 0 (and say so) when an audit is due: claude installed and the last run
# is older than DUE_AFTER_DAYS or absent. Quiet exit 1 otherwise.
cca_due() {
  local age
  [ -x "$CLAUDE_BIN" ] || return 1
  age="$(cca_stamp_age_days "$STAMP_FILE")"
  if [ "$age" = never ]; then
    printf 'claude-context-audit: never run — run claude-context-audit.sh to measure the per-turn payload\n'
    return 0
  fi
  if [ "$age" -ge "$DUE_AFTER_DAYS" ]; then
    printf 'claude-context-audit: last run %s days ago — run claude-context-audit.sh\n' "$age"
    return 0
  fi
  return 1
}

[ "${CLAUDE_CONTEXT_AUDIT_LIB:-0}" = 1 ] && return 0

# --- the run ----------------------------------------------------------------

usage() {
  cat <<'USAGE'
Usage: claude-context-audit.sh [--interactive] [--here] [--refresh] [--top N] [--dry-run]
       claude-context-audit.sh --due
       claude-context-audit.sh --help

Measures what Claude Code sends the model on every turn. Starts a local
logging proxy (agent-proxy), sends one headless probe through it from an empty
directory, and records tool count / tool bytes / real input tokens in
~/.local/state/claude-context-audit/history.tsv. The full request (system
prompt, every tool schema) is kept as Markdown under
~/.local/state/claude-context-audit/agent-proxy/logs/.

  --interactive  open a normal Claude Code session through the proxy instead
                 of the headless probe; quit it when done and the biggest
                 request of the session is recorded
  --here         probe from the current directory (includes this project's
                 CLAUDE.md, MCP servers, plugins) instead of the neutral dir
  --refresh      re-download proxy.mjs (pinned revision)
  --top N        rows of the ranked tool table to print (default 12)
  --dry-run      print what would run; touch nothing
  --due          exit 0 and print a line when the last audit is 30+ days old
                 or missing (used by .zprofile, run.sh, update.sh)

One probe costs one API request of roughly your normal per-turn size.
USAGE
}

MODE=headless
WHERE=global
REFRESH=0
DRY_RUN=0
TOP=12
while [ $# -gt 0 ]; do
  case "$1" in
    --interactive) MODE=interactive ;;
    --here) WHERE=here ;;
    --refresh) REFRESH=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --top)
      shift
      TOP="${1:-}"
      case "$TOP" in '' | *[!0-9]*) echo "error: --top needs a number" >&2; exit 2 ;; esac
      ;;
    --due) cca_due; exit $? ;;
    -h | --help) usage; exit 0 ;;
    *)
      echo "error: unknown flag: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

say() { printf '%s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

port_busy() { lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1; }
pick_port() {
  local p="$PROXY_PORT_DEFAULT" tries=0
  while port_busy "$p"; do
    p=$((p + 1)); tries=$((tries + 1))
    [ "$tries" -lt 20 ] || die "no free port between $PROXY_PORT_DEFAULT and $p"
  done
  printf '%s\n' "$p"
}

PORT="$(pick_port)"
BASE_URL="http://localhost:$PORT"
if [ "$WHERE" = here ]; then RUN_DIR="$PWD"; else RUN_DIR="$PROBE_DIR"; fi

if [ "$DRY_RUN" = 1 ]; then
  say "[dry-run] state dir: $STATE_DIR"
  if [ ! -f "$PROXY_FILE" ] || [ "$REFRESH" = 1 ]; then
    say "[dry-run] curl -fsSL $PROXY_URL -o $PROXY_FILE"
  else
    say "[dry-run] proxy.mjs present (gist rev ${PROXY_GIST_REV%${PROXY_GIST_REV#????????????}})"
  fi
  say "[dry-run] (cd $PROXY_DIR && PORT=$PORT node proxy.mjs)   # background"
  if [ "$MODE" = interactive ]; then
    say "[dry-run] (cd $RUN_DIR && ANTHROPIC_BASE_URL=$BASE_URL claude)"
  else
    say "[dry-run] (cd $RUN_DIR && ANTHROPIC_BASE_URL=$BASE_URL claude -p '$PROBE_PROMPT' --max-turns 1)"
  fi
  say "[dry-run] append to $HISTORY_FILE; touch $STAMP_FILE"
  exit 0
fi

[ -x "$CLAUDE_BIN" ] || die "Claude Code is not installed at $CLAUDE_BIN (run ./run.sh and select claude-code)"
command -v node >/dev/null 2>&1 || die "node not found — brew install node (the proxy needs Node 18+)"

mkdir -p "$PROXY_DIR" "$PROBE_DIR"
if [ ! -f "$PROXY_FILE" ] || [ "$REFRESH" = 1 ]; then
  say "fetching agent-proxy (gist rev ${PROXY_GIST_REV%${PROXY_GIST_REV#????????????}}) …"
  curl -fsSL "$PROXY_URL" -o "$PROXY_FILE.tmp" || die "could not download $PROXY_URL"
  grep -q 'agent-proxy' "$PROXY_FILE.tmp" || die "downloaded file does not look like proxy.mjs"
  mv "$PROXY_FILE.tmp" "$PROXY_FILE"
fi

PROXY_OUT="$(mktemp "${TMPDIR:-/tmp}/claude-context-audit.XXXXXX")"
PROXY_PID=""
cleanup() {
  [ -n "$PROXY_PID" ] && kill "$PROXY_PID" 2>/dev/null
  rm -f "$PROXY_OUT"
}
trap cleanup EXIT INT TERM

(cd "$PROXY_DIR" && PORT="$PORT" exec node proxy.mjs) >"$PROXY_OUT" 2>&1 &
PROXY_PID=$!
waited=0
until port_busy "$PORT"; do
  kill -0 "$PROXY_PID" 2>/dev/null || { cat "$PROXY_OUT" >&2; die "proxy exited before listening"; }
  sleep 0.2; waited=$((waited + 1))
  [ "$waited" -lt 50 ] || die "proxy did not start listening on $BASE_URL within 10s"
done

if [ "$MODE" = interactive ]; then
  say "proxy on $BASE_URL — opening Claude Code in $RUN_DIR; send a message, then quit to record the audit"
  (cd "$RUN_DIR" && ANTHROPIC_BASE_URL="$BASE_URL" "$CLAUDE_BIN")
else
  say "proxy on $BASE_URL — sending one headless probe from $RUN_DIR …"
  (cd "$RUN_DIR" && ANTHROPIC_BASE_URL="$BASE_URL" "$CLAUDE_BIN" -p "$PROBE_PROMPT" --max-turns 1 >/dev/null) ||
    say "warning: the probe exited non-zero; recording whatever the proxy saw"
fi
sleep 0.5   # let the proxy flush its summary after the stream closes

summary="$(cca_pick_summary "$PROXY_OUT")" || { cat "$PROXY_OUT" >&2; die "the proxy saw no request — nothing recorded"; }
parsed="$(cca_parse_summary "$summary")"
tools="$(printf '%s' "$parsed" | cut -f1)"
bytes="$(printf '%s' "$parsed" | cut -f2)"
tokens="$(printf '%s' "$parsed" | cut -f3)"
prev_tokens="$(cca_history_last_tokens "$HISTORY_FILE")"
prev_row="$(cca_history_last "$HISTORY_FILE")"

say ""
cca_report_top "$PROXY_OUT" "$TOP" | sed "s#^  logs/#  $PROXY_DIR/logs/#"
say ""
if [ -n "$prev_row" ]; then
  say "previous: $(printf '%s' "$prev_row" | cut -f1) — $(printf '%s' "$prev_row" | cut -f2) tools, $(printf '%s' "$prev_row" | cut -f4) input tokens ($(printf '%s' "$prev_row" | cut -f5))"
  growth="$(cca_growth_pct "$prev_tokens" "$tokens")"
  if [ -n "$growth" ]; then
    if [ "$growth" -ge 10 ]; then
      say "WARNING: input tokens grew ${growth}% since the last audit — something new is riding along on every turn. Trim it in dotfiles/.claude/settings.json (permissions.deny with bare tool names, disable* flags, skillOverrides)."
    elif [ "$growth" -le -10 ]; then
      say "input tokens down ${growth#-}% since the last audit"
    else
      say "input tokens within ±10% of the last audit (${growth}%)"
    fi
  fi
else
  say "first audit recorded — this is the baseline"
fi
cca_history_append "$HISTORY_FILE" "$(date +%Y-%m-%d)" "$tools" "$bytes" "$tokens" "$MODE $WHERE"
touch "$STAMP_FILE"
say "history: $HISTORY_FILE"
