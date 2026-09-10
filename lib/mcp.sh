#!/bin/bash
# Managed MCP servers: apply the repo roster dotfiles/mcp-servers.conf to
# every installed agent CLI (Claude Code, Codex, Gemini CLI) through the
# CLI's own `mcp add` / `mcp remove` in user scope, so the servers are there
# in the terminal and in the agents' VS Code extensions alike. Sourced after
# lib/drivers.sh by run.sh, update.sh and the tests. Pure functions; every
# mutation goes through run_cmd; nothing writes to stdout inside a function
# whose output is captured.
#
# Roster record: name|transport|command-or-url [args...]
#   transport  stdio | http
#   a leading ~/ in the target is expanded to $HOME (the CLIs do not)
#
# State ($CONFIG_DIR/mcp.conf): TSV, one "agent<TAB>name<TAB>record" line per
# server this unit applied. A record that changed upstream is re-applied
# (remove + add); a name dropped from the roster is removed. Servers the user
# added themselves are never in the state file and are never touched — a
# roster name that already exists on an agent is left alone, not recorded.

MCP_ROSTER_FILE="${MCP_ROSTER_FILE:-$REPO_ROOT/dotfiles/mcp-servers.conf}"
MCP_KNOWN_AGENTS="claude codex gemini"

# ---- roster ------------------------------------------------------------------

# Prints the records (no comments, no blank lines); rc 1 when the file is missing.
mcp_roster_records() {
  if [ ! -f "$MCP_ROSTER_FILE" ]; then return 1; fi
  grep -v -e '^[[:space:]]*#' -e '^[[:space:]]*$' "$MCP_ROSTER_FILE"
  return 0
}

mcp_record_name()      { printf '%s\n' "$1" | cut -d'|' -f1; }
mcp_record_transport() { printf '%s\n' "$1" | cut -d'|' -f2; }

# The command line (stdio) or URL (http), with a leading ~/ expanded.
mcp_record_target() {
  local t
  t="$(printf '%s\n' "$1" | cut -d'|' -f3-)"
  # shellcheck disable=SC2088  # case pattern match on a literal "~/" prefix, not tilde expansion
  case "$t" in
    "~/"*) t="$HOME/${t#\~/}" ;;
  esac
  printf '%s\n' "$t"
}

# 0 when name, transport and target are all acceptable.
mcp_record_valid() {
  local name transport target
  name="$(mcp_record_name "$1")"
  transport="$(mcp_record_transport "$1")"
  target="$(mcp_record_target "$1")"
  printf '%s' "$name" | grep -Eq '^[A-Za-z0-9_-]+$' || return 1
  case "$transport" in
    stdio | http) ;;
    *) return 1 ;;
  esac
  [ -n "$target" ]
}

# ---- agents ------------------------------------------------------------------

# Claude Code's native install is ~/.local/bin/claude (apps/claude-code.sh);
# codex and gemini are brew-installed and on PATH.
mcp_agent_cli() {
  case "$1" in
    claude) printf '%s/.local/bin/claude\n' "$HOME" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

mcp_agent_ready() {
  case "$1" in
    claude) [ -x "$HOME/.local/bin/claude" ] ;;
    codex | gemini) command -v "$1" >/dev/null 2>&1 ;;
    *) return 1 ;;
  esac
}

mcp_ready_agents() {
  local a out=""
  for a in $MCP_KNOWN_AGENTS; do
    if mcp_agent_ready "$a"; then out="$out $a"; fi
  done
  printf '%s\n' "${out# }"
}

# mcp_agent_has agent name -> 0 when the agent already has a server by that
# name (any scope). Gemini has no `mcp get`, so its settings file is read.
mcp_agent_has() {
  case "$1" in
    claude | codex) "$(mcp_agent_cli "$1")" mcp get "$2" >/dev/null 2>&1 </dev/null ;;
    gemini)
      if [ ! -f "$HOME/.gemini/settings.json" ]; then return 1; fi
      python3 - "$HOME/.gemini/settings.json" "$2" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
sys.exit(0 if sys.argv[2] in (d.get("mcpServers") or {}) else 1)
PY
      ;;
    *) return 1 ;;
  esac
}

# mcp_agent_add agent record — the per-CLI add command in user scope.
mcp_agent_add() {
  local agent="$1" rec="$2" cli name transport target
  cli="$(mcp_agent_cli "$agent")"
  name="$(mcp_record_name "$rec")"
  transport="$(mcp_record_transport "$rec")"
  target="$(mcp_record_target "$rec")"
  # shellcheck disable=SC2086  # a stdio target is a command line: split on purpose
  case "$agent:$transport" in
    claude:stdio) run_cmd "$cli" mcp add -s user "$name" -- $target ;;
    claude:http)  run_cmd "$cli" mcp add -s user --transport http "$name" "$target" ;;
    codex:stdio)  run_cmd "$cli" mcp add "$name" -- $target ;;
    codex:http)   run_cmd "$cli" mcp add "$name" --url "$target" ;;
    gemini:stdio) run_cmd "$cli" mcp add -s user "$name" -- $target ;;
    gemini:http)  run_cmd "$cli" mcp add -s user -t http "$name" "$target" ;;
    *)
      err "mcp: unsupported agent/transport '$agent/$transport' for '$name'"
      return 1
      ;;
  esac
}

mcp_agent_remove() {
  local cli
  cli="$(mcp_agent_cli "$1")"
  case "$1" in
    claude | gemini) run_cmd "$cli" mcp remove -s user "$2" ;;
    codex) run_cmd "$cli" mcp remove "$2" ;;
    *) return 1 ;;
  esac
}
