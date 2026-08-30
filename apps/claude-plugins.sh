#!/bin/bash
# shellcheck disable=SC2034
# Claude Code plugins — the 11-plugin roster from 8 marketplaces, per the
# inventory in claude-nyamaste-studios-strategy/tech/skills.md (2026-08-27).
# Managed headlessly via the `claude plugin` CLI; requires the claude-code app.
APP_NAME="Claude Code plugins"
APP_NOTE="Restart Claude Code (new session) so freshly installed/updated plugins load."

CLAUDE_PLUGIN_MARKETPLACES="anthropics/claude-plugins-official mksglu/context-mode thedotmack/claude-mem forrestchang/andrej-karpathy-skills cloudflare/skills Egonex-AI/Understand-Anything anthropics/skills blader/humanizer"

CLAUDE_PLUGINS="superpowers@claude-plugins-official frontend-design@claude-plugins-official mattpocock-skills@claude-plugins-official context-mode@context-mode claude-mem@thedotmack andrej-karpathy-skills@karpathy-skills cloudflare@cloudflare understand-anything@understand-anything example-skills@anthropic-agent-skills document-skills@anthropic-agent-skills humanizer@humanizer"

claude_plugins_require_cli() {
  if ! command -v claude >/dev/null 2>&1; then
    err "claude CLI not found — select the claude-code app first"
    return 1
  fi
}

claude_plugins_install() {
  local m p
  if ! claude_plugins_require_cli; then return 1; fi
  # Re-adding an existing marketplace errors; tolerate it — a genuinely
  # missing marketplace surfaces as a loud failure at plugin install below.
  # shellcheck disable=SC2086
  for m in $CLAUDE_PLUGIN_MARKETPLACES; do
    if ! run_cmd claude plugin marketplace add "$m"; then
      log "marketplace $m: already added (or add failed — plugin install will tell)"
    fi
  done
  # shellcheck disable=SC2086
  for p in $CLAUDE_PLUGINS; do
    if ! run_cmd claude plugin install "$p"; then
      err "plugin $p: install failed"
      return 1
    fi
  done
}

claude_plugins_update() {
  local p
  if ! claude_plugins_require_cli; then return 1; fi
  if ! claude_plugins_installed && [ "$DRY_RUN" != 1 ]; then
    claude_plugins_install
    return
  fi
  run_cmd claude plugin marketplace update
  # shellcheck disable=SC2086
  for p in $CLAUDE_PLUGINS; do
    if ! run_cmd claude plugin update "$p"; then
      err "plugin $p: update failed"
      return 1
    fi
  done
}

claude_plugins_uninstall() {
  local p
  if ! claude_plugins_require_cli; then return 1; fi
  # Marketplace definitions are left in place — harmless, and they make a
  # future reinstall fast. $1 (keep|zap) is ignored: plugin data dirs are
  # only removed by `claude plugin uninstall` itself.
  # shellcheck disable=SC2086
  for p in $CLAUDE_PLUGINS; do
    if ! run_cmd claude plugin uninstall "$p"; then
      log "plugin $p: not installed, nothing to remove"
    fi
  done
}

claude_plugins_installed() {
  local p list
  command -v claude >/dev/null 2>&1 || return 1
  list="$(claude plugin list 2>/dev/null)" || return 1
  # shellcheck disable=SC2086
  for p in $CLAUDE_PLUGINS; do
    case "$list" in
      *"${p%%@*}"*) ;;
      *) return 1 ;;
    esac
  done
}
