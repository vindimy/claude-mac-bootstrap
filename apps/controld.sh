#!/bin/bash
# shellcheck disable=SC2034
# Control D GUI Setup Utility — no Homebrew cask; installed from the vendor
# dmg (URL verified 2026-08-28). The utility self-updates, so update only
# reinstalls when the app is missing.
APP_NAME="Control D"
APP_CATEGORY="System Tools"
APP_NOTE="Open 'Control D Utility App' and sign in to finish DNS setup (resolver config is per-machine, not managed by this repo)."

CONTROLD_BUNDLE="Control D Utility App"

controld_url() {
  if [ "$(uname -m)" = arm64 ]; then
    printf 'https://assets.controld.com/utility/controld_arm.dmg\n'
  else
    printf 'https://assets.controld.com/utility/controld_x86.dmg\n'
  fi
}

controld_install()   { dmg_install "$(controld_url)" "$CONTROLD_BUNDLE"; }
controld_update()    { dmg_update "$(controld_url)" "$CONTROLD_BUNDLE"; }
controld_uninstall() { dmg_uninstall "$CONTROLD_BUNDLE" "$1"; }
controld_installed() { dmg_installed "$CONTROLD_BUNDLE"; }
