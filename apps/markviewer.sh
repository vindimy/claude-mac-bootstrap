#!/bin/bash
# shellcheck disable=SC2034
# MarkViewer markdown viewer/editor — Homebrew cask (auto-updates itself once installed).
APP_NAME="MarkViewer"
APP_CATEGORY="Development"

markviewer_install()   { cask_install markviewer; }
markviewer_update()    { cask_update markviewer; }
markviewer_uninstall() { cask_uninstall markviewer "$1"; }
markviewer_installed() { cask_installed markviewer; }
