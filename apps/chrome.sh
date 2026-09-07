#!/bin/bash
# shellcheck disable=SC2034
# Google Chrome — vendor dmg from dl.google.com (URL verified 2026-09-07;
# universal stable build). The brew cask is no longer used. Chrome
# self-updates, so update only reinstalls when the app is missing.
APP_NAME="Google Chrome"
APP_CATEGORY="Browsers"
APP_NOTE="Installed from Google's stable download; Chrome keeps itself current. The brew cask is not used."

CHROME_BUNDLE="Google Chrome"
CHROME_URL="https://dl.google.com/chrome/mac/universal/stable/GGRO/googlechrome.dmg"

chrome_install() {
  # Take over from a previously brew-managed install. The cask uninstall
  # removes the bundle only; the profile in ~/Library survives.
  if cask_installed google-chrome; then
    log "chrome: removing the brew cask — the vendor dmg manages Chrome now"
    cask_uninstall google-chrome || return 1
  fi
  dmg_install "$CHROME_URL" "$CHROME_BUNDLE"
}

chrome_update() {
  if cask_installed google-chrome; then
    chrome_install
    return
  fi
  dmg_update "$CHROME_URL" "$CHROME_BUNDLE"
}

chrome_uninstall() { dmg_uninstall "$CHROME_BUNDLE" "$1"; }
chrome_installed() { dmg_installed "$CHROME_BUNDLE"; }
