#!/bin/bash
# The cloud-clis unit (Azure + AWS formulas, Google Cloud cask under one
# name) and the glab unit (GitLab CLI formula).
. "$(dirname "$0")/lib.sh"
setup_sandbox
load_libs
discover_apps
brew_log() { cat "$FAKE_BREW_LOG"; }

has() { in_list "$1" "${APP_IDS[*]}"; }
idx_of() { local i=0; while [ "$i" -lt "${#APP_IDS[@]}" ]; do if [ "${APP_IDS[$i]}" = "$1" ]; then printf '%s\n' "$i"; return; fi; i=$((i + 1)); done; printf -- '-1\n'; }
cat_for() { local i; i="$(idx_of "$1")"; [ "$i" -ge 0 ] && printf '%s\n' "${APP_CATEGORIES[$i]}"; }

# stage name — mark a formula or cask as installed in the fake brew.
stage() { mkdir -p "$FAKE_BREW_CASKROOM/$1/1.0"; }
unstage() { rm -rf "${FAKE_BREW_CASKROOM:?}/$1"; }

# ---- discovery ---------------------------------------------------------------
assert_ok "cloud-clis discovered" has cloud-clis
assert_contains "$(app_name_for cloud-clis)" "Cloud CLIs" "cloud-clis name"
assert_eq "Development" "$(cat_for cloud-clis)" "cloud-clis category"
assert_contains "$(app_note_for cloud-clis)" "az login" "cloud-clis note names the sign-in steps"
assert_ok "glab discovered" has glab
assert_eq "GitLab CLI" "$(app_name_for glab)" "glab name"
assert_eq "Development" "$(cat_for glab)" "glab category"
assert_contains "$(app_note_for glab)" "glab auth login" "glab note names the sign-in step"

# ---- cloud-clis: install -----------------------------------------------------
: >"$FAKE_BREW_LOG"
assert_ok "install with nothing present" cloud_clis_install
assert_contains "$(brew_log)" "install azure-cli" "installs the Azure formula"
assert_contains "$(brew_log)" "install awscli" "installs the AWS formula"
assert_contains "$(brew_log)" "install --cask --adopt gcloud-cli" "installs the Google Cloud cask"

# ---- cloud-clis: installed ---------------------------------------------------
assert_fail "nothing present -> not installed" cloud_clis_installed
stage azure-cli
stage awscli
assert_fail "cask missing -> not installed" cloud_clis_installed
stage gcloud-cli
assert_ok "all three present -> installed" cloud_clis_installed

# ---- cloud-clis: update ------------------------------------------------------
: >"$FAKE_BREW_LOG"
assert_ok "update with everything current" cloud_clis_update
assert_not_contains "$(brew_log)" "install" "current tools are not reinstalled"
assert_not_contains "$(brew_log)" "upgrade" "current tools are not upgraded"

: >"$FAKE_BREW_LOG"
FAKE_BREW_OUTDATED="awscli" cloud_clis_update
assert_contains "$(brew_log)" "upgrade --formula awscli" "outdated formula is upgraded"
assert_not_contains "$(brew_log)" "upgrade --formula azure-cli" "current formula is left alone"

# one tool removed by hand: update reinstalls just that one
unstage azure-cli
: >"$FAKE_BREW_LOG"
assert_ok "update with one formula missing" cloud_clis_update
assert_contains "$(brew_log)" "install azure-cli" "missing formula is reinstalled"
assert_not_contains "$(brew_log)" "install awscli" "present formula is not reinstalled"
assert_not_contains "$(brew_log)" "install --cask --adopt gcloud-cli" "present cask is not reinstalled"
stage azure-cli

# a failing formula fails the unit
: >"$FAKE_BREW_LOG"
unstage awscli
failing_update() { FAKE_BREW_FAIL=install cloud_clis_update; }
assert_fail "brew install failure fails the unit" failing_update
assert_contains "$(brew_log)" "install awscli" "the failing install was attempted"
stage awscli

# ---- cloud-clis: uninstall ---------------------------------------------------
: >"$FAKE_BREW_LOG"
assert_ok "uninstall keep" cloud_clis_uninstall keep
assert_contains "$(brew_log)" "uninstall --formula azure-cli" "keep removes the Azure formula"
assert_contains "$(brew_log)" "uninstall --formula awscli" "keep removes the AWS formula"
assert_contains "$(brew_log)" "uninstall --cask gcloud-cli" "keep removes the Google Cloud cask"
assert_not_contains "$(brew_log)" "--zap" "keep passes no --zap"

: >"$FAKE_BREW_LOG"
assert_ok "uninstall zap" cloud_clis_uninstall zap
assert_contains "$(brew_log)" "uninstall --cask --zap gcloud-cli" "zap reaches the cask"
assert_contains "$(brew_log)" "uninstall --formula awscli" "zap still removes the formulas"

unstage azure-cli
unstage awscli
unstage gcloud-cli
: >"$FAKE_BREW_LOG"
out="$(cloud_clis_uninstall keep 2>&1)"
assert_contains "$out" "nothing to remove" "absent tools report nothing to remove"
assert_not_contains "$(brew_log)" "uninstall" "absent tools run no uninstall"

# ---- glab --------------------------------------------------------------------
: >"$FAKE_BREW_LOG"
assert_fail "glab absent -> not installed" glab_installed
assert_ok "glab install" glab_install
assert_contains "$(brew_log)" "install glab" "installs the glab formula"
stage glab
assert_ok "glab present -> installed" glab_installed
: >"$FAKE_BREW_LOG"
assert_ok "glab uninstall zap" glab_uninstall zap
assert_contains "$(brew_log)" "uninstall --formula glab" "glab uninstall goes through the formula driver"

finish
