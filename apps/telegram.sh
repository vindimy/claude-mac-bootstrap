#!/bin/bash
# shellcheck disable=SC2034
# Telegram Desktop (tdesktop) — Homebrew cask (auto-updates itself once installed).
# Cask `telegram-desktop`, not `telegram`: the latter is the separate native
# Swift "Telegram for macOS" build. This one installs "Telegram Desktop.app".
APP_NAME="Telegram Desktop"
APP_CATEGORY="Messaging"
APP_NOTE="Open Telegram Desktop and sign in with your phone number."

telegram_install()   { cask_install telegram-desktop; }
telegram_update()    { cask_update telegram-desktop; }
telegram_uninstall() { cask_uninstall telegram-desktop "$1"; }
telegram_installed() { cask_installed telegram-desktop; }
