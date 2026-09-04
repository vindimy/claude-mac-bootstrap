#!/bin/bash
# shellcheck disable=SC2034
# Maccy clipboard manager — Homebrew cask.
APP_NAME="Maccy"
APP_CATEGORY="System Tools"

maccy_install()   { cask_install maccy; }
maccy_update()    { cask_update maccy; }
maccy_uninstall() { cask_uninstall maccy "$1"; }
maccy_installed() { cask_installed maccy; }
