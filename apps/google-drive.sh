#!/bin/bash
# shellcheck disable=SC2034
# Google Drive — Homebrew cask (auto-updates itself once installed).
APP_NAME="Google Drive"
APP_CATEGORY="Cloud Storage"
APP_NOTE="Open Google Drive and sign in to start syncing."

google_drive_install()   { cask_install google-drive; }
google_drive_update()    { cask_update google-drive; }
google_drive_uninstall() { cask_uninstall google-drive "$1"; }
google_drive_installed() { cask_installed google-drive; }
