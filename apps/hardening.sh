#!/bin/bash
# shellcheck disable=SC2034
# macOS Hardening — not an app but a managed set of security settings.
# "install" applies the Tier 1 baseline, "update" re-applies it (drift
# correction on every update.sh run), "installed" is a compliance check that
# holds only while every Tier 1 setting is in place, and "uninstall zap"
# restores the macOS defaults. Tier 2 items (FileVault, SIP, Gatekeeper, SSH
# password auth) are reported but never changed — they need Recovery, a user
# secret, or a configuration profile. Design and rationale:
# docs/superpowers/specs/2026-09-04-macos-hardening-design.md
APP_NAME="macOS Hardening"
APP_CATEGORY="System Tools"
APP_NOTE="Needs your admin password (sudo). Applies: app firewall + stealth + logging, guest login/SMB off, auto-login off, all automatic updates on, show all filename extensions, Touch ID for sudo. Only reports FileVault, SIP, Gatekeeper and SSH password auth (see docs/howto.md). Remote Login (SSH) is left as you set it."

HARDENING_FW=/usr/libexec/ApplicationFirewall/socketfilterfw
HARDENING_LOGINWINDOW=/Library/Preferences/com.apple.loginwindow
HARDENING_SMB=/Library/Preferences/SystemConfiguration/com.apple.smb.server
HARDENING_SWUPDATE=/Library/Preferences/com.apple.SoftwareUpdate
HARDENING_COMMERCE=/Library/Preferences/com.apple.commerce
HARDENING_SWUPDATE_KEYS="AutomaticCheckEnabled AutomaticDownload AutomaticallyInstallMacOSUpdates CriticalUpdateInstall ConfigDataInstall"
HARDENING_SUDO_LOCAL=/etc/pam.d/sudo_local
HARDENING_PAM_TID='auth       sufficient     pam_tid.so'

# ---- Touch ID for sudo -------------------------------------------------------
# /etc/pam.d/sudo includes sudo_local (Sonoma+); that file survives OS updates,
# unlike edits to /etc/pam.d/sudo itself. On Macs without Touch ID pam_tid.so
# fails through to the normal password prompt, so it is harmless there.

hardening_sudo_local_supported() { grep -q 'sudo_local' /etc/pam.d/sudo 2>/dev/null; }

hardening_touchid_ok() {
  grep -qE '^auth[[:space:]]+sufficient[[:space:]]+pam_tid\.so' "$HARDENING_SUDO_LOCAL" 2>/dev/null
}

hardening_touchid_apply() {
  if ! hardening_sudo_local_supported; then
    warn "hardening: /etc/pam.d/sudo has no sudo_local include (pre-Sonoma?) — skipping Touch ID for sudo"
    return 0
  fi
  if hardening_touchid_ok; then return 0; fi
  if [ "$DRY_RUN" = 1 ]; then
    log "[dry-run] append '$HARDENING_PAM_TID' to $HARDENING_SUDO_LOCAL"
    return 0
  fi
  # Append rather than overwrite: a hand-added pam_reattach line (tmux) must
  # stay, and must stay ahead of pam_tid.
  if [ ! -f "$HARDENING_SUDO_LOCAL" ]; then
    printf '# Managed by claude-mac-bootstrap (apps/hardening.sh)\n' | sudo tee "$HARDENING_SUDO_LOCAL" >/dev/null || return 1
  fi
  printf '%s\n' "$HARDENING_PAM_TID" | sudo tee -a "$HARDENING_SUDO_LOCAL" >/dev/null
}

hardening_touchid_revert() {
  if ! hardening_touchid_ok; then return 0; fi
  run_cmd sudo sed -i '' '/pam_tid\.so/d' "$HARDENING_SUDO_LOCAL" || return 1
  if [ "$DRY_RUN" = 1 ]; then return 0; fi
  # Nothing but comments left -> the file was ours; remove it.
  if ! grep -qvE '^[[:space:]]*(#|$)' "$HARDENING_SUDO_LOCAL" 2>/dev/null; then
    sudo rm -f "$HARDENING_SUDO_LOCAL"
  fi
}

# ---- Tier 2: report only -------------------------------------------------------

hardening_report() {
  case "$(fdesetup status 2>/dev/null)" in
    *"FileVault is On"*) ;;
    *) warn "hardening: FileVault is OFF — turn it on in System Settings > Privacy & Security and store the recovery key (skip on a machine that must boot colima before login)" ;;
  esac
  case "$(csrutil status 2>/dev/null)" in
    *enabled*) ;;
    *) warn "hardening: System Integrity Protection is disabled — boot to Recovery and run: csrutil enable" ;;
  esac
  case "$(spctl --status 2>/dev/null)" in
    *"assessments enabled"*) ;;
    *) warn "hardening: Gatekeeper is off — spctl cannot re-enable it since Sequoia; use System Settings > Privacy & Security" ;;
  esac
  hardening_report_ssh
}

