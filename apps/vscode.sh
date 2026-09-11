#!/bin/bash
# shellcheck disable=SC2034
# Visual Studio Code — Homebrew cask (self-updates). Also installs the VS Code
# extension of every managed agent CLI installed on this machine, so Claude
# Code, Codex and Gemini CLI work inside the editor with the same skills and
# MCP servers they have in the terminal: each extension drives the same CLI
# against the same ~/.claude, ~/.codex or ~/.gemini. Extensions update
# themselves inside VS Code; the pass here only fills gaps, on every
# install/update. Deselecting an agent later leaves its extension in place.
# Gemini Code Assist (google.geminicodeassist) is deliberately not on the
# roster: since 2026-09 its VS Code client refuses individual accounts
# ("no longer supported for Gemini Code Assist for individuals", pointing at
# Antigravity), so only enterprise sign-ins would get anything from it.
APP_NAME="Visual Studio Code"
APP_CATEGORY="Development"
APP_NOTE="Agent extensions (Claude Code, Codex, Gemini CLI Companion) are installed for whichever of claude-code, codex, gemini-cli is installed; each needs its own sign-in on first use. Deselecting an agent leaves its extension in place. zap removes ~/.vscode (all extensions) and VS Code's user settings."

# agent-unit-id|extension ids (space-separated). Unit ids are the apps/*.sh
# names; <unit>_installed decides whether the extensions are wanted.
VSCODE_AGENT_EXTENSIONS="claude-code|anthropic.claude-code
codex|openai.chatgpt
gemini-cli|google.gemini-cli-vscode-ide-companion"

# Install the missing extensions for every agent whose unit reports
# installed. Keeps going after a failure and returns 1 at the end if any
# install failed. The extension listing is read once per pass.
vscode_extensions_apply() {
  local rc=0 n i rec unit exts ext code list
  if ! code="$(vscode_code_bin)"; then
    if [ "$DRY_RUN" = 1 ]; then
      log "[dry-run] install agent extensions once VS Code is present"
      return 0
    fi
    err "vscode: 'code' CLI not found — cannot install agent extensions"
    return 1
  fi
  list="$("$code" --list-extensions 2>/dev/null | tr '[:upper:]' '[:lower:]')"
  # Line-numbered iteration (not `while read`) so the CLI calls inside never
  # compete with the loop for stdin — same rule as lib/skills.sh.
  n="$(printf '%s\n' "$VSCODE_AGENT_EXTENSIONS" | grep -c '|')"
  i=1
  while [ "$i" -le "$n" ]; do
    rec="$(printf '%s\n' "$VSCODE_AGENT_EXTENSIONS" | sed -n "${i}p")"
    i=$((i + 1))
    unit="${rec%%|*}"
    exts="${rec#*|}"
    if ! "$(app_fn "$unit" installed)" >/dev/null 2>&1; then continue; fi
    for ext in $exts; do
      if vscode_ext_installed "$ext" "$list"; then continue; fi
      log "vscode: installing extension $ext (for $unit)"
      if ! vscode_ext_install "$ext"; then
        err "vscode: failed to install extension $ext"
        rc=1
      fi
    done
  done
  return "$rc"
}

vscode_install()   { cask_install visual-studio-code && vscode_extensions_apply; }
vscode_update()    { cask_update visual-studio-code && vscode_extensions_apply; }
vscode_uninstall() { cask_uninstall visual-studio-code "$1"; }
vscode_installed() { cask_installed visual-studio-code; }
