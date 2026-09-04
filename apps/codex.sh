#!/bin/bash
# shellcheck disable=SC2034
# OpenAI Codex CLI — Homebrew cask (binary release from github.com/openai/codex;
# does not self-update, so update.sh upgrades it via brew).
APP_NAME="Codex CLI"
APP_CATEGORY="AI"

codex_install()   { cask_install codex; }
codex_update()    { cask_update codex; }
codex_uninstall() { cask_uninstall codex "$1"; }
codex_installed() { cask_installed codex; }
