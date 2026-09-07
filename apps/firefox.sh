#!/bin/bash
# shellcheck disable=SC2034
# Mozilla Firefox — vendor dmg from download.mozilla.org (URL verified
# 2026-09-07; redirects to the current stable universal build). The brew
# cask is no longer used. Firefox self-updates, so update only reinstalls
# when the app is missing.
APP_NAME="Firefox"
APP_CATEGORY="Browsers"
APP_NOTE="Installed from Mozilla's stable download; Firefox keeps itself current. The brew cask is not used."

FIREFOX_BUNDLE="Firefox"
FIREFOX_URL="https://download.mozilla.org/?product=firefox-latest-ssl&os=osx&lang=en-US"

firefox_install() {
  # Take over from a previously brew-managed install. The cask uninstall
  # removes the bundle only; the profile in ~/Library survives.
  if cask_installed firefox; then
    log "firefox: removing the brew cask — the vendor dmg manages Firefox now"
    cask_uninstall firefox || return 1
  fi
  dmg_install "$FIREFOX_URL" "$FIREFOX_BUNDLE"
}

firefox_update() {
  if cask_installed firefox; then
    firefox_install
    return
  fi
  dmg_update "$FIREFOX_URL" "$FIREFOX_BUNDLE"
}

firefox_uninstall() { dmg_uninstall "$FIREFOX_BUNDLE" "$1"; }
firefox_installed() { dmg_installed "$FIREFOX_BUNDLE"; }
