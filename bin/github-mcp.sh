#!/bin/bash
# GitHub MCP server launcher for the managed MCP roster
# (dotfiles/mcp-servers.conf). Runs github-mcp-server (brew formula, installed
# by the mcp-servers unit) over stdio with the token gh is logged in with, so
# no token is stored in any agent's config file. Claude Code, Codex and Gemini
# CLI launch this — sometimes from a GUI app whose PATH lacks Homebrew, hence
# the explicit lookup. Toolsets are limited to keep every agent's tool list
# (and Claude Code's per-turn payload) small; widen the list here if needed.
set -u

find_bin() {
  local b
  for b in "$(command -v "$1" 2>/dev/null)" "/opt/homebrew/bin/$1" "/usr/local/bin/$1"; do
    if [ -n "$b" ] && [ -x "$b" ]; then
      printf '%s\n' "$b"
      return 0
    fi
  done
  return 1
}

if ! gh="$(find_bin gh)"; then
  echo "github-mcp: gh not found — select the gh unit in run.sh" >&2
  exit 1
fi
if ! server="$(find_bin github-mcp-server)"; then
  echo "github-mcp: github-mcp-server not found — select the mcp-servers unit in run.sh" >&2
  exit 1
fi
if ! token="$("$gh" auth token 2>/dev/null)" || [ -z "$token" ]; then
  echo "github-mcp: gh is not logged in — run: gh auth login" >&2
  exit 1
fi
GITHUB_PERSONAL_ACCESS_TOKEN="$token" exec "$server" stdio --toolsets repos,issues,pull_requests
