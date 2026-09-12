#!/bin/bash
# shellcheck disable=SC2034
# Claude Code plugins — the 11-plugin roster from 9 marketplaces, per the
# inventory in claude-nyamaste-studios-strategy/tech/skills.md (2026-08-27);
# ecc (Everything Claude Code, affaan-m/ecc) added 2026-09-04. Registered by
# git URL, not owner/repo shorthand: the managed settings.json declares the
# marketplace as {"source":"git","url":".../ECC.git"} and the CLI refuses to
# add a marketplace whose source kind differs from that declaration.
# Managed headlessly via the `claude plugin` CLI; requires the claude-code app.
APP_NAME="Claude Code plugins"
APP_CATEGORY="AI"
APP_NOTE="Restart Claude Code (new session) so freshly installed/updated plugins load."

CLAUDE_PLUGIN_MARKETPLACES="anthropics/claude-plugins-official mksglu/context-mode thedotmack/claude-mem forrestchang/andrej-karpathy-skills cloudflare/skills Egonex-AI/Understand-Anything anthropics/skills blader/humanizer https://github.com/affaan-m/ECC.git"

CLAUDE_PLUGINS="superpowers@claude-plugins-official frontend-design@claude-plugins-official context-mode@context-mode claude-mem@thedotmack andrej-karpathy-skills@karpathy-skills cloudflare@cloudflare understand-anything@understand-anything example-skills@anthropic-agent-skills document-skills@anthropic-agent-skills humanizer@humanizer ecc@ecc"

claude_plugins_require_cli() {
  # On a fresh machine the claude-code unit installed ~/.local/bin/claude
  # moments ago in this same run — no login shell has put it on PATH yet.
  if ! command -v claude >/dev/null 2>&1 && [ -x "$HOME/.local/bin/claude" ]; then
    PATH="$HOME/.local/bin:$PATH"
  fi
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
  # `claude plugin install` flips enabledPlugins.<p>=true in
  # ~/.claude/settings.json, but the managed settings deliberately keep some
  # of the roster installed-but-disabled. Re-apply the repo copy so the
  # profile wins even on a fresh machine (both units are sourced into the
  # same shell by discover_apps, so the claude-code helper is available).
  if command -v claude_code_settings_apply >/dev/null 2>&1; then
    claude_code_settings_apply
  fi
}

claude_plugins_update() {
  local p rc
  if ! claude_plugins_require_cli; then return 1; fi
  # `|| rc=$?` keeps the call in a condition context so errexit stays off.
  rc=0
  claude_plugins_installed || rc=$?
  if [ "$rc" = 2 ]; then
    err "claude-plugins: 'claude plugin list' failed — refusing to reinstall on a guess. Fix the claude CLI (its error is above) and re-run."
    return 1
  fi
  if [ "$rc" != 0 ] && [ "$DRY_RUN" != 1 ]; then
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

# claude_plugins_installed -> 0 every roster plugin is installed
#                             1 the CLI answered, but some are missing
#                             2 the CLI failed, so the state is unknown
# The 1/2 split is load-bearing: a `claude` that cannot run at all used to
# read as "nothing installed", which turned an update into a reinstall and
# buried the real error (see the kqueue note in docs/howto.md). `claude
# plugin list` keeps its stderr for the same reason — its diagnostics belong
# in the run log, not in /dev/null.
claude_plugins_installed() {
  local p list
  claude_plugins_require_cli 2>/dev/null || return 2
  list="$(claude plugin list)" || return 2
  # shellcheck disable=SC2086
  for p in $CLAUDE_PLUGINS; do
    case "$list" in
      *"${p%%@*}"*) ;;
      *) return 1 ;;
    esac
  done
}
