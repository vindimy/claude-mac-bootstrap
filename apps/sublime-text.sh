#!/bin/bash
# shellcheck disable=SC2034
# Sublime Text editor — Homebrew cask.
APP_NAME="Sublime Text"
APP_CATEGORY="Development"

sublime_text_install()   { cask_install sublime-text; }
sublime_text_update()    { cask_update sublime-text; }
sublime_text_uninstall() { cask_uninstall sublime-text "$1"; }
sublime_text_installed() { cask_installed sublime-text; }
