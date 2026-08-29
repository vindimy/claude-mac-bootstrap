#!/bin/bash
# shellcheck disable=SC2034
# Claude Desktop — Homebrew cask (auto-updates itself once installed).
APP_NAME="Claude Desktop"

claude_install()   { cask_install claude; }
claude_update()    { cask_update claude; }
claude_uninstall() { cask_uninstall claude "$1"; }
claude_installed() { cask_installed claude; }
