#!/bin/bash
# shellcheck disable=SC2034
# Google Gemini CLI — Homebrew formula. Creates ~/.gemini/skills so the skills
# units (lib/skills.sh, agent gemini-cli) can link into it on the same run;
# Gemini CLI reads that directory natively (`gemini skills list`).
APP_NAME="Gemini CLI"
APP_CATEGORY="AI"

gemini_cli_skills_dir() { run_cmd mkdir -p "$HOME/.gemini/skills"; }

gemini_cli_install()   { formula_install gemini-cli && gemini_cli_skills_dir; }
gemini_cli_update()    { formula_update gemini-cli && gemini_cli_skills_dir; }
# keep leaves ~/.gemini (settings, skills links, MCP config); zap removes it.
gemini_cli_uninstall() {
  formula_uninstall gemini-cli "$1" || return 1
  if [ "${1:-keep}" = zap ]; then run_cmd rm -rf "$HOME/.gemini"; fi
}
gemini_cli_installed() { formula_installed gemini-cli; }
