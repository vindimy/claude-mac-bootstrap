#!/bin/bash
# shellcheck disable=SC2034
# Dropbox — Homebrew cask (auto-updates itself once installed).
APP_NAME="Dropbox"
APP_NOTE="Open Dropbox and sign in to start syncing (per-machine sync selections are manual)."

dropbox_install()   { cask_install dropbox; }
dropbox_update()    { cask_update dropbox; }
dropbox_uninstall() { cask_uninstall dropbox "$1"; }
dropbox_installed() { cask_installed dropbox; }
