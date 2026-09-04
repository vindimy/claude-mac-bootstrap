#!/bin/bash
# shellcheck disable=SC2034
# Xcode — Mac App Store, driven headlessly via the `mas` CLI (brew formula).
# Full Xcode (not just the Command Line Tools) is required to build iOS apps.
# Updates ride the App Store once installed; `mas upgrade` forces the check.
APP_NAME="Xcode"
APP_NOTE="Needs the machine signed into the App Store app (~12GB download). First install accepts the license and installs components, which asks for your admin password."

XCODE_MAS_ID=497799835
XCODE_APP="/Applications/Xcode.app"

xcode_installed() { [ -d "$XCODE_APP" ]; }

# License acceptance + additional components + pointing the CLI tools at the
# full Xcode. Needed once per major Xcode version; -checkFirstLaunchStatus
# reports whether it is still pending, so this is a cheap no-op afterward.
xcode_first_launch() {
  local xb="$XCODE_APP/Contents/Developer/usr/bin/xcodebuild"
  if [ "$DRY_RUN" = 1 ]; then
    log "[dry-run] accept Xcode license, run first-launch setup, xcode-select $XCODE_APP"
    return 0
  fi
  if [ "$(xcode-select -p 2>/dev/null)" != "$XCODE_APP/Contents/Developer" ]; then
    log "Xcode: pointing xcode-select at $XCODE_APP (admin password may be asked)"
    sudo xcode-select -s "$XCODE_APP/Contents/Developer" || return 1
  fi
  if "$xb" -checkFirstLaunchStatus >/dev/null 2>&1; then return 0; fi
  log "Xcode: accepting license and installing components (admin password may be asked)"
  sudo "$xb" -license accept && sudo "$xb" -runFirstLaunch
}

xcode_install() {
  formula_update mas
  if xcode_installed; then
    log "xcode: already present at $XCODE_APP"
    xcode_first_launch
    return
  fi
  if [ "$DRY_RUN" = 1 ]; then
    log "[dry-run] mas install $XCODE_MAS_ID  # Xcode from the Mac App Store"
    return 0
  fi
  if ! mas install "$XCODE_MAS_ID"; then
    err "Xcode: mas install failed — open the App Store app, sign in with your Apple ID, then re-run"
    return 1
  fi
  xcode_first_launch
}

xcode_update() {
  if ! xcode_installed; then
    xcode_install
    return
  fi
  formula_update mas
  run_cmd mas upgrade "$XCODE_MAS_ID" || return 1
  xcode_first_launch
}

# mas cannot uninstall App Store apps; remove the bundle directly. The mas
# helper formula is owned by this unit, so it goes too. Zap also clears
# ~/Library/Developer (simulators, DerivedData, archives, devices).
xcode_uninstall() {
  if ! xcode_installed; then
    log "xcode: not installed, nothing to remove"
  else
    run_cmd sudo rm -rf "$XCODE_APP"
  fi
  formula_uninstall mas "$1"
  if [ "${1:-keep}" = zap ]; then
    run_cmd rm -rf "$HOME/Library/Developer"
  fi
}
