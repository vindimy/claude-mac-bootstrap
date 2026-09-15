#!/bin/bash
# The cask driver, in particular the state it infers from Homebrew's receipt
# vs. what is actually on disk.
. "$(dirname "$0")/lib.sh"
setup_sandbox
load_libs
brew_log() { cat "$FAKE_BREW_LOG"; }

APPS="$SANDBOX/Applications"
mkdir -p "$APPS"

# stage_cask name [app] — build a Caskroom entry like the real one: metadata
# files plus, when an app is given, a symlink to $APPS/<app>.app.
stage_cask() {
  local dir="$FAKE_BREW_CASKROOM/$1/1.0"
  mkdir -p "$dir" "$FAKE_BREW_CASKROOM/$1/.metadata"
  : >"$FAKE_BREW_CASKROOM/$1/.metadata/INSTALL_RECEIPT.json"
  if [ -n "${2:-}" ]; then
    mkdir -p "$APPS/$2.app"
    ln -sf "$APPS/$2.app" "$dir/$2.app"
  fi
}

# ---- cask_state --------------------------------------------------------------
assert_eq "absent" "$(cask_state nothing-here)" "no receipt -> absent"
stage_cask vlc VLC
assert_eq "present" "$(cask_state vlc)" "receipt + app on disk -> present"
stage_cask some-pkg
assert_eq "present" "$(cask_state some-pkg)" "receipt with no staged symlink (pkg cask) -> present"

# the reported bug: the app is deleted by hand, the receipt stays behind
stage_cask whatsapp WhatsApp
rm -rf "$APPS/WhatsApp.app"
assert_eq "orphaned" "$(cask_state whatsapp)" "receipt + app deleted by hand -> orphaned"

# ---- cask_installed ----------------------------------------------------------
assert_ok "present counts as installed" cask_installed vlc
assert_fail "absent is not installed" cask_installed nothing-here
assert_fail "orphaned is not installed" cask_installed whatsapp

# ---- cask_update -------------------------------------------------------------
: >"$FAKE_BREW_LOG"
cask_update vlc
assert_not_contains "$(brew_log)" "upgrade" "current cask is left alone"
assert_not_contains "$(brew_log)" "reinstall" "current cask is not reinstalled"

: >"$FAKE_BREW_LOG"
FAKE_BREW_OUTDATED="vlc" cask_update vlc
assert_contains "$(brew_log)" "upgrade --cask vlc" "outdated cask is upgraded"

: >"$FAKE_BREW_LOG"
cask_update nothing-here
assert_contains "$(brew_log)" "install --cask --adopt nothing-here" "absent cask is installed"

# the fix: an orphaned cask is reinstalled, because plain `brew install` would
# no-op against the surviving receipt
: >"$FAKE_BREW_LOG"
out="$(cask_update whatsapp 2>&1)"
assert_contains "$(brew_log)" "reinstall --cask whatsapp" "orphaned cask is reinstalled"
assert_not_contains "$(brew_log)" "install --cask --adopt whatsapp" "orphaned cask does not take the adopt path"
assert_contains "$out" "the installed app is gone" "the reinstall is explained"

# dry-run reinstalls nothing
: >"$FAKE_BREW_LOG"
out="$(DRY_RUN=1 cask_update whatsapp 2>&1)"
assert_contains "$out" "[dry-run] brew reinstall --cask whatsapp" "dry-run prints the reinstall"
assert_eq "" "$(brew_log | grep reinstall || true)" "dry-run runs no reinstall"

# ---- cask_uninstall ----------------------------------------------------------
: >"$FAKE_BREW_LOG"
out="$(cask_uninstall nothing-here keep 2>&1)"
assert_contains "$out" "nothing to remove" "absent cask reports nothing to remove"
assert_not_contains "$(brew_log)" "uninstall" "absent cask runs no uninstall"

# an orphaned cask still owns a receipt, so removal must clear it
: >"$FAKE_BREW_LOG"
assert_ok "orphaned cask uninstalls" cask_uninstall whatsapp keep
assert_contains "$(brew_log)" "uninstall --cask whatsapp" "orphaned cask still gets uninstalled"

: >"$FAKE_BREW_LOG"
assert_ok "zap mode" cask_uninstall vlc zap
assert_contains "$(brew_log)" "uninstall --cask --zap vlc" "zap passes --zap"

finish
