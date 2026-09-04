#!/bin/bash
# shellcheck disable=SC2034
# Google Chrome — Homebrew cask (auto-updates itself once installed).
APP_NAME="Google Chrome"
APP_CATEGORY="Browsers"

chrome_install()   { cask_install google-chrome; }
chrome_update()    { cask_update google-chrome; }
chrome_uninstall() { cask_uninstall google-chrome "$1"; }
chrome_installed() { cask_installed google-chrome; }
