#!/bin/bash
# shellcheck disable=SC2034
# Claude Code CLI — native installer (https://claude.ai/install.sh).
# The brew cask lags many versions behind, so brew no longer manages this.
# Footprint: ~/.local/bin/claude symlink into ~/.local/share/claude/versions/,
# plus ~/.claude/settings.json and ~/.claude/statusline-command.sh, copies of
# the same-named files under dotfiles/.claude/.
APP_NAME="Claude Code"
APP_CATEGORY="AI"
APP_NOTE="Installed via the native installer; the app keeps itself current. The brew cask is not used — it trails releases. ~/.claude/settings.json and ~/.claude/statusline-command.sh are overwritten from the repo's dotfiles/.claude/ copies on every install/update — edit the repo copies, not the live files."

CLAUDE_CODE_SETTINGS_SRC="$REPO_ROOT/dotfiles/.claude/settings.json"
CLAUDE_CODE_SETTINGS_DST="$HOME/.claude/settings.json"
CLAUDE_CODE_STATUSLINE_SRC="$REPO_ROOT/dotfiles/.claude/statusline-command.sh"
CLAUDE_CODE_STATUSLINE_DST="$HOME/.claude/statusline-command.sh"

claude_code_installed() { [ -x "$HOME/.local/bin/claude" ]; }

# Global settings are a managed file: the repo copy is authoritative and
# replaces ~/.claude/settings.json whenever they differ. A copy, not a
# symlink — Claude Code rewrites settings.json itself (plugin toggles,
# /model, /theme, `claude plugin install`), and a symlink would either leak
# those edits into the checkout or be replaced by a plain file on an atomic
# save. Drift is therefore expected and is corrected on every update run;
# the first adoption of a differing file is kept as settings.json.pre-bootstrap.bak.
claude_code_settings_in_sync() { cmp -s "$CLAUDE_CODE_SETTINGS_SRC" "$CLAUDE_CODE_SETTINGS_DST"; }

claude_code_settings_apply() {
  local bak="$CLAUDE_CODE_SETTINGS_DST.pre-bootstrap.bak"
  if [ ! -f "$CLAUDE_CODE_SETTINGS_SRC" ]; then
    err "claude-code: $CLAUDE_CODE_SETTINGS_SRC missing from the repo"
    return 1
  fi
  if claude_code_settings_in_sync; then return 0; fi
  if [ -f "$CLAUDE_CODE_SETTINGS_DST" ]; then
    if [ ! -f "$bak" ]; then
      log "claude-code: keeping the pre-bootstrap ~/.claude/settings.json as $bak"
      run_cmd cp -p "$CLAUDE_CODE_SETTINGS_DST" "$bak" || return 1
    fi
    log "claude-code: ~/.claude/settings.json differs from the repo copy — overwriting (repo is authoritative)"
  else
    log "claude-code: installing ~/.claude/settings.json from the repo"
  fi
  run_cmd mkdir -p "$(dirname "$CLAUDE_CODE_SETTINGS_DST")" || return 1
  run_cmd cp "$CLAUDE_CODE_SETTINGS_SRC" "$CLAUDE_CODE_SETTINGS_DST" || return 1
  # Settings can hold tokens/paths; match Claude Code's own 0600.
  run_cmd chmod 600 "$CLAUDE_CODE_SETTINGS_DST"
}

# The status line script settings.json points at (statusLine.command). Same
# rule as settings: repo copy is authoritative, re-copied whenever it differs.
# Nothing else writes this file, so no pre-bootstrap backup is kept.
claude_code_statusline_apply() {
  if [ ! -f "$CLAUDE_CODE_STATUSLINE_SRC" ]; then
    err "claude-code: $CLAUDE_CODE_STATUSLINE_SRC missing from the repo"
    return 1
  fi
  if cmp -s "$CLAUDE_CODE_STATUSLINE_SRC" "$CLAUDE_CODE_STATUSLINE_DST"; then return 0; fi
  log "claude-code: installing ~/.claude/statusline-command.sh from the repo"
  run_cmd mkdir -p "$(dirname "$CLAUDE_CODE_STATUSLINE_DST")" || return 1
  run_cmd cp "$CLAUDE_CODE_STATUSLINE_SRC" "$CLAUDE_CODE_STATUSLINE_DST" || return 1
  run_cmd chmod 755 "$CLAUDE_CODE_STATUSLINE_DST"
}

# Everything the unit manages under ~/.claude, in one call.
claude_code_files_apply() {
  local rc=0
  claude_code_settings_apply || rc=1
  claude_code_statusline_apply || rc=1
  return "$rc"
}

claude_code_install() {
  # Take over from a previously brew-managed install: the cask trails
  # releases, and its binary on PATH would conflict with the native one.
  if cask_installed claude-code; then
    log "claude-code: removing the brew cask — the native installer manages Claude Code now"
    cask_uninstall claude-code
  fi
  if [ "$DRY_RUN" = 1 ]; then
    log "[dry-run] install Claude Code from https://claude.ai/install.sh"
  # Bypasses run_cmd: a pipeline can't be passed to it as a simple command.
  elif ! curl -fsSL https://claude.ai/install.sh | bash; then
    err "Claude Code: native installer failed — see https://code.claude.com/docs/setup"
    return 1
  fi
  claude_code_files_apply
}

# The native install auto-updates in the background; `claude update` just
# forces the check now. Settings and the status line script are re-applied
# here so every update.sh run corrects drift.
claude_code_update() {
  if ! claude_code_installed; then
    claude_code_install
    return
  fi
  run_cmd "$HOME/.local/bin/claude" update || return 1
  claude_code_files_apply
}

# keep leaves ~/.claude/settings.json in place (it is the user's settings,
# managed or not). Zap also removes ~/.claude and ~/.claude.json (settings,
# history, skills, plugins) — that wipes the footprint of the claude-plugins,
# gsd, and agent-skills units too, so zap only when abandoning Claude Code
# entirely.
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
