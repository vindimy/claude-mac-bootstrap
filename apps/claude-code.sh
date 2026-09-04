#!/bin/bash
# shellcheck disable=SC2034
# Claude Code CLI — native installer (https://claude.ai/install.sh).
# The brew cask lags many versions behind, so brew no longer manages this.
# Footprint: ~/.local/bin/claude symlink into ~/.local/share/claude/versions/.
APP_NAME="Claude Code"
APP_CATEGORY="AI"
APP_NOTE="Installed via the native installer; the app keeps itself current. The brew cask is not used — it trails releases."

claude_code_installed() { [ -x "$HOME/.local/bin/claude" ]; }

claude_code_install() {
  # Take over from a previously brew-managed install: the cask trails
  # releases, and its binary on PATH would conflict with the native one.
  if cask_installed claude-code; then
    log "claude-code: removing the brew cask — the native installer manages Claude Code now"
    cask_uninstall claude-code
  fi
  if [ "$DRY_RUN" = 1 ]; then
    log "[dry-run] install Claude Code from https://claude.ai/install.sh"
    return 0
  fi
  # Bypasses run_cmd: a pipeline can't be passed to it as a simple command.
  if ! curl -fsSL https://claude.ai/install.sh | bash; then
    err "Claude Code: native installer failed — see https://code.claude.com/docs/setup"
    return 1
  fi
}

# The native install auto-updates in the background; `claude update` just
# forces the check now.
claude_code_update() {
  if ! claude_code_installed; then
    claude_code_install
    return
  fi
  run_cmd "$HOME/.local/bin/claude" update
}

# Zap also removes ~/.claude and ~/.claude.json (settings, history, skills,
# plugins) — that wipes the footprint of the claude-plugins, gsd, and
# agent-skills units too, so zap only when abandoning Claude Code entirely.
claude_code_uninstall() {
  if ! claude_code_installed && ! cask_installed claude-code; then
    log "claude-code: not installed, nothing to remove"
    return 0
  fi
  if cask_installed claude-code; then
    cask_uninstall claude-code "$1"
  fi
  run_cmd rm -f "$HOME/.local/bin/claude"
  run_cmd rm -rf "$HOME/.local/share/claude"
  if [ "${1:-keep}" = zap ]; then
    run_cmd rm -rf "$HOME/.claude" "$HOME/.claude.json"
  fi
}
