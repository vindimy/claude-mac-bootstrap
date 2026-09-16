#!/bin/bash
# shellcheck disable=SC2034
# Google Gemini CLI — Homebrew formula. Creates ~/.gemini/skills so the skills
# units (lib/skills.sh, agent gemini-cli) can link into it on the same run;
# Gemini CLI reads that directory natively (`gemini skills list`). Also pins
# Auto Memory off in ~/.gemini/settings.json on every install/update.
APP_NAME="Gemini CLI"
APP_CATEGORY="AI"
APP_NOTE="Auto Memory (experimental.autoMemory) is pinned off in ~/.gemini/settings.json on every install/update; the Gemini CLI Companion VS Code extension runs this same CLI, so it holds there too. Only that key is written."

GEMINI_CLI_SETTINGS="$HOME/.gemini/settings.json"

gemini_cli_skills_dir() { run_cmd mkdir -p "$HOME/.gemini/skills"; }

# Auto Memory extracts memory patches from past sessions in the background.
# Off by default today; pinned so an upstream default flip cannot turn it on.
# Only this key is written — the mcp-servers unit's entries and everything
# else in settings.json stay. A settings.json that does not parse fails the
# unit rather than being overwritten.
gemini_cli_settings_apply() {
  if json_bool_is "$GEMINI_CLI_SETTINGS" experimental.autoMemory false; then return 0; fi
  log "gemini-cli: turning Auto Memory off in ~/.gemini/settings.json"
  json_set_bool "$GEMINI_CLI_SETTINGS" experimental.autoMemory false
}

gemini_cli_install()   { formula_install gemini-cli && gemini_cli_skills_dir && gemini_cli_settings_apply; }
gemini_cli_update()    { formula_update gemini-cli && gemini_cli_skills_dir && gemini_cli_settings_apply; }
# keep leaves ~/.gemini (settings, skills links, MCP config); zap removes it.
gemini_cli_uninstall() {
  formula_uninstall gemini-cli "$1" || return 1
  if [ "${1:-keep}" = zap ]; then run_cmd rm -rf "$HOME/.gemini"; fi
}
gemini_cli_installed() { formula_installed gemini-cli; }
