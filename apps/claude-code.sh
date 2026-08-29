#!/bin/bash
# shellcheck disable=SC2034
# Claude Code CLI — Homebrew cask.
APP_NAME="Claude Code"

claude_code_install()   { cask_install claude-code; }
claude_code_update()    { cask_update claude-code; }
claude_code_uninstall() { cask_uninstall claude-code "$1"; }
claude_code_installed() { cask_installed claude-code; }
