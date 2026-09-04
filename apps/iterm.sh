#!/bin/bash
# shellcheck disable=SC2034
# iTerm2 — Homebrew cask (auto-updates itself once installed).
APP_NAME="iTerm2"

iterm_install()   { cask_install iterm2; }
iterm_update()    { cask_update iterm2; }
iterm_uninstall() { cask_uninstall iterm2 "$1"; }
iterm_installed() { cask_installed iterm2; }