# Remote Login stays however the user set it (SSH is wanted on these
# machines). What gets flagged is password authentication while SSH is on.
hardening_report_ssh() {
  local pw
  if [ "$DRY_RUN" = 1 ]; then
    log "[dry-run] check: if Remote Login is on, warn when sshd still accepts passwords"
    return 0
  fi
  case "$(sudo systemsetup -getremotelogin 2>/dev/null)" in
    *On*) ;;
    *) return 0 ;;
  esac
  pw="$(sudo /usr/sbin/sshd -T 2>/dev/null | awk '$1 == "passwordauthentication" { print $2 }')"
  if [ "$pw" != no ]; then
    warn "hardening: SSH accepts passwords — add 'PasswordAuthentication no' and 'KbdInteractiveAuthentication no' to /etc/ssh/sshd_config.d/ and use keys only (see docs/howto.md)"
  fi
}

# ---- Contract ----------------------------------------------------------------

hardening_install() {
  local k
  log "hardening: applying Tier 1 settings (admin password may be asked)"
  run_cmd sudo "$HARDENING_FW" --setglobalstate on --setstealthmode on --setloggingmode on || return 1
  run_cmd sudo defaults write "$HARDENING_LOGINWINDOW" GuestEnabled -bool false || return 1
  run_cmd sudo defaults write "$HARDENING_SMB" AllowGuestAccess -bool false || return 1
  if defaults read "$HARDENING_LOGINWINDOW" autoLoginUser >/dev/null 2>&1; then
    run_cmd sudo defaults delete "$HARDENING_LOGINWINDOW" autoLoginUser || return 1
  fi
  for k in $HARDENING_SWUPDATE_KEYS; do
    run_cmd sudo defaults write "$HARDENING_SWUPDATE" "$k" -bool true || return 1
  done
  run_cmd sudo defaults write "$HARDENING_COMMERCE" AutoUpdate -bool true || return 1
  # Blocks invoice.pdf.app-style double-extension tricks in Finder.
  run_cmd defaults write NSGlobalDomain AppleShowAllExtensions -bool true || return 1
  hardening_touchid_apply || return 1
  hardening_report
  return 0
}

# Re-applying is the drift correction; every command above is idempotent.
hardening_update() { hardening_install; }

hardening_installed() {
  local k
  case "$("$HARDENING_FW" --getglobalstate 2>/dev/null)" in *"State = 1"* | *"State = 2"*) ;; *) return 1 ;; esac
  case "$("$HARDENING_FW" --getstealthmode 2>/dev/null)" in *enabled*) ;; *) return 1 ;; esac
  case "$("$HARDENING_FW" --getloggingmode 2>/dev/null)" in *on*) ;; *) return 1 ;; esac
  pref_is "$HARDENING_LOGINWINDOW" GuestEnabled 0 || return 1
  pref_is "$HARDENING_SMB" AllowGuestAccess 0 || return 1
  if defaults read "$HARDENING_LOGINWINDOW" autoLoginUser >/dev/null 2>&1; then return 1; fi
  for k in $HARDENING_SWUPDATE_KEYS; do
    pref_is "$HARDENING_SWUPDATE" "$k" 1 || return 1
  done
  pref_is "$HARDENING_COMMERCE" AutoUpdate 1 || return 1
  pref_is NSGlobalDomain AppleShowAllExtensions 1 || return 1
  if hardening_sudo_local_supported; then hardening_touchid_ok || return 1; fi
  return 0
}

# keep: leave the machine hardened. zap: back to macOS defaults (firewall off,
# managed keys removed so the OS default applies, Touch ID line dropped).
# Auto-login is not restored — it was removed, not replaced.
hardening_uninstall() {
  local k
  if [ "${1:-keep}" != zap ]; then
    log "hardening: settings kept (choose zap to restore macOS defaults)"
    return 0
  fi
  run_cmd sudo "$HARDENING_FW" --setglobalstate off --setstealthmode off --setloggingmode off
  pref_delete sudo "$HARDENING_LOGINWINDOW" GuestEnabled
  pref_delete sudo "$HARDENING_SMB" AllowGuestAccess
  for k in $HARDENING_SWUPDATE_KEYS; do
    pref_delete sudo "$HARDENING_SWUPDATE" "$k"
  done
  pref_delete sudo "$HARDENING_COMMERCE" AutoUpdate
  pref_delete NSGlobalDomain AppleShowAllExtensions
  hardening_touchid_revert
}
