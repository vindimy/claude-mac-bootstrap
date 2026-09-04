#!/bin/bash
# shellcheck disable=SC2034
# Google Gemini CLI — Homebrew formula.
APP_NAME="Gemini CLI"
APP_CATEGORY="AI"

gemini_cli_install()   { formula_install gemini-cli; }
gemini_cli_update()    { formula_update gemini-cli; }
gemini_cli_uninstall() { formula_uninstall gemini-cli "$1"; }
gemini_cli_installed() { formula_installed gemini-cli; }
