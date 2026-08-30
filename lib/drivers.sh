#!/bin/bash
# Install/update/uninstall drivers shared by apps/*.sh.
# Sourced after lib/common.sh (uses run_cmd/log/err/DRY_RUN).

# ---- Homebrew cask ----------------------------------------------------------

cask_installed() { brew list --cask "$1" >/dev/null 2>&1; }

# --adopt takes over an app the user already installed manually, but only
# when it is identical to the cask's copy. Self-updating apps usually drift
# from the cask version, so on adopt failure fall back to --force: the bundle
# is replaced by the cask's copy (settings in ~/Library survive) and the
# app's own updater brings it current afterward. Under --dry-run, run_cmd
# returns 0, so only the adopt line is printed.
cask_install() {
  if ! run_cmd brew install --cask --adopt "$1"; then
    warn "$1: existing app differs from the cask — replacing it with the brew-managed copy (settings preserved)"
    run_cmd brew install --cask --force "$1"
  fi
}

# `brew outdated <name>` exits non-zero when a newer version exists. Casks
# marked auto_updates (Chrome, Claude, ChatGPT, Gemini) are not reported
# outdated here on purpose — those apps update themselves.
cask_update() {
  if ! cask_installed "$1"; then
    cask_install "$1"
    return
  fi
  if ! brew outdated --cask "$1" >/dev/null 2>&1; then
    run_cmd brew upgrade --cask "$1"
  fi
}

cask_uninstall() {
  if ! cask_installed "$1"; then
    log "$1: not installed via brew, nothing to remove"
    return 0
  fi
  if [ "${2:-keep}" = zap ]; then
    run_cmd brew uninstall --cask --zap "$1"
  else
    run_cmd brew uninstall --cask "$1"
  fi
}

# ---- Homebrew formula -------------------------------------------------------

formula_installed() { brew list --formula "$1" >/dev/null 2>&1; }

formula_install() { run_cmd brew install "$1"; }

formula_update() {
  if ! formula_installed "$1"; then
    formula_install "$1"
    return
  fi
  if ! brew outdated --formula "$1" >/dev/null 2>&1; then
    run_cmd brew upgrade --formula "$1"
  fi
}

# Formulas have no --zap; zap mode is the same as keep.
formula_uninstall() {
  if ! formula_installed "$1"; then
    log "$1: not installed via brew, nothing to remove"
    return 0
  fi
  run_cmd brew uninstall --formula "$1"
}

# ---- Direct dmg (vendor download) ------------------------------------------

dmg_installed() { [ -d "/Applications/$1.app" ]; }

# dmg_install url bundle-name: download, mount, copy the .app, unmount.
dmg_install() {
  local url="$1" app="$2" tmp dmg vol
  if [ "$DRY_RUN" = 1 ]; then
    log "[dry-run] download $url and install /Applications/$app.app"
    return 0
  fi
  tmp="$(mktemp -d)"
  dmg="$tmp/app.dmg"
  if ! curl -fL --retry 2 -o "$dmg" "$url"; then
    err "$app: download failed: $url — install manually from the vendor site"
    rm -rf "$tmp"
    return 1
  fi
  vol="$(hdiutil attach -nobrowse -readonly "$dmg" | sed -n 's/.*\(\/Volumes\/.*\)/\1/p' | tail -1)"
  if [ -z "$vol" ] || [ ! -d "$vol/$app.app" ]; then
    err "$app: $app.app not found in dmg from $url"
    if [ -n "$vol" ]; then hdiutil detach "$vol" -quiet || true; fi
    rm -rf "$tmp"
    return 1
  fi
  # ditto merges into an existing bundle; remove any pre-existing copy first
  # so stale files from an older version cannot linger inside the new one.
  if [ -d "/Applications/$app.app" ]; then
    rm -rf "/Applications/$app.app"
  fi
  if ! ditto "$vol/$app.app" "/Applications/$app.app"; then
    err "$app: copy failed — could not install the app"
    hdiutil detach "$vol" -quiet || true
    rm -rf "$tmp"
    return 1
  fi
  if ! hdiutil detach "$vol" -quiet; then
    warn "could not detach $vol"
  fi
  rm -rf "$tmp"
  log "$app: installed to /Applications/$app.app"
}

# Self-updating apps: reinstall only when the bundle is missing.
dmg_update() {
  if ! dmg_installed "$2"; then
    dmg_install "$1" "$2"
  fi
}

# dmg_uninstall bundle-name keep|zap. Zap paths are derived from the app's
# bundle id (read before deletion) — nothing vendor-specific hardcoded here.
dmg_uninstall() {
  local app="$1" mode="${2:-keep}" bid=""
  if ! dmg_installed "$app"; then
    log "$app: not installed, nothing to remove"
    return 0
  fi
  bid="$(defaults read "/Applications/$app.app/Contents/Info" CFBundleIdentifier 2>/dev/null || true)"
  run_cmd rm -rf "/Applications/$app.app"
  if [ "$mode" = zap ]; then
    run_cmd rm -rf "$HOME/Library/Application Support/$app"
    if [ -n "$bid" ]; then
      run_cmd rm -rf \
        "$HOME/Library/Preferences/$bid.plist" \
        "$HOME/Library/Caches/$bid" \
        "$HOME/Library/Application Support/$bid"
    fi
  fi
}
