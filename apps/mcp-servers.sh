#!/bin/bash
# shellcheck disable=SC2034
# Managed MCP servers — the roster dotfiles/mcp-servers.conf applied to every
# installed agent CLI (Claude Code, Codex, Gemini CLI) in user scope through
# the CLI's own `mcp add`, so the servers are available in the terminal and in
# the agents' VS Code extensions alike. Engine in lib/mcp.sh; this file is the
# unit plus the github-mcp-server formula the roster's github entry needs.
# The id sorts after claude-code, codex and gemini-cli (apps/*.sh load
# alphabetically), so a fresh machine gets its servers on the first run.
APP_NAME="MCP servers (context7, GitHub)"
APP_CATEGORY="AI"
APP_NOTE="Servers are added per agent in user scope; agents not installed yet are picked up on the next update. The github server takes its token from 'gh auth token' — run 'gh auth login' once. MCP tools add to Claude Code's per-turn payload: run claude-context-audit.sh after roster changes."

mcp_servers_install()   { formula_install github-mcp-server && mcp_apply; }
mcp_servers_update()    { formula_update github-mcp-server && mcp_apply; }
# keep and zap are the same: the servers are removed from every agent's
# config either way; nothing else is written.
mcp_servers_uninstall() { mcp_remove_all && formula_uninstall github-mcp-server; }
mcp_servers_installed() { formula_installed github-mcp-server; }
